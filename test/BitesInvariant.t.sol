// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Bites} from "../src/Bites.sol";

/// @dev Exercises a closed set of holders and maintains an independent accounting model.
contract BitesHandler is Test {
    Bites public immutable token;
    address[5] public actors;
    mapping(address => uint256) public modelBalances;
    mapping(address => mapping(address => uint256)) public modelAllowances;

    constructor(Bites token_) {
        token = token_;
        actors =
            [makeAddr("actor 0"), makeAddr("actor 1"), makeAddr("actor 2"), makeAddr("actor 3"), makeAddr("actor 4")];
        modelBalances[actors[0]] = 1_000_000_000 * 10 ** 18;
    }

    function move(uint256 fromSeed, uint256 toSeed, uint256 amount) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, modelBalances[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        modelBalances[from] -= amount;
        modelBalances[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        modelAllowances[owner][spender] = amount;
    }

    function approveUnlimited(uint256 ownerSeed, uint256 spenderSeed) public {
        approve(ownerSeed, spenderSeed, type(uint256).max);
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) public {
        approve(ownerSeed, spenderSeed, 0);
        overspend(ownerSeed, spenderSeed);
    }

    function moveAll(uint256 fromSeed, uint256 toSeed) public {
        move(fromSeed, toSeed, modelBalances[actors[fromSeed % actors.length]]);
    }

    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 amount) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 fromBefore = token.balanceOf(from);
        uint256 toBefore = token.balanceOf(to);
        amount = bound(amount, 0, modelBalances[from]);
        move(fromSeed, toSeed, amount);
        // Check the outward leg too: two broken transfers must not cancel each other out.
        assertEq(token.balanceOf(from), modelBalances[from]);
        assertEq(token.balanceOf(to), modelBalances[to]);
        move(toSeed, fromSeed, amount);
        assertEq(token.balanceOf(from), fromBefore);
        assertEq(token.balanceOf(to), toBefore);
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 allowed = modelAllowances[owner][spender];
        uint256 balance = modelBalances[owner];
        amount = bound(amount, 0, allowed < balance ? allowed : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        if (allowed != type(uint256).max) {
            modelAllowances[owner][spender] -= amount;
        }
        modelBalances[owner] -= amount;
        modelBalances[to] += amount;
    }

    function overspend(uint256 ownerSeed, uint256 spenderSeed) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 allowed = modelAllowances[owner][spender];
        // Make every invocation exercise a rejection, even after an unlimited approval.
        if (allowed == type(uint256).max) {
            allowed -= 1;
            approve(ownerSeed, spenderSeed, allowed);
        }

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, spender, allowed + 1);
        // A rejected spend must leave both balances and allowances equal to the model.
    }

    function transferBeyondBalance(uint256 fromSeed, uint256 toSeed, uint256 amount) public {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = modelBalances[from];
        amount = bound(amount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function spendBeyondBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = modelBalances[owner];
        amount = bound(amount, balance + 1, type(uint256).max - 1);
        // Sufficient approval isolates the balance check. A revert must restore this approval.
        approve(ownerSeed, spenderSeed, unlimited ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, spender, amount);
    }

    function rejectZeroAddress(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, uint8 operation) public {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        if (operation % 3 == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(owner);
            token.transfer(address(0), amount);
        } else if (operation % 3 == 1) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            vm.prank(owner);
            token.approve(address(0), amount);
        } else {
            uint256 allowed = modelAllowances[owner][spender];
            uint256 balance = modelBalances[owner];
            amount = bound(amount, 0, allowed < balance ? allowed : balance);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        }
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract BitesInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Bites internal token;
    BitesHandler internal handler;

    function setUp() public {
        token = new Bites();
        handler = new BitesHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        // Give every actor funds and an approval so spending is reachable from the first call.
        for (uint256 i = 1; i < 5; ++i) {
            handler.move(0, i, SUPPLY / 5);
        }
        for (uint256 i; i < 5; ++i) {
            handler.approve(i, (i + 1) % 5, SUPPLY);
        }
        handler.approveUnlimited(0, 1);
        handler.approve(1, 2, type(uint256).max - 1);

        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = BitesHandler.move.selector;
        selectors[1] = BitesHandler.approve.selector;
        selectors[2] = BitesHandler.spend.selector;
        selectors[3] = BitesHandler.overspend.selector;
        selectors[4] = BitesHandler.approveUnlimited.selector;
        selectors[5] = BitesHandler.revoke.selector;
        selectors[6] = BitesHandler.moveAll.selector;
        selectors[7] = BitesHandler.roundTrip.selector;
        selectors[8] = BitesHandler.transferBeyondBalance.selector;
        selectors[9] = BitesHandler.spendBeyondBalance.selector;
        selectors[10] = BitesHandler.rejectZeroAddress.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_FixedSupplyAndExactBalances() public view {
        uint256 sum;
        for (uint256 i; i < 5; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.modelBalances(actor));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.name(), "Bites");
        assertEq(token.symbol(), "BIT");
        assertEq(token.decimals(), 18);
    }

    function invariant_ExactAllowances() public view {
        for (uint256 i; i < 5; ++i) {
            address owner = handler.actors(i);
            assertEq(token.allowance(owner, address(0)), 0);
            assertEq(token.allowance(address(0), owner), 0);
            for (uint256 j; j < 5; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.modelAllowances(owner, spender));
            }
        }
    }

    function afterInvariant() public {
        // Every holder can still transfer its entire balance after any random sequence.
        for (uint256 i = 1; i < 5; ++i) {
            handler.moveAll(i, 0);
            assertEq(token.balanceOf(handler.actors(i)), 0);
        }
        assertEq(token.balanceOf(handler.actors(0)), SUPPLY);
        handler.roundTrip(0, 1, SUPPLY);
        invariant_FixedSupplyAndExactBalances();
        invariant_ExactAllowances();
    }

    function test_HandlerAllowanceLifecycleAndFailureRecovery() public {
        handler.spend(0, 1, 2, 1);
        assertEq(token.allowance(handler.actors(0), handler.actors(1)), type(uint256).max);
        handler.approve(0, 1, 10);
        handler.spend(0, 1, 2, 10);
        assertEq(token.allowance(handler.actors(0), handler.actors(1)), 0);
        handler.overspend(0, 1);
        invariant_FixedSupplyAndExactBalances();
        invariant_ExactAllowances();

        handler.spendBeyondBalance(0, 1, type(uint256).max, false);
        invariant_ExactAllowances();
        handler.spendBeyondBalance(0, 1, type(uint256).max, true);
        invariant_ExactAllowances();
        handler.revoke(0, 1);
        handler.transferBeyondBalance(0, 1, type(uint256).max);
        handler.approve(0, 1, 10);
        for (uint8 operation; operation < 3; ++operation) {
            handler.rejectZeroAddress(0, 1, 10, operation);
            invariant_FixedSupplyAndExactBalances();
            invariant_ExactAllowances();
        }
        handler.spend(0, 1, 2, 10);
        handler.roundTrip(2, 3, 1);
        invariant_FixedSupplyAndExactBalances();
        invariant_ExactAllowances();
        afterInvariant();
    }
}
