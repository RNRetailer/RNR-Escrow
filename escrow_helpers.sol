// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

//import "@openzeppelin/contracts/utils/Create2.sol";

interface RNREscrowInterface {
    function getTransactionParties(string calldata transactionId) external view returns (address[] memory); 
}

contract EscrowHelpers {
    RNREscrowInterface public RNR_ESCROW = RNREscrowInterface(0x0000000000000000000000000000000000000000);
    address private constant creatorAddress = 0x8Fb9bcdde589059a87eE1056f5bc3F52782d55BB;

    mapping(string => string[]) public transactionIDToEvidenceMap;

    // modifier

    modifier onlyCreator() {
        require(
            msg.sender == creatorAddress, 
            "FAILURE: Only the creator can call this method."
        );

        _;
    }

    // helper functions

    function setUpEscrowInterface(address RNREscrowInterfaceAddress) external onlyCreator{
        require(
            RNR_ESCROW == RNREscrowInterface(0x0000000000000000000000000000000000000000),
            "Error: RNR_ESCROW can only be set once."
        );

        RNR_ESCROW = RNREscrowInterface(RNREscrowInterfaceAddress);
    }

    function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10 ** 64) {
                value /= 10 ** 64;
                result += 64;
            }
            if (value >= 10 ** 32) {
                value /= 10 ** 32;
                result += 32;
            }
            if (value >= 10 ** 16) {
                value /= 10 ** 16;
                result += 16;
            }
            if (value >= 10 ** 8) {
                value /= 10 ** 8;
                result += 8;
            }
            if (value >= 10 ** 4) {
                value /= 10 ** 4;
                result += 4;
            }
            if (value >= 10 ** 2) {
                value /= 10 ** 2;
                result += 2;
            }
            if (value >= 10 ** 1) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) external pure returns (string memory) {
        unchecked {
            uint256 length = EscrowHelpers.log10(value) + 1;
            string memory buffer = new string(length);
            uint256 ptr;
            assembly ("memory-safe") {
                ptr := add(buffer, add(32, length))
            }
            while (true) {
                ptr--;
                assembly ("memory-safe") {
                    mstore8(ptr, byte(mod(value, 10), "0123456789abcdef"))
                }
                value /= 10;
                if (value == 0) break;
            }
            return buffer;
        }
    }

    function substring(string memory str, uint256 startIndex, uint256 endIndex) public pure returns (string memory substr) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);

        for(uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }

        substr = string(result);
    }

    function stringToUint(string memory numString) public pure returns(uint256 val) {
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

    function hexcharToByte(bytes1 _char) public pure returns (uint8) {
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

    function stringToAddress(string memory str) public pure returns (address addr) {
        bytes memory strBytes = bytes(str);
        require(strBytes.length == 42, "Invalid address length");
        bytes memory addrBytes = new bytes(20);

        for (uint i = 0; i < 20; i++) {
            addrBytes[i] = bytes1(hexcharToByte(strBytes[2 + i * 2]) * 16 + hexcharToByte(strBytes[3 + i * 2]));
        }

        addr = address(uint160(bytes20(addrBytes)));
    }

    function char(bytes1 b) public pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }

    function addressToAsciiString(address x) external pure returns (string memory) {
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
       
    function isArbitratorAddressInArray(address arbitratorToCheck, address[] memory arbitratorAddressArray) external pure returns (bool) {
        for (uint i = 0; i < arbitratorAddressArray.length; i++) {
            address tempArbitratorAddress = arbitratorAddressArray[i];

            if(arbitratorToCheck == tempArbitratorAddress){
                return true;
            }
        }

        return false;
    }

    function getInitializedEvidenceArray(string calldata transactionId) private returns (string[] storage evidenceArray){
        evidenceArray = transactionIDToEvidenceMap[transactionId];

        uint8 evidenceArrayLength = uint8(evidenceArray.length);

        if(evidenceArrayLength == 0){
            evidenceArray.push('');
            evidenceArray.push('');
        }
    }

    function submitEvidence(string calldata transactionId, string calldata evidenceURL) external{
        address[] memory transactionParties = RNR_ESCROW.getTransactionParties(transactionId);

        require(
            (msg.sender == transactionParties[0]) || (msg.sender == transactionParties[1]), 
            "Error: msg.sender is not the sender or receiver of the transaction. Evidence rejected."
        );

        uint8 evidenceArrayIndex;

        if(msg.sender == transactionParties[0]){
            evidenceArrayIndex = 0;
        }
        else if(msg.sender == transactionParties[1]){
            evidenceArrayIndex = 1;
        }

        string[] storage evidenceArray = getInitializedEvidenceArray(transactionId);
        bytes memory existingEvidence = bytes(evidenceArray[evidenceArrayIndex]);

        require(
            existingEvidence.length == 0,
            "Error: Evidence can only be submitted once for an escrow transaction."
        );

        evidenceArray[evidenceArrayIndex] = evidenceURL;
    }
}

//contract Deployer {
//   event ContractDeployed(address deployedContractAddress);

//   constructor() {
//     emit ContractDeployed(
//       Create2.deploy(
//            0, 
//            "Escrow Helper v0.01 Alpha", 
//            type(EscrowHelpers).creationCode
//        )
//      );
//   }
//}