# Split Protocol for DSR

Split protocol allows users to strip coupon payments off interest bearing dai in the Dai Savings Rate contract. Users lock Dai into Split to issue two assets- Zero Coupon Dai(ZCD) and Dai Coupon Payment(DCP).

Both ZCD and DCP are set to an expiry date which allows ZCD holders to redeem their balance for dai after expiry and DCP holders to claim dai savings rate coupon payments until expiry.

Some potential use cases for split protocol are,

- Users can buy ZCD at a discount instead of Dai to receive a fixed savings rate for a certain term.
- DCP is a rate swap instrument which allows users to exchange a fixed savings rate(amount paid to buy DCP) for a floating Dai Savings Rate(future coupon payments DCP can claim). Vault holders can hedge the stability fee volatility contributed by frequent changes to DSR by holding a DCP balance equal to their debt and paying a fixed fee for a certain term.

## Deployment

*Please setup [dapp.tools](https://dapp.tools) and ensure `seth` works before proceeding. These variables need to be set in the `sethrc` file: `SETH_CHAIN`, `ETH_RPC_URL`, `ETH_KEYSTORE`, `ETH_FROM`.*

Setup repository locally.

```bash
# mainnet deployment - https://changelog.makerdao.com
export POT=0x197e90f9fad81970ba7976f33cbd77088e5d7cf7

# download repo
git clone git@github.com:makerdao/split-dsr.git
cd split-dsr

# build
dapp update
dapp build --extract # set DAPP_SOLC_VERSION=0.5.12 in .dapprc to compile dss
```

Deploy SplitDSR contract.

```bash
# deploy
seth send --create out/SplitDSR.bin 'SplitDSR(address)' $POT --gas 2500000 --gas-price $(seth --to-wei 3 gwei)
seth send --create out/SplitDSRProxyActions.bin 'SplitDSRProxyActions()' -G 2500000 -P $(seth --to-wei 3 gwei)

# save split contract addresses
export SPLIT=0x76c27990d3125ea19dd17018a1dd019236f21d3f
export SPLIT_ACTIONS=0xf1695a8531cf772c95635237e85cebd60c54b594
```

## Setup

Setup DSProxy to interact with Split proxy actions.

```bash
export PROXY_REGISTRY=0x4678f0a6958e4d2bc4f1baf7bc52e8f3564f3fe4
seth call $PROXY_REGISTRY 'proxies(address)(address)' $ETH_FROM
seth send $PROXY_REGISTRY 'build()' -G 750000

export MY_PROXY=0x24510130e164aa8b3f10efc12593fc007e435503
```

Transfer DAI ERC20 tokens to your internal Vat Dai balance.

```bash
export DAI_TOKEN=0x6b175474e89094c44da98b954eedeac495271d0f
export DAI_JOIN=0x9759a6ac90977b93b58547b4a71c78317f391a28
export VAT=0x35d1b3f3d7966a1dfe207aa4514c12a259a0492b

seth send $DAI_TOKEN 'approve(address,uint)' $DAI_JOIN $(seth --to-uint256 $(seth --to-wei 100000000000 eth)) -G 100000 -P $(seth --to-wei 3 gwei)
seth send $DAI_JOIN "join(address,uint)" $ETH_FROM $(seth --to-uint256 $(seth --to-wei 15 eth)) -G 100000 -P $(seth --to-wei 3 gwei)

seth --to-dec $(seth call $VAT 'dai(address)(uint256)' $ETH_FROM)

```

Approve SplitDSR contract in Vat.

```bash
seth send $VAT 'hope(address)' $SPLIT -G 100000 -P $(seth --to-wei 3 gwei)
```

Approve dsproxy contract in Vat and Split.

```bash
seth send $VAT 'hope(address)' $MY_PROXY -G 100000 -P $(seth --to-wei 3 gwei)
seth send $SPLIT 'approve(address, bool)' $MY_PROXY  true -G 100000 -P $(seth --to-wei 3 gwei)
```

## Usage

Issue ZCD and DCP at a certain expiry time.

```bash
seth send $SPLIT 'issue(address,uint,uint)' $ETH_FROM $(seth --to-uint256 1578498359) $(seth --to-uint256 $(seth --to-wei 0.95 eth)) -G 1000000 -P $(seth --to-wei 3 gwei)
```

Check ZCD and DCP balances.

```bash
#check class in event logs
export ZCD_CLASS=0xf2d68dd021e5582307659fcf751490415d6e4067796a29437db37248f60d21fc #1578498359
seth --to-dec $(seth call $SPLIT 'zcd(address,bytes32)' $ETH_FROM $ZCD_CLASS)

export DCP_CLASS=0x072fae45b94c0f653c4c370164e8a11024374327828e746095fe5b38e774b734 # 1578496737 1578498359
seth --to-dec $(seth call $SPLIT 'dcp(address,bytes32)' $ETH_FROM $DCP_CLASS)
```

Claim accrued DSR payments with DCP balance.

```bash
# take a snapshot of chi
seth send $SPLIT 'snapshot()' -G 500000 -P $(seth --to-wei 3 gwei)

# use the time of last snapshot to process coupon payments
seth send $SPLIT 'claim(address,uint,uint,uint)' $ETH_FROM $(seth --to-uint256 1578496737) $(seth --to-uint256 1578498359) $(seth --to-uint256 1578497133) -G 1000000 -P $(seth --to-wei 3 gwei)

# check balance (DCP class is updated after claim)
export DCP_CLASS_NEW=0x7f37fa028c4a8dc75a26406e6c0ed75e6944b9af5f36b7e65b224ea687237141 # 1578497133 1578498359
seth --to-dec $(seth call $SPLIT 'dcp(address,bytes32)' $ETH_FROM $DCP_CLASS_NEW)

# check vat.dai balance
seth --to-dec $(seth call $VAT 'dai(address)(uint256)' $ETH_FROM)
```

Redeem ZCD for Dai after expiry using a proxy action.

```bash
export ZCD_BALANCE=$(seth call $SPLIT 'zcd(address,bytes32)' $ETH_FROM $ZCD_CLASS)
export REDEEM_CALLDATA=$(seth calldata 'calcAndRedeem(address,address,uint,uint)' $SPLIT $ETH_FROM $(seth --to-uint256 1578498359) $ZCD_BALANCE)

seth send $MY_PROXY 'execute(address,bytes memory)' $SPLIT_ACTIONS $REDEEM_CALLDATA -G 2000000 -P $(seth --to-wei 3 gwei)

# check vat.dai balance
seth --to-dec $(seth call $VAT 'dai(address)(uint256)' $ETH_FROM)
```

## Misc

Additional [notes](https://gist.github.com/vamsiraju/a0b166e2138cf23c5e23debf04485992).
