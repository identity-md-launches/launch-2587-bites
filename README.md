# Bites (BIT)

Bites is a fixed-supply ERC-20 for Ethereum. The constructor mints all
1,000,000,000 BIT to the immediate deployer in one operation. Transfers have no
tax, burn, fee, restriction list, or recipient callback. There is no owner,
administrator, later minting, public burning, pause, upgrade, or initializer.

## Deployment parameters

| Parameter | Value |
| --- | --- |
| Source / Solidity identifier | `src/Bites.sol:Bites` / `Bites` |
| Token name | `Bites` |
| Symbol | `BIT` |
| Decimals | `18` (OpenZeppelin ERC-20 default) |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Supply constant | `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` |
| Constructor arguments | None (`[]`) |
| Constructor ETH value | `0`; constructor is nonpayable |
| Initial recipient | `msg.sender`, the immediate deploying account or factory |
| Application contracts | None |
| Solidity | `0.8.26`, optimizer enabled, 200 runs |
| EVM target | `cancun` |
| Metadata bytecode hash | `none` |

Deploy the creation bytecode built for `Bites`; it requires no library linking,
configuration, external calls, or follow-up initialization. A Solidity deployer
can use `new Bites()` or `new Bites{salt: salt}()`. The constructor emits
`Transfer(address(0), deployer, 10^27)`. A factory deployment assigns the entire
supply to that factory, not to its external caller or transaction origin.

The launch system supplies the factory and performs the subsequent distribution,
pool initialization, and trading setup. The stated 10% swarm / 80% pool / 10%
remainder allocation is performed outside this token, after its constructor.
No allocation or launch address is embedded in Bites. The manifest is produced by
the separate launch step; this project does not provide `launch.json` or send any
transactions.

## Behavior and assumptions

The implementation inherits the vendored OpenZeppelin Contracts v5.0.2 `ERC20`
without overriding its balance or allowance accounting. `transfer`, `approve`,
and `transferFrom` return `true` on success and revert with ERC-6093 errors on
failure. Zero-value transfers between nonzero addresses succeed and emit
`Transfer`. Transfers to the zero address and approvals to the zero address
revert. Self-transfers preserve balances. Every successful ordinary transfer
credits exactly the requested number of smallest units.

`approve` replaces the caller's allowance for that spender. A finite allowance
decreases on `transferFrom`, including delegated self-transfers. An allowance of
`type(uint256).max` remains unchanged when spent. `approve` emits `Approval`;
OpenZeppelin v5 does not emit an additional `Approval` when spending an allowance.
Integrations should read `allowance` to determine the current value. Even the
deployer needs an explicit allowance to call `transferFrom` on a holder's tokens.
Failed transfers roll back allowance changes as well as balance changes.

Standard ERC-20 behavior is assumed because the brief requests no additional
transfer rules. Permit signatures, staking, vesting, redemption, taxes, automatic
liquidity management, and recovery of assets sent to the token are not part of
this contract. Tokens sent to an address that cannot transfer them, including the
token contract itself, remain there; they do not reduce `totalSupply`.

## Build and test

Foundry and the pinned Solidity 0.8.26 compiler must be installed. All Solidity
dependencies are included as ordinary source files under `lib/`; builds and tests
need no package download, RPC, wallet, secrets, or environment configuration.

```sh
forge build
FOUNDRY_FUZZ_SEED=0xe5f5f1fa10ff202a37a32a87fc595aa6c657d1f4027dcd66b2a8e35f69c22bb7 forge test
forge fmt --check
```

The seed above reproduces the assignment's fuzzing seed. Tests do not read or
change environment variables. Default fuzz runs are 1,024 per fuzz test;
invariants use 256 runs of 64 calls each with unexpected reverts treated as
failures. Every test constructs independent state and works in parallel.

- `test/Bites.t.sol`: metadata, constructor allocation and event, full/zero/self
  transfers, approvals, finite/infinite allowances, revocation, invalid addresses,
  insufficient balances and allowances, failure atomicity, and absent admin APIs.
  Fuzz cases check successful transfers and rejected overspending.
- `test/BitesFactory.t.sol`: CREATE2 deployment to a predicted address, allocation
  to the immediate factory, and exact transfers through distribution, claim, and
  pool-manager roles. These test token movements, not a real Uniswap pool or its
  pricing and settlement logic.
- `test/BitesInvariant.t.sol`: randomized transfers, approvals, delegated spends,
  and rejected overspends across five holders. Checks all balances and allowances
  against a separate accounting model and conserves the full supply.

See [DEPENDENCIES.md](DEPENDENCIES.md) for pinned upstream revisions and licenses.
The root Foundry configuration uses repository-local libraries and enables no FFI
or filesystem permissions. Inputs under `.imd/reads` and temporary files under
`test/scratch` are not required to build or test the delivered project.

## After launch

There are no owner settings or maintenance transactions. The launch operator is
responsible for deploying the reviewed artifact on Ethereum, verifying its source
and compiler settings, checking name/symbol/decimals/supply and the mint event,
and executing the launch's distribution and pool setup. Constructor allocation
must be checked at the deployment point, before the factory distributes tokens.
Factory deployment does not grant the factory any continuing privilege.

Holders control their balances and approvals. Wallets should display 18 decimals,
use the deployed contract address to identify BIT, and let holders revoke unused
allowances. When replacing an existing nonzero allowance, revoke it and confirm
that transaction before granting a new one to mitigate the standard ERC-20
approval race. Holders remain responsible for trusting approved spenders; the
token has no administrator who can reverse transactions or recover assets.

## Review scope

The supplied security reference was reviewed for input validation, accounting,
authorization, external calls, and upgrade risks. Bites introduces only a supply
constant and a constructor mint; its runtime makes no external calls. No oracle,
randomness, signature validation, or administrative access control is needed.
Tests deliberately retain standard zero-value transfers and unlimited-allowance
semantics for ERC-20 compatibility.

Local verification uses Foundry build, unit tests, fuzz tests, stateful invariants,
and formatting checks. The supplied protected checks were read as integration
requirements; their full launch harness, manifest inputs, and Uniswap contracts
are supplied by the independent verifier and are not included here. Slither,
Mythril, mainnet fork tests, and an independent security audit were not run.
Independent review and the launch system's protected checks remain release steps.
