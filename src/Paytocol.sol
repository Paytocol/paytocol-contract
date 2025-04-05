// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from
    "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ICctpV2TokenMessenger } from "src/interface/ICctpV2TokenMessenger.sol";

contract Paytocol {
    using SafeERC20 for IERC20;

    function openStreamViaCctp(
        ICctpV2TokenMessenger cctpV2TokenMessenger,
        address recipient,
        uint32 recipientDomainId,
        address recipientDomainPaytocol,
        IERC20 token,
        uint256 tokenAmountPerInterval,
        uint256 startedAt,
        uint256 interval,
        uint8 intervalCount
    ) external {
        uint256 tokenAmount = tokenAmountPerInterval * intervalCount;
        token.safeTransferFrom(msg.sender, address(this), tokenAmount);
        token.approve(address(cctpV2TokenMessenger), tokenAmount);

        cctpV2TokenMessenger.depositForBurnWithHook({
            amount: tokenAmount,
            destinationDomain: recipientDomainId,
            mintRecipient: bytes32(bytes20(recipientDomainPaytocol)),
            burnToken: address(token),
            destinationCaller: bytes32(bytes20(address(0))),
            maxFee: 0,
            minFinalityThreshold: 2000,
            hookData: bytes("")
        });
    }
}
