// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

library AddressUtil {
    /**
     * @notice Converts an address to bytes32 by left-padding with zeros
     * (alignment preserving cast.)
     * @param addr The address to convert to bytes32
     */
    function toBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    /**
     * @notice Converts bytes32 to address (alignment preserving cast.)
     * @dev Warning: it is possible to have different input values _buf map to
     * the same address.
     * For use cases where this is not acceptable, validate that the first 12
     * bytes of _buf are zero-padding.
     * @param _buf the bytes32 to convert to address
     */
    function toAddress(bytes32 _buf) internal pure returns (address) {
        return address(uint160(uint256(_buf)));
    }
}
