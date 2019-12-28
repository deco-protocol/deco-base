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

contract ZCDLike {
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
    uint256 constant RAY = 10 ** 27;

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "mul-overflow");
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "sub-overflow");
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
    // Claim and Withdraw
    function claimAndWithdraw(address zcd_, address usr, uint start, uint end, uint wad) public {
        ZCDLike zcd = ZCDLike(zcd_);
        require(zcd.approvals(usr, msg.sender));

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
        int  dart = toInt(mul(wad, RAY) / rate) + 1; // additional wei to fix precision issues
        vat.frob(ilk_, usr, usr, usr, 0, dart);
        zcd.issue(usr, end, wad);
    }
}