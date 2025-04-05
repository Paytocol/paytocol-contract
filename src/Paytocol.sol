// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { Test, console } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from
    "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ICctpV2MessageTransmitter } from
    "src/interface/ICctpV2MessageTransmitter.sol";
import { ICctpV2TokenMessenger } from "src/interface/ICctpV2TokenMessenger.sol";
import { ICctpV2TokenMinter } from "src/interface/ICctpV2TokenMinter.sol";
import { AddressUtil } from "src/library/AddressUtil.sol";
import { TypedMemView } from "src/library/TypedMemView.sol";
import { BurnMessageV2 } from "src/library/cctp/BurnMessageV2.sol";
import { MessageV2 } from "src/library/cctp/MessageV2.sol";

contract Paytocol {
    using AddressUtil for address;
    using SafeERC20 for IERC20;
    using TypedMemView for bytes;
    using TypedMemView for bytes29;

    error ChainUnsupported();

    event StreamRelayed(
        bytes32 indexed streamId,
        uint256 indexed senderChainId,
        uint256 indexed recipientChainId
    );
    event StreamClaimed(
        bytes32 indexed streamId, uint256 amount, uint256 timestamp
    );
    event StreamOpened(
        bytes32 indexed streamId,
        address indexed sender,
        address indexed recipient
    );

    struct RelayStream {
        bytes32 streamId;
        address sender;
        uint256 senderChainId;
        address recipient;
        uint256 recipientChainId;
        IERC20 token;
        uint256 tokenAmountPerInterval;
        uint256 startedAt;
        uint256 interval;
        uint32 intervalCount;
    }

    struct Stream {
        bytes32 streamId;
        address sender;
        uint256 senderChainId;
        address recipient;
        uint256 recipientChainId;
        IERC20 token;
        uint256 tokenAmountPerInterval;
        uint256 tokenAmountClaimed;
        uint256 lastClaimedAt;
        uint256 startedAt;
        uint256 interval;
        uint32 intervalCount;
    }

    mapping(bytes32 streamId => Stream) private streams;

    function openStreamViaCctp(
        ICctpV2TokenMessenger cctpV2TokenMessenger,
        uint256 cctpMaxFee,
        uint32 cctpMinFinalityThreshold,
        address recipient,
        uint256 recipientChainId,
        address recipientChainPaytocol,
        IERC20 token,
        uint256 tokenAmountPerInterval,
        uint256 startedAt,
        uint256 interval,
        uint32 intervalCount
    ) external {
        uint256 tokenAmount = tokenAmountPerInterval * intervalCount;

        token.safeTransferFrom(msg.sender, address(this), tokenAmount);
        token.approve(address(cctpV2TokenMessenger), tokenAmount);

        bytes32 streamId = keccak256(
            abi.encode(
                msg.sender,
                getChainId(),
                recipient,
                recipientChainId,
                token,
                tokenAmountPerInterval,
                startedAt,
                interval,
                intervalCount
            )
        );
        RelayStream memory relayStream = RelayStream(
            streamId,
            msg.sender,
            getChainId(),
            recipient,
            recipientChainId,
            token,
            tokenAmountPerInterval,
            startedAt,
            interval,
            intervalCount
        );
        emit StreamRelayed(streamId, getChainId(), recipientChainId);

        cctpV2TokenMessenger.depositForBurnWithHook({
            amount: tokenAmount,
            destinationDomain: getCctpDomainId(recipientChainId),
            mintRecipient: recipientChainPaytocol.toBytes32(),
            burnToken: address(token),
            destinationCaller: recipientChainPaytocol.toBytes32(),
            maxFee: cctpMaxFee,
            minFinalityThreshold: cctpMinFinalityThreshold,
            hookData: abi.encode(relayStream)
        });
    }

    function relayStreamViaCctp(
        ICctpV2MessageTransmitter cctpV2MessageTransmitter,
        ICctpV2TokenMinter cctpV2TokenMinter,
        bytes calldata message,
        bytes calldata attestation
    ) external returns (bytes32 streamId) {
        // Validate message
        bytes29 msgRef = message.ref(0);
        MessageV2._validateMessageFormat(msgRef);
        require(MessageV2._getVersion(msgRef) == 1, "Invalid message version");

        // Validate burn message
        bytes29 msgBody = MessageV2._getMessageBody(msgRef);
        BurnMessageV2._validateBurnMessageFormat(msgBody);
        require(
            BurnMessageV2._getVersion(msgBody) == 1,
            "Invalid message body version"
        );

        // Relay message
        bool relaySuccess =
            cctpV2MessageTransmitter.receiveMessage(message, attestation);
        require(relaySuccess, "Receive message failed");

        // Validate hook data
        bytes29 hookData = BurnMessageV2._getHookData(msgBody);
        require(hookData.isValid(), "Invalid hook data");

        (RelayStream memory relayStream) =
            abi.decode(hookData.clone(), (RelayStream));

        address localToken = cctpV2TokenMinter.getLocalToken(
            MessageV2._getSourceDomain(msgRef),
            address(relayStream.token).toBytes32()
        );

        streams[relayStream.streamId] = Stream(
            relayStream.streamId,
            relayStream.sender,
            relayStream.senderChainId,
            relayStream.recipient,
            relayStream.recipientChainId,
            IERC20(localToken),
            relayStream.tokenAmountPerInterval,
            0,
            0,
            relayStream.startedAt,
            relayStream.interval,
            relayStream.intervalCount
        );
        emit StreamOpened(
            relayStream.streamId, relayStream.sender, relayStream.recipient
        );

        return relayStream.streamId;
    }

    function claim(bytes32 streamId) external {
        Stream storage s = streams[streamId];
        require(s.streamId != bytes32(""), "Stream not found");
        require(s.startedAt <= block.timestamp, "Stream not able to claim yet");

        if (s.tokenAmountClaimed == s.tokenAmountPerInterval * s.intervalCount)
        {
            return;
        }

        uint256 elapsed = block.timestamp - s.startedAt;
        uint256 intervalCount = elapsed / s.interval;
        if (intervalCount > s.intervalCount) {
            intervalCount = s.intervalCount;
        }
        uint256 tokenAmountClaimable =
            s.tokenAmountPerInterval * intervalCount - s.tokenAmountClaimed;

        s.tokenAmountClaimed += tokenAmountClaimable;
        s.lastClaimedAt = block.timestamp;

        emit StreamClaimed(s.streamId, tokenAmountClaimable, block.timestamp);

        s.token.safeTransfer(s.recipient, tokenAmountClaimable);
    }

    function getStream(bytes32 streamId)
        external
        view
        returns (Stream memory)
    {
        Stream storage s = streams[streamId];
        return s;
    }

    function getChainId() public view returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }

    function getCctpDomainId(uint256 chainId)
        public
        pure
        returns (uint32 domainId)
    {
        if (chainId == 11155111 || chainId == 1) {
            return 0;
        }
        if (chainId == 84532 || chainId == 8453) {
            return 6;
        }
        revert ChainUnsupported();
    }
}
