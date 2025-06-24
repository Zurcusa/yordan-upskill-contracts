// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import {EnvLoader} from "./EnvLoader.s.sol";
import {ZurcusNFT} from "../contracts/ZurcusNFT.sol";

/// @title  NFTDeployWithPublicSaleScript
/// @notice Deployment script for the ZurcusNFT ERC721 contract
/// @dev    Requires environment variables to be set in `.env` file
contract NFTDeployWithPublicSaleScript is EnvLoader {
    ZurcusNFT public nft;
    uint256 private privateKey;
    string private name;
    string private symbol;
    string private baseUri;
    uint256 private initialPrice;
    uint256 private maxSupply;

    /// @notice Executes the deployment of the ZurcusNFT contract
    /// @dev    Requires the following environment variables:
    /// - TEST_ACCOUNT_1_PRIVATE_KEY
    /// - NFT_NAME
    /// - NFT_SYMBOL
    /// - NFT_BASE_URI
    /// - NFT_INITIAL_PRICE
    /// - NFT_MAX_SUPPLY
    function run() public {
        loadEnvVars();

        vm.startBroadcast(privateKey);

        nft = new ZurcusNFT(name, symbol, baseUri, initialPrice, maxSupply);
        enablePublicSale();

        vm.stopBroadcast();
    }

    function loadEnvVars() internal override {
        privateKey = getEnvPrivateKey("TEST_ACCOUNT_1_PRIVATE_KEY");
        name = getEnvString("NFT_NAME");
        symbol = getEnvString("NFT_SYMBOL");
        baseUri = getEnvString("NFT_BASE_URI");
        initialPrice = getEnvUint("NFT_INITIAL_PRICE");
        maxSupply = getEnvUint("NFT_MAX_SUPPLY");
    }

    function enablePublicSale() internal {
        nft.setSalePhase(uint8(ZurcusNFT.SalePhase.PublicSale));
    }
}
