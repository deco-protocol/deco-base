# Split Protocol for DSR

Split protocol allows users to exchange dai for two assets tied to a future maturity date- Zero Coupon Dai(ZCD) and Dai Claim Coupon(DCC). Split protocol then locks this dai in the Dai Savings Rate contract immediately and gives these guarantees to any ZCD and DCC asset holder,

- ZCD owner receives the original dai deposit after the maturity date.
- DCC owner receives the savings earnt by this dai deposit from issuance until maturity date.

Some benefits to owners of these assets are,

- ZCD owners earn a fixed savings rate until maturity since they are able to purchase it at a discount to dai today and redeem it for a full dai at maturity.
- Vault owners can fix the DSR portion of their stability fee by paying a fixed amount upfront to purchase DCC.

## Deployment

*Please setup [dapp.tools](https://dapp.tools) and ensure `seth` works before proceeding. These variables need to be set in the `sethrc` file: `SETH_CHAIN`, `ETH_RPC_URL`, `ETH_KEYSTORE`, `ETH_FROM`.*

Setup repository locally.

```bash
# kovan 1.0.6 deployment - https://changelog.makerdao.com
export POT=0xEA190DBDC7adF265260ec4dA6e9675Fd4f5A78bb

# download repo
git clone git@github.com:makerdao/split-dsr.git
cd split-dsr

# build
dapp update
dapp build --extract # DAPP_SOLC_VERSION=0.5.12 is set in .dapprc
```

Deploy contracts.

```bash
# Deploy ValueDSR used for emergency shutdown
export VALUEDSR=$(dapp create ValueDSR)

# Deploy Core Split contract
export SPLITDSR=$(dapp create SplitDSR $POT $VALUEDSR)
seth send $VALUEDSR 'init(address)' $SPLITDSR # Initialize ValueDSR with SplitDSR address

# Deploy ERC20 adapter contracts
export ZCDERC20=$(dapp create ZCDAdapterERC20 $(seth --to-uint256 42) $SPLITDSR)
export DCCERC20=$(dapp create DCCAdapterERC20 $(seth --to-uint256 42) $SPLITDSR)

# Deploy ERC721 adapter contracts
export ZCDERC721=$(dapp create ZCDAdapterERC721 $SPLITDSR)
export DCCERC721=$(dapp create DCCAdapterERC721 $SPLITDSR)

# Deploy Proxy actions contract
export SPLITACTIONS=$(dapp create SplitDSRProxyActions)
```

Kovan deployment.

```bash
export POT=0xEA190DBDC7adF265260ec4dA6e9675Fd4f5A78bb
export VAT=0xbA987bDB501d131f766fEe8180Da5d81b34b69d9
export DAI=0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa
export JOIN_DAI=0x5AA71a3ae1C0bd6ac27A1f28e1415fFFB6F15B8c
export VALUEDSR=0x28c51E14eB70DD8d057eE6250D5c71CC6E3B0998
export SPLITDSR=0x688fc01c53bF95f7cB867304A3b30755D786224D
export ZCDERC20=0xD18246E4bbc07387B38445c99b3E95D70964d545
export DCCERC20=0x45906a70aBf9f3e887B6791C00a12156870cc97c
export ZCDERC721=0x4281f006C7d427b09091b613b8d9D24270484E79
export DCCERC721=0x1EECCc4D07776DB0BEA2a941fC9024A2992aFDD8
export SPLITACTIONS=0xdfbA09aE700CF14F00d36765674DD43d797FB9ed
```

## Setup

Setup DSProxy to interact with Split proxy actions.

```bash
export PROXY_REGISTRY=0x64A436ae831C1672AE81F674CAb8B6775df3475C
export ETH_FROM=0x6a3AE20C315E845B2E398e68EfFe39139eC6060C
seth call $PROXY_REGISTRY 'proxies(address)(address)' $ETH_FROM
seth send $PROXY_REGISTRY 'build()' -G 750000

export MY_PROXY=0xDee6D78d92a06250031af241e7Dc2b81aF37e26f
```

Transfer DAI ERC20 tokens to your internal Vat Dai balance.

```bash
seth send $DAI 'approve(address,uint)' $JOIN_DAI $(seth --to-uint256 $(seth --to-wei 100000000000 eth)) -G 100000 -P $(seth --to-wei 3 gwei)
seth send $JOIN_DAI "join(address,uint)" $ETH_FROM $(seth --to-uint256 $(seth --to-wei 15 eth)) -G 100000 -P $(seth --to-wei 3 gwei)

seth --to-dec $(seth call $VAT 'dai(address)(uint256)' $ETH_FROM)

```

Approve SplitDSR contract in Vat.

```bash
seth send $VAT 'hope(address)' $SPLITDSR -G 100000 -P $(seth --to-wei 3 gwei)
```

Approve dsproxy contract in Vat and Split.

```bash
seth send $VAT 'hope(address)' $MY_PROXY -G 100000 -P $(seth --to-wei 3 gwei)
seth send $SPLITDSR 'approve(address, bool)' $MY_PROXY  true -G 100000 -P $(seth --to-wei 3 gwei)
```

## Usage

Issue ZCD and DCC at a maturity date.

```bash
seth send $SPLITDSR 'issue(address,uint,uint)' $ETH_FROM $(seth --to-uint256 1609372800) $(seth --to-uint256 $(seth --to-wei 0.95 eth)) -G 1000000 -P $(seth --to-wei 3 gwei)
```

Check ZCD and DCC balances.

```bash
#check event #6 for zcd class in transaction
export ZCD_CLASS=0x1a5e4e30f8f4368aa7a60437c84cb7180dcca8cd3ff3d719a76e663d7ec0b2f6
export ZCD_END=1609372800
seth --to-dec $(seth call $SPLITDSR 'zcd(address,bytes32)' $ETH_FROM $ZCD_CLASS)

#check event #7 for dcc class in transaction
export DCC_CLASS=0xd729ce82b67cd8cd0cef9e16b90d7615f757aa5ea177378087bba66aa6cb38f0
export DCC_START=1589766772
export DCC_END=1609372800
seth --to-dec $(seth call $SPLITDSR 'dcc(address,bytes32)' $ETH_FROM $DCC_CLASS)
```

These assets can be transferred to others using `moveZCD` and `moveDCC` functions.

Claim accrued DSR payments with your DCC asset balance.

```bash
# take a snapshot of chi to use later
seth send $SPLITDSR 'snapshot()' -G 500000 -P $(seth --to-wei 3 gwei)

# note down timestamp of snapshot from event logs
export SNAPSHOT1=1589766988

# use a previous snapshot to claim DSR earnings for DCC
seth send $SPLITDSR 'claim(address,uint,uint,uint,uint)' $ETH_FROM $(seth --to-uint256 $DCC_START) $(seth --to-uint256 $DCC_END) $(seth --to-uint256 $SNAPSHOT1) $(seth --to-dec $(seth call $SPLITDSR 'dcc(address,bytes32)' $ETH_FROM $DCC_CLASS)) -G 1000000 -P $(seth --to-wei 3 gwei)

# check balance (DCC class is updated after claim when start is reset)
export DCC_CLASS_NEW=0x57addb7077ff7cbb1a297fd5c171c285649305280b45825ebb1098489a773d03
export DCC_START=1589766988
seth --to-dec $(seth call $SPLITDSR 'dcc(address,bytes32)' $ETH_FROM $DCC_CLASS_NEW)

# check vat.dai balance
seth --to-dec $(seth call $VAT 'dai(address)(uint256)' $ETH_FROM)
```

Redeem your ZCD asset balance for Dai after expiry using a proxy action.

```bash
export ZCD_BALANCE=$(seth call $SPLITDSR 'zcd(address,bytes32)' $ETH_FROM $ZCD_CLASS)
export REDEEM_CALLDATA=$(seth calldata 'redeemNow(address,address,uint,uint)' $SPLITDSR $ETH_FROM $(seth --to-uint256 $ZCD_END) $ZCD_BALANCE)

seth send $MY_PROXY 'execute(address,bytes memory)' $SPLITACTIONS $REDEEM_CALLDATA -G 2000000 -P $(seth --to-wei 3 gwei)

# check vat.dai balance
seth --to-dec $(seth call $VAT 'dai(address)(uint256)' $ETH_FROM)
```
