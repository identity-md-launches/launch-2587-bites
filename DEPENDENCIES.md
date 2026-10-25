# Vendored dependencies

Dependencies are ordinary repository files, not submodules. No installation step
or network access is required for compilation. `dependencies.lock.json` records
the upstream commit, downloaded archive SHA-256, and SHA-256 of each vendored
file. The dependency files are unmodified upstream sources.

| Dependency | Version / commit | Included files | License |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/dbb6104ce834628e473d2173bbc9d47f81a9eec3) | v5.0.2 / `dbb6104ce834628e473d2173bbc9d47f81a9eec3` | ERC20, IERC20, IERC20Metadata, Context, IERC6093 errors and LICENSE | MIT |
| [forge-std](https://github.com/foundry-rs/forge-std/tree/3b20d60d14b343ee4f908cb8079495c07f5e8981) | v1.9.6 / `3b20d60d14b343ee4f908cb8079495c07f5e8981` | Complete `src/` tree and LICENSE-APACHE / LICENSE-MIT | Apache-2.0 or MIT |

OpenZeppelin is the only production dependency. forge-std is used only by tests.
The original licenses are included in each dependency's directory. Remappings
are explicit in `remappings.txt`. The pinned versions are intentional; dependency
updates require source review and rerunning the tests.
