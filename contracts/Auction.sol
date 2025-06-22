// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title English Auction
 * @notice A gas-optimized English auction contract for a single ERC-721 token.
 * @dev    The auction follows these rules:
 *           • Seller (owner) starts the auction by transferring the NFT into the contract.
 *           • Anyone can bid; each new bid must exceed the current bid by `minBidIncrement`.
 *           • Last-minute bids (within `BID_EXTENSION_GRACE_PERIOD`) extend the auction by
 *             `EXTENSION_DURATION` to prevent sniping.
 *           • Out-bid users can withdraw their funds at any time.
 *           • When the auction ends the NFT & funds are transferred atomically.
 *           • The seller can cancel if no bids have been placed.
 *           • Inherits {Ownable} for access control; the deployer is the seller/owner.
 */
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Auction is IERC721Receiver, Ownable, ReentrancyGuard {
    /*───────────────────────── ERRORS ──────────────────────────*/
    error ZeroAddressError();
    error InvalidDurationError();
    error InvalidMinBidIncrementError();
    error AuctionAlreadyStartedError();
    error NotApprovedForNFTError();
    error AuctionNotStartedError();
    error AuctionEndedError();
    error BidTooLowError();
    error NoBalanceError();
    error AuctionNotCancellableError();
    error BidExistsError();
    error AuctionNotActiveError();
    error AuctionTimeNotOverError();
    error AuctionAlreadyEndedError();
    error ETHTransferFailedError();
    error DirectTransferNotAllowedError();

    /*───────────────────────── ENUMS ──────────────────────────*/
    enum AuctionState {
        NotStarted,
        Active,
        Ended
    }

    /*───────────────────────── EVENTS ──────────────────────────*/
    event AuctionStarted(uint256 startTime, uint256 endTime);
    event AuctionEnded(address indexed winner, uint256 amount);
    event AuctionCancelled();
    event AuctionExtended(uint256 newEndTime, address extendedBy);
    event AuctionCreated(
        address indexed auctionAddress,
        address indexed creator,
        address indexed nft,
        uint256 tokenId,
        uint256 duration,
        uint256 minBidIncrement
    );
    event BidPlaced(address indexed bidder, uint256 amount);
    event FundsWithdrawn(address indexed bidder, uint256 amount);

    /*───────────────────────── CONSTANTS ──────────────────────────*/
    uint256 private constant MAX_DURATION = 10 days;
    uint256 private constant BID_EXTENSION_GRACE_PERIOD = 5 minutes;
    uint256 private constant EXTENSION_DURATION = 2 minutes;

    IERC721 private immutable nft;
    uint256 private immutable nftId;
    uint256 private immutable duration;
    address payable private immutable seller;

    /*───────────────────────── STATE VARIABLES ──────────────────────────*/
    uint256 private minBidIncrement;
    uint256 public endAt;
    uint256 public highestBid;

    AuctionState private auctionState;
    address public highestBidder;

    mapping(address => uint256) private bids;

    /// @notice                 Initializes a new English Auction contract
    /// @param _seller          The address of the NFT owner
    /// @param _nft             The NFT contract address
    /// @param _nftId           The ID of the auctioned NFT
    /// @param _duration        Duration of the auction (in seconds)
    /// @param _minBidIncrement Minimum increment required for new bids
    constructor(address _seller, address _nft, uint256 _nftId, uint256 _duration, uint256 _minBidIncrement)
        Ownable(_seller)
    {
        if (_seller == address(0)) revert ZeroAddressError();
        if (_nft == address(0)) revert ZeroAddressError();
        if (_duration == 0 || _duration > MAX_DURATION) {
            revert InvalidDurationError();
        }
        if (_minBidIncrement == 0) revert InvalidMinBidIncrementError();

        nft = IERC721(_nft);
        nftId = _nftId;
        seller = payable(_seller);
        duration = _duration;
        minBidIncrement = _minBidIncrement;
    }

    /*───────────────────────── FUNCTIONS ──────────────────────────*/
    /**
     * @notice Check whether the auction is active.
     * @return True if in {@link AuctionState.Active} state.
     */
    function isStarted() public view returns (bool) {
        return auctionState == AuctionState.Active;
    }

    /**
     * @notice Check whether the auction has completed (either ended or cancelled).
     * @return True if in {@link AuctionState.Ended} state.
     */
    function isEnded() public view returns (bool) {
        return auctionState == AuctionState.Ended;
    }

    /**
     * @notice Start the auction.
     * @dev    Requirements:
     *           • Caller must be the contract owner (seller).
     *           • Auction must not have been started before.
     *           • The NFT must be approved for transfer to this contract.
     *         Emits {AuctionStarted}.
     */
    function start() external onlyOwner {
        if (auctionState != AuctionState.NotStarted) {
            revert AuctionAlreadyStartedError();
        }
        if (nft.getApproved(nftId) != address(this)) {
            revert NotApprovedForNFTError();
        }

        auctionState = AuctionState.Active;
        uint256 currentTime = block.timestamp;
        endAt = currentTime + duration;
        nft.safeTransferFrom(seller, address(this), nftId);

        emit AuctionStarted(currentTime, endAt);
    }

    /**
     * @notice Place a bid.
     * @dev    Behaviour:
     *           • Validates the bid amount against current highest bid + increment.
     *           • Extends the auction if within grace period.
     *           • Refunds the previous highest bidder by crediting their balance.
     *         Emits {BidPlaced} and optionally {AuctionExtended}.
     */
    function bid() external payable {
        if (!isStarted()) revert AuctionNotStartedError();

        uint256 currentTime = block.timestamp;
        uint256 endTime = endAt;
        address currentHighestBidder = highestBidder;
        uint256 currentHighestBid = highestBid;
        uint256 increment = minBidIncrement;

        if (currentTime >= endTime) revert AuctionEndedError();
        if (msg.value < currentHighestBid + increment) revert BidTooLowError();

        uint256 timeLeft = endTime - currentTime;
        if (timeLeft <= BID_EXTENSION_GRACE_PERIOD) {
            unchecked {
                endAt = endTime + EXTENSION_DURATION;
            }
            emit AuctionExtended(endAt, msg.sender);
        }

        if (currentHighestBidder != address(0)) {
            bids[currentHighestBidder] += currentHighestBid;
        }

        highestBid = msg.value;
        highestBidder = msg.sender;

        emit BidPlaced(msg.sender, msg.value);
    }

    /**
     * @notice Withdraw previously-outbid funds.
     * @dev    Non-reentrant; emits {Withdrawal}.
     */
    function withdraw() external nonReentrant {
        uint256 bal = bids[msg.sender];
        if (bal == 0) revert NoBalanceError();
        bids[msg.sender] = 0;

        _safeTransferETH(msg.sender, bal);

        emit FundsWithdrawn(msg.sender, bal);
    }

    /**
     * @notice Cancel the auction.
     * @dev    Only callable by owner when no bids have been placed.
     *         Transfers NFT back to seller and emits {AuctionCancelled}.
     */
    function cancelAuction() external onlyOwner {
        if (auctionState != AuctionState.Active) {
            revert AuctionNotCancellableError();
        }
        if (highestBidder != address(0)) revert BidExistsError();

        auctionState = AuctionState.Ended;
        nft.safeTransferFrom(address(this), seller, nftId);

        emit AuctionCancelled();
    }

    /**
     * @notice Finalize the auction.
     * @dev    Transfers the NFT to the winner and funds to the seller.
     *         Reverts if auction is still active or already ended.
     *         Emits {AuctionEnded}.
     */
    function end() external payable onlyOwner {
        if (auctionState != AuctionState.Active) revert AuctionNotActiveError();
        if (block.timestamp < endAt) revert AuctionTimeNotOverError();
        if (isEnded()) revert AuctionAlreadyEndedError();

        address currentHighestBidder = highestBidder;
        auctionState = AuctionState.Ended;

        uint256 salePrice = highestBid;
        if (currentHighestBidder != address(0)) {
            nft.safeTransferFrom(address(this), currentHighestBidder, nftId);

            _safeTransferETH(seller, salePrice);
        } else {
            nft.safeTransferFrom(address(this), seller, nftId);
        }

        emit AuctionEnded(currentHighestBidder, salePrice);
    }

    /**
     * @dev Internal helper to send ETH safely.
     *      Reverts with {ETHTransferFailedError} on failure.
     */
    function _safeTransferETH(address receiver, uint256 amount) internal {
        (bool success,) = receiver.call{value: amount}("");
        if (!success) revert ETHTransferFailedError();
    }

    /*───────────────────────── RECEIVE AND FALLBACK ──────────────────────────*/
    /**
     * @dev Reject direct ETH transfers (only bids via {bid}).
     */
    receive() external payable {
        revert DirectTransferNotAllowedError();
    }

    /**
     * @dev Reject unexpected or invalid calls; only `bid()` is allowed.
     */
    fallback() external payable {
        revert DirectTransferNotAllowedError();
    }

    /**
     * @inheritdoc IERC721Receiver
     */
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
