// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract EscrowHelpers {
    // helper functions

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

    function substring(string memory str, uint256 startIndex, uint256 endIndex) pure external returns (string memory substr) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);

        for(uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }

        substr = string(result);
    }

    function stringToUint(string memory numString) external pure returns(uint256 val) {
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

    function stringToAddress(string memory str) external pure returns (address addr) {
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
}