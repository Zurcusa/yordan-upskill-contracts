// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import {EnvLoader} from "./EnvLoader.s.sol";
import {AuctionFactory} from "../contracts/AuctionFactory.sol";
import {ZurcusNFT} from "../contracts/ZurcusNFT.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title  MintAndCreateAuction1Script
/// @notice Mints an NFT and creates an auction for it using the AuctionFactory
/// @dev    Requires environment variables to be set in `.env` file
contract MintAndCreateAuction1Script is EnvLoader {
    AuctionFactory private factory;
    ZurcusNFT private nft;
    uint256 private mintPrice;
    uint256 private auctionDuration;
    uint256 private minBidIncrement;
    uint256 private privateKey;
    address private sender;

    /// @notice Deploys a new English auction for a newly minted NFT
    /// @dev    Requires the following environment variables:
    /// - TEST_ACCOUNT_1_PRIVATE_KEY: Private key used for broadcasting transactions
    /// - AUCTION_FACTORY_ADDRESS: Address of the deployed AuctionFactory contract
    /// - NFT_CONTRACT_ADDRESS: Address of the deployed ZurcusNFT contract
    /// - MINT_PUBLIC_PRICE: Price required to mint an NFT during the public sale
    /// - AUCTION_DURATION: Duration (in seconds) for the auction
    /// - AUCTION_MIN_BID_INCREMENT: Minimum bid increment for the auction
    /// This function mints an NFT, creates an auction, and approves the auction to transfer the token.
    function run() public {
        loadEnvVars();

        vm.startBroadcast(privateKey);

        uint256 tokenId = mintNFT();
        address auctionAddress = deployAuction(tokenId);
        approveAuction(tokenId, auctionAddress);

        console.log("Auction1 deployed at:", address(auctionAddress));

        vm.stopBroadcast();
    }

    function loadEnvVars() internal override {
        privateKey = getEnvPrivateKey("TEST_ACCOUNT_1_PRIVATE_KEY");
        sender = vm.addr(privateKey);

        factory = AuctionFactory(getEnvAddress("AUCTION_FACTORY_ADDRESS"));
        nft = ZurcusNFT(payable(getEnvAddress("NFT_CONTRACT_ADDRESS")));
        mintPrice = getEnvUint("MINT_PUBLIC_PRICE");
        auctionDuration = getEnvUint("AUCTION_DURATION");
        minBidIncrement = getEnvUint("AUCTION_MIN_BID_INCREMENT");
    }

    /// @notice         Mints one NFT during the public sale
    /// @dev            Sends `mintPrice` ETH along with the transaction
    /// @return tokenId The newly minted token's ID
    function mintNFT() internal returns (uint256 tokenId) {
        require(sender.balance >= mintPrice, "Insufficient ETH for mint");

        nft.setSalePhase(uint8(ZurcusNFT.SalePhase.PublicSale));
        nft.mint{value: mintPrice}(sender);
        tokenId = nft.mintedCount();
    }

    /// @notice               Approves the deployed auction to transfer the minted NFT
    /// @param tokenId        The ID of the NFT to approve
    /// @param auctionAddress The address of the deployed auction contract
    function approveAuction(uint256 tokenId, address auctionAddress) internal {
        nft.approve(auctionAddress, tokenId);
    }

    /// @notice                Deploys an English auction for the minted NFT
    /// @param tokenId         The ID of the NFT to auction
    /// @return auctionAddress The address of the newly created auction contract
    function deployAuction(
        uint256 tokenId
    ) internal returns (address auctionAddress) {
        auctionAddress = factory.createAuction(
            address(nft),
            tokenId,
            auctionDuration,
            minBidIncrement
        );
    }
}
