pragma solidity ^0.5.10;

contract VatLike {
    function can(address, address) public view returns (uint);
    function ilks(bytes32) public view returns (uint, uint, uint, uint, uint);
    function dai(address) public view returns (uint);
    function urns(bytes32, address) public view returns (uint, uint);
    function frob(bytes32, address, address, address, int, int) public;
    function hope(address) public;
    function move(address, address, uint) public;
}

contract JugLike {
    function drip(bytes32) public returns (uint);
}

contract PotLike {
    function vat() public returns (VatLike);
    function chi() external returns (uint ray);
    function rho() external returns (uint);
    function drip() public returns (uint);
    function join(uint pie) public;
    function exit(uint pie) public;
}

contract SplitDSRLike {
    function pot() external returns (PotLike);
    function zcd(address, bytes32) external returns (uint);
    function dcp(address, bytes32) external returns (uint);
    function chi(uint, uint) external returns (uint);
    function totalSupply() external returns (uint);
    function approvals(address, address) external returns (bool);
    function moveZCD(address, address, bytes32, uint) external;
    function moveDCP(address, address, bytes32, uint) external;
    function snapshot() public returns (uint);
    function issue(address, uint, uint) external;
    function redeem(address, uint, uint) external;
    function claim(address, uint, uint, uint) external;
    function withdraw(address, uint, uint) external;
    function slice(address, uint, uint, uint, uint) external;
    function sliceFuture(address, uint, uint, uint, uint, uint) external;
    function start(address, uint, uint, uint, uint) external;
    function merge(address, uint, uint, uint, uint, uint) external;
    function mergeFuture(address, uint, uint, uint, uint, uint) external;
}

contract DaiLike {
    function approve(address, uint) public;
    function transferFrom(address, address, uint) public;
}

contract DaiJoinLike {
    function vat() public returns (VatLike);
    function dai() public returns (DaiLike);
    function join(address, uint) public payable;
    function exit(address, uint) public;
}

contract Common {
    uint256 constant ONE = 10 ** 27;

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "mul-overflow");
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "sub-overflow");
    }

    function rdiv(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, ONE) / y;
    }

    function toInt(uint x) internal pure returns (int y) {
        y = int(x);
        require(y >= 0, "int-overflow");
    }

    function toRad(uint wad) internal pure returns (uint rad) {
        rad = mul(wad, ONE);
    }

    function toWad(uint rad) internal pure returns (uint wad) {
        wad = rad / ONE;

        // If the rad precision has some dust, it will need to request for 1 extra wad wei
        wad = mul(wad, ONE) < rad ? wad + 1 : wad;
    }

    // Inspiration from https://github.com/makerdao/dss-proxy-actions/blob/master/src/DssProxyActions.sol
    function daiJoin_join(address apt, address urn, uint wad) public {
        // Gets DAI from the user's wallet
        DaiJoinLike(apt).dai().transferFrom(msg.sender, address(this), wad);
        // Approves adapter to take the DAI amount
        DaiJoinLike(apt).dai().approve(apt, wad);
        // Joins DAI into the vat
        DaiJoinLike(apt).join(urn, wad);
    }
}

contract SplitDSRProxyActions is Common {
    // Calc and Issue
    function calcAndIssue(address split_, address daiJoin_, address usr, uint end, uint wad) public {
        SplitDSRLike split = SplitDSRLike(split_);

        daiJoin_join(daiJoin_, usr, wad);
        uint dai = toRad(wad);

        uint pie = rdiv(dai, split.pot().drip());
        split.issue(usr, end, pie);
    }

    // Calc and Redeem
    function calcAndRedeem(address split_, address daiJoin_, address usr, uint end, uint dai) public {
        SplitDSRLike split = SplitDSRLike(split_);

        uint pie = dai / split.pot().drip(); // rad / ray -> wad
        split.redeem(usr, end, pie);

        uint wad = toWad(dai);
        DaiJoinLike(daiJoin_).exit(usr, wad);
    }

    // Claim and Withdraw
    function claimAndWithdraw(address split_, address usr, uint start, uint end, uint pie) public {
        SplitDSRLike split = SplitDSRLike(split_);

        split.claim(usr, start, end, now);
        split.withdraw(usr, end, pie);
    }

    // Generate Dai and Issue ZCD
    function generateDaiAndIssueZCD(
        address split_,
        address vat_,
        address jug,
        bytes32 ilk_,
        address usr,
        uint end,
        uint pie
    ) public {
        SplitDSRLike split = SplitDSRLike(split_);
        VatLike vat = VatLike(vat_);

        uint rate = JugLike(jug).drip(ilk_);
        int  dart = toInt(mul(pie, ONE) / rate) + 1; // additional wei to fix precision issues
        vat.frob(ilk_, usr, usr, usr, 0, dart);
        split.issue(usr, end, pie);
    }

    // Claim and payback stability fee
    function claimAndPaybackStabilityFee() public {
        // TODO
    }

    // Redeposit claimed savings into pot
    function redepositClaimedSavings() public {
        // TODO
    }
}