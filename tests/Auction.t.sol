// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../contracts/Auction.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

/*───────────────────────── MOCKS ──────────────────────────*/

contract MockERC721 is ERC721 {
    uint256 private _id;

    constructor() ERC721("Mock", "MCK") {}

    function mint(address to) external returns (uint256) {
        _id += 1;
        _mint(to, _id);
        return _id;
    }
}

/*───────────────────────── TESTS ──────────────────────────*/

contract AuctionTest is Test, ERC721Holder {
    /*//////////////////////////////////////////////////////////////*/
    /*                            SET-UP                            */
    /*//////////////////////////////////////////////////////////////*/

    uint256 private constant DURATION = 1 days;
    uint256 private constant MIN_INCREMENT = 0.1 ether;

    address private OWNER = address(this);
    address private constant ALICE = address(0xA1);
    address private constant BOB = address(0xB2);

    MockERC721 private nft;
    Auction private auction;
    uint256 private tokenId;

    function setUp() public {
        nft = new MockERC721();
        tokenId = nft.mint(OWNER);

        auction = new Auction(
            OWNER,
            address(nft),
            tokenId,
            DURATION,
            MIN_INCREMENT
        );

        // Fund bidders
        vm.deal(ALICE, 10 ether);
        vm.deal(BOB, 10 ether);
    }

    /*───────────────────────── START ──────────────────────────*/

    function testStart_Succeeds_TransfersNFTAndSetsState() public {
        nft.approve(address(auction), tokenId);

        vm.expectEmit();
        emit Auction.AuctionStarted(
            block.timestamp,
            block.timestamp + DURATION
        );

        auction.start();

        // Contract owns NFT
        assertEq(nft.ownerOf(tokenId), address(auction));
        // Auction is active
        assertTrue(auction.isStarted());
    }

    function testStart_Reverts_NotApproved() public {
        vm.expectRevert(Auction.NotApprovedForNFTError.selector);
        auction.start();
    }

    function testStart_Reverts_AlreadyStarted() public {
        nft.approve(address(auction), tokenId);
        auction.start();
        vm.expectRevert(Auction.AuctionAlreadyStartedError.selector);
        auction.start();
    }

    /*───────────────────────── BID ──────────────────────────*/

    function _startAuction() internal {
        nft.approve(address(auction), tokenId);
        auction.start();
    }

    function testBid_Succeeds_FirstBid() public {
        _startAuction();
        vm.prank(ALICE);
        auction.bid{value: 1 ether}();

        assertEq(auction.highestBidder(), ALICE);
        assertEq(auction.highestBid(), 1 ether);
    }

    function testBid_Succeeds_SecondBidAndExtension() public {
        _startAuction();

        vm.prank(ALICE);
        auction.bid{value: 1 ether}();

        // Warp close to end to trigger extension
        vm.warp(block.timestamp + DURATION - 1 minutes);
        uint256 oldEnd = auction.endAt();

        vm.prank(BOB);
        auction.bid{value: 1 ether + MIN_INCREMENT}();

        assertGt(auction.endAt(), oldEnd); // auction extended
        assertEq(auction.highestBidder(), BOB);
    }

    function testBid_Reverts_NotStarted() public {
        vm.prank(ALICE);
        vm.expectRevert(Auction.AuctionNotStartedError.selector);
        auction.bid{value: 1 ether}();
    }

    function testBid_Reverts_BidTooLow() public {
        _startAuction();
        vm.prank(ALICE);
        auction.bid{value: 1 ether}();

        vm.prank(BOB);
        vm.expectRevert(Auction.BidTooLowError.selector);
        auction.bid{value: 1 ether + MIN_INCREMENT - 1}();
    }

    function testBid_Reverts_AuctionEnded() public {
        _startAuction();
        vm.warp(block.timestamp + DURATION + 1);
        vm.prank(ALICE);
        vm.expectRevert(Auction.AuctionEndedError.selector);
        auction.bid{value: 1 ether}();
    }

    /*───────────────────────── WITHDRAW ──────────────────────────*/

    function testWithdraw_Succeeds() public {
        _startAuction();
        vm.prank(ALICE);
        auction.bid{value: 1 ether}();

        vm.prank(BOB);
        auction.bid{value: 1 ether + MIN_INCREMENT}();

        uint256 balBefore = ALICE.balance;
        vm.prank(ALICE);
        auction.withdraw();
        uint256 balAfter = ALICE.balance;

        assertEq(balAfter - balBefore, 1 ether);
    }

    function testWithdraw_Reverts_NoBalance() public {
        _startAuction();
        vm.expectRevert(Auction.NoBalanceError.selector);
        auction.withdraw();
    }

    /*───────────────────────── CANCEL ──────────────────────────*/

    function testCancelAuction_Succeeds_NoBids() public {
        _startAuction();
        auction.cancelAuction();
        assertTrue(auction.isEnded());
        assertEq(nft.ownerOf(tokenId), OWNER);
    }

    function testCancelAuction_Reverts_WithBid() public {
        _startAuction();
        vm.prank(ALICE);
        auction.bid{value: 1 ether}();

        vm.expectRevert(Auction.BidExistsError.selector);
        auction.cancelAuction();
    }

    /*───────────────────────── END ──────────────────────────*/

    function testEnd_Succeeds_WithBid() public {
        _startAuction();
        vm.prank(ALICE);
        auction.bid{value: 1 ether}();

        vm.warp(block.timestamp + DURATION + 1);
        uint256 sellerBalBefore = OWNER.balance;
        auction.end();
        uint256 sellerBalAfter = OWNER.balance;

        assertEq(sellerBalAfter - sellerBalBefore, 1 ether);
        assertEq(nft.ownerOf(tokenId), ALICE);
        assertTrue(auction.isEnded());
    }

    function testEnd_Succeeds_NoBid() public {
        _startAuction();
        vm.warp(block.timestamp + DURATION + 1);
        auction.end();
        assertEq(nft.ownerOf(tokenId), OWNER);
    }

    function testEnd_Reverts_NotActive() public {
        vm.expectRevert(Auction.AuctionNotActiveError.selector);
        auction.end();
    }

    function testEnd_Reverts_TimeNotOver() public {
        _startAuction();
        vm.warp(block.timestamp + DURATION - 10 seconds);
        vm.expectRevert(Auction.AuctionTimeNotOverError.selector);
        auction.end();
    }

    function testIsEnded_Succeeds() public {
        _startAuction();
        vm.warp(block.timestamp + DURATION + 1);
        auction.end();
        assertTrue(auction.isEnded());
    }

    // Allow contract to receive ETH silently in tests
    receive() external payable {}
    fallback() external payable {}
}
