pragma solidity ^0.5.10;

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

    constructor(address dai_, address adapter_, address pot_) public {
        wards[msg.sender] = 1;

        dai = TokenLike(dai_);
        adapter = AdapterLike(adapter_);
        pot = PotLike(pot_);
        vat = pot.vat();

        vat.hope(address(adapter));
        vat.hope(address(pot));

        dai.approve(address(adapter), uint(-1));
    }

    mapping (address => mapping (bytes32 => uint)) public zcd; // user address => zcd class => zcd balance in wad
    mapping (address => mapping (bytes32 => uint)) public dcp; // user address => dcp class => dcp balance in wad
    mapping (uint => uint) public chiSnapshot; // time => value of chi at time
    uint public totalSupply; // total ZCD supply

    struct classZCD {
        uint end;
    }

    struct classDCP {
        uint start;
        uint end;
    }

    event MintZCD(address usr, uint end, uint wad);
    event BurnZCD(address usr, uint end, uint wad);
    event MoveZCD(address src, address dst, uint end, uint wad);

    event MintDCP(address usr, uint start, uint end, uint wad);
    event BurnDCP(address usr, uint start, uint end, uint wad);
    event MoveDCP(address src, address dst, uint start, uint end, uint wad);
    event ChiSnapshot(uint time, uint chi);

    // --- Internal functions ---
    function mintZCD(address usr, uint end, uint wad) internal auth {
        bytes32 class = keccak256(abi.encodePacked(end));

        zcd[usr][class] = add(zcd[usr][class], wad);
        totalSupply = add(totalSupply, wad);
        emit MintZCD(usr, end, wad);
    }

    function burnZCD(address usr, uint end, uint wad) internal auth {
        bytes32 class = keccak256(abi.encodePacked(end));

        require(zcd[usr][class] >= wad, "zcd/insufficient-balance");

        zcd[usr][class] = sub(zcd[usr][class], wad);
        totalSupply = sub(totalSupply, wad);
        emit BurnZCD(usr, end, wad);
    }

    function mintDCP(address usr, uint start, uint end, uint wad) internal auth {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        dcp[usr][class] = add(dcp[usr][class], wad);
        emit MintDCP(usr, start, end, wad);
    }

    function burnDCP(address usr, uint start, uint end, uint wad) internal auth {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        require(dcp[usr][class] >= wad, "dcp/insufficient-balance");

        dcp[usr][class] = sub(dcp[usr][class], wad);
        emit BurnDCP(usr, start, end, wad);
    }

    // --- External and Public functions ---
    // Transfers ZCD balance of a certain class
    function moveZCD(address src, address dst, uint end, uint wad) external returns (bool) {
        require(wish(src, msg.sender));

        bytes32 class = keccak256(abi.encodePacked(end));

        require(zcd[src][class] >= wad, "zcd/insufficient-balance");

        zcd[src][class] = sub(zcd[src][class], wad);
        zcd[dst][class] = add(zcd[dst][class], wad);

        emit MoveZCD(src, dst, end, wad);
        return true;
    }

    // Transfers DCP balance of a certain class
    function moveDCP(address src, address dst, uint start, uint end, uint wad) external returns (bool) {
        require(wish(src, msg.sender));

        bytes32 class = keccak256(abi.encodePacked(start, end));

        require(dcp[src][class] >= wad, "dcp/insufficient-balance");

        dcp[src][class] = sub(dcp[src][class], wad);
        dcp[dst][class] = add(dcp[dst][class], wad);

        emit MoveDCP(src, dst, start, end, wad);
        return true;
    }

    // Locks dai in DSR contract to mint ZCD and DCP balance
    function issue(address usr, uint end, uint wad) public {
        require(wish(usr, msg.sender));

        uint val = rmul(wad, pot.drip());

        require(dai.transferFrom(usr, address(this), val));
        adapter.join(address(this), val);
        pot.join(wad);

        mintZCD(usr, end, val);
        mintDCP(usr, now, end, wad);
        snapshot();
    }

    // Merge equal amounts of ZCD and DCP of same class to withdraw dai
    function withdraw(address usr, uint start, uint end, uint wad) public {
        require(wish(usr, msg.sender));

        uint val = rmul(wad, pot.drip());

        claim(usr, start, end, now); // will fail if start is in the future

        burnZCD(usr, end, val);
        burnDCP(usr, start, end, wad);

        pot.exit(wad);
        adapter.exit(usr, val);
        require(dai.transferFrom(address(this), usr, val));
    }

    // Redeem ZCD for dai after maturity
    function redeem(address usr, uint end, uint wad) public {
        require(wish(usr, msg.sender));

        require(now > end);

        uint val = rmul(wad, pot.drip());

        burnZCD(usr, end, val);

        pot.exit(wad);
        adapter.exit(usr, val);
        require(dai.transferFrom(address(this), usr, val));
    }

    // Snapshots chi value at a particular time for future use
    function snapshot() public returns (uint chi_) {
        chi_ = pot.drip();
        chiSnapshot[now] = chi_;

        emit ChiSnapshot(now, chi_);
    }

    // Sets DCP start to time for which a snapshot is available
    function activate(address usr, uint start, uint end, uint time) public {
        require(wish(usr, msg.sender));
        
        bytes32 class = keccak256(abi.encodePacked(start, end));

        require(chiSnapshot[start] == 0);
        require(chiSnapshot[time] != 0);
        require(start <= time && time <= end);
        require(start != time);

        burnDCP(usr, start, end, dcp[usr][class]);
        mintDCP(usr, time, end, dcp[usr][class]);
    }

    // Claims DCP coupon payments and deposits them as dai
    function claim(address usr, uint start, uint end, uint time) public {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        uint balance = dcp[usr][class];
        uint startChi = chiSnapshot[start];
        uint timeChi = chiSnapshot[time];
        uint currentChi = snapshot();

        uint payment;
        uint val;

        require((startChi != 0) && (timeChi != 0) && (timeChi >= startChi));
        require((start <= time) && (time <= end));

        payment = mul(balance, sub(timeChi, startChi)); // wad * ray -> rad

        burnDCP(usr, start, end, balance);
        mintDCP(usr, time, end, balance);

        val = payment / currentChi; // rad / ray -> wad
        payment = rmul(val, currentChi); // wad * ray -> wad

        pot.exit(val);
        adapter.exit(usr, payment);
        require(dai.transferFrom(address(this), usr, payment));
    }

    // Splits a single DCP into two contiguous DCPs
    function split(address usr, uint start, uint end, uint mid, uint wad) public {
        require(wish(usr, msg.sender));

        require(start > mid && mid > end);

        burnDCP(usr, start, end, wad);

        mintDCP(usr, start, mid, wad);
        mintDCP(usr, add(mid, 1), end, wad);
    }

    // Merges two contiguous DCPs into a single DCP
    function merge(address usr, uint start1, uint end1, uint start2, uint end2, uint wad) public {
        require(wish(usr, msg.sender));

        require(add(end1, 1) == start2);

        burnDCP(usr, start1, end1, wad);
        burnDCP(usr, start2, end2, wad);

        mintDCP(usr, start1, end2, wad);
    }
}