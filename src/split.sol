pragma solidity 0.5.12;

contract VatLike {
    function hope(address) external;
    function move(address,address,uint256) external;
}

contract PotLike {
    function vat() public returns (VatLike);
    function chi() external returns (uint ray);
    function rho() external returns (uint);
    function live() public returns (uint);
    function drip() public returns (uint);
    function join(uint pie) public;
    function exit(uint pie) public;
}

contract ValueDSRLike {
    function split() public returns (address);
    function initialized() public returns (bool);
    function zcd(uint,uint) public returns (uint);
    function dcc(uint,uint) public returns (uint);
}

contract SplitDSR {
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
    mapping(address => mapping (address => bool)) public approvals; // holder address => approved address => approval status

    event Approval(address indexed sender, address indexed usr, bool approval);

    // Allow/disallow an address to perform actions on balances within split and adapters
    function approve(address usr, bool approval) external {
        approvals[msg.sender][usr] = approval;
        emit Approval(msg.sender, usr, approval);
    }

    modifier approved(address usr) {
        require(either(msg.sender == usr, approvals[usr][msg.sender] == true));
        _;
    }

    VatLike public vat;
    PotLike public pot;
    address public gov; // governance contract

    ValueDSRLike public value; // Reports ZCD and DCC valuation to process emergency shutdown
    uint public last; // Split emergency shutdown timestamp

    constructor(address pot_, address value_) public {
        gov = msg.sender;

        pot = PotLike(pot_);
        vat = pot.vat();
        value = ValueDSRLike(value_);

        last = uint(-1); // Initialized to MAX_UINT and updated after emergency shutdown is triggered on Pot
        vat.hope(address(pot)); // Approve Pot to modify Split's Dai balance within Vat
    }

    mapping (address => mapping (bytes32 => uint)) public zcd; // user address => zcd class => zcd balance [rad: 45 decimal fixed point number]
    mapping (address => mapping (bytes32 => uint)) public dcc; // user address => dcc class => dcc balance [wad: 18 decimal fixed point number]
    mapping (uint => uint) public chi; // time => pot.chi value [ray: 27 decimal fixed point number]
    uint public totalSupply; // total ZCD supply [rad]

    // dai : vat uses the rad number type to track dai balances
    // pie : pot uses the wad number type to track pie balances

    event MintZCD(address indexed usr, bytes32 indexed class, uint end, uint dai);
    event BurnZCD(address indexed usr, bytes32 indexed class, uint end, uint dai);
    event MintDCC(address indexed usr, bytes32 indexed class, uint start, uint end, uint pie);
    event BurnDCC(address indexed usr, bytes32 indexed class, uint start, uint end, uint pie);
    event MintFutureDCC(address indexed usr, bytes32 indexed class, uint start, uint slice, uint end, uint pie);
    event BurnFutureDCC(address indexed usr, bytes32 indexed class, uint start, uint slice, uint end, uint pie);
    event MoveZCD(address indexed src, address indexed dst, bytes32 indexed class, uint dai);
    event MoveDCC(address indexed src, address indexed dst, bytes32 indexed class, uint pie);
    event ChiSnapshot(uint time, uint chi);

    // --- Governance Modifiers ---
    modifier onlyGov() {
        require(msg.sender == gov);
        _;
    }

    // --- Emergency Shutdown Modifiers ---
    modifier untilLast(uint time) {
        require(time <= last); // execute normally when input timestamp is before or at emergency shutdown timestamp
        _;
    }

    modifier afterLast(uint time) {
        require(last < time); // allow emergency shutdown processing when input timestamp is after emergency shutdown timestamp
        _;
    }

    // --- Internal functions ---
    // Mint ZCD balance with maturity set to end timestamp
    function mintZCD(address usr, uint end, uint dai) internal {
        bytes32 class = keccak256(abi.encodePacked(end));

        zcd[usr][class] = add(zcd[usr][class], dai);
        totalSupply = add(totalSupply, dai);
        emit MintZCD(usr, class, end, dai);
    }

    // Burn ZCD balance with maturity set to end timestamp
    function burnZCD(address usr, uint end, uint dai) internal {
        bytes32 class = keccak256(abi.encodePacked(end));

        require(zcd[usr][class] >= dai, "zcd/insufficient-balance");

        zcd[usr][class] = sub(zcd[usr][class], dai);
        totalSupply = sub(totalSupply, dai);
        emit BurnZCD(usr, class, end, dai);
    }

    // Mint DCC balance with start and end timestamps
    function mintDCC(address usr, uint start, uint end, uint pie) internal {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        dcc[usr][class] = add(dcc[usr][class], pie);
        emit MintDCC(usr, class, start, end, pie);
    }

    // Burn DCC balance with start and end timestamps
    function burnDCC(address usr, uint start, uint end, uint pie) internal {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        require(dcc[usr][class] >= pie, "dcc/insufficient-balance");

        dcc[usr][class] = sub(dcc[usr][class], pie);
        emit BurnDCC(usr, class, start, end, pie);
    }

    // Mint Future DCC balance with start, slice, and end timestamps
    function mintFutureDCC(address usr, uint start, uint slice, uint end, uint pie) internal {
        bytes32 class = keccak256(abi.encodePacked(start, slice, end));

        dcc[usr][class] = add(dcc[usr][class], pie);
        emit MintFutureDCC(usr, class, start, slice, end, pie);
    }

    // Burn Future DCC balance with start, slice, and end timestamps
    function burnFutureDCC(address usr, uint start, uint slice, uint end, uint pie) internal {
        bytes32 class = keccak256(abi.encodePacked(start, slice, end));

        require(dcc[usr][class] >= pie, "dcc/insufficient-balance");

        dcc[usr][class] = sub(dcc[usr][class], pie);
        emit BurnFutureDCC(usr, class, start, slice, end, pie);
    }

    // --- External and Public functions ---
    // Update governance address
    function updateGov(address newGov) public onlyGov {
        gov = newGov;
    }

    // Transfer ZCD balance
    function moveZCD(address src, address dst, bytes32 class, uint dai) external approved(src) {
        require(zcd[src][class] >= dai, "zcd/insufficient-balance");

        zcd[src][class] = sub(zcd[src][class], dai);
        zcd[dst][class] = add(zcd[dst][class], dai);

        emit MoveZCD(src, dst, class, dai);
    }

    // Transfer DCC or FutureDCC balance
    function moveDCC(address src, address dst, bytes32 class, uint pie) external approved(src) {
        require(dcc[src][class] >= pie, "dcc/insufficient-balance");

        dcc[src][class] = sub(dcc[src][class], pie);
        dcc[dst][class] = add(dcc[dst][class], pie);

        emit MoveDCC(src, dst, class, pie);
    }

    // Snapshot and store updated chi value at current block timestamp
    function snapshot() public returns (uint chi_) {
        chi_ = pot.drip(); // Update chi in Pot
        chi[now] = chi_;
        emit ChiSnapshot(now, chi_);
    }

    // Insert a chi value at timestamp between two existing snapshots
    function insert(uint t0, uint t1, uint t2, uint chi) public onlyGov {
        require(t0 < t1 < t2); // snapshot set for t1 needs to be between t0 and t2
        require(t0 >= t1 - 3 days); // t0 needs to be within 3 days of t1
        require(t2 <= t1 + 3 days); // t2 needs to be within 3 days after t1

        require(chi[t1] == 0); // timestamp should not have an existing snapshot
        require(chi[t0] <= chi <= chi[t2]); // chi value at t1 needs to be in between chi values at t0 and t2

        chi[t1] = chi; // set input chi value at t1
        emit ChiSnapshot(t1, chi);
    }

    // Issue ZCD and DCC in exchange for dai
    // * User transfers dai balance to Split
    // * User receives ZCD balance equal to the dai balance which we'll refer to as the notional amount
    // * User receives DCC balance equal to the pie balance of the DSR deposit (pie = dai notional amount / current chi value)
    function issue(address usr, uint end, uint pie) external approved(usr) untilLast(now) {
        require(now <= end); // Assets can only be issued with future maturity

        uint dai = mul(pie, snapshot()); // Calculate dai amount with pie input. pie is the equivalent normalized dai balance stored in Pot at current chi value: pie * chi = dai
        vat.move(usr, address(this), dai); // Move dai from usr to Split
        pot.join(pie); // Split deposits dai into Pot

        mintZCD(usr, end, dai); // Mint ZCD balance for dai amount at end. dai is 45 decimal fixed point number.
        mintDCC(usr, now, end, pie); // Mint DCC balance for pie value between now and end timestamps. pie is 18 decimal fixed point number.
    }

    // Redeem ZCD for dai after maturity
    // * User transfers ZCD balance to Split
    // * User receives dai balance equal to the ZCD balance
    // * User receives DSR earnt on this dai balance after end until redemption if a valid snapshot is present
    function redeem(address usr, uint end, uint snap, uint dai) external approved(usr) untilLast(end) {
        require((end <= snap) && (snap <= now)); // Redemption can happen only after end timestamp is past. Snap timestamp needs to be after end but before now.

        uint chiSnap = chi[snap]; // chi value at snap timestamp
        uint chiNow = snapshot(); // current chi value
        require(chiSnap != 0); // ensure a valid chi snapshot exists before calculating any DSR earnt

        burnZCD(usr, end, dai); // Burn ZCD balance

        // Calculate pie assuming user redeemed dai in the past at end timestamp and deposited it in Pot at snap timestamp
        uint pie = dai / chiSnap; // rad / ray -> wad
        pot.exit(pie); // pie removed from Pot
        vat.move(address(this), usr, mul(pie, chiNow)); // Total payout to user is redeemed dai + dsr earnt from snap timestamp until now
    }

    // Claim dai earnt by DCC balance from the Dai Savings Rate
    // * User transfers DCC balance to Split
    // * User receives dai earnt from DSR by this pie balance beween start and snap timestamps
    // * DCC balance burnt for the time period between start and snap timestamps
    // * User receives DCC balance with new class for remaining time period between snap and end timestamps
    function claim(address usr, uint start, uint end, uint snap, uint pie) external approved(usr) untilLast(snap) {
        require((start <= snap) && (snap <= end));

        uint chiNow = snapshot(); // current chi value
        uint chiStart = chi[start]; // chi value at start timestamp
        uint chiSnap = chi[snap]; // chi value at snap timestamp

        require((chiStart != 0) && (chiSnap != 0) && (chiSnap > chiStart));

        burnDCC(usr, start, end, pie); // Burn entire DCC balance

        // Mint DCC balance for remaining time period between snap and end
        // This balance won't be usable if end is in the past and no other snapshot between snap and end exists
        // Division rounds down and new balance might be slightly lower
        mintDCC(usr, snap, end, rdiv(rmul(pie, chiStart), chiSnap));

        // dai earnt by deposit as savings between two chi values is moved out. Deposit remains in Pot.
        uint pieOut = mul(pie, sub(chiSnap, chiStart)) / chiNow; // wad * ray / ray -> wad

        pot.exit(pieOut);
        vat.move(address(this), usr, mul(pieOut, chiNow)); // Dai earnt sent to DCC owner
    }

    // Rewind start timestamp of DCC balance to a past snapshot timestamp (opposite of claim which forwards start timestamp to a future snapshot)
    // * User transfers DCC balance
    // * User transfers dai balance to cover the additional savings they will be entitled to after rewind
    // * User receives DCC balance at new class with start timestamp set to an earlier chi snapshot
    function rewind(address usr, uint start, uint end, uint snap, uint pie) external approved(usr) untilLast(now) {
        require((snap <= start) && (start <= end));

        uint chiNow = snapshot();
        uint chiSnap = chi[snap];
        uint chiStart = chi[start];

        require((chiSnap != 0) && (chiStart != 0) && (chiSnap < chiStart));

        uint notional = mul(pie, chiStart); // notional amount in dai earning DSR from start for current dcc balance. wad * ray -> rad
        uint pieSnap = notional / chiSnap; // pie value for the same notional amount if deposited at the earlier snap timestamp. rad / ray -> wad

        // New total dai amount at start timestamp with earlier deposit = notional amount + dai earnt from dsr between snap and start timestamps
        uint total = mul(pieSnap, chiStart); // wad * ray -> rad 

        burnDCC(usr, start, end, pie); // Burn old DCC balance between start and end timestamps

        // New DCC balance is higher to reflect the same dai notional amount earning DSR starting from an earlier timestamp
        mintDCC(usr, snap, end, pieSnap); // Mint new DCC balance between snap and end timestamps.

        // Difference between new total and old notional amount at the start timestamp, in pie terms at current chi value
        uint pieIn = sub(total, notional) / chiNow; // (rad - rad) / ray -> wad

        vat.move(usr, address(this), mul(pieIn, chiNow)); // Collect dai from user for this adjustment
        pot.join(pieIn); // Deposit dai in Pot
    }

    // Withdraw ZCD and DCC before maturity to dai
    // * User transfers ZCD balance with an end timestamp
    // * User transfers DCC balance with savings claimed until now and the same end timestamp as ZCD
    // * User receives dai from Split equal to both their dai notional amounts
    function withdraw(address usr, uint end, uint pie) external approved(usr) untilLast(now) {
        uint dai = mul(pie, snapshot()); // dai notional amount calculated from input pie value
        pot.exit(pie);
        vat.move(address(this), usr, dai);

        burnZCD(usr, end, dai);
        burnDCC(usr, now, end, pie); // DCC balance needs to be claimed from its start until current timestamp
    }

    // Slice a DCC balance at a future timestamp into contiguous DCC and FutureDCC balances
    // * User transfers DCC balance with t1 and t3 timestamps
    // * User receives DCC balance with t1 and t2 timestamps
    // * User receives FutureDCC balance that can be converted later to regular DCC balance with t2 and t3 timestamps
    function slice(address usr, uint t1, uint t2, uint t3, uint pie) external approved(usr) {
        require(t1 < t2 && t2 < t3); // slice timestamp t2 needs to be between t1 and t3

        burnDCC(usr, t1, t3, pie);
        mintDCC(usr, t1, t2, pie);
        mintFutureDCC(usr, t1, t2, t3, pie); // Earns DSR between t2 and t3 timestamps on the original dai notional amount (pie * chi[t1])
    }

    // Merge continguous DCC and FutureDCC balances into a DCC balance
    // * User transfers a DCC balance with t2 and t3 timestamps
    // * User transfers a FutureDCC with t1, t3 and t4 timestamps
    // * User receives a DCC balance with t2 and t4 timestamps
    function merge(address usr, uint t1, uint t2, uint t3, uint t4, uint pie) external approved(usr) {
        require(t1 <= t2 && t2 < t3 && t3 < t4); // t1 can equal t2
        uint futurePie = (t1 == t2) ? pie : mul(pie, chi[t2]) / chi[t1]; // FutureDCC balance that needs to be burnt if t1 and t2 are not equal

        burnDCC(usr, t2, t3, pie);
        burnFutureDCC(usr, t1, t3, t4, futurePie);
        mintDCC(usr, t2, t4, pie);
    }

    // Slice a FutureDCC balance into two contiguous FutureDCC balances
    // * User transfers FutureDCC balance with t1, t2 and t4 timestamps
    // * User receives FutureDCC balance with t1, t2 and t3 timestamps
    // * User receives FutureDCC balance with t1, t3 and t4 timestamps
    function sliceFuture(address usr, uint t1, uint t2, uint t3, uint t4, uint pie) external approved(usr) {
        require(t1 < t2 && t2 < t3 && t3 < t4);

        burnFutureDCC(usr, t1, t2, t4, pie);
        mintFutureDCC(usr, t1, t2, t3, pie);
        mintFutureDCC(usr, t1, t3, t4, pie);
    }

    // Merge two continguous FutureDCC balances into a FutureDCC balance
    // * User transfers FutureDCC balance with t1, t2 and t3 timestamps
    // * User transfers FutureDCC balance with t1, t3 and t4 timestamps
    // * User receives FutureDCC balance with t1, t2 and t4 timestamps
    function mergeFuture(address usr, uint t1, uint t2, uint t3, uint t4, uint pie) external approved(usr) {
        require(t1 < t2 && t2 < t3 && t3 < t4);

        burnFutureDCC(usr, t1, t2, t3, pie);
        burnFutureDCC(usr, t1, t3, t4, pie);
        mintFutureDCC(usr, t1, t2, t4, pie);
    }

    // Convert FutureDCC balance into a regular DCC balance once a chi snapshot becomes available after sliced timestamp
    // * User transfers FutureDCC balance with t1, t2 and t4 timestamps
    // * User receives DCC balance with t3 and t4 timestamps
    // * t3 is the closest timestamp at which a chi snapshot is available after t2
    function convert(address usr, uint t1, uint t2, uint t3, uint t4, uint pie) external approved(usr) untilLast(t3) {
        require(t1 < t2 && t2 <= t3 && t3 < t4); // t2 can also be equal to t3 if the sliced timestamp has a chi snapshot

        require(chi[t1] != 0); // chi value at t1 is used to calculate original dai notional amount
        require(chi[t3] != 0); // chi value snapshot needs to exist to create DCC balance with start timestamp set to t3

        uint newpie = mul(pie, chi[t1]) / chi[t3]; // original dai notional amount normalized with chi value at t3 timestamp for new DCC balance

        burnFutureDCC(usr, t1, t2, t4, pie);
        mintDCC(usr, t3, t4, newpie); // savings earnt between t2 to t3 are lost if they aren't equal
    }

    // Emergency Shutdown Split after Pot is caged
    function cage() external {
        require(pot.live() == 0); // Pot needs to be caged
        require(last == uint(-1)); // last timestamp can be set only once
        require(value.split() == address(this)); // SplitDSR address set in ValueDSR matches this contract address

        snapshot(); // Snapshot is taken at last timestamp
        last = now; // set last timestamp
    }

    // Emergency Shutdown processing in ValueDSR before ZCD and DCC balances with end timestamps after last can be cashed
    // * Execute Value.update() once to set last timestamp in ValueDSR
    // * Execute Value.calculate(end) for all future end timestamps

    // Exchange ZCD balance for Dai after emergency shutdown
    // * User transfers ZCD balance with end timestamp greater than last
    // * User receives the dai value reported by ValueDSR
    function cashZCD(address usr, uint end, uint dai) external afterLast(end) {
        burnZCD(usr, end, dai);

        uint cash = value.zcd(end, dai); // Get value of ZCD balance in dai from ValueDSR

        uint chiNow = pot.drip();
        uint pieOut = cash / chiNow;
        pot.exit(pieOut);
        vat.move(address(this), usr, mul(pieOut, chiNow));
    }

    // Exchange DCC balance for Dai after emergency shutdown
    // * User transfers DCC balance with end timestamp greater than last
    // * User receives the dai value reported by ValueDSR
    function cashDCC(address usr, uint end, uint pie) external afterLast(end) {
        burnDCC(usr, last, end, pie); // Savings earnt until last need to be claimed prior to cashing out

        uint dai = mul(pie, chi[last]);
        uint cash = value.dcc(end, dai); // Get value of DCC balance in dai from ValueDSR

        uint chiNow = pot.drip();
        uint pieOut = cash / chiNow;
        pot.exit(pieOut);
        vat.move(address(this), usr, mul(pieOut, chiNow));
    }

    // Exchange FutureDCC balance for Dai after emergency shutdown
    // * User transfers FutureDCC balance with slice timestamp greater than last
    // * User receives the dai value reported by ValueDSR
    function cashFutureDCC(address usr, uint start, uint slice, uint end, uint pie) external afterLast(slice) {
        burnFutureDCC(usr, start, slice, end, pie);

        uint dai = mul(pie, chi[start]); // calculate original dai notional amount

        // FutureDCC value calculated from values in dai reported by ValueDSR for DCC balances with end timestamps at slice and end
        uint cash = sub(value.dcc(end, dai), value.dcc(slice, dai));

        uint chiNow = pot.drip();
        uint pieOut = cash / chiNow;
        pot.exit(pieOut);
        vat.move(address(this), usr, mul(pieOut, chiNow));
    }
}