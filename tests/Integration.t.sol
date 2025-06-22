// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../contracts/ZurcusNFT.sol";
import "../contracts/AuctionFactory.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

contract IntegrationTest is Test, ERC721Holder {
    /*───────────────────────── CONSTANTS ──────────────────────────*/
    uint256 private constant PRICE = 1 ether;
    uint256 private constant MAX_SUPPLY = 5;
    uint256 private constant DURATION = 1 days;
    uint256 private constant MIN_INC = 0.1 ether;

    string private constant NAME = "Zurcus";
    string private constant SYMBOL = "ZRC";
    string private constant BASE_URI = "ipfs://base/";

    address private OWNER = address(this);
    address private constant ALICE = address(0xA1);
    address private constant BOB = address(0xB2);

    ZurcusNFT private nft;
    AuctionFactory private factory;

    function setUp() public {
        nft = new ZurcusNFT(NAME, SYMBOL, BASE_URI, PRICE, MAX_SUPPLY);
        factory = new AuctionFactory();

        vm.deal(ALICE, 10 ether);
        vm.deal(BOB, 10 ether);
    }

    /*───────────────────────── FULL FLOW ──────────────────────────*/
    function testEndToEnd_AuctionFlow() public {
        /*---------- Private-phase mint ----------*/
        nft.addWhitelistedUser(ALICE);
        vm.prank(ALICE);
        nft.mint{value: PRICE}(ALICE); // tokenId 1

        /*---------- Switch to public and mint ----------*/
        nft.setSalePhase(uint8(ZurcusNFT.SalePhase.PublicSale));
        vm.prank(BOB);
        nft.mint{value: PRICE}(BOB); // tokenId 2

        /*---------- Create auction for tokenId 1 ----------*/
        // ALICE approves factory-created auction later; first deploy auction
        vm.prank(ALICE);
        address auctionAddr = factory.createAuction(
            address(nft),
            1,
            DURATION,
            MIN_INC
        );
        Auction auction = Auction(payable(auctionAddr));

        // ALICE approves auction and owner starts it (owner is ALICE of tokenId?) Actually seller must be ALICE.
        vm.prank(ALICE);
        nft.approve(auctionAddr, 1);

        vm.prank(ALICE);
        auction.start();

        /*---------- Bidding ----------*/
        vm.prank(ALICE);
        auction.bid{value: 1 ether}();

        vm.prank(BOB);
        auction.bid{value: 1 ether + MIN_INC}();

        /*---------- Finalize ----------*/
        vm.warp(block.timestamp + DURATION + 1);
        vm.prank(ALICE); // owner/seller ends
        auction.end();

        /*---------- Assertions ----------*/
        assertTrue(auction.isEnded(), "Auction should be ended");
        assertEq(nft.ownerOf(1), BOB, "Token should belong to highest bidder");
        assertEq(auction.highestBid(), 1 ether + MIN_INC);
        // Seller (ALICE) balance increased
        assertEq(
            ALICE.balance,
            10 ether - PRICE - (1 ether) + (1 ether + MIN_INC)
        );
    }

    /*───────────────────────── WITHDRAW FLOW ──────────────────────────*/

    function testEndToEnd_WithdrawFlow() public {
        // ALICE mints NFT #1 in private sale
        nft.addWhitelistedUser(ALICE);
        vm.prank(ALICE);
        nft.mint{value: PRICE}(ALICE);

        // Deploy auction for tokenId 1
        vm.prank(ALICE);
        address auctionAddr = factory.createAuction(
            address(nft),
            1,
            DURATION,
            MIN_INC
        );
        Auction auction = Auction(payable(auctionAddr));

        // ALICE approves & starts auction
        vm.prank(ALICE);
        nft.approve(auctionAddr, 1);
        vm.prank(ALICE);
        auction.start();

        address CAROL = address(0xC3);

        // BOB bids then CAROL overbids
        vm.deal(CAROL, 10 ether);
        vm.prank(BOB);
        auction.bid{value: 1 ether}();
        vm.prank(CAROL);
        auction.bid{value: 1 ether + MIN_INC}();

        // End auction
        vm.warp(block.timestamp + DURATION + 1);
        vm.prank(ALICE);
        auction.end();

        // BOB withdraws refund
        uint256 balBefore = BOB.balance;
        vm.prank(BOB);
        auction.withdraw();
        uint256 balAfter = BOB.balance;

        assertEq(balAfter - balBefore, 1 ether, "Refund incorrect");
        assertEq(nft.ownerOf(1), CAROL, "NFT owner mismatch");
        assertTrue(auction.isEnded());
    }

    /*───────────────────────── NO-BID FLOW ──────────────────────────*/

    function testEndToEnd_NoBidFlow() public {
        // ALICE mints tokenId 1 in private sale
        nft.addWhitelistedUser(ALICE);
        vm.prank(ALICE);
        nft.mint{value: PRICE}(ALICE);

        // Deploy auction
        vm.prank(ALICE);
        address auctionAddr = factory.createAuction(
            address(nft),
            1,
            DURATION,
            MIN_INC
        );
        Auction auction = Auction(payable(auctionAddr));

        vm.prank(ALICE);
        nft.approve(auctionAddr, 1);
        vm.prank(ALICE);
        auction.start();

        // Fast-forward past auction duration without any bids
        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(ALICE);
        auction.end();

        // Assertions
        assertTrue(auction.isEnded(), "Auction should be ended");
        assertEq(nft.ownerOf(1), ALICE, "NFT should return to seller");
        assertEq(auction.highestBid(), 0, "No bids expected");
    }

    // allow receive
    receive() external payable {}
}
