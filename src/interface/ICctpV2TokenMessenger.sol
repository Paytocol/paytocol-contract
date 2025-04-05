// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ICctpV2TokenMessenger {
    function depositForBurnWithHook(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold,
        bytes calldata hookData
    ) external;
}
