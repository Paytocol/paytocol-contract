// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Test, console } from "forge-std/Test.sol";

import { Paytocol } from "src/Paytocol.sol";
import { ICctpV2TokenMessenger } from "src/interface/ICctpV2TokenMessenger.sol";
import { AddressUtil } from "src/library/AddressUtil.sol";

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
        IERC20(burnToken).transferFrom(msg.sender, address(this), amount);
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
    using AddressUtil for address;

    Paytocol public paytocol = new Paytocol();
    CctpV2TokenMessengerStub public cctpV2TokenMessengerStub =
        new CctpV2TokenMessengerStub();

    function testOpenStreamViaCctp() public {
        address sender = makeAddr("sender");
        address recipient = makeAddr("recipient");
        uint256 recipientChainId = 84532;
        uint32 recipientDomainId = 6;
        address recipientChainPaytocol = makeAddr("recipientDomainPaytocol");

        uint256 tokenAmount = 100;
        vm.startPrank(sender);
        Token token = new Token(tokenAmount);
        token.approve(address(paytocol), tokenAmount);
        vm.stopPrank();

        uint256 startedAt = vm.getBlockTimestamp();
        uint256 interval = 10; // 10 secs
        uint32 intervalCount = 10;
        uint256 tokenAmountPerInterval = tokenAmount / intervalCount;

        bytes32 streamId = keccak256(
            abi.encode(
                sender,
                paytocol.getChainId(),
                recipient,
                recipientChainId,
                token,
                tokenAmountPerInterval,
                startedAt,
                interval,
                intervalCount
            )
        );
        Paytocol.RelayStream memory relayStream = Paytocol.RelayStream(
            streamId,
            sender,
            paytocol.getChainId(),
            recipient,
            recipientChainId,
            token,
            tokenAmountPerInterval,
            startedAt,
            interval,
            intervalCount
        );

        vm.expectEmit();
        emit Paytocol.StreamRelayed(
            streamId, paytocol.getChainId(), recipientChainId
        );

        vm.expectEmit();
        emit CctpV2TokenMessengerStub.DepositForBurnWithHook(
            tokenAmountPerInterval * intervalCount,
            recipientDomainId,
            recipientChainPaytocol.toBytes32(),
            address(token),
            recipientChainPaytocol.toBytes32(),
            0,
            2000,
            abi.encode(relayStream)
        );

        vm.startPrank(sender);
        paytocol.openStreamViaCctp(
            cctpV2TokenMessengerStub,
            recipient,
            recipientChainId,
            recipientChainPaytocol,
            token,
            tokenAmountPerInterval,
            startedAt,
            interval,
            intervalCount
        );

        assertEq(token.balanceOf(sender), 0);
        assertEq(token.balanceOf(address(paytocol)), 0);
        assertEq(
            token.balanceOf(address(cctpV2TokenMessengerStub)), tokenAmount
        );
    }
}
