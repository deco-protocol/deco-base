pragma solidity ^0.5.10;

import {DCP} from "./dcp.sol";

contract VatLike {
    function hope(address) external;
}

contract TokenLike {
    function transferFrom(address src, address dst, uint wad) public returns (bool);
    function approve(address usr, uint wad) external returns (bool);
}

contract AdapterLike {
    function join(address usr, uint wad) public;
    function exit(address usr, uint wad) public;
}

contract PotLike {
    function vat() public returns (VatLike);
    function chi() external returns (uint ray);
    function rho() external returns (uint);
    function drip() public returns (uint);
    function join(uint wad) public;
    function exit(uint wad) public;
}

contract ZCD {
    // --- Contract Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external auth { wards[usr] = 1; }
    function deny(address usr) external auth { wards[usr] = 0; }
    modifier auth { require(wards[msg.sender] == 1); _; }

    // --- User Approvals ---
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
    uint256 constant ONE = 10 ** 27;

    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, y) / ONE;
    }

    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    VatLike  public vat;
    TokenLike public dai;
    AdapterLike public adapter;
    PotLike public pot;
    DCP public dcp;

    constructor(address dai_, address adapter_, address pot_) public {
        wards[msg.sender] = 1;

        dai = TokenLike(dai_);
        adapter = AdapterLike(adapter_);
        pot = PotLike(pot_);
        vat = pot.vat();
        dcp = new DCP(dai_, adapter_, pot_);

        vat.hope(address(adapter));
        vat.hope(address(pot));

        dai.approve(address(adapter), uint(-1));
        dai.approve(address(dcp), uint(-1));
    }

    mapping (address => mapping (bytes32 => uint)) public balanceOf; // user address => zcd class => balance in wad
    uint public totalSupply;

    struct Class {
        uint end;
    }

    event Mint(address usr, uint end, uint wad);
    event Burn(address usr, uint end, uint wad);
    event Move(address src, address dst, uint end, uint wad);

    // --- Internal functions ---
    function mint(address usr, uint end, uint wad) internal auth {
        bytes32 class = keccak256(abi.encodePacked(end));

        balanceOf[usr][class] = add(balanceOf[usr][class], wad);
        totalSupply = add(totalSupply, wad);
        emit Mint(usr, end, wad);
    }

    function burn(address usr, uint end, uint wad) internal auth {
        bytes32 class = keccak256(abi.encodePacked(end));

        require(balanceOf[usr][class] >= wad, "zcd/insufficient-balance");

        balanceOf[usr][class] = sub(balanceOf[usr][class], wad);
        totalSupply = sub(totalSupply, wad);
        emit Burn(usr, end, wad);
    }

    // --- External and Public functions ---
    // Transfers ZCD balance of a certain class
    function move(address src, address dst, uint end, uint wad) external returns (bool) {
        require(wish(src, msg.sender));

        bytes32 class = keccak256(abi.encodePacked(end));

        require(balanceOf[src][class] >= wad, "zcd/insufficient-balance");

        balanceOf[src][class] = sub(balanceOf[src][class], wad);
        balanceOf[dst][class] = add(balanceOf[dst][class], wad);

        emit Move(src, dst, end, wad);
        return true;
    }

    // Locks dai in DSR contract to mint ZCD and DCP balance
    function issue(address usr, uint end, uint wad) public {
        require(wish(usr, msg.sender));

        uint val = rmul(wad, pot.drip());

        require(dai.transferFrom(usr, address(this), val));
        adapter.join(address(this), val);
        pot.join(wad);

        mint(usr, end, val);
        dcp.mint(usr, now, end, val);
        dcp.snapshot();
    }

    // Merge equal amounts of ZCD and DCP of same class to withdraw dai
    function withdraw(address usr, uint start, uint end, uint wad) public {
        require(wish(usr, msg.sender));

        uint val = rmul(wad, pot.drip());

        dcp.claim(usr, start, end, now);

        burn(usr, end, val);
        dcp.burn(usr, start, end, val);

        pot.exit(wad);
        adapter.exit(usr, val);
        require(dai.transferFrom(address(this), usr, val));
    }

    // Redeem ZCD for dai after maturity
    function redeem(address usr, uint end, uint wad) public {
        require(wish(usr, msg.sender));

        require(now > end);

        uint val = rmul(wad, pot.drip());

        burn(usr, end, val);

        pot.exit(wad);
        adapter.exit(usr, val);
        require(dai.transferFrom(address(this), usr, val));
    }
}