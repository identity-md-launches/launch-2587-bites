// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Bites} from "../src/Bites.sol";

/// @dev Test-only helper; the production factory is supplied by the launch system.
contract BitesFactoryProbe {
    function deploy(bytes32 salt) external returns (Bites) {
        return new Bites{salt: salt}();
    }

    function move(Bites token, address recipient, uint256 amount) external {
        require(token.transfer(recipient, amount), "transfer failed");
    }
}

contract BitesFactoryTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    function test_Create2MintsOnlyToImmediateFactory() public {
        BitesFactoryProbe factory = new BitesFactoryProbe();
        bytes32 salt = keccak256("Bites deployment test");
        address expected = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(Bites).creationCode))
                    )
                )
            )
        );
        address requester = makeAddr("requester");
        vm.prank(requester);
        Bites token = factory.deploy(salt);

        assertEq(address(token), expected);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(requester), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertLe(address(token).code.length, 24_576);
    }

    function test_DistributionClaimAndPoolTransfersArriveWhole() public {
        BitesFactoryProbe factory = new BitesFactoryProbe();
        Bites token = factory.deploy(keccak256("Bites distribution test"));
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("pool manager");
        address remainderRecipient = makeAddr("remainder recipient");
        address claimant = makeAddr("claimant");
        address trader = makeAddr("trader");

        // Exercise the token side of the provided launch distribution; no pool is mocked here.
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY * 8 / 10;
        uint256 remainder = SUPPLY - swarm - pool;
        factory.move(token, distributor, swarm);
        factory.move(token, poolManager, pool);
        factory.move(token, remainderRecipient, remainder);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), swarm);
        assertEq(token.balanceOf(poolManager), pool);
        assertEq(token.balanceOf(remainderRecipient), remainder);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarm));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(claimant), swarm);

        uint256 tradeAmount = 123 ether;
        vm.prank(poolManager);
        assertTrue(token.transfer(trader, tradeAmount));
        assertEq(token.balanceOf(trader), tradeAmount);
        assertEq(token.balanceOf(poolManager), pool - tradeAmount);
        vm.prank(trader);
        assertTrue(token.transfer(poolManager, tradeAmount));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(poolManager), pool);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
