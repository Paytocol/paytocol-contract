// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ICctpV2MessageTransmitter {
    function receiveMessage(bytes calldata message, bytes calldata attestation)
        external
        returns (bool success);
}
