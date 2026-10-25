// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Bites} from "src/Bites.sol";

/// @dev Complements the existing constructor, factory and ordinary ERC-20 tests.
/// forge-config: default.fuzz.runs = 1024
contract BitesEdgeCasesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Bites internal token;
    address internal alice = makeAddr("edge alice");
    address internal bob = makeAddr("edge bob");
    address internal spender = makeAddr("edge spender");
    address internal otherSpender = makeAddr("edge other spender");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new Bites();
    }

    function test_OneWeiCanMoveAndBeSpentExactly() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferStillRequiresSufficientBalance() public {
        assertTrue(token.transfer(alice, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(alice);
        token.transfer(alice, 2);
        vm.prank(alice);
        assertTrue(token.approve(spender, 2));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(spender);
        token.transferFrom(alice, alice, 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.allowance(alice, spender), 2);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromByOwnerRequiresSelfApproval() public {
        assertTrue(token.transfer(alice, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);
        vm.startPrank(alice);
        assertTrue(token.approve(alice, 1));
        assertTrue(token.transferFrom(alice, bob, 1));
        vm.stopPrank();
        assertEq(token.allowance(alice, alice), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumFiniteAllowanceIsConsumedWhenSpendingEntireSupply() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_UnlimitedApprovalDoesNotPermitMaximumTransferWithoutBalance() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);

        // A failed oversized spend must not poison the next valid spend.
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroSpenderRejectsZeroAndMaximumApprovalsWithoutChangingOtherApproval() public {
        assertTrue(token.approve(spender, 7));
        uint256[2] memory amounts = [uint256(0), type(uint256).max];
        for (uint256 i; i < amounts.length; ++i) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            token.approve(address(0), amounts[i]);
            assertEq(token.allowance(address(this), address(0)), 0);
            assertEq(token.allowance(address(this), spender), 7);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_ZeroDelegatedTransferToZeroIsRejectedWithAndWithoutApproval() public {
        uint256[3] memory allowances = [uint256(0), uint256(1), type(uint256).max];
        for (uint256 i; i < allowances.length; ++i) {
            assertTrue(token.approve(spender, allowances[i]));
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(address(this), address(0), 0);
            assertEq(token.allowance(address(this), spender), allowances[i]);
            assertEq(token.balanceOf(address(this)), SUPPLY);
            assertEq(token.balanceOf(address(0)), 0);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_AllowanceIsBoundToOwnerAndSpenderNotRecipient() public {
        assertTrue(token.transfer(alice, 10));
        vm.prank(alice);
        assertTrue(token.approve(spender, 10));

        // Paying the approved spender does not give the caller that spender's authority.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(alice, spender, 1);
        // A spender's approval from Alice also grants no authority over a different owner.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 10);
        assertEq(token.allowance(alice, spender), 10);

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 10));
        assertEq(token.balanceOf(bob), 10);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ZeroTransfersPreserveExistingAllowance(uint256 approval) public {
        assertTrue(token.approve(spender, approval));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 0));
        assertTrue(token.transfer(alice, 0));
        assertEq(token.allowance(address(this), spender), approval);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferRoundTripRestoresBothHolders(uint256 funding, uint256 amount) public {
        funding = bound(funding, 0, SUPPLY);
        amount = bound(amount, 0, funding);
        assertTrue(token.transfer(alice, funding));
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(alice), funding - amount);
        assertEq(token.balanceOf(bob), amount);
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), funding);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - funding);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitTransfersEqualOneTransfer(uint256 total, uint256 first) public {
        total = bound(total, 0, SUPPLY);
        first = bound(first, 0, total);
        Bites unsplit = new Bites();
        assertTrue(unsplit.transfer(alice, total));
        assertTrue(token.transfer(alice, first));
        assertTrue(token.transfer(alice, total - first));
        assertEq(token.balanceOf(alice), total);
        assertEq(token.balanceOf(alice), unsplit.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), unsplit.balanceOf(address(this)));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(unsplit.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalReplacementAndSpendingDoNotAffectOtherPairs(
        uint256 initial,
        uint256 replacement,
        uint256 amount
    ) public {
        assertTrue(token.approve(spender, initial));
        assertTrue(token.approve(otherSpender, SUPPLY));
        vm.prank(alice);
        assertTrue(token.approve(spender, 7));
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, replacement);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        // Repeating the same approval replaces rather than adds to the allowance.
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);

        amount = bound(amount, 0, replacement < SUPPLY ? replacement : SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, amount));
        uint256 remaining = replacement == type(uint256).max ? replacement : replacement - amount;
        assertEq(token.allowance(address(this), spender), remaining);
        assertEq(token.allowance(address(this), otherSpender), SUPPLY);
        assertEq(token.allowance(alice, spender), 7);
        assertEq(token.allowance(bob, spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_FailedSpendRestoresAllowanceAndSucceedsAfterFunding(
        uint256 funding,
        uint256 amount,
        uint256 approval,
        bool unlimited
    ) public {
        funding = bound(funding, 0, SUPPLY - 1);
        amount = bound(amount, funding + 1, SUPPLY);
        approval = unlimited ? type(uint256).max : bound(approval, amount, type(uint256).max - 1);
        assertTrue(token.transfer(alice, funding));
        vm.prank(alice);
        assertTrue(token.approve(spender, approval));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, funding, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.balanceOf(alice), funding);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - funding);
        assertEq(token.allowance(alice, spender), approval);
        assertEq(token.totalSupply(), SUPPLY);

        // Top up only the shortfall; the exact same call can now use the restored allowance.
        assertTrue(token.transfer(alice, amount - funding));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(alice, spender), unlimited ? approval : approval - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_RevocationAfterPartialSpendBlocksOldAuthority(uint256 funding, uint256 spent) public {
        funding = bound(funding, 1, SUPPLY);
        spent = bound(spent, 0, funding - 1);
        assertTrue(token.transfer(alice, funding));
        vm.prank(alice);
        assertTrue(token.approve(spender, funding));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, spent));
        assertEq(token.allowance(alice, spender), funding - spent);
        vm.prank(alice);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), funding - spent);
        assertEq(token.balanceOf(bob), spent);
        assertEq(token.balanceOf(address(this)), SUPPLY - funding);

        vm.prank(alice);
        assertTrue(token.transfer(bob, funding - spent));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), funding);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
