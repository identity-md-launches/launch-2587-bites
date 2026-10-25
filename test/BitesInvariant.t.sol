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
        if (allowed == type(uint256).max) return;

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, spender, allowed + 1);
        // A rejected spend must leave both balances and allowances equal to the model.
    }
}

contract BitesInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    Bites internal token;
    BitesHandler internal handler;

    function setUp() public {
        token = new Bites();
        handler = new BitesHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = BitesHandler.move.selector;
        selectors[1] = BitesHandler.approve.selector;
        selectors[2] = BitesHandler.spend.selector;
        selectors[3] = BitesHandler.overspend.selector;
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
    }

    function invariant_ExactAllowances() public view {
        for (uint256 i; i < 5; ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < 5; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.modelAllowances(owner, spender));
            }
        }
    }
}
