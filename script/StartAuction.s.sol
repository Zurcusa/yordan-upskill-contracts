// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import {EnvLoader} from "./EnvLoader.s.sol";
import {Auction} from "../contracts/Auction.sol";

/// @title  StartAuction1Script
/// @notice A script to start a specific EnglishAuction contract using a private key from environment
/// @dev    Requires environment variables to be set in `.env` file
contract StartAuction1Script is EnvLoader {
    uint256 private privateKey;
    address private auctionAddress;

    /// @notice Runs the broadcast script to call `start()` on a deployed auction
    /// @dev    Requires the `TEST_ACCOUNT_1_PRIVATE_KEY` and `AUCTION_1_ADDRESS` environment variables
    function run() public {
        loadEnvVars();

        vm.startBroadcast(privateKey);
        Auction(payable(auctionAddress)).start();
        vm.stopBroadcast();
    }

    function loadEnvVars() internal override {
        privateKey = getEnvPrivateKey("TEST_ACCOUNT_1_PRIVATE_KEY");
        auctionAddress = getEnvAddress("AUCTION_1_ADDRESS");
    }
}
