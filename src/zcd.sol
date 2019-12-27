pragma solidity ^0.5.10;

contract VatLike {
    function hope(address) external;
    function move(address,address,uint256) external;
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
    function rdiv(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, ONE) / y;
    }

    // --- Approvals ---
    mapping(address => mapping (address => bool)) public approvals;

    event Approval(address indexed sender, address indexed usr, bool approval);
    
    function approve(address usr, bool approval) external {
        approvals[msg.sender][usr] = approval;
        emit Approval(msg.sender, usr, approval);
    }

    modifier approved(address usr) {
        require(either(msg.sender == usr, approvals[usr][msg.sender] == true));
        _;
    }

    VatLike  public vat;
    PotLike public pot;

    constructor(address pot_) public {
        pot = PotLike(pot_);
        vat = pot.vat();
        vat.hope(address(pot));
    }

    mapping (address => mapping (bytes32 => uint)) public zcd; // user address => zcd class => zcd balance [rad]
    mapping (address => mapping (bytes32 => uint)) public dcp; // user address => dcp class => dcp balance [wad]
    mapping (uint => uint) public chi; // time => pot.chi value [ray]
    uint public totalSupply; // total ZCD supply [rad]

    event MintZCD(address usr, uint end, uint rad);
    event BurnZCD(address usr, uint end, uint rad);
    event MoveZCD(address src, address dst, uint end, uint rad);

    event MintDCP(address usr, uint start, uint end, uint wad);
    event BurnDCP(address usr, uint start, uint end, uint wad);
    event MoveDCP(address src, address dst, uint start, uint end, uint wad);
    event ChiSnapshot(uint time, uint chi);

    // --- Private functions ---
    function mintZCD(address usr, uint end, uint rad) private {
        bytes32 class = keccak256(abi.encodePacked(end));

        zcd[usr][class] = add(zcd[usr][class], rad);
        totalSupply = add(totalSupply, rad);
        emit MintZCD(usr, end, rad);
    }

    function burnZCD(address usr, uint end, uint rad) private {
        bytes32 class = keccak256(abi.encodePacked(end));

        require(zcd[usr][class] >= rad, "zcd/insufficient-balance");

        zcd[usr][class] = sub(zcd[usr][class], rad);
        totalSupply = sub(totalSupply, rad);
        emit BurnZCD(usr, end, rad);
    }

    function mintDCP(address usr, uint start, uint end, uint wad) private {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        dcp[usr][class] = add(dcp[usr][class], wad);
        emit MintDCP(usr, start, end, wad);
    }

    function burnDCP(address usr, uint start, uint end, uint wad) private {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        require(dcp[usr][class] >= wad, "dcp/insufficient-balance");

        dcp[usr][class] = sub(dcp[usr][class], wad);
        emit BurnDCP(usr, start, end, wad);
    }

    // --- External and Public functions ---
    // Transfers ZCD balance of a certain class
    function moveZCD(address src, address dst, uint end, uint rad) external approved(src) {
        bytes32 class = keccak256(abi.encodePacked(end));

        require(zcd[src][class] >= rad, "zcd/insufficient-balance");

        zcd[src][class] = sub(zcd[src][class], rad);
        zcd[dst][class] = add(zcd[dst][class], rad);

        emit MoveZCD(src, dst, end, rad);
    }

    // Transfers DCP balance of a certain class
    function moveDCP(address src, address dst, uint start, uint end, uint wad) external approved(src) {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        require(dcp[src][class] >= wad, "dcp/insufficient-balance");

        dcp[src][class] = sub(dcp[src][class], wad);
        dcp[dst][class] = add(dcp[dst][class], wad);

        emit MoveDCP(src, dst, start, end, wad);
    }

    // Locks dai in DSR contract to mint ZCD and DCP balance
    function issue(address usr, uint end, uint wad) external approved(usr) {
        uint rad = mul(wad, snapshot());
        vat.move(usr, address(this), rad);
        pot.join(wad);

        mintZCD(usr, end, rad);
        mintDCP(usr, now, end, wad);
    }

    // Merge equal amounts of ZCD and DCP of same class to withdraw dai
    function withdraw(address usr, uint end, uint wad) external approved(usr) {
        uint rad = mul(wad, snapshot());
        pot.exit(wad);
        vat.move(address(this), usr, rad);

        burnZCD(usr, end, rad);
        burnDCP(usr, now, end, wad); // DCP should be fully claimed
    }

    // Redeem ZCD for dai after maturity
    function redeem(address usr, uint end, uint wad) external approved(usr) {
        require(now > end);

        uint rad = mul(wad, snapshot());
        pot.exit(wad);
        vat.move(address(this), usr, rad);

        burnZCD(usr, end, rad);
    }

    // Snapshots chi value at a particular time
    function snapshot() public returns (uint chi_) {
        chi_ = pot.drip();
        chi[now] = chi_;
        emit ChiSnapshot(now, chi_);
    }

    // Sets DCP start to time for which a snapshot is available
    function activate(address usr, uint start, uint end, uint time) external approved(usr) {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        require(chi[start] == 0);
        require(chi[time] != 0);
        require(start <= time && time <= end);
        require(start != time);
        
        uint wad = dcp[usr][class];
        burnDCP(usr, start, end, wad);
        mintDCP(usr, time, end, wad);
    }

    // Claims DCP coupon payments and deposits them as dai
    function claim(address usr, uint start, uint end, uint time) external {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        uint wad = dcp[usr][class];
        snapshot();

        require((chi[start] != 0) && (chi[time] != 0) && (chi[time] > chi[start]));
        require((start <= time) && (time <= end));
        require(wad > 0);

        burnDCP(usr, start, end, wad);
        mintDCP(usr, time, end, rdiv(rmul(wad, chi[start]), chi[time])); // division rounds down wad

        uint val = mul(wad, sub(chi[time], chi[start])) / chi[now]; // wad * ray / ray -> wad

        pot.exit(val);
        vat.move(address(this), usr, mul(val, chi[now]));
    }

    // Splits a single DCP into two contiguous DCPs
    function split(address usr, uint start, uint end, uint mid, uint wad) external approved(usr) {
        require(start > mid && mid > end);

        burnDCP(usr, start, end, wad);

        mintDCP(usr, start, mid, wad);
        mintDCP(usr, add(mid, 1), end, wad);
    }

    // Merges two contiguous DCPs into a single DCP
    function merge(address usr, uint start1, uint end1, uint start2, uint end2, uint wad) external approved(usr) {
        require(add(end1, 1) == start2);

        burnDCP(usr, start1, end1, wad);
        burnDCP(usr, start2, end2, wad);

        mintDCP(usr, start1, end2, wad);
    }
}