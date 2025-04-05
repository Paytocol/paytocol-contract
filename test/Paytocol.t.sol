// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { Test, console } from "forge-std/Test.sol";
import { Paytocol } from "src/Paytocol.sol";
import { ICctpV2TokenMessenger } from "src/interface/ICctpV2TokenMessenger.sol";

contract Token is ERC20 {
    constructor(uint256 initialSupply) ERC20("Token", "TKN") {
        _mint(msg.sender, initialSupply);
    }
}

contract CctpV2TokenMessengerStub is ICctpV2TokenMessenger {
    event DepositForBurnWithHook(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold,
        bytes hookData
    );

    function depositForBurnWithHook(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold,
        bytes calldata hookData
    ) external {
        emit DepositForBurnWithHook(
            amount,
            destinationDomain,
            mintRecipient,
            burnToken,
            destinationCaller,
            maxFee,
            minFinalityThreshold,
            hookData
        );
    }
}

contract PaytocolTest is Test {
    Paytocol public paytocol = new Paytocol();
    CctpV2TokenMessengerStub public cctpV2TokenMessengerStub =
        new CctpV2TokenMessengerStub();

    function testOpenStreamViaCctp() public {
        address sender = makeAddr("sender");
        address recipient = makeAddr("recipient");
        uint32 recipientDomainId = 6;
        address recipientDomainPaytocol = makeAddr("recipientDomainPaytocol");

        uint256 tokenAmount = 100;
        vm.startPrank(sender);
        Token token = new Token(tokenAmount);
        token.approve(address(paytocol), tokenAmount);
        vm.stopPrank();

        uint256 startedAt = vm.getBlockTimestamp();
        uint256 interval = 10; // 10 secs
        uint8 intervalCount = 10;
        uint256 tokenAmountPerInterval = tokenAmount / intervalCount;

        vm.expectEmit();
        emit CctpV2TokenMessengerStub.DepositForBurnWithHook(
            tokenAmountPerInterval * intervalCount,
            recipientDomainId,
            bytes32(bytes20(recipientDomainPaytocol)),
            address(token),
            bytes32(bytes20(address(0))),
            0,
            2000,
            bytes("")
        );

        vm.startPrank(sender);
        paytocol.openStreamViaCctp(
            cctpV2TokenMessengerStub,
            recipient,
            recipientDomainId,
            recipientDomainPaytocol,
            token,
            tokenAmountPerInterval,
            startedAt,
            interval,
            intervalCount
        );
    }
}
