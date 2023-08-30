//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import "../contracts/ERC20Burn.sol";
import "./helper.sol";


// Run with medusa fuzz --target contracts/ERC20Test.sol --deployment-order MyToken
/*
contract MyToken is ERC20Burn {
    
    // Test that the total supply is always below or equal to 10**18
    function fuzz_Supply() public returns(bool) {
        return totalSupply <= 10**18;
    }


    function calculateRootHash(bytes32 variableToSkip) public view returns (bytes32) {
        bytes32 rootHash;

        assembly {
            let slot := 0 // Initialize the slot variable

            // Slot layout (start with slot 0):
            // Slot N: a
            // Slot N+1: b
            // Slot N+2: c
            // Slot N+3: d
            // ...

            for {} lt(slot, sload(0)) {slot := add(slot, 1)} {
                // Load the value at the current slot
                let value := sload(slot)

                // If the current variable is not the one to skip, include it in the root hash
                if iszero(eq(slot, variableToSkip)) {
                    rootHash := keccak256(abi.encodePacked(rootHash, slot, value))
                }
            }
        }
        return rootHash;
    }
}
*/
contract test is PropertiesAsserts {

    uint256 a = 12;
    uint256 b = 21111;
    uint256 c = 223;
    uint256 d = 121211;

    function updateVar() public {
        bytes32 originalRootHash = calculateRootHash(bytes32(c));

        _updateC();

        bytes32 _b = calculateRootHash(bytes32(c));

        bytes32 newRootHash = calculateRootHash(bytes32(c)); // Step 2

        // Compare the original and updated root hashes
        //string memory aStr = PropertiesLibString.toString(originalRootHash);
        //string memory bStr = PropertiesLibString.toString(newRootHash);
        bytes memory assertMsg = abi.encodePacked(
                "Invalid: ",
                originalRootHash,
                "   !=   ",
                newRootHash
        );
        if (newRootHash != originalRootHash) {
            emit AssertGtFail(string(assertMsg));
            assert(false);
        }
    }

    function calculateRootHash(bytes32 variableToSkip) public view returns (bytes32) {
        bytes32 rootHash;

        assembly {
            let slot := 0 // Initialize the slot variable

            for {} lt(slot, sload(0)) {slot := add(slot, 1)} {
                // Load the value at the current slot
                let value := sload(slot)

                // If the current variable is not the one to skip, include it in the root hash
                if iszero(eq(slot, variableToSkip)) {
                    // Manually encode the arguments for keccak256
                    let encoded := mload(0x40) // Get the free memory pointer
                    mstore(encoded, rootHash) // Store rootHash in the first 32 bytes
                    mstore(add(encoded, 0x20), slot) // Store slot in the second 32 bytes
                    mstore(add(encoded, 0x40), value) // Store value in the third 32 bytes
                    rootHash := keccak256(encoded, 0x60) // Calculate the hash

                    // Free the allocated memory
                    mstore(0x40, add(encoded, 0x80))
                }
            }
        }
        return rootHash;
    }

    function _updateC() internal {
        c = 1;
    }
}