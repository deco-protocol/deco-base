# Zero Coupon Dai

Zero Coupon Dai allows users to strip coupon payments off interest bearing tokens. Users lock Dai to issue two assets- Zero Coupon Dai(ZCD) and Dai Coupon Payment(DCP).

Both ZCD and DCP are set to an expiry date which allows ZCD holders to redeem their balance for dai after expiry and DCP holders to claim dai savings rate coupon payments until expiry.

Some potential use cases for this zero coupon protocol are,

- Users can buy ZCD at a discount instead of Dai to receive a fixed savings rate for a certain term.
- DCP is a rate swap instrument which allows users to exchange a fixed savings rate(amount paid to buy DCP) for a floating Dai Savings Rate(future coupon payments DCP can claim). Vault holders can hedge the stability fee volatility contributed by frequent changes to DSR by holding a DCP balance equal to their debt and paying a fixed fee for a certain term.

## Deployment

*Please setup [dapp.tools](https://dapp.tools) and ensure `seth` works before proceeding. These variables need to be set in the `sethrc` file: `SETH_CHAIN`, `ETH_RPC_URL`, `ETH_KEYSTORE`, `ETH_FROM`.*

Setup repository locally.

```bash
# mainnet deployment - https://changelog.makerdao.com
export POT=0x197e90f9fad81970ba7976f33cbd77088e5d7cf7

# download repo
git clone git@github.com:makerdao/zero-coupon-dai.git
cd zero-coupon-dai

# build
dapp update
dapp build --extract # set DAPP_SOLC_VERSION=0.5.12 in .dapprc to compile dss
```

Deploy ZCD.

```bash
# deploy
seth send --create out/ZCD.bin 'ZCD(address)' $POT --gas 2500000 --gas-price $(seth --to-wei 2.1 gwei)
seth send --create out/ZCDProxyActions.bin 'ZCDProxyActions()' -G 2500000 -P $(seth --to-wei 2.1 gwei)

# save zcd contract addresses
export ZCD=0x423c04054b1a6711786642479338488158be6f00
export ZCD_ACTIONS=0x27ec574f560caed95c76fe1b32a2481adbd27f2b
```

## Usage

Setup DSProxy to interact with ZCD proxy actions.

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

seth send $DAI_TOKEN 'approve(address,uint)' $DAI_JOIN $(seth --to-uint256 $(seth --to-wei 100000000000 eth)) -G 100000 -P $(seth --to-wei 2 gwei)
seth send $DAI_JOIN "join(address,uint)" $ETH_FROM $(seth --to-uint256 $(seth --to-wei 15 eth)) -G 100000 -P $(seth --to-wei 2 gwei)

seth --to-dec $(seth call $VAT 'dai(address)(uint256)' $ETH_FROM)

```

Approve ZCD contract in Vat.

```bash
seth send $VAT 'hope(address)' $ZCD -G 100000 -P $(seth --to-wei 2 gwei)
```

Approve dsproxy contract in Vat and ZCD.

```bash
seth send $VAT 'hope(address)' $MY_PROXY -G 100000 -P $(seth --to-wei 2 gwei)
seth send $ZCD 'approve(address, bool)' $MY_PROXY  true -G 100000 -P $(seth --to-wei 2 gwei)
```

Issue ZCD and DCP at a certain expiry time.

```bash
seth send $ZCD 'issue(address,uint,uint)' $ETH_FROM $(seth --to-uint256 1578461936) $(seth --to-uint256 $(seth --to-wei 0.95 eth)) -G 1000000 -P $(seth --to-wei 2 gwei)
```

Check ZCD and DCP balances.

```bash
#check class in event logs
export ZCD_CLASS=0xab5251b6e40a4869e6c0585542a556290772213394710c8d1b078495d8ed5043
seth --to-dec $(seth call $ZCD 'zcd(address,bytes32)' $ETH_FROM $ZCD_CLASS)

export DCP_CLASS=0x4d7a964b7b1acd62d22891218f3ad1be63e282564c7ac9365776766d2178d115
seth --to-dec $(seth call $ZCD 'dcp(address,bytes32)' $ETH_FROM $DCP_CLASS)
```

Claim accrued DSR payments with DCP balance.

```bash
# take a snapshot of chi
seth send $ZCD 'snapshot()' -G 500000 -P $(seth --to-wei 2 gwei)

# use the time of last snapshot to process coupon payments
seth send $ZCD 'claim(address,uint,uint,uint)' $ETH_FROM $(seth --to-uint256 1578443604) $(seth --to-uint256 1578461936) $(seth --to-uint256 1578454019) -G 1000000 -P $(seth --to-wei 3 gwei)

# check balance (DCP class is updated after claim)
export DCP_CLASS_NEW=0xb0730eee0c9c06cdaf17190729e18b589c896701d839983693a934a123026493
seth --to-dec $(seth call $ZCD 'dcp(address,bytes32)' $ETH_FROM $DCP_CLASS_NEW)

# check vat.dai balance
seth --to-dec $(seth call $VAT 'dai(address)(uint256)' $ETH_FROM)
```

Redeem ZCD for Dai after expiry.

```bash
export ZCD_BALANCE=$(seth --to-dec $(seth call $ZCD 'zcd(address,bytes32)' $ETH_FROM $ZCD_CLASS))
seth send $ZCD 'redeem(address,uint,uint)' $ETH_FROM $(seth --to-uint256 1578461936) $ZCD_BALANCE

# check vat.dai balance
seth --to-dec $(seth call $VAT 'dai(address)(uint256)' $ETH_FROM)
```

## Misc

Additional [notes](https://gist.github.com/vamsiraju/a0b166e2138cf23c5e23debf04485992).
