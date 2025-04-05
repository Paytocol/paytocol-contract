// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from
    "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Paytocol {
    event StreamOpened(
        bytes32 indexed streamId,
        address indexed sender,
        address indexed recipient
    );

    function openStream(
        address recipient,
        uint256 recipientChainId,
        IERC20 token,
        uint256 tokenAmountPerInterval,
        uint256 startedAt,
        uint256 interval,
        uint8 intervalCount
    ) external returns (bytes32 streamId) {
        streamId = keccak256(
            abi.encode(
                msg.sender,
                recipient,
                recipientChainId,
                token,
                tokenAmountPerInterval,
                startedAt,
                interval,
                intervalCount
            )
        );
        emit StreamOpened(streamId, msg.sender, recipient);

        return streamId;
    }
}
