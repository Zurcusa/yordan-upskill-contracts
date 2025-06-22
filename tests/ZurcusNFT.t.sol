// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../contracts/ZurcusNFT.sol";

contract ZurcusNFTTest is Test {
    ZurcusNFT private nft;

    address private OWNER = address(this);
    address private constant ALICE = address(0x2);
    address private constant BOB = address(0x3);

    uint256 private constant PRICE = 1 ether;
    uint256 private constant MAX_SUPPLY = 2;

    string private constant NAME = "ZurcusNFT";
    string private constant SYMBOL = "ZRC";
    string private constant BASE_URI = "ipfs://base/";

    event PriceUpdated(uint256 oldPrice, uint256 newPrice);
    event WhitelistedUserAdded(address indexed user);

    function setUp() public {
        nft = new ZurcusNFT(NAME, SYMBOL, BASE_URI, PRICE, MAX_SUPPLY);

        vm.deal(ALICE, 10 ether);
        vm.deal(BOB, 10 ether);
    }

    /*───────────────────────── MINT ──────────────────────────*/

    function testMint_Succeeds_IncrementsCounterAndAssignsIds() public {
        nft.mint{value: PRICE}(ALICE); // id 1
        nft.mint{value: PRICE}(ALICE); // id 2

        assertEq(nft.mintedCount(), 2);
        assertEq(nft.ownerOf(1), ALICE);
        assertEq(nft.ownerOf(2), ALICE);
    }

    function testMint_Reverts_NotWhitelisted_PrivateSale() public {
        vm.prank(ALICE);
        vm.expectRevert(ZurcusNFT.SenderNotWhitelistedError.selector);
        nft.mint{value: PRICE}(ALICE);
    }

    function testMint_Reverts_IncorrectPayment_PrivateSale() public {
        vm.expectRevert(ZurcusNFT.IncorrectPaymentError.selector);
        nft.mint{value: PRICE - 1}(OWNER);
    }

    function testMint_Reverts_IncorrectPayment_PublicSale() public {
        nft.setSalePhase(uint8(ZurcusNFT.SalePhase.PublicSale));
        vm.prank(ALICE);
        vm.expectRevert(ZurcusNFT.IncorrectPaymentError.selector);
        nft.mint{value: PRICE - 1}(ALICE);
    }

    function testMint_Reverts_ExceedsMaxSupply() public {
        nft.mint{value: PRICE}(ALICE);
        nft.mint{value: PRICE}(ALICE);
        vm.expectRevert(ZurcusNFT.ExceedsMaxSupplyError.selector);
        nft.mint{value: PRICE}(OWNER);
    }

    /*───────────────────────── BURN ──────────────────────────*/

    function testBurn_Reverts_NonexistentToken() public {
        vm.expectRevert();
        nft.burn(1);
    }

    function testBurn_Reverts_NotTokenOwner() public {
        nft.mint{value: PRICE}(BOB); // tokenId = 1
        vm.prank(ALICE);
        vm.expectRevert();
        nft.burn(1);
    }

    /*───────────────────────── WHITELIST MANAGEMENT ──────────────────────────*/

    function testAddWhitelistedUser_Reverts_AlreadyWhitelisted() public {
        nft.addWhitelistedUser(ALICE);
        vm.expectRevert(ZurcusNFT.UserAlreadyWhitelistedError.selector);
        nft.addWhitelistedUser(ALICE);
    }

    function testRemoveWhitelistedUser_Reverts_ZeroAddress() public {
        vm.expectRevert(ZurcusNFT.InvalidAddressError.selector);
        nft.removeWhitelistedUser(address(0));
    }

    function testAddWhitelistedUser_Succeeds_EmitsEvent() public {
        vm.expectEmit();
        emit WhitelistedUserAdded(ALICE);

        nft.addWhitelistedUser(ALICE);

        assertTrue(
            nft.hasRole(nft.WHITELISTED_ROLE(), ALICE),
            "ALICE should be whitelisted"
        );
    }

    function testAddWhitelistedUser_Reverts_NotOwner() public {
        vm.prank(ALICE);
        vm.expectRevert();
        nft.addWhitelistedUser(BOB);
    }

    /*───────────────────────── SALE-PHASE MANAGEMENT ──────────────────────────*/

    function testSetSalePhase_Reverts_InvalidPhase() public {
        vm.expectRevert(ZurcusNFT.InvalidPhaseError.selector);
        nft.setSalePhase(2);
    }

    /*───────────────────────── PRICE MANAGEMENT ──────────────────────────*/

    function testSetPrice_Reverts_NotOwner() public {
        vm.prank(ALICE);
        vm.expectRevert();
        nft.setPrice(2 ether);
    }

    function testSetPrice_Succeeds_EmitsEvent() public {
        uint256 newPrice = 2 ether;

        vm.expectEmit();
        emit PriceUpdated(PRICE, newPrice);

        nft.setPrice(newPrice);

        vm.expectRevert(ZurcusNFT.IncorrectPaymentError.selector);
        nft.mint{value: PRICE}(ALICE);
    }

    /*───────────────────────── WITHDRAW ──────────────────────────*/

    function testWithdraw_Succeeds() public {
        nft.mint{value: PRICE}(ALICE);

        RevertingReceiver receiver = new RevertingReceiver();
        address receiverAddress = address(receiver);
        nft.transferOwnership(receiverAddress);
        vm.prank(receiverAddress);

        uint256 balBefore = (payable(receiverAddress)).balance;
        nft.withdraw();
        uint256 balAfter = (payable(receiverAddress)).balance;

        assertEq(balAfter - balBefore, PRICE, "owner should receive funds");
        assertEq(address(nft).balance, 0, "contract balance cleared");
    }

    function testWithdraw_Reverts_TransferFails() public {
        nft.mint{value: PRICE}(ALICE);

        vm.expectRevert(ZurcusNFT.WithdrawFailedError.selector);
        nft.withdraw();
    }

    /*───────────────────────── FALLBACK ──────────────────────────*/

    function testReceive_Reverts_DirectTransfer() public {
        vm.expectRevert(ZurcusNFT.DirectTransferNotAllowed.selector);
        (bool ok, ) = address(nft).call{value: PRICE}("");
        ok;
    }

    function testFallback_Reverts_DirectCall() public {
        vm.expectRevert(ZurcusNFT.DirectTransferNotAllowed.selector);
        (bool ok, ) = address(nft).call{value: PRICE}(
            abi.encodeWithSignature("doesNotExist()")
        );
        ok;
    }

    /*───────────────────────── TEST CONTRACT FUNCTIONS ──────────────────────────*/

    receive() external payable {
        revert();
    }
}

/*───────────────────────── HELPERS ──────────────────────────*/

contract RevertingReceiver {
    receive() external payable {}
}
