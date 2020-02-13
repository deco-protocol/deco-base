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
    function join(uint pie) public;
    function exit(uint pie) public;
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

    event MintZCD(address usr, uint end, bytes32 class, uint dai);
    event BurnZCD(address usr, uint end, bytes32 class, uint dai);
    event MoveZCD(address src, address dst, uint end, bytes32 class, uint dai);

    event MintDCP(address usr, uint start, uint end, bytes32 class, uint pie);
    event BurnDCP(address usr, uint start, uint end, bytes32 class, uint pie);
    event MoveDCP(address src, address dst, uint start, uint end, bytes32 class, uint pie);
    event ChiSnapshot(uint time, uint chi);

    // --- Internal functions ---
    function mintZCD(address usr, uint end, uint dai) internal {
        bytes32 class = keccak256(abi.encodePacked(end));

        zcd[usr][class] = add(zcd[usr][class], dai);
        totalSupply = add(totalSupply, dai);
        emit MintZCD(usr, end, class, dai);
    }

    function burnZCD(address usr, uint end, uint dai) internal {
        bytes32 class = keccak256(abi.encodePacked(end));

        require(zcd[usr][class] >= dai, "zcd/insufficient-balance");

        zcd[usr][class] = sub(zcd[usr][class], dai);
        totalSupply = sub(totalSupply, dai);
        emit BurnZCD(usr, end, class, dai);
    }

    function mintDCP(address usr, uint start, uint end, uint pie) internal {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        dcp[usr][class] = add(dcp[usr][class], pie);
        emit MintDCP(usr, start, end, class, pie);
    }

    function burnDCP(address usr, uint start, uint end, uint pie) internal {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        require(dcp[usr][class] >= pie, "dcp/insufficient-balance");

        dcp[usr][class] = sub(dcp[usr][class], pie);
        emit BurnDCP(usr, start, end, class, pie);
    }

    // --- External and Public functions ---
    // Transfers ZCD balance of a certain class
    function moveZCD(address src, address dst, uint end, uint dai) external approved(src) {
        bytes32 class = keccak256(abi.encodePacked(end));

        require(zcd[src][class] >= dai, "zcd/insufficient-balance");

        zcd[src][class] = sub(zcd[src][class], dai);
        zcd[dst][class] = add(zcd[dst][class], dai);

        emit MoveZCD(src, dst, end, class, dai);
    }

    // Transfers DCP balance of a certain class
    function moveDCP(address src, address dst, uint start, uint end, uint pie) external approved(src) {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        require(dcp[src][class] >= pie, "dcp/insufficient-balance");

        dcp[src][class] = sub(dcp[src][class], pie);
        dcp[dst][class] = add(dcp[dst][class], pie);

        emit MoveDCP(src, dst, start, end, class, pie);
    }

    // Snapshots chi value at a particular time
    function snapshot() public returns (uint chi_) {
        chi_ = pot.drip();
        chi[now] = chi_;
        emit ChiSnapshot(now, chi_);
    }

    // Locks dai in DSR contract to mint ZCD and DCP balance
    function issue(address usr, uint end, uint pie) external approved(usr) {
        require(now <= end);

        uint dai = mul(pie, snapshot());
        vat.move(usr, address(this), dai);
        pot.join(pie);

        mintZCD(usr, end, dai);
        mintDCP(usr, now, end, pie);
    }

    // Redeem ZCD for dai after maturity
    function redeem(address usr, uint end, uint pie) external approved(usr) {
        require(now > end);

        uint dai = mul(pie, snapshot());
        pot.exit(pie);
        vat.move(address(this), usr, dai);

        burnZCD(usr, end, dai);
    }

    // Claims DCP coupon payments and deposits them as dai
    function claim(address usr, uint start, uint end, uint time) external approved(usr) {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        uint pie = dcp[usr][class];
        require(pie > 0);
        require((start <= time) && (time <= end));

        uint chiNow = snapshot();
        uint chiStart = chi[start];
        uint chiTime = chi[time];

        require((chiStart != 0) && (chiTime != 0) && (chiTime > chiStart));

        burnDCP(usr, start, end, pie);
        mintDCP(usr, time, end, rdiv(rmul(pie, chiStart), chiTime)); // division rounds down wad

        uint pieOut = mul(pie, sub(chiTime, chiStart)) / chiNow; // wad * ray / ray -> wad

        pot.exit(pieOut);
        vat.move(address(this), usr, mul(pieOut, chiNow));
    }

    // Merge equal amounts of ZCD and DCP of same class to withdraw dai
    function withdraw(address usr, uint end, uint pie) external approved(usr) {
        uint dai = mul(pie, snapshot());
        pot.exit(pie);
        vat.move(address(this), usr, dai);

        burnZCD(usr, end, dai);
        burnDCP(usr, now, end, pie); // DCP should be fully claimed
    }

    // Splits a single DCP into two contiguous DCPs
    function split(address usr, uint t1, uint t2, uint t3, uint pie) external approved(usr) {
        require(t1 < t2 && t2 < t3);

        burnDCP(usr, t1, t3, pie);
        mintDCP(usr, t1, t2, pie);
        mintDCP(usr, t2, t3, pie);
    }

    // Sets DCP start to time for which a snapshot is available
    function activate(address usr, uint start, uint end, uint time) external approved(usr) {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        require(chi[start] == 0);
        require(chi[time] != 0);
        require(start <= time && time <= end);
        require(start != time);
        
        uint pie = dcp[usr][class];
        burnDCP(usr, start, end, pie);
        mintDCP(usr, time, end, pie);
    }

    // Merges two contiguous DCPs into a single DCP
    function merge(address usr, uint t1, uint t2, uint t3, uint pie) external approved(usr) {
        require(t1 < t2 && t2 < t3);

        burnDCP(usr, t1, t2, pie);
        burnDCP(usr, t2, t3, pie);
        mintDCP(usr, t1, t3, pie);
    }
}