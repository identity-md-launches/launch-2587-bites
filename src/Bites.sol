// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Bites (BIT)
/// @notice Fixed-supply ERC-20 with 18 decimals and no administrative powers.
contract Bites is ERC20 {
    /// @notice One billion BIT, expressed in the smallest token units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev The immediate deployer receives all tokens, including when deployed by a factory.
    constructor() ERC20("Bites", "BIT") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
