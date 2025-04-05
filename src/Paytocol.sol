// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from
    "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ICctpV2TokenMessenger } from "src/interface/ICctpV2TokenMessenger.sol";

contract Paytocol {
    using SafeERC20 for IERC20;

    error ChainUnsupported();

    event StreamRelayed(
        bytes32 indexed streamId,
        uint256 indexed senderChainId,
        uint256 indexed recipientChainId
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

    function openStreamViaCctp(
        ICctpV2TokenMessenger cctpV2TokenMessenger,
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
            mintRecipient: bytes32(bytes20(recipientChainPaytocol)),
            burnToken: address(token),
            destinationCaller: bytes32(bytes20(recipientChainPaytocol)),
            maxFee: 0,
            minFinalityThreshold: 2000,
            hookData: abi.encode(relayStream)
        });
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
