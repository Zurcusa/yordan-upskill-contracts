// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../contracts/AuctionFactory.sol";
import "../contracts/Auction.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "forge-std/console.sol";

/*───────────────────────── MOCK ──────────────────────────*/
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
contract AuctionFactoryTest is Test, ERC721Holder {
    uint256 private constant DURATION = 1 days;
    uint256 private constant MIN_INC = 0.1 ether;

    address private OWNER = address(this);
    address private constant ALICE = address(0xA1);

    AuctionFactory private factory;
    MockERC721 private nft;
    uint256 private tokenId;

    function setUp() public {
        factory = new AuctionFactory();
        nft = new MockERC721();
        tokenId = nft.mint(OWNER);

        vm.deal(ALICE, 10 ether);
    }

    /*───────────────────────── HELPERS ──────────────────────────*/
    function _slotKey(address _collection, uint256 _id) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_collection, _id));
    }

    /*───────────────────────── CREATE ──────────────────────────*/
    function testCreateAuction_Succeeds() public {
        bytes32 key = _slotKey(address(nft), tokenId);

        vm.expectEmit(false, true, true, true);
        emit AuctionFactory.AuctionCreated(address(0), OWNER, address(nft), tokenId, DURATION, MIN_INC);

        address auctionAddr = factory.createAuction(address(nft), tokenId, DURATION, MIN_INC);

        assertEq(factory.liveAuctions(key), auctionAddr);
        assertEq(factory.auctions(0), auctionAddr);
    }

    function testCreateAuction_Reverts_Duplicate() public {
        factory.createAuction(address(nft), tokenId, DURATION, MIN_INC);
        vm.expectRevert(AuctionFactory.AuctionExistsError.selector);
        factory.createAuction(address(nft), tokenId, DURATION, MIN_INC);
    }

    function testCreateAuction_Reverts_InvalidParams() public {
        vm.expectRevert(AuctionFactory.ZeroAddressError.selector);
        factory.createAuction(address(0), tokenId, DURATION, MIN_INC);

        vm.expectRevert(AuctionFactory.InvalidDurationError.selector);
        factory.createAuction(address(nft), tokenId, 0, MIN_INC);

        vm.expectRevert(AuctionFactory.InvalidMinBidIncrementError.selector);
        factory.createAuction(address(nft), tokenId, DURATION, 0);
    }

    /*───────────────────────── REMOVE ──────────────────────────*/
    function _deployAndEnd() internal returns (Auction auction) {
        address auctionAddr = factory.createAuction(address(nft), tokenId, DURATION, MIN_INC);
        auction = Auction(payable(auctionAddr));

        // start & end auction with no bids
        nft.approve(auctionAddr, tokenId);
        auction.start();
        vm.warp(block.timestamp + DURATION + 1);
        auction.end();
    }

    function testRemoveAuction_Succeeds() public {
        _deployAndEnd();
        bytes32 key = _slotKey(address(nft), tokenId);
        factory.removeAuction(address(nft), tokenId);
        assertEq(factory.liveAuctions(key), address(0));
    }

    function testRemoveAuction_Reverts_NotEnded() public {
        address payable auctionAddr = payable(factory.createAuction(address(nft), tokenId, DURATION, MIN_INC));
        nft.approve(auctionAddr, tokenId);
        Auction(auctionAddr).start();
        vm.expectRevert(AuctionFactory.AuctionNotEndedError.selector);
        factory.removeAuction(address(nft), tokenId);
    }

    function testRemoveAuction_Reverts_NoAuction() public {
        vm.expectRevert(AuctionFactory.AuctionExistsError.selector);
        factory.removeAuction(address(nft), tokenId);
    }

    /* Allow contract to accept ETH */
    receive() external payable {}
}
