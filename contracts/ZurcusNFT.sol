// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title  Zurcus NFT Collection
 * @notice ERC-721 contract with a two-phase minting process (private whitelist + public sale).
 * @dev    Key features:
 *           • Fixed-price minting controlled by the owner via {setPrice}.
 *           • PrivateSale phase enforces a whitelist managed through {addWhitelistedUser} / {removeWhitelistedUser}.
 *           • PublicSale phase allows anyone to mint once activated by the owner.
 *           • Max supply is immutable and enforced in {mint}.
 *           • Owner can withdraw all accrued ETH with {withdraw}.
 *           • Utilises {AccessControl} for whitelist tracking and {Ownable} for admin rights.
 */
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract ZurcusNFT is ERC721, Ownable, AccessControl, ReentrancyGuard {
    /*───────────────────────── ERRORS ──────────────────────────*/
    error SenderNotWhitelistedError();
    error UserAlreadyWhitelistedError();
    error InvalidPhaseError();
    error InvalidAddressError();
    error IncorrectPaymentError();
    error WithdrawFailedError();
    error DirectTransferNotAllowed();
    error EmptyNameError();
    error EmptySymbolError();
    error EmptyBaseURIError();
    error InvalidMaxSupplyError();
    error ExceedsMaxSupplyError();

    /*───────────────────────── ENUMS ──────────────────────────*/
    enum SalePhase {
        PrivateSale,
        PublicSale
    }

    /*───────────────────────── EVENTS ──────────────────────────*/
    event PriceUpdated(uint256 oldPrice, uint256 newPrice);
    event WhitelistedUserAdded(address indexed user);
    event SalePhaseUpdated(SalePhase oldPhase, SalePhase newPhase);
    event FundsWithdrawn(uint256 amount);
    event BaseURIUpdated(string oldURI, string newURI);

    /*───────────────────────── CONSTANTS ──────────────────────────*/
    bytes32 public constant WHITELISTED_ROLE = keccak256("WHITELISTED");

    uint256 private immutable maxSupply;

    /*───────────────────────── STATE VARIABLES ──────────────────────────*/
    SalePhase private salePhase;

    uint256 private price;
    uint256 public mintedCount;

    string private baseTokenURI;

    /**
     * @param _name             Token name
     * @param _symbol           Token symbol
     * @param _initialBaseURI   Initial base URI for token metadata
     * @param _initialPrice     Static mint price (in wei)
     * @param _maxSupply        Maximum number of tokens that can ever exist
     */
    constructor(
        string memory _name,
        string memory _symbol,
        string memory _initialBaseURI,
        uint256 _initialPrice,
        uint256 _maxSupply
    ) ERC721(_name, _symbol) Ownable(msg.sender) {
        if (bytes(_name).length == 0) revert EmptyNameError();
        if (bytes(_symbol).length == 0) revert EmptySymbolError();
        if (bytes(_initialBaseURI).length == 0) revert EmptyBaseURIError();
        if (_maxSupply == 0) revert InvalidMaxSupplyError();

        // Give deployer full control.
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(WHITELISTED_ROLE, msg.sender);

        salePhase = SalePhase.PrivateSale;
        price = _initialPrice;
        baseTokenURI = _initialBaseURI;

        maxSupply = _maxSupply;
    }

    /*───────────────────────── MODIFIERS ──────────────────────────*/
    // Enforce whitelist during the private phase.
    modifier onlyWhitelisted() {
        if (salePhase == SalePhase.PrivateSale && !hasRole(WHITELISTED_ROLE, msg.sender)) {
            revert SenderNotWhitelistedError();
        }
        _;
    }

    /*───────────────────────── FUNCTIONS ──────────────────────────*/
    /**
     * @notice Mint a new Zurcus NFT.
     * @dev Emits the ERC-721 {Transfer} event from the zero address to `_to`.
     *      Requirements:
     *        • Caller must own the `WHITELISTED_ROLE` while the sale is in
     *          `PrivateSale` phase.
     *        • `msg.value` must equal the configured `price`.
     * @param _to      Recipient address.
     */
    function mint(address _to) external payable onlyWhitelisted {
        uint256 currentPrice = price;
        uint256 currentMinted = mintedCount;
        uint256 cap = maxSupply;

        // Validate payment amount and supply limits.
        if (msg.value != currentPrice) revert IncorrectPaymentError();
        if (currentMinted >= cap) revert ExceedsMaxSupplyError();

        // Increment counter & mint using the new index as tokenId (1-based).
        unchecked {
            currentMinted += 1;
            mintedCount = currentMinted;
        }
        _safeMint(_to, currentMinted);
    }

    /**
     * @notice Burn an existing token permanently.
     * @dev Emits the ERC-721 {Transfer} event from the current owner to the
     *      zero address.
     * @param _tokenId Token identifier to burn.
     */
    function burn(uint256 _tokenId) external {
        // This validates that the sender is the owner of the token.
        address previousOwner = _update(address(0), _tokenId, msg.sender);
        if (previousOwner == address(0)) {
            revert ERC721NonexistentToken(_tokenId);
        }
    }

    /*───────────────────────── ADMIN FUNCTIONS ──────────────────────────*/
    /**
     * @notice Withdraw all Ether held by the contract to the owner.
     * @dev Emits a {FundsWithdrawn} event.
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        address payable ownerAddr = payable(owner());
        (bool sent,) = ownerAddr.call{value: balance}("");
        if (!sent) revert WithdrawFailedError();
        emit FundsWithdrawn(balance);
    }

    /**
     * @notice Update the public mint price.
     * @dev Emits a {PriceUpdated} event.
     * @param _newPrice Price in wei.
     */
    function setPrice(uint256 _newPrice) external onlyOwner {
        uint256 oldPrice = price;
        price = _newPrice;
        emit PriceUpdated(oldPrice, _newPrice);
    }

    /**
     * @notice Grant the `WHITELISTED_ROLE` to `_user`.
     * @dev Emits:
     *      • {RoleGranted} (from {AccessControl})
     *      • {WhitelistedUserAdded}
     */
    function addWhitelistedUser(address _user) external onlyOwner {
        if (hasRole(WHITELISTED_ROLE, _user)) {
            revert UserAlreadyWhitelistedError();
        }
        _grantRole(WHITELISTED_ROLE, _user);
        emit WhitelistedUserAdded(_user);
    }

    /**
     * @notice Revoke the `WHITELISTED_ROLE` from `_user`.
     * @dev Emits {RoleRevoked} from {AccessControl}.
     */
    function removeWhitelistedUser(address _user) external onlyOwner {
        if (_user == address(0)) revert InvalidAddressError();
        _revokeRole(WHITELISTED_ROLE, _user);
    }

    /**
     * @notice Change the sale phase.
     * @dev Emits {SalePhaseUpdated}.
     * @param _phase 0 ⇒ PrivateSale, 1 ⇒ PublicSale.
     */
    function setSalePhase(uint8 _phase) external onlyOwner {
        if (_phase > uint8(SalePhase.PublicSale)) revert InvalidPhaseError();
        SalePhase previousPhase = salePhase;
        salePhase = SalePhase(_phase);
        emit SalePhaseUpdated(previousPhase, salePhase);
    }

    /*───────────────────────── RECEIVE AND FALLBACK ──────────────────────────*/
    receive() external payable {
        revert DirectTransferNotAllowed();
    }

    fallback() external payable {
        revert DirectTransferNotAllowed();
    }

    /**
     * @dev Override {_baseURI} so OpenSea & others resolve
     *      `tokenURI(tokenId) = string.concat(baseURI, tokenId)`.
     */
    function _baseURI() internal view override returns (string memory) {
        return baseTokenURI;
    }

    /**
     * @notice Update the base URI used for token metadata.
     * @dev Emits {BaseURIUpdated}.
     * @param newBaseURI New base URI string.
     */
    function setBaseURI(string memory newBaseURI) external onlyOwner {
        string memory old = baseTokenURI;
        baseTokenURI = newBaseURI;
        emit BaseURIUpdated(old, newBaseURI);
    }

    /**
     * @dev Resolve multiple inheritance of {supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
