# Mutually Assured Destruction (MAD)

`src/MADToken.sol` — Solidity contract `MADToken` (the launch records it under this name).

| Parameter | Value |
|---|---|
| name() | Mutually Assured Destruction |
| symbol() | MAD |
| decimals() | 18 |
| totalSupply | 1,000,000,000 × 10^18 = `1000000000000000000000000000` |
| Constructor arguments | none |

## Behaviour and assumptions
- The whole supply is minted once, in the constructor, to `msg.sender` (the launch factory). No other mint exists; the supply can never grow.
- Plain ERC-20: no owner, no admin, no fees, no burn, no pause, no blacklist. So transfers to and from the factory, distributor and PoolManager move exactly the amount requested.
- `type(uint256).max` allowance is treated as infinite and is not decreased.
- Transfers to the zero address and approvals to the zero spender revert.

## Deployment
Deploy with no constructor arguments, using compiler 0.8.26 with optimizer at 200 runs and `bytecode_hash = "none"` (see `foundry.toml`). IMD's launch deploys it. This repository has no deploy script or keys.
Launch terms (set by the launch, not this repo): Ethereum mainnet, paired with FWA `0xa0df17b5ac76ababa36e1450e2cbcd18a620c845`, fee 12500, tick spacing 60, poolBps 6000, remainder to `0x1ee3ffadfe138415a2ddaedeebe5f46616fa413d`.

## Operational responsibilities
None. There are no privileged roles and nothing to configure after launch.

## After launch
Nothing to set.

## Verification
`forge build`, `forge test`, `forge fmt --check`. forge-std is vendored in `lib/forge-std`. These tests are not a security audit.
