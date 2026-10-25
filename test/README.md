# Bites test properties

The suite tests the deployed `Bites` implementation through its public interface.
The fixed supply is independently specified as `1_000_000_000 * 10 ** 18`;
expected values are not read from the token's supply constant.

## Discovery and coverage

The five discovery passes from the supplied Pashov fizz reference were applied
locally. The supplied Trail of Bits reference informed bounded input generation,
explicit boundary cases, and checks against vacuous properties. No external
runner, generated template, or additional dependency is required.

| Pass | Property and basis | Coverage |
| --- | --- | --- |
| Conservation | The constructor mints exactly `10^27` units once (`src/Bites.sol:10,14`); balances must sum to that fixed supply. | Existing constructor tests; `invariant_FixedSupplyAndExactBalances` checks every tracked balance and the aggregate after each handler call. |
| State transitions | Approvals replace the selected owner/spender pair; successful finite spends consume allowance; failed calls roll back (`ERC20.sol:132,154,284,305` in the vendored OpenZeppelin source). | Approval replacement and isolation fuzz tests, revocation, balance/allowance failures, zero-address failures, `invariant_ExactAllowances`. |
| Round trips | With no transfer fee or rounding, sending an amount out and back restores both balances (`ERC20.sol:188`); splitting a payment delivers the same total. | `roundTrip` handler checks both legs; round-trip and split-payment fuzz tests cover arbitrary minor-unit amounts. No share conversions or interest calculations exist. |
| Adversarial sequences | Approval cannot bypass the balance limit; authority is specific to both owner and spender; valid transfers remain possible after rejection (`ERC20.sol:154,171,193,305`). | Maximum-amount and self-transfer rejection tests, failed-spend/funding/retry fuzz test, revocation sequences, full-balance transfers in `afterInvariant`. |
| Token properties | Metadata stays Bites/BIT/18, zero transfers preserve balances, self-transfers preserve balances, zero-address transfers cannot burn tokens, and only `uint256.max` denotes unlimited approval. | Existing ERC-20 tests plus one-unit, maximum finite allowance, unlimited allowance, and zero-transfer edge cases; invariant metadata and zero-address checks. |

These are expected properties of the requested fixed-supply token and its
vendored ERC-20 behavior. They are not assumptions that a failing implementation
may override. No implementation defect was identified in this review.

## Stateful model

`BitesHandler` tracks five actors' expected balances and all 25 allowance pairs.
Only successful operations update that model. Amounts are bounded using model
state, not copied from potentially incorrect token getters. Rejections leave the
model untouched, except for any explicit preparatory approval made before the
rejected call. Exact revert data distinguishes balance and allowance failures.

All actors start funded, and seeded approvals make positive delegated transfers
reachable immediately. Eleven targeted actions mix valid transfers and spends
with full-balance moves, round trips, approval replacement, unlimited approval,
revocation, allowance overspending, balance overspending, and invalid recipients
or spenders. The allowance-overspend handler reduces an unlimited allowance to
the largest finite allowance instead of silently skipping the call.

The actor set is deliberately closed. Checks that the test contract, handler,
token contract and zero address hold no tokens describe this harness, not a rule
that arbitrary addresses cannot receive BIT. End-of-sequence consolidation
checks transfer liveness and a round trip of the entire supply. A deterministic
handler lifecycle test pins nonzero spending and every rejection branch so the
random campaign is not the only evidence that those paths work.

Inline settings select 1,024 runs for each new fuzz property and 256 invariant
sequences of depth 128, failing on unexpected handler reverts. The existing
constructor and factory tests remain in place. Factory tests exercise token-side
distribution flows; the external launch system's full protected integration
harness is not present in this repository and is not claimed as locally run.

## Reproduction

Run from the repository root with Foundry and Solidity 0.8.26 installed. All
Solidity imports are already vendored as ordinary files. No RPC, fork, FFI,
wallet, or environment mutation inside tests is used.

```sh
FOUNDRY_OUT=test/scratch/out FOUNDRY_CACHE_PATH=test/scratch/cache forge build --offline
FOUNDRY_OUT=test/scratch/out FOUNDRY_CACHE_PATH=test/scratch/cache FOUNDRY_FUZZ_FAILURE_PERSIST_DIR=test/scratch/cache/fuzz FOUNDRY_INVARIANT_FAILURE_PERSIST_DIR=test/scratch/cache/invariant FOUNDRY_FUZZ_SEED=0xe5f5f1fa10ff202a37a32a87fc595aa6c657d1f4027dcd66b2a8e35f69c22bb7 forge test --offline
```

The scratch paths only redirect generated build/check artifacts. No delivered
test imports anything from `test/scratch/` or `.imd/reads/`.
