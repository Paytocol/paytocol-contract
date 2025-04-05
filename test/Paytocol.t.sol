// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { Test, console } from "forge-std/Test.sol";
import { Paytocol } from "src/Paytocol.sol";

contract Token is ERC20 {
    constructor(uint256 initialSupply) ERC20("Token", "TKN") {
        _mint(msg.sender, initialSupply);
    }
}

contract PaytocolTest is Test {
    Paytocol public paytocol = new Paytocol();

    function testStreamLifecycleOnSameChain() public {
        address sender = makeAddr("sender");
        address recipient = makeAddr("recipient");

        uint256 recipientChainId;
        assembly {
            recipientChainId := chainid()
        }

        uint256 tokenAmount = 100;
        vm.startPrank(sender);
        Token token = new Token(tokenAmount);
        token.approve(address(paytocol), tokenAmount);
        vm.stopPrank();

        uint256 startedAt = vm.getBlockTimestamp();
        uint256 interval = 10; // 10 secs
        uint8 intervalCount = 10;
        uint256 tokenAmountPerInterval = tokenAmount / intervalCount;

        bytes32 streamId = keccak256(
            abi.encode(
                sender,
                recipient,
                recipientChainId,
                token,
                tokenAmountPerInterval,
                startedAt,
                interval,
                intervalCount
            )
        );

        vm.expectEmit();
        emit Paytocol.StreamOpened(streamId, sender, recipient);

        vm.prank(sender);
        paytocol.openStream(
            recipient,
            recipientChainId,
            token,
            tokenAmountPerInterval,
            startedAt,
            interval,
            intervalCount
        );
    }
}
