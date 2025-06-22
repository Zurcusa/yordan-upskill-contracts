// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title  Auction Factory
 * @notice Deploys and tracks Auction contracts, ensuring only one active auction exists per NFT/token.
 * @dev    Mimics style and best-practices of `Auction.sol` / `ZurcusNFT.sol`.
 */

import "./Auction.sol";

contract AuctionFactory {
    /*───────────────────────── ERRORS ──────────────────────────*/
    error ZeroAddressError();
    error InvalidDurationError();
    error InvalidMinBidIncrementError();
    error AuctionExistsError();
    error AuctionNotEndedError();

    /*───────────────────────── EVENTS ──────────────────────────*/
    event AuctionCreated(
        address indexed auctionAddress,
        address indexed creator,
        address indexed nft,
        uint256 tokenId,
        uint256 duration,
        uint256 minBidIncrement
    );

    event AuctionRemoved(address indexed nft, uint256 indexed tokenId);

    /*───────────────────────── CONSTANTS ──────────────────────────*/
    uint256 private constant MAX_AUCTION_DURATION = 10 days;

    /*───────────────────────── STATE VARIABLES ──────────────────────────*/
    address[] public auctions;

    mapping(bytes32 => address) public liveAuctions;

    /*───────────────────────── FUNCTIONS ──────────────────────────*/
    /**
     * @notice Create a new Auction contract.
     * @param _collection      NFT contract address.
     * @param _tokenId         Token ID being auctioned.
     * @param _duration        Auction duration (seconds).
     * @param _minBidIncrement Minimum bid increment.
     * @return auctionAddr  Address of the deployed auction.
     */
    function createAuction(
        address _collection,
        uint256 _tokenId,
        uint256 _duration,
        uint256 _minBidIncrement
    ) external returns (address auctionAddr) {
        if (_collection == address(0)) revert ZeroAddressError();
        if (_duration == 0 || _duration > MAX_AUCTION_DURATION)
            revert InvalidDurationError();
        if (_minBidIncrement == 0) revert InvalidMinBidIncrementError();
        bytes32 slotKey = _key(_collection, _tokenId);
        if (liveAuctions[slotKey] != address(0)) revert AuctionExistsError();

        auctionAddr = address(
            new Auction(msg.sender, _collection, _tokenId, _duration, _minBidIncrement)
        );

        auctions.push(auctionAddr);
        liveAuctions[slotKey] = auctionAddr;

        emit AuctionCreated(
            auctionAddr,
            msg.sender,
            _collection,
            _tokenId,
            _duration,
            _minBidIncrement
        );
    }

    /// @dev Computes the storage key for a given NFT contract and tokenId.
    function _key(
        address _collection,
        uint256 _tokenId
    ) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(_collection, _tokenId));
    }

    /**
     * @notice Remove an ended auction from the active mapping.
     * @param _collection     NFT contract address.
     * @param _tokenId         Token ID.
     */
    function removeAuction(address _collection, uint256 _tokenId) external {
        if (_collection == address(0)) revert ZeroAddressError();

        bytes32 slotKey = _key(_collection, _tokenId);
        address auction = liveAuctions[slotKey];
        if (auction == address(0)) revert AuctionExistsError();

        if (!Auction(payable(auction)).isEnded()) revert AuctionNotEndedError();

        delete liveAuctions[slotKey];

        emit AuctionRemoved(_collection, _tokenId);
    }
}
