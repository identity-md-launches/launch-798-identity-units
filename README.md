# Identity Units (UI)

Identity Units is a fixed-supply ERC-20. Every transfer delivers its full amount;
there are no token fees, burns, rebases, exemptions, or administrative controls.

| Deployment parameter | Value |
| --- | --- |
| Contract | `src/IdentityUnits.sol:IdentityUnits` |
| Name / symbol | `Identity Units` / `UI` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in minor units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Constructor value | `0` |
| Initial recipient | Immediate constructor caller (`msg.sender`) |
| Solidity / EVM target | `0.8.26` / Paris |
| Optimizer | Enabled, 200 runs |
| Metadata bytecode hash | `none` |

The constructor is the only minting path. There is no owner, mint/burn interface,
pause, blacklist, seizure, upgrade, initialization, or external callback. A factory
deployment mints all tokens to the factory, not to the originating wallet. The
deployer has the same permissions as every other holder after construction.

## Build and check

With Foundry and Solidity 0.8.26 installed:

```sh
forge build
forge test
forge fmt --check
```

All Solidity dependencies are vendored as ordinary files under `lib/`, with
versions, archive checksums, and licenses recorded in `DEPENDENCIES.md`. No network
access is needed once the pinned compiler and Foundry are available. FFI and
filesystem cheatcode permissions are disabled. Tests need no environment variables,
RPC endpoint, wallet, or fork and each uses a fresh deployment.

Validation completed with Foundry 1.8.5 and Solidity 0.8.26: `forge build`,
`forge test`, and `forge fmt --check` passed. All 31 tests passed, including four
fuzz tests with 512 cases each and an invariant with 128 runs / 8,192 calls.
A clean copy containing only the delivered configuration, sources, tests, and
vendored libraries also passed an offline build, tests with four threads, and the
format check with an empty process environment.

Tests cover metadata and constructor allocation, CREATE2 factory deployment,
exact transfers and approvals, zero/self transfers, event emission, invalid
recipients, insufficient balances/allowances, atomic rollback, approval revocation,
infinite allowances, rejected admin calls, and runtime opcode restrictions. Fuzz
and stateful invariant tests check balances, allowances, and supply conservation.
The launch-route test models distributor claims and transfers to/from a pool
custodian. The supplied protected harness was read but was not run locally: it
requires the network's Uniswap v4 launch infrastructure, environment, and manifest,
which are not included in this standalone token assignment.

## Deployment and operation

The deployment operator uses the creation bytecode in
`out/IdentityUnits.sol/IdentityUnits.json`, with no constructor arguments or
initialization calls. Deploy the concrete contract directly using CREATE or
CREATE2; do not put it behind a proxy. No chain addresses are embedded in the token.
No deployment script, key access, or transaction broadcast is needed for this
deliverable.

For an IdentityMD custom launch, the manifest's token section should identify the
contract above, `constructorArgs: []`, the exact metadata above, and
`totalSupply: "1000000000000000000000000000"`. There are no application contracts.
The network launch operator supplies chain-specific factory/pool/distributor
addresses and the job's pool and economic parameters. Those parameters were not
provided here. Allocation (including the factory's swarm distribution) happens
through ordinary transfers after construction; it is not a token fee. The factory
must be able to forward its initial balance.

Before release, the operator is responsible for independent adversarial review,
checking the artifact and deployed bytecode with these compiler settings, source
verification, confirming the supply and its initial recipient, and validating the
network's launch integration. There are no ongoing privileged maintenance calls
or upgrade keys. The initial supply holder is responsible for custody and its
subsequent distribution; the token cannot reverse mistaken transfers or recover
assets sent to the token contract.

Standard ERC-20 behavior applies: nonzero recipient addresses may receive zero
amount transfers, self transfers preserve balances, zero-address transfers and
approvals revert, and `transferFrom` requires the caller's allowance even if the
caller is also the source. `approve` replaces an allowance; callers should revoke
and confirm an existing allowance before replacing it to limit the standard
approval transaction-ordering race. The maximum uint256 allowance is treated as
unlimited and is not decremented. OpenZeppelin 5 does not emit `Approval` when
`transferFrom` spends an allowance; consumers should query `allowance` for its
current value. Gas fees still apply on the chosen chain.

Local Foundry checks are evidence of tested behavior, not an independent security
audit. Slither and Mythril were not run.
