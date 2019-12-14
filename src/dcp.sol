pragma solidity ^0.5.10;

import {ZCD} from "./zcd.sol";

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

contract DCP {
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

    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, y) / ONE;
    }

    VatLike  public vat;
    TokenLike public dai;
    AdapterLike public adapter;
    PotLike public pot;
    ZCD public zcd;

    constructor(address dai_, address adapter_, address pot_) public {
        wards[msg.sender] = 1;

        dai = TokenLike(dai_);
        adapter = AdapterLike(adapter_);
        pot = PotLike(pot_);
        vat = pot.vat();
        zcd = ZCD(msg.sender);
    }

    mapping (uint => uint) public chiSnapshot; // time => value of chi at time

    mapping (address => mapping (bytes32 => uint)) public balanceOf; // user address => dcp class => balance in wad

    struct Class {
        uint start;
        uint end;
    }

    event Mint(address usr, uint start, uint end, uint wad);
    event Burn(address usr, uint start, uint end, uint wad);
    event Move(address src, address dst, uint start, uint end, uint wad);
    event ChiSnapshot(uint time, uint chi);

    // --- Internal functions ---
    function mint(address usr, uint start, uint end, uint wad) public auth {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        balanceOf[usr][class] = add(balanceOf[usr][class], wad);
        emit Mint(usr, start, end, wad);
    }

    function burn(address usr, uint start, uint end, uint wad) public auth {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        require(balanceOf[usr][class] >= wad, "dcp/insufficient-balance");

        balanceOf[usr][class] = sub(balanceOf[usr][class], wad);
        emit Burn(usr, start, end, wad);
    }

    // --- External and Public functions ---
    // Transfers DCP balance of a certain class
    function move(address src, address dst, uint start, uint end, uint wad) external returns (bool) {
        require(wish(src, msg.sender));

        bytes32 class = keccak256(abi.encodePacked(start, end));

        require(balanceOf[src][class] >= wad, "dcp/insufficient-balance");

        balanceOf[src][class] = sub(balanceOf[src][class], wad);
        balanceOf[dst][class] = add(balanceOf[dst][class], wad);

        emit Move(src, dst, start, end, wad);
        return true;
    }

    // Snapshots chi value at a particular time for future use
    function snapshot() public returns (uint chi_) {
        chi_ = pot.drip();
        chiSnapshot[now] = chi_;

        emit ChiSnapshot(now, chi_);
    }

    // Sets start to time for which a snapshot is available
    function activate(address usr, uint start, uint end, uint time) public {
        require(wish(usr, msg.sender));
        
        bytes32 class = keccak256(abi.encodePacked(start, end));

        require(chiSnapshot[start] == 0);
        require(chiSnapshot[time] != 0);
        require(start <= time && time <= end);
        require(start != time);

        burn(usr, start, end, balanceOf[usr][class]);
        mint(usr, time, end, balanceOf[usr][class]);
    }

    // Claims coupon payments and deposits them as dai
    function claim(address usr, uint start, uint end, uint time) public {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        uint balance = balanceOf[usr][class];
        uint startChi = chiSnapshot[start];
        uint timeChi = chiSnapshot[time];
        uint currentChi = snapshot();

        uint payment;
        uint val;

        require((startChi != 0) && (timeChi != 0) && (timeChi > startChi));
        require((start <= time) && (time <= end));

        payment = mul(balance, sub(timeChi, startChi)); // wad * ray -> rad
        require(payment > 0);

        burn(usr, start, end, balance);
        mint(usr, time, end, balance);

        val = payment / currentChi; // rad / ray -> wad
        payment = rmul(val, currentChi); // wad * ray -> wad

        pot.exit(val);
        adapter.exit(usr, payment);
        require(dai.transferFrom(address(zcd), usr, payment));
    }

    // Splits a single DCP into two contiguous DCPs
    function split(address usr, uint start, uint end, uint mid, uint wad) public {
        require(wish(usr, msg.sender));

        require(start > mid && mid > end);

        burn(usr, start, end, wad);

        mint(usr, start, mid, wad);
        mint(usr, add(mid, 1), end, wad);
    }

    // Merges two contiguous DCPs into a single DCP
    function merge(address usr, uint start1, uint end1, uint start2, uint end2, uint wad) public {
        require(wish(usr, msg.sender));

        require(add(end1, 1) == start2);

        burn(usr, start1, end1, wad);
        burn(usr, start2, end2, wad);

        mint(usr, start1, end2, wad);
    }
}