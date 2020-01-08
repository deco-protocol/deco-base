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
    function join(uint wad) public;
    function exit(uint wad) public;
}

contract ZCDLike {
    function pot() external returns (PotLike);
    function zcd(address, bytes32) external returns (uint);
    function dcp(address, bytes32) external returns (uint);
    function chi(uint, uint) external returns (uint);
    function totalSupply() external returns (uint);
    function approvals(address, address) external returns (bool);
    function moveZCD(address, address, uint, uint) external;
    function moveDCP(address, address, uint, uint, uint) external;
    function issue(address, uint, uint) external;
    function withdraw(address, uint, uint) external;
    function redeem(address, uint, uint) external;
    function snapshot() public returns (uint);
    function activate(address, uint, uint, uint) external;
    function claim(address, uint, uint, uint) external;
    function split(address, uint, uint, uint, uint) external;
    function merge(address, uint, uint, uint, uint) external;
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
        rad = mul(wad, 10 ** 27);
    }
}

contract ZCDProxyActions is Common {
    // Calc and Issue
    function calcAndIssue(address zcd_, address usr, uint end, uint val) public {
        ZCDLike zcd = ZCDLike(zcd_);

        uint wad = rdiv(val, zcd.pot().drip());
        zcd.issue(usr, end, wad);
    }

    // Claim and Withdraw
    function claimAndWithdraw(address zcd_, address usr, uint start, uint end, uint wad) public {
        ZCDLike zcd = ZCDLike(zcd_);

        zcd.claim(usr, start, end, now);
        zcd.withdraw(usr, end, wad);
    }

    // Generate Dai and Issue ZCD
    function generateDaiAndIssueZCD(
        address zcd_,
        address vat_,
        address jug,
        bytes32 ilk_,
        address usr,
        uint end,
        uint wad
    ) public {
        ZCDLike zcd = ZCDLike(zcd_);
        VatLike vat = VatLike(vat_);

        uint rate = JugLike(jug).drip(ilk_);
        int  dart = toInt(mul(wad, ONE) / rate) + 1; // additional wei to fix precision issues
        vat.frob(ilk_, usr, usr, usr, 0, dart);
        zcd.issue(usr, end, wad);
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