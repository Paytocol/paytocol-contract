// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Test, console } from "forge-std/Test.sol";

import { Paytocol } from "src/Paytocol.sol";
import { ICctpV2MessageTransmitter } from
    "src/interface/ICctpV2MessageTransmitter.sol";
import { ICctpV2TokenMessenger } from "src/interface/ICctpV2TokenMessenger.sol";
import { AddressUtil } from "src/library/AddressUtil.sol";
import { BurnMessageV2 } from "src/library/cctp/BurnMessageV2.sol";
import { MessageV2 } from "src/library/cctp/MessageV2.sol";

contract Token is ERC20 {
    constructor(uint256 initialSupply) ERC20("Token", "TKN") {
        _mint(msg.sender, initialSupply);
    }
}

contract CctpV2MessageTransmitterStub is ICctpV2MessageTransmitter {
    event ReceiveMessage(bytes message, bytes attestation);

    IERC20 token;
    uint256 tokenAmount;

    constructor(IERC20 _token, uint256 _tokenAmount) {
        token = _token;
        tokenAmount = _tokenAmount;
    }

    function receiveMessage(bytes calldata message, bytes calldata attestation)
        external
        returns (bool success)
    {
        emit ReceiveMessage(message, attestation);
        token.transfer(msg.sender, tokenAmount);
        return true;
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

    address sender = makeAddr("sender");
    uint256 senderChainId = 11155111;
    uint32 senderDomainId = 0;

    address recipient = makeAddr("recipient");
    uint256 recipientChainId = 84532;
    uint32 recipientDomainId = 6;

    address recipientChainPaytocol = address(paytocol);

    uint256 startedAt = 0;
    uint256 interval = 10; // 10 secs
    uint32 intervalCount = 10;

    uint256 tokenAmountPerInterval = 10;
    uint256 tokenAmount = tokenAmountPerInterval * intervalCount;

    Token token = new Token(tokenAmount);

    CctpV2MessageTransmitterStub public cctpV2MessageTransmitter =
        new CctpV2MessageTransmitterStub(token, tokenAmount);
    CctpV2TokenMessengerStub public cctpV2TokenMessengerStub =
        new CctpV2TokenMessengerStub();

    uint256 cctpMaxFee = 1;
    uint32 cctpMinFinalityThreshold = 500;

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
    Paytocol.RelayStream relayStream = Paytocol.RelayStream(
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

    function testOpenStreamViaCctp() public {
        token.transfer(sender, tokenAmount);
        vm.prank(sender);
        token.approve(address(paytocol), tokenAmount);

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
            cctpMaxFee,
            cctpMinFinalityThreshold,
            abi.encode(relayStream)
        );

        vm.startPrank(sender);
        paytocol.openStreamViaCctp(
            cctpV2TokenMessengerStub,
            cctpMaxFee,
            cctpMinFinalityThreshold,
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

    function testRelayStreamViaCctp() public {
        token.transfer(address(cctpV2MessageTransmitter), tokenAmount);

        bytes memory burnMessage = this.formatBurnMessageForRelay(
            address(token),
            recipientChainPaytocol,
            tokenAmount,
            address(paytocol),
            cctpMaxFee,
            abi.encode(relayStream)
        );
        bytes memory message = this.formatMessageForRelay(
            senderDomainId,
            recipientDomainId,
            address(paytocol),
            recipientChainPaytocol,
            recipientChainPaytocol,
            cctpMinFinalityThreshold,
            burnMessage
        );
        bytes memory attestation = bytes("attestation");

        vm.expectEmit();
        emit CctpV2MessageTransmitterStub.ReceiveMessage(message, attestation);

        bytes32 relayStreamId = paytocol.relayStreamViaCctp(
            cctpV2MessageTransmitter, message, attestation
        );
        assertEq(relayStreamId, streamId);
        assertEq(token.balanceOf(address(paytocol)), tokenAmount);

        Paytocol.Stream memory stream = paytocol.getStream(relayStreamId);
        assertEq(stream.streamId, relayStreamId);

        {
            paytocol.claim(relayStreamId);
            assertEq(token.balanceOf(recipient), 0);
            assertEq(token.balanceOf(address(paytocol)), 100);
        }

        {
            vm.warp(interval * 3);
            paytocol.claim(relayStreamId);
            assertEq(token.balanceOf(recipient), 30);
            assertEq(token.balanceOf(address(paytocol)), 70);
        }

        {
            vm.warp(interval * 10);
            paytocol.claim(relayStreamId);
            assertEq(token.balanceOf(recipient), 100);
            assertEq(token.balanceOf(address(paytocol)), 0);
        }

        {
            vm.warp(interval * 20);
            paytocol.claim(relayStreamId);
            assertEq(token.balanceOf(recipient), 100);
            assertEq(token.balanceOf(address(paytocol)), 0);
        }
    }

    /* utils */

    function formatBurnMessageForRelay(
        address _burnToken,
        address _mintRecipient,
        uint256 _amount,
        address _messageSender,
        uint256 _maxFee,
        bytes calldata _hookData
    ) public pure returns (bytes memory) {
        return BurnMessageV2._formatMessageForRelay(
            1,
            _burnToken.toBytes32(),
            _mintRecipient.toBytes32(),
            _amount,
            _messageSender.toBytes32(),
            _maxFee,
            _hookData
        );
    }

    function formatMessageForRelay(
        uint32 _sourceDomain,
        uint32 _destinationDomain,
        address _sender,
        address _recipient,
        address _destinationCaller,
        uint32 _minFinalityThreshold,
        bytes calldata _messageBody
    ) public pure returns (bytes memory) {
        return MessageV2._formatMessageForRelay(
            1,
            _sourceDomain,
            _destinationDomain,
            _sender.toBytes32(),
            _recipient.toBytes32(),
            _destinationCaller.toBytes32(),
            _minFinalityThreshold,
            _messageBody
        );
    }
}
