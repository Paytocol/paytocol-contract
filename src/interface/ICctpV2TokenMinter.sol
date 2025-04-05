// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ICctpV2TokenMinter {
    function getLocalToken(uint32 remoteDomain, bytes32 remoteToken)
        external
        view
        returns (address);
}
