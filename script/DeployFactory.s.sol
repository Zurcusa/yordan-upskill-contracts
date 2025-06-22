// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import {EnvLoader} from "./EnvLoader.s.sol";
import {AuctionFactory} from "../contracts/AuctionFactory.sol";

/// @title  DeployAuctionFactoryScript
/// @notice Deployment script for the AuctionFactory contract
/// @dev    Requires environment variables to be set in `.env` file
contract DeployAuctionFactoryScript is EnvLoader {
    AuctionFactory public factory;
    uint256 private privateKey;

    /// @notice Executes the deployment of the AuctionFactory contract
    /// @dev    Requires the `TEST_ACCOUNT_1_PRIVATE_KEY` environment variables
    function run() public {
        loadEnvVars();

        vm.startBroadcast(privateKey);
        factory = new AuctionFactory();
        vm.stopBroadcast();

        console.log("AuctionFactory deployed at:", address(factory));
    }

    function loadEnvVars() internal override {
        privateKey = getEnvPrivateKey("TEST_ACCOUNT_1_PRIVATE_KEY");
    }
}
