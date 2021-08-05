# Deco Protocol

Deco is a simple and flexible protocol that can be attached to any yield protocol to decompose its yield token into zero-yield and pure-yield fixed-term assets: zeros and claims. Zero holders receive a fixed savings rate over a fixed term, and Claim holders take on the risk of rate volatility.

*Please refer to the [technical documentation](https://docs.deco.money) for information about the core protocol.*

## Base Repo

This base repo was designed to be modified to customize Deco for the specific needs of a yield protocol and its tokens. Our [integrations guide](https://docs.deco.money/#/build-integration) will explain the changes that need to be made to achieve your goals.

### Core

`core.sol` Deco Core

### Balance Adapters

`adapters/erc20_adapters.sol` Adapters to convert Deco internal balances to ERC20
`adapters/erc721_adapters.sol` Adapters to convert Deco internal balances to ERC721

### Installation and Tests

```bash
npm run clean
npm run build
npm run test

```

## Integrations

Current list of integrations:

### Maker Fixed-Rate Vaults

MakerDAO can issue tokens that permit Vault owner to hedge their stability fee for a fixed duration and for a specific collateral type. This proposed Deco and Maker integration uses a market driven solution so that vault owners of all sizes can hedge stability fees for any desired duration.

[Design Proposal](https://docs.deco.money/#/integrations/maker-vaults)

## License

