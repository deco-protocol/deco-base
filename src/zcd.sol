pragma solidity ^0.5.10;
// pragma experimental ABIEncoderV2;

import {DCP} from "./dcp.sol";

contract TokenLike {
    function transferFrom(address src, address dst, uint wad) public returns (bool);
    function approve(address usr, uint wad) external returns (bool);
}

contract AdapterLike {
    function join(address usr, uint wad) public;
    function exit(address usr, uint wad) public;
}

contract PotLike {
    function chi() external returns (uint);
    function drip() public;
    function join(uint wad) public;
    function exit(uint wad) public;
}

contract ZCD {
    // --- Contract Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external auth { wards[usr] = 1; }
    function deny(address usr) external auth { wards[usr] = 0; }
    modifier auth { require(wards[msg.sender] == 1); _; }

    // --- User Auth ---
    mapping(address => mapping (address => uint)) public can;
    function hope(address usr) external { can[msg.sender][usr] = 1; }
    function nope(address usr) external { can[msg.sender][usr] = 0; }
    function wish(address bit, address usr) internal view returns (bool) {
        return either(bit == usr, can[bit][usr] == 1);
    }

    // --- Lib ---
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }

    // --- Math ---
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // Contract addresses
    TokenLike public dai;
    AdapterLike public adapter;
    PotLike public pot;
    DCP public dcp;

    constructor(address dai_, address adapter_, address pot_) public {
        wards[msg.sender] = 1;

        dai = TokenLike(dai_);
        adapter = AdapterLike(adapter_);
        pot = PotLike(pot_);
        dcp = new DCP(dai_, adapter_, pot_, address(this));

        dai.approve(address(dcp), uint(-1));
    }

    struct Terms {
        address owner;
        uint256 end;
    }

    mapping (bytes32 => Terms) public terms;
    mapping (bytes32 => uint256) public zcd;
    uint256 public total;

    event Move(address src, address dst, uint256 end, uint256 wad);

    function move( 
        address src, 
        address dst, 
        uint256 end, 
        uint256 wad
    ) 
        external 
        returns (bool)
    {
        require(wish(src, msg.sender));

        bytes32 srcTerms = keccak256(abi.encodePacked(src, end));
        bytes32 dstTerms = keccak256(abi.encodePacked(dst, end));

        require(zcd[srcTerms] >= wad, "zcd/insufficient-balance");

        zcd[srcTerms] = sub(zcd[srcTerms], wad);
        zcd[dstTerms] = add(zcd[dstTerms], wad);

        // update usrTerms and dstTerms terms struct

        emit Move(src, dst, end, wad);
        return true;
    }

    function mint(address usr, uint256 end, uint256 wad) public auth {
        bytes32 usrTerms = keccak256(abi.encodePacked(usr, end));

        terms[usrTerms].owner = usr;
        terms[usrTerms].end = end;

        zcd[usrTerms] = add(zcd[usrTerms], wad);
        total = add(total, wad);
        emit Move(address(0), usr, end, wad);
    }

    function burn(address usr, uint256 end, uint256 wad) public auth {
        bytes32 usrTerms = keccak256(abi.encodePacked(usr, end));

        require(zcd[usrTerms] >= wad, "zcd/insufficient-balance");

        zcd[usrTerms] = sub(zcd[usrTerms], wad);
        total = sub(total, wad);
        emit Move(usr, address(0), end, wad);
    }

    // Issue new ZCD and DCP bonds for requested terms
    function issue(address usr, uint256 end, uint256 wad) public {
        require(wish(usr, msg.sender));

        uint depositAmt = mul(pot.chi(), wad);

        // Transfer and lock Dai in savings mode
        require(dai.transferFrom(usr, address(this), depositAmt));
        adapter.join(address(this), depositAmt);
        pot.join(wad);

        // issue zcd and dcp bonds to same owner
        mint(usr, end, depositAmt);
        dcp.mint(usr, now, end, depositAmt);
    }

    // Redeem ZCD bonds after maturity
    function redeem(address usr, uint256 end, uint256 wad) public {
        require(wish(usr, msg.sender));

        require(now > end);
        uint withdrawAmt = mul(pot.chi(), wad);

        burn(usr, end, withdrawAmt);

        // Remove Dai from savings mode and transfer to user
        pot.exit(wad);
        adapter.exit(usr, withdrawAmt);
        require(dai.transferFrom(address(this), usr, withdrawAmt));
    }

    // Redeem ZCD bonds before maturity
    function redeem(address usr, uint256 start, uint256 end, uint wad) public {
        require(wish(usr, msg.sender));

        uint withdrawAmt = mul(pot.chi(), wad);

        bytes32 usrTerms = keccak256(abi.encodePacked(usr, start, end));
        dcp.claim(usrTerms);

        burn(usr, end, withdrawAmt);
        dcp.burn(usr, start, end, withdrawAmt);

        // Remove Dai from savings mode and transfer to user
        pot.exit(wad);
        adapter.exit(usr, withdrawAmt);
        require(dai.transferFrom(address(this), usr, withdrawAmt));
    }
}