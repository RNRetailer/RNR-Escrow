// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

//import "@openzeppelin/contracts/utils/Create2.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "https://github.com/RNRetailer/RandomNumberRetailer/blob/main/RandomNumberRetailerInterface.sol";

contract Escrow is ReentrancyGuard{
    // enums

    enum VoteStatus {
        NONE,
        APPROVED,
        REJECTED
    }

    enum MoneyStatus {
        MONEY_IN_ESCROW,
        MONEY_RELEASED_TO_RECEIVER,
        MONEY_RETURNED_TO_SENDER,
        MONEY_RELEASED_PARTIALLY_TO_BOTH_SENDER_AND_RECEIVER
    }

    enum ArbitrationStatus{
        NOT_IN_ARBITRATION,
        IN_ARBITRATION,
        ARBITRATION_COMPLETE
    }

    enum ArbitratorStatus{
        NOT_AN_ARBITRATOR,
        VALID_ARBITRATOR,
        BANNED_ARBITRATOR
    }

    enum JuryVote{
        NOT_YET_VOTED,
        DECISION_WAS_VALID,
        DECISION_WAS_INVALID
    }

    enum TrialStatus{
        TRIAL_HAS_NOT_BEEN_INVOKED,
        TRIAL_ONGOING,
        TRIAL_DECIDED
    }

    // structs

    struct Transaction{
        address sender;
        address receiver;
        uint256 amountInWei;
        VoteStatus senderVote;
        VoteStatus receiverVote;
        MoneyStatus moneyStatus;
        ArbitrationStatus arbitrationStatus;
        uint16 senderCutInBps;
        address arbitrator;
        uint256 arbitrationStartBlock;
        uint256 arbitrationEndBlock;
        address[] juryPool;
        JuryVote[] juryVotes;
        TrialStatus trialStatus;
        uint256 trialStartBlock;
    }

    // events

    event VoteSubmitted(address indexed voter, string transactionId, VoteStatus vote);
    event EscrowReleased(address indexed recipient, string transactionId, uint256 amountInWei);
    event ArbitrationInitiated(address indexed initiator, string transactionId, address arbitrator);
    event ArbitrationDecided(address indexed arbitrator, string transactionId, MoneyStatus decision);
    event ArbitratorAdded(address indexed arbitrator);
    event ArbitratorApplied(address indexed arbitrator);
    event ArbitratorRejected(address indexed arbitrator);
    event ArbitratorRemovedForTardiness(address indexed arbitrator);
    event ArbitratorRemovedForMalfeasance(address indexed arbitrator);
    event JurySelected(string indexed transactionId, address[] juryPool);
    event JuryDecided(string indexed transactionId, address[] juryPool, JuryVote juryVote);

    // globals

    mapping(address => ArbitratorStatus) public isArbitrator;
    mapping(address => Transaction[]) public senderAddressToTransactionArrayMap;
    mapping(address => string[]) public receiverAddressToTransactionIdArrayMap;
    mapping(address => string[]) public jurorToContestedTransactionIdArrayMap;

    enum LocalVariablesIndex{
        MAXIMUM_BASIS_POINTS,
        MINIMUM_TRANSACTION_VALUE_IN_WEI,
        STANDARD_EVENT_LENGTH,
        ARBITRATOR_SIGN_UP_COST_IN_WEI,
        ARBITRATION_MIN_FEE,
        ARBITRATION_PERCENTAGE_COST,
        ARBITRATION_ARBITRATOR_FEE_PERCENTAGE,
        ARBITRATORS_IN_A_JURY,
        JURY_TRIAL_MIN_COST_IN_WEI,
        JURY_TRIAL_PERCENTAGE_COST,
        JURY_TRIAL_JURY_FEE_PERCENTAGE,
        amount_owed_to_creator
    }

    address private constant creatorAddress = 0x8Fb9bcdde589059a87eE1056f5bc3F52782d55BB;
    bool public isPaused = false;

    // Points to the official RandomNumberRetailer contract.
    RandomNumberRetailerInterface public constant RANDOM_NUMBER_RETAILER = RandomNumberRetailerInterface(0xd058eA7e3DfE100775Ce954F15bB88257CC10191);

    uint256[] public localVariables = new uint256[](12);     
    address[] public arbitratorApplicantsAddresses = new address[](0);
    address[] public arbitratorAddresses = new address[](0);

    constructor() {
        localVariables[uint256(LocalVariablesIndex.MAXIMUM_BASIS_POINTS)] = 100 * 100; //MAXIMUM_BASIS_POINTS

        localVariables[uint256(LocalVariablesIndex.MINIMUM_TRANSACTION_VALUE_IN_WEI)] = .05 ether; //MINIMUM_TRANSACTION_VALUE_IN_WEI
        localVariables[uint256(LocalVariablesIndex.STANDARD_EVENT_LENGTH)] = 50134; //STANDARD_EVENT_LENGTH

        localVariables[uint256(LocalVariablesIndex.ARBITRATOR_SIGN_UP_COST_IN_WEI)] = .1 ether; //ARBITRATOR_SIGN_UP_COST_IN_WEI
        localVariables[uint256(LocalVariablesIndex.ARBITRATION_MIN_FEE)] = .01 ether; //ARBITRATION_MIN_FEE
        localVariables[uint256(LocalVariablesIndex.ARBITRATION_PERCENTAGE_COST)] = 5; //ARBITRATION_PERCENTAGE_COST
        localVariables[uint256(LocalVariablesIndex.ARBITRATION_ARBITRATOR_FEE_PERCENTAGE)] = 75; //ARBITRATION_ARBITRATOR_FEE_PERCENTAGE

        localVariables[uint256(LocalVariablesIndex.ARBITRATORS_IN_A_JURY)] = 3; //ARBITRATORS_IN_A_JURY
        localVariables[uint256(LocalVariablesIndex.JURY_TRIAL_MIN_COST_IN_WEI)] = .1 ether; //JURY_TRIAL_MIN_COST_IN_WEI
        localVariables[uint256(LocalVariablesIndex.JURY_TRIAL_PERCENTAGE_COST)] = 10; //JURY_TRIAL_PERCENTAGE_COST
        localVariables[uint256(LocalVariablesIndex.JURY_TRIAL_JURY_FEE_PERCENTAGE)] = 90; //JURY_TRIAL_JURY_FEE_PERCENTAGE

        localVariables[uint256(LocalVariablesIndex.amount_owed_to_creator)] = 0; //amount_owed_to_creator
    }

    modifier onlyCreator() {
        require(
            msg.sender == creatorAddress, 
            "FAILURE: Only the creator can call this method."
        );

        _;
    }

    modifier checkIfPaused() {
        require(
            !isPaused,
            "FAILURE: Contract is paused."
        );

        _;
    }

    // setters

    function setIsPaused(bool _isPaused) external onlyCreator{
        isPaused = _isPaused;
    }

    function setMinimumTransactionValueInWei(uint256 _minimumTransactionValueInWei) external onlyCreator{
        localVariables[uint256(LocalVariablesIndex.MINIMUM_TRANSACTION_VALUE_IN_WEI)] = _minimumTransactionValueInWei;
    }

    // helper functions

    function substring(string memory str, uint256 startIndex, uint256 endIndex) pure private returns (string memory substr) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);

        for(uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }

        substr = string(result);
    }

    function stringToUint(string memory numString) private pure returns(uint256 val) {
        val = 0;

        bytes memory stringBytes = bytes(numString);

        for (uint256 i =  0; i < stringBytes.length; i++) {
            uint256 exp = stringBytes.length - i;
            bytes1 ival = stringBytes[i];
            uint8 uval = uint8(ival);
            uint256 jval = uval - uint256(0x30);
   
            val += (uint256(jval) * (10**(exp-1))); 
        }
    }

    function hexCharToByte(bytes1 _char) internal pure returns (uint8) {
        uint8 byteValue = uint8(_char);
        if (byteValue >= uint8(bytes1('0')) && byteValue <= uint8(bytes1('9'))) {
            return byteValue - uint8(bytes1('0'));
        } else if (byteValue >= uint8(bytes1('a')) && byteValue <= uint8(bytes1('f'))) {
            return 10 + byteValue - uint8(bytes1('a'));
        } else if (byteValue >= uint8(bytes1('A')) && byteValue <= uint8(bytes1('F'))) {
            return 10 + byteValue - uint8(bytes1('A'));
        }
        revert("Invalid hex character");
    }

    function stringToAddress(string memory str) private pure returns (address addr) {
        bytes memory strBytes = bytes(str);
        require(strBytes.length == 42, "Invalid address length");
        bytes memory addrBytes = new bytes(20);

        for (uint i = 0; i < 20; i++) {
            addrBytes[i] = bytes1(hexCharToByte(strBytes[2 + i * 2]) * 16 + hexCharToByte(strBytes[3 + i * 2]));
        }

        addr = address(uint160(bytes20(addrBytes)));
    }

    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }

    function addressToAsciiString(address x) internal pure returns (string memory) {
        bytes memory s = new bytes(40);

        for (uint i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint(uint160(x)) / (2**(8*(19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2*i] = char(hi);
            s[2*i+1] = char(lo);            
        }

        return string(s);
    }

    // escrow functions

    function startTransaction(address receiver) external payable checkIfPaused returns (string memory transactionId){
        require(
            msg.value >= localVariables[uint256(LocalVariablesIndex.MINIMUM_TRANSACTION_VALUE_IN_WEI)],
            "Error: The minimum size of a transaction is MINIMUM_TRANSACTION_VALUE_IN_WEI"
        );

        address sender = msg.sender;

        Transaction memory transaction;
        transaction.sender = sender;
        transaction.receiver = receiver;
        transaction.amountInWei = msg.value;

        Transaction[] storage currentSenderTransactions = senderAddressToTransactionArrayMap[sender];

        uint256 newSenderTransactionIndex = currentSenderTransactions.length;

        currentSenderTransactions.push(transaction);

        transactionId = string.concat(
            addressToAsciiString(sender),
            "-", 
            Strings.toString(newSenderTransactionIndex)
        );

        receiverAddressToTransactionIdArrayMap[receiver].push(transactionId);
    }

    function getTransactionFromTransactionId(string memory transactionId) private view returns (Transaction storage currentTransaction){
        string memory senderAddressHex = substring(transactionId, 0, 42);
        address sender = stringToAddress(senderAddressHex);

        uint256 transactionIdLength = bytes(transactionId).length;
        string memory currentSenderTransactionsArrayIndexString = substring(transactionId, 43, transactionIdLength);
        uint256 currentSenderTransactionsArrayIndex = stringToUint(currentSenderTransactionsArrayIndexString);

        currentTransaction = senderAddressToTransactionArrayMap[sender][currentSenderTransactionsArrayIndex];
    }

    function voteOnTransaction(VoteStatus voteType, string calldata transactionId) private returns(Transaction storage currentTransaction){
        currentTransaction = getTransactionFromTransactionId(transactionId);

        if(msg.sender == currentTransaction.sender){
            currentTransaction.senderVote = voteType;
        }
        else if(msg.sender == currentTransaction.receiver){
            currentTransaction.receiverVote = voteType;
        }
        else{
            revert("Error: You are not the sender or receiver of this transaction.");
        }

        emit VoteSubmitted(msg.sender, transactionId, voteType);
    }

    function approveTransaction(string calldata transactionId) external nonReentrant checkIfPaused{
        Transaction storage currentTransaction = voteOnTransaction(VoteStatus.APPROVED, transactionId);

        if((currentTransaction.senderVote == VoteStatus.APPROVED) && (currentTransaction.receiverVote == VoteStatus.APPROVED)){
            require(
                payable(currentTransaction.receiver).send(currentTransaction.amountInWei),
                "Error: Failed to withdraw ETH to the receiver."
            );

            emit EscrowReleased(currentTransaction.receiver, transactionId, currentTransaction.amountInWei);

            currentTransaction.moneyStatus = MoneyStatus.MONEY_RELEASED_TO_RECEIVER;
        }   
    }

    function rejectTransaction(string calldata transactionId) external checkIfPaused{
        voteOnTransaction(VoteStatus.REJECTED, transactionId);
    }

    function signUpAsArbitrator() external payable checkIfPaused{
        require(
            msg.value >= localVariables[uint256(LocalVariablesIndex.ARBITRATOR_SIGN_UP_COST_IN_WEI)],
            "Error: You must pay ARBITRATOR_SIGN_UP_COST_IN_WEI to apply to be an arbitrator."
        );

        address newArbitrator = msg.sender;

        require(
            isArbitrator[newArbitrator] == ArbitratorStatus.NOT_AN_ARBITRATOR,
            "Error: This address is already banned or registered as an active arbitrator."
        );

        arbitratorApplicantsAddresses.push(newArbitrator);

        emit ArbitratorApplied(newArbitrator);

        localVariables[uint256(LocalVariablesIndex.amount_owed_to_creator)] += msg.value; 
    }

    function decideOnArbitratorApplication(address applicantAddress, bool approveApplication) external onlyCreator checkIfPaused{
        if(approveApplication){
            // approve arbitrator
            arbitratorAddresses.push(applicantAddress);
            isArbitrator[applicantAddress] = ArbitratorStatus.VALID_ARBITRATOR;
            emit ArbitratorAdded(applicantAddress);
        }
        else{
            // reject arbitrator
            emit ArbitratorRejected(applicantAddress);
        }

        // remove from applicant array
        uint256 currentArbitratorApplicationsAddressesArrayLength = arbitratorApplicantsAddresses.length;
        bool arbitratorFound = false;
        uint256 arbitratorIndex;

        for (uint256 i = 0; i < currentArbitratorApplicationsAddressesArrayLength; i++) {
            address tempAddress = arbitratorApplicantsAddresses[i];

            if(tempAddress == applicantAddress){
                arbitratorFound = true;
                arbitratorIndex = i;
                break;
            }
        }

        require(
            arbitratorFound,
            "Could not find arbitrator in arbitratorApplicantsAddresses array"
        );

        arbitratorApplicantsAddresses[arbitratorIndex] = arbitratorApplicantsAddresses[--currentArbitratorApplicationsAddressesArrayLength];
        arbitratorApplicantsAddresses.pop();
    }

    function withdrawCreatorEarnings(uint256 weiToWithdraw) external nonReentrant onlyCreator checkIfPaused{
        require(
            localVariables[uint256(LocalVariablesIndex.amount_owed_to_creator)] >= weiToWithdraw,
            "Owner cannot withdraw that much ETH"
        );

        localVariables[uint256(LocalVariablesIndex.amount_owed_to_creator)] -= weiToWithdraw;

        require(
            payable(creatorAddress).send(weiToWithdraw),
            "FAILURE: Failed to withdraw ETH to the creator."
        );
    }

    function chooseArbitrator(address sender, address receiver, uint256 randomness) private view returns(address){
        uint256 arbitratorAddressesLength = arbitratorAddresses.length;
        uint256 nonce = 0;

        while(true){
            address chosenArbitrator = arbitratorAddresses[
                uint256(keccak256(abi.encodePacked(block.prevrandao, block.timestamp, randomness, nonce))) % arbitratorAddressesLength // get random arbitrator
            ];

            if((chosenArbitrator != sender) && (chosenArbitrator != receiver)){
                return chosenArbitrator;  // make sure arbitrator is not a party to the transaction
            }

            nonce++;
        }

        revert("It is impossible to get here.");
    }

    function requestArbitration(string calldata transactionId, RandomNumberRetailerInterface.Proof memory proof, RandomNumberRetailerInterface.RequestCommitment memory rc) external payable checkIfPaused returns(address chosenArbitrator){
        Transaction storage currentTransaction = getTransactionFromTransactionId(transactionId);

        require(
            currentTransaction.moneyStatus == MoneyStatus.MONEY_IN_ESCROW,
            "Error: Arbitration request denied. Money was already paid out."
        );

        require(
            currentTransaction.arbitrationStatus == ArbitrationStatus.NOT_IN_ARBITRATION,
            "Error: Arbitration was already requested for this transaction."
        );

        if(msg.sender == currentTransaction.sender){
            if(currentTransaction.senderVote != VoteStatus.REJECTED){
                currentTransaction.senderVote = VoteStatus.REJECTED;
                emit VoteSubmitted(msg.sender, transactionId, VoteStatus.REJECTED);
            }
        }
        else if(msg.sender == currentTransaction.receiver){
            if(currentTransaction.receiverVote != VoteStatus.REJECTED){
                currentTransaction.receiverVote = VoteStatus.REJECTED;
                emit VoteSubmitted(msg.sender, transactionId, VoteStatus.REJECTED);
            }
        }
        else{
            revert("Error: You are not the sender or receiver of this transaction.");
        }

        uint256 priceOfARandomNumberInWei = RANDOM_NUMBER_RETAILER.priceOfARandomNumberInWei();

        require(
            msg.value >= priceOfARandomNumberInWei, 
            string.concat("Error: You must pay at least ", Strings.toString(priceOfARandomNumberInWei), " wei to begin arbitration")
        );

        uint256[] memory randomNumbersFromRNRetailer = RANDOM_NUMBER_RETAILER.requestRandomNumbersSynchronousUsingVRFv2Seed{value: priceOfARandomNumberInWei}(1, proof, rc);

        chosenArbitrator = chooseArbitrator(currentTransaction.sender, currentTransaction.receiver, randomNumbersFromRNRetailer[0]);

        currentTransaction.arbitrator = chosenArbitrator;
        currentTransaction.arbitrationStatus = ArbitrationStatus.IN_ARBITRATION;
        currentTransaction.arbitrationStartBlock = block.number;

        emit ArbitrationInitiated(msg.sender, transactionId, chosenArbitrator);
    }

    function makeArbitrationSimpleDecision(string calldata transactionId, MoneyStatus decision) external checkIfPaused{
        Transaction storage currentTransaction = getTransactionFromTransactionId(transactionId);

        require(
            currentTransaction.moneyStatus == MoneyStatus.MONEY_IN_ESCROW,
            "Error: Arbitration request denied. Money was already paid out."
        );

        require(
            currentTransaction.arbitrator == msg.sender,
            "Error: Only the official arbitrator for the transaction can make an arbitration decision."
        );

        if (decision == MoneyStatus.MONEY_RELEASED_TO_RECEIVER){
            currentTransaction.senderCutInBps = 0;
        }
        else if (decision == MoneyStatus.MONEY_RETURNED_TO_SENDER){
            currentTransaction.senderCutInBps = uint16(localVariables[uint256(LocalVariablesIndex.MAXIMUM_BASIS_POINTS)]);
        }
        else{
            revert("Error: Invalid decision. Money must be returned to the recipient or the sender.");
        }

        currentTransaction.arbitrationStatus = ArbitrationStatus.ARBITRATION_COMPLETE;
        currentTransaction.arbitrationEndBlock = block.number;

        emit ArbitrationDecided(msg.sender, transactionId, decision);
    }

    function makeArbitrationSplitDecision(string calldata transactionId, uint16 basisPointsForReceiver) external checkIfPaused{
        require(
            (basisPointsForReceiver > 0) && (basisPointsForReceiver < localVariables[uint256(LocalVariablesIndex.MAXIMUM_BASIS_POINTS)]),
            "Error: makeArbitrationSplitDecision cannot give all of the money to one address. Use makeArbitrationSimpleDecision instead."
        );

        Transaction storage currentTransaction = getTransactionFromTransactionId(transactionId);

        require(
            currentTransaction.moneyStatus == MoneyStatus.MONEY_IN_ESCROW,
            "Error: Arbitration request denied. Money was already paid out."
        );

        require(
            currentTransaction.arbitrator == msg.sender,
            "Error: Only the official arbitrator for the transaction can make an arbitration decision."
        );

        currentTransaction.senderCutInBps = uint16(localVariables[uint256(LocalVariablesIndex.MAXIMUM_BASIS_POINTS)]) - basisPointsForReceiver;

        currentTransaction.arbitrationStatus = ArbitrationStatus.ARBITRATION_COMPLETE;
        currentTransaction.arbitrationEndBlock = block.number;

        emit ArbitrationDecided(msg.sender, transactionId, MoneyStatus.MONEY_RELEASED_PARTIALLY_TO_BOTH_SENDER_AND_RECEIVER);
    }

    function banArbitrator(address currentArbitrator) private{
        if (isArbitrator[currentArbitrator] == ArbitratorStatus.BANNED_ARBITRATOR){
            return;
        }

        isArbitrator[currentArbitrator] = ArbitratorStatus.BANNED_ARBITRATOR;

        uint256 currentArbitratorAddressesArrayLength = arbitratorAddresses.length;
        bool arbitratorFound = false;
        uint256 arbitratorIndex;

        for (uint256 i = 0; i < currentArbitratorAddressesArrayLength; i++) {
            address tempAddress = arbitratorAddresses[i];

            if(tempAddress == currentArbitrator){
                arbitratorFound = true;
                arbitratorIndex = i;
                break;
            }
        }

        require(
            arbitratorFound,
            "Could not find arbitrator in arbitratorAddresses array"
        );

        arbitratorAddresses[arbitratorIndex] = arbitratorAddresses[--currentArbitratorAddressesArrayLength];
        arbitratorAddresses.pop();
    }

    function requestNewArbitratorForTardiness(string calldata transactionId, RandomNumberRetailerInterface.Proof memory proof, RandomNumberRetailerInterface.RequestCommitment memory rc) external payable checkIfPaused returns(address chosenArbitrator){
        Transaction storage currentTransaction = getTransactionFromTransactionId(transactionId);

        require(
            (msg.sender == currentTransaction.sender) || (msg.sender == currentTransaction.receiver),
            "Error: Only the transaction sender or receiver can request a new arbitrator."
        );

        uint256 cutoffBlock = currentTransaction.arbitrationStartBlock + localVariables[uint256(LocalVariablesIndex.STANDARD_EVENT_LENGTH)];

        require(
            cutoffBlock < block.number,
            string.concat("Error: The arbitrator has until block ", Strings.toString(cutoffBlock), " to make a decision.")
        );

        address currentArbitrator = currentTransaction.arbitrator;

        banArbitrator(currentArbitrator);

        emit ArbitratorRemovedForTardiness(currentArbitrator);

        uint256 priceOfARandomNumberInWei = RANDOM_NUMBER_RETAILER.priceOfARandomNumberInWei();

        require(
            msg.value >= priceOfARandomNumberInWei, 
            string.concat("Error: You must pay at least ", Strings.toString(priceOfARandomNumberInWei), " wei to ban an arbitrator for tardiness")
        );

        uint256[] memory randomNumbersFromRNRetailer = RANDOM_NUMBER_RETAILER.requestRandomNumbersSynchronousUsingVRFv2Seed{value: priceOfARandomNumberInWei}(1, proof, rc);

        chosenArbitrator = chooseArbitrator(currentTransaction.sender, currentTransaction.receiver, randomNumbersFromRNRetailer[0]);
        currentTransaction.arbitrator = chosenArbitrator;
        currentTransaction.arbitrationStartBlock = block.number;

        emit ArbitrationInitiated(msg.sender, transactionId, chosenArbitrator);
    }

    function completePayoutAfterArbitration(Transaction storage currentTransaction) private{
        uint256 totalAmount = currentTransaction.amountInWei;

        uint256 totalArbitrationFeeInWei = (totalAmount * localVariables[uint256(LocalVariablesIndex.ARBITRATION_PERCENTAGE_COST)]) / 100;

        uint256 arbitrationMinFeeInWei = localVariables[uint256(LocalVariablesIndex.ARBITRATION_MIN_FEE)];

        if(totalArbitrationFeeInWei < arbitrationMinFeeInWei){
            totalArbitrationFeeInWei = arbitrationMinFeeInWei;
        }

        uint256 feeForArbitratorInWei = (totalArbitrationFeeInWei * localVariables[uint256(LocalVariablesIndex.ARBITRATION_ARBITRATOR_FEE_PERCENTAGE)]) / 100;
        uint256 feeForCreatorInWei = totalArbitrationFeeInWei - feeForArbitratorInWei;
        uint256 weiRemainingForParticipants = totalAmount - totalArbitrationFeeInWei;

        uint256 payoutForSenderInWei = (weiRemainingForParticipants * uint256(currentTransaction.senderCutInBps)) / localVariables[uint256(LocalVariablesIndex.MAXIMUM_BASIS_POINTS)];
        uint256 payoutForReceiverInWei = weiRemainingForParticipants - payoutForSenderInWei;

        require(
            (feeForArbitratorInWei + feeForCreatorInWei + payoutForSenderInWei + payoutForReceiverInWei) <= totalAmount,
            "CRITICAL ERROR: Payout calculation is incorrect. Infinite money glitch discovered."
        );

        if(payoutForSenderInWei == 0){
            currentTransaction.moneyStatus = MoneyStatus.MONEY_RELEASED_TO_RECEIVER;

            require(
                payable(currentTransaction.receiver).send(payoutForReceiverInWei),
                "Error: Failed to pay receiver after arbitration."
            );
        }
        else if(payoutForReceiverInWei == 0){
            currentTransaction.moneyStatus = MoneyStatus.MONEY_RETURNED_TO_SENDER;

            require(
                payable(currentTransaction.sender).send(payoutForSenderInWei),
                "Error: Failed to pay sender after arbitration."
            );
        }
        else{
            currentTransaction.moneyStatus = MoneyStatus.MONEY_RELEASED_PARTIALLY_TO_BOTH_SENDER_AND_RECEIVER;

            require(
                payable(currentTransaction.receiver).send(payoutForReceiverInWei),
                "Error: Failed to pay receiver after arbitration."
            );

            require(
                payable(currentTransaction.sender).send(payoutForSenderInWei),
                "Error: Failed to pay sender after arbitration."
            );
        }

        localVariables[uint256(LocalVariablesIndex.amount_owed_to_creator)] += feeForCreatorInWei;
    }

    function requestPayoutAfterArbitrationGracePeriodEnds(string calldata transactionId) external nonReentrant{
        Transaction storage currentTransaction = getTransactionFromTransactionId(transactionId);

        require(
            (msg.sender == currentTransaction.sender) || (msg.sender == currentTransaction.receiver),
            "Error: Only the transaction sender or receiver can request a payout after arbitration."
        );

        require(
            currentTransaction.arbitrationEndBlock + localVariables[uint256(LocalVariablesIndex.STANDARD_EVENT_LENGTH)] < block.number,
            "Error: Please wait for the end of the grace period, which is STANDARD_EVENT_LENGTH blocks after currentTransaction.arbitrationEndBlock"
        );

        completePayoutAfterArbitration(currentTransaction);
    }

    function isArbitratorAddressInArray(address arbitratorToCheck, address[] memory arbitratorAddressArray) private pure returns (bool) {
        for (uint i = 0; i < arbitratorAddressArray.length; i++) {
            address tempArbitratorAddress = arbitratorAddressArray[i];

            if(arbitratorToCheck == tempArbitratorAddress){
                return true;
            }
        }

        return false;
    }

    function selectJury(string memory transactionId, Transaction storage currentTransaction, RandomNumberRetailerInterface.Proof memory proof, RandomNumberRetailerInterface.RequestCommitment memory rc) private {
        uint256 ARBITRATORS_IN_A_JURY = localVariables[uint256(LocalVariablesIndex.ARBITRATORS_IN_A_JURY)];
        uint256 arbitratorAddressesLength = arbitratorAddresses.length;
        uint256 costOfRandomNumbers = RANDOM_NUMBER_RETAILER.priceOfARandomNumberInWei() * ARBITRATORS_IN_A_JURY;

        uint8 currentIndexOfJuryPool = 0;

        address[] memory juryPool = new address[](ARBITRATORS_IN_A_JURY);
        uint256[] memory randomNumbers = RANDOM_NUMBER_RETAILER.requestRandomNumbersSynchronousUsingVRFv2Seed{value: costOfRandomNumbers}(ARBITRATORS_IN_A_JURY, proof, rc);

        address[] memory invalidAddressesForJury = new address[](5);
        invalidAddressesForJury[0] = currentTransaction.sender;
        invalidAddressesForJury[1] = currentTransaction.receiver;
        invalidAddressesForJury[2] = currentTransaction.arbitrator;

        uint256 nonce;

        for(uint8 i=0; i < ARBITRATORS_IN_A_JURY; i++){
           uint256 currentRandomNumber = randomNumbers[i];
           nonce = 0;

            while (true){
                address arbitratorToCheck = arbitratorAddresses[
                    uint256(keccak256(abi.encodePacked(block.prevrandao, block.timestamp, currentIndexOfJuryPool, currentRandomNumber, nonce))) % arbitratorAddressesLength // get random arbitrator
                ];

                if(!isArbitratorAddressInArray(arbitratorToCheck, invalidAddressesForJury)){
                    juryPool[currentIndexOfJuryPool++] = arbitratorToCheck;

                    if(currentIndexOfJuryPool != uint8(ARBITRATORS_IN_A_JURY)){
                        invalidAddressesForJury[2 + currentIndexOfJuryPool] = arbitratorToCheck;
                    }

                    jurorToContestedTransactionIdArrayMap[arbitratorToCheck].push(transactionId);

                    break;
                }
                else{
                    nonce += 1;
                }
            }
        }

        currentTransaction.juryPool = juryPool;
        currentTransaction.juryVotes = new JuryVote[](ARBITRATORS_IN_A_JURY);
        currentTransaction.trialStartBlock = block.number;
        currentTransaction.trialStatus = TrialStatus.TRIAL_ONGOING;
        emit JurySelected(transactionId, juryPool);
    }

    function checkIfUserCanAffordJuryTrial(Transaction storage currentTransaction) private{
        uint256 priceOfARandomNumberInWei = RANDOM_NUMBER_RETAILER.priceOfARandomNumberInWei();
        uint256 priceOfRandomJurySelection = priceOfARandomNumberInWei * localVariables[uint256(LocalVariablesIndex.ARBITRATORS_IN_A_JURY)];

        uint256 juryTrialTotalFee = (currentTransaction.amountInWei * localVariables[uint256(LocalVariablesIndex.JURY_TRIAL_PERCENTAGE_COST)]) / 100;

        uint256 juryTrialMinimumFee = localVariables[uint256(LocalVariablesIndex.JURY_TRIAL_MIN_COST_IN_WEI)];

        if (juryTrialTotalFee < juryTrialMinimumFee){
            juryTrialTotalFee = juryTrialMinimumFee;
        }

        uint256 totalCostOfTrial = priceOfRandomJurySelection + juryTrialTotalFee;

        require(
            msg.value >= totalCostOfTrial, 
            string.concat("Error: You must pay at least ", Strings.toString(totalCostOfTrial), " wei to invoke a jury trial for this transaction")
        );
    }

    function invokeJuryTrial(string calldata transactionId, RandomNumberRetailerInterface.Proof memory proof, RandomNumberRetailerInterface.RequestCommitment memory rc) external payable checkIfPaused{
        Transaction storage currentTransaction = getTransactionFromTransactionId(transactionId);

        require(
            (msg.sender == currentTransaction.sender) || (msg.sender == currentTransaction.receiver),
            "Error: Only the transaction sender or receiver can request a jury trial after arbitration."
        );

        require(
            currentTransaction.arbitrationStatus == ArbitrationStatus.ARBITRATION_COMPLETE, 
            "Arbitration must have already completed before a jury trial can be requested."
        );

        require(
            currentTransaction.trialStatus == TrialStatus.TRIAL_HAS_NOT_BEEN_INVOKED,
            "Error: Trial was already invoked."
        );

        require(
            currentTransaction.moneyStatus == MoneyStatus.MONEY_IN_ESCROW,
            "Error: The money was already paid out. A trial is not possible."
        );

        checkIfUserCanAffordJuryTrial(currentTransaction);

        selectJury(transactionId, currentTransaction, proof, rc);
    }

    function castVoteAsJuror(string calldata transactionId, JuryVote wasPreviousArbitrationValid, RandomNumberRetailerInterface.Proof memory proof, RandomNumberRetailerInterface.RequestCommitment memory rc) external payable nonReentrant checkIfPaused{
        Transaction storage currentTransaction = getTransactionFromTransactionId(transactionId);
        address[] memory juryPool = currentTransaction.juryPool;
        JuryVote[] storage juryVotes = currentTransaction.juryVotes;
        address sender = msg.sender;
        bool foundMatchingJuror = false;

        for (uint8 i = 0; i < juryPool.length; i++) {
            address tempJuror = juryPool[i];

            if(sender == tempJuror){
                juryVotes[i] = wasPreviousArbitrationValid;
                foundMatchingJuror = true;
                break;
            }
        }

        require(
            foundMatchingJuror, 
            "Error: msg.sender is not in the juror pool for this transaction."
        );

        uint8 validVotes = 0;
        uint8 invalidVotes = 0;

        for (uint8 i = 0; i < juryVotes.length; i++){
            JuryVote tempVote = juryVotes[i];

            if(tempVote == JuryVote.NOT_YET_VOTED){
                break;
            }
            else if(tempVote == JuryVote.DECISION_WAS_VALID){
                validVotes += 1;
            }
            else if(tempVote == JuryVote.DECISION_WAS_INVALID){
                invalidVotes += 1;
            }
            else{
                revert("Vote was not in the enum.");
            }
        }

        if((validVotes + invalidVotes) == juryPool.length){
            JuryVote finalVote;

            if (validVotes > invalidVotes){
                finalVote = JuryVote.DECISION_WAS_VALID;
            }
            else{
                finalVote = JuryVote.DECISION_WAS_INVALID;
            }

            completeTrial(currentTransaction, juryPool, finalVote, proof, rc);
            emit JuryDecided(transactionId, juryPool, finalVote);
        }
    }

    function requestNewJuryForTardiness(string calldata transactionId, RandomNumberRetailerInterface.Proof memory proof, RandomNumberRetailerInterface.RequestCommitment memory rc) external payable checkIfPaused{
        Transaction storage currentTransaction = getTransactionFromTransactionId(transactionId);

        require(
            (msg.sender == currentTransaction.sender) || (msg.sender == currentTransaction.receiver),
            "Error: Only the transaction sender or receiver can request a new jury."
        );

        require(
            currentTransaction.trialStatus == TrialStatus.TRIAL_ONGOING,
            "Error: Trial must be ongoing to request a new Jury."
        );

        uint256 cutoffBlock = currentTransaction.trialStartBlock + localVariables[uint256(LocalVariablesIndex.STANDARD_EVENT_LENGTH)];

        require(
            cutoffBlock < block.number,
            string.concat("Error: The jury has until block ", Strings.toString(cutoffBlock), " to make a decision.")
        );

        address[] memory juryPool = currentTransaction.juryPool;
        uint8 juryPoolSize = uint8(juryPool.length);
        JuryVote[] memory juryVotes = currentTransaction.juryVotes;
        uint8 bannedJurors = 0;

        for (uint8 i=0; i < juryPoolSize; i++){
            JuryVote tempVote = juryVotes[i];

            if(tempVote == JuryVote.NOT_YET_VOTED){
                address jurorToBan = juryPool[i];
                banArbitrator(jurorToBan);
                bannedJurors += 1;
                emit ArbitratorRemovedForTardiness(jurorToBan);
            }
        }

        require(
            bannedJurors > 0,
            "Error: All of the jurors have already voted. Trial will not be restarted."
        );

        uint256 priceOfARandomNumberInWei = RANDOM_NUMBER_RETAILER.priceOfARandomNumberInWei();
        uint256 priceOfRandomJurySelection = priceOfARandomNumberInWei * juryPoolSize;

        require(
            msg.value >= priceOfRandomJurySelection, 
            string.concat("Error: You must pay at least ", Strings.toString(priceOfRandomJurySelection), " wei to restart the jury trial.")
        );

        selectJury(transactionId, currentTransaction, proof, rc);
    }

    function completeTrial(Transaction storage currentTransaction, address[] memory juryPool, JuryVote finalVote, RandomNumberRetailerInterface.Proof memory proof, RandomNumberRetailerInterface.RequestCommitment memory rc) private{
        if(finalVote == JuryVote.DECISION_WAS_VALID){
            // pay out the money as the previous arbitrator decided and mark the transaction as TRIAL_DECIDED

            completePayoutAfterArbitration(currentTransaction);
            currentTransaction.trialStatus = TrialStatus.TRIAL_DECIDED;
        }
        else{
            // ban the current arbitrator for malfeasance, select a new arbitrator for the transaction and go back to arbitration

            uint256 priceOfARandomNumberInWei = RANDOM_NUMBER_RETAILER.priceOfARandomNumberInWei();

            require(
                msg.value >= priceOfARandomNumberInWei,
                string.concat("Error: You must include at least ", Strings.toString(priceOfARandomNumberInWei), " wei as payment.")
            );

            uint256[] memory randomNumbers = RANDOM_NUMBER_RETAILER.requestRandomNumbersSynchronousUsingVRFv2Seed{value: priceOfARandomNumberInWei}(1, proof, rc);

            address currentArbitrator = currentTransaction.arbitrator;
            banArbitrator(currentArbitrator);
            emit ArbitratorRemovedForMalfeasance(currentArbitrator);

            address newArbitrator = chooseArbitrator(currentTransaction.sender, currentTransaction.receiver, randomNumbers[0]);
            currentTransaction.arbitrator = newArbitrator;

            currentTransaction.arbitrationStatus = ArbitrationStatus.IN_ARBITRATION;
            currentTransaction.senderCutInBps = 0;
            currentTransaction.arbitrationStartBlock = block.number;
            currentTransaction.juryPool = new address[](0);
            currentTransaction.juryVotes = new JuryVote[](0);
            currentTransaction.trialStatus = TrialStatus.TRIAL_HAS_NOT_BEEN_INVOKED;
        }

        // pay the jury

        uint256 juryPoolLength = juryPool.length;
        uint8 juryPoolLengthUint8 = uint8(juryPoolLength);

        uint256 juryTrialTotalFee = (currentTransaction.amountInWei * localVariables[uint256(LocalVariablesIndex.JURY_TRIAL_PERCENTAGE_COST)]) / 100;

        uint256 juryTrialMinimumFee = localVariables[uint256(LocalVariablesIndex.JURY_TRIAL_MIN_COST_IN_WEI)];

        if (juryTrialTotalFee < juryTrialMinimumFee){
            juryTrialTotalFee = juryTrialMinimumFee;
        }

        uint256 totalPayoutForJury = (juryTrialTotalFee * localVariables[uint256(LocalVariablesIndex.JURY_TRIAL_JURY_FEE_PERCENTAGE)]) / 100;
        uint256 payoutForCreator = juryTrialTotalFee - totalPayoutForJury;

        uint256 payoutPerJurorInWei = totalPayoutForJury / juryPoolLength;

        require(
            juryTrialTotalFee >= ((payoutPerJurorInWei * juryPoolLength) + payoutForCreator),
            "Error: Infinite money glitch. Jurors + creator got more money than juryTrialTotalFee"
        );

        for (uint8 i=0; i < juryPoolLengthUint8; i++){
            address currentJuror = juryPool[i];

            require(
                payable(currentJuror).send(payoutPerJurorInWei),
                "Error: Failed to pay juror."
            );
        }

        localVariables[uint256(LocalVariablesIndex.amount_owed_to_creator)] += payoutForCreator;
    }
}

//contract Deployer {
//   event ContractDeployed(address deployedContractAddress);

//   constructor() {
//      emit ContractDeployed(
//        Create2.deploy(
//            0, 
//            "Escrow v0.01 Alpha", 
//            type(Escrow).creationCode
//        )
//      );
//   }
//}