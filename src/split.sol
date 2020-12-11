pragma solidity 0.5.12;

import "./lib/DSMath.sol";
import "./interfaces/YieldLike.sol";

contract Split is DSMath {
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

    address public gov; // governance contract

    constructor() public {
        gov = msg.sender;
    }

    mapping (address => bool) public yields; // approved yield adapter addresses
    mapping (address => mapping (bytes32 => uint)) public zcd; // user address => zcd class => zcd balance [rad: 45 decimal fixed point number]
    mapping (address => mapping (bytes32 => uint)) public dcc; // user address => dcc class => dcc balance [wad: 18 decimal fixed point number]
    mapping (address => mapping (uint => uint)) public chi; // yield adapter => time => pot.chi value [ray: 27 decimal fixed point number]
    mapping (address => uint) public lastSnapshot; // yield adapter => last snapshot timestamp
    mapping (bytes32 => uint) public totalSupply; // class => zcd supply [rad]

    // dai : implies rad number type is being used in input
    // pie : implies wad number type is being used in input

    event MintZCD(address indexed usr, bytes32 indexed class, address yield, uint end, uint dai);
    event BurnZCD(address indexed usr, bytes32 indexed class, address yield, uint end, uint dai);
    event MintDCC(address indexed usr, bytes32 indexed class, address yield, uint start, uint end, uint pie);
    event BurnDCC(address indexed usr, bytes32 indexed class, address yield, uint start, uint end, uint pie);
    event MintFutureDCC(address indexed usr, bytes32 indexed class, address yield, uint start, uint slice, uint end, uint pie);
    event BurnFutureDCC(address indexed usr, bytes32 indexed class, address yield, uint start, uint slice, uint end, uint pie);
    event MoveZCD(address indexed src, address indexed dst, bytes32 indexed class, uint dai);
    event MoveDCC(address indexed src, address indexed dst, bytes32 indexed class, uint pie);
    event ChiSnapshot(address yield, uint time, uint chi);

    // --- Governance Modifiers ---
    modifier onlyGov() {
        require(msg.sender == gov);
        _;
    }

    modifier onlySplitOrYieldAdapters() {
        require(msg.sender == address(this) || yields[msg.sender] == true);
        _;
    }

    // --- Emergency Shutdown Modifiers ---
    modifier untilFinal(address yield, uint time) {
        require(time <= YieldLike(yield).final()); // execute normally when input timestamp is before or at emergency shutdown timestamp
        _;
    }

    // --- Yield Adapters ---
    function addYieldAdapter(address yield_) public onlyGov {
        require(YieldLike(yield_).split() == address(this)); // ensure yield adapter is configured for this split deployment
        yields[yield_] = true;
    }

    // --- Internal functions ---
    // Mint ZCD balance with maturity set to end timestamp
    function mintZCD(address yield, address usr, uint end, uint dai) public onlySplitOrYieldAdapters {
        bytes32 class = keccak256(abi.encodePacked(yield, end));

        zcd[usr][class] = addu(zcd[usr][class], dai);
        totalSupply[class] = addu(totalSupply[class], dai);
        emit MintZCD(usr, class, yield, end, dai);
    }

    // Burn ZCD balance with maturity set to end timestamp
    function burnZCD(address yield, address usr, uint end, uint dai) public onlySplitOrYieldAdapters {
        bytes32 class = keccak256(abi.encodePacked(yield, end));

        require(zcd[usr][class] >= dai, "zcd/insufficient-balance");

        zcd[usr][class] = subu(zcd[usr][class], dai);
        totalSupply[class] = subu(totalSupply[class], dai);
        emit BurnZCD(usr, class, yield, end, dai);
    }

    // Mint DCC balance with start and end timestamps
    function mintDCC(address yield, address usr, uint start, uint end, uint pie) public onlySplitOrYieldAdapters {
        bytes32 class = keccak256(abi.encodePacked(yield, start, end));

        dcc[usr][class] = addu(dcc[usr][class], pie);
        emit MintDCC(usr, class, yield, start, end, pie);
    }

    // Burn DCC balance with start and end timestamps
    function burnDCC(address yield, address usr, uint start, uint end, uint pie) public onlySplitOrYieldAdapters {
        bytes32 class = keccak256(abi.encodePacked(yield, start, end));

        require(dcc[usr][class] >= pie, "dcc/insufficient-balance");

        dcc[usr][class] = subu(dcc[usr][class], pie);
        emit BurnDCC(usr, class, yield, start, end, pie);
    }

    // Mint Future DCC balance with start, slice, and end timestamps
    function mintFutureDCC(address yield, address usr, uint start, uint slice, uint end, uint pie) public onlySplitOrYieldAdapters {
        bytes32 class = keccak256(abi.encodePacked(yield, start, slice, end));

        dcc[usr][class] = addu(dcc[usr][class], pie);
        emit MintFutureDCC(usr, class, yield, start, slice, end, pie);
    }

    // Burn Future DCC balance with start, slice, and end timestamps
    function burnFutureDCC(address yield, address usr, uint start, uint slice, uint end, uint pie) public onlySplitOrYieldAdapters {
        bytes32 class = keccak256(abi.encodePacked(yield, start, slice, end));

        require(dcc[usr][class] >= pie, "dcc/insufficient-balance");

        dcc[usr][class] = subu(dcc[usr][class], pie);
        emit BurnFutureDCC(usr, class, yield, start, slice, end, pie);
    }

    // --- External and Public functions ---
    // Update governance address
    function updateGov(address newGov) public onlyGov {
        gov = newGov;
    }

    // Transfer ZCD balance
    function moveZCD(address src, address dst, bytes32 class, uint dai) external approved(src) {
        require(zcd[src][class] >= dai, "zcd/insufficient-balance");

        zcd[src][class] = subu(zcd[src][class], dai);
        zcd[dst][class] = addu(zcd[dst][class], dai);

        emit MoveZCD(src, dst, class, dai);
    }

    // Transfer DCC or FutureDCC balance
    function moveDCC(address src, address dst, bytes32 class, uint pie) external approved(src) {
        require(dcc[src][class] >= pie, "dcc/insufficient-balance");

        dcc[src][class] = subu(dcc[src][class], pie);
        dcc[dst][class] = addu(dcc[dst][class], pie);

        emit MoveDCC(src, dst, class, pie);
    }

    // Snapshot and store updated chi value at current block timestamp
    function snapshot(address yield) public returns (uint chi_) {
        require(YieldLike(yield).canSnapshot()); // only if yield adapter allows snapshots
        chi_ = YieldLike(yield).snapshot(); // retrive snapshot from yield adapter
        chi[yield][now] = chi_;

        lastSnapshot[yield] = now; // update last snapshot timestamp

        emit ChiSnapshot(yield, now, chi_);
    }

    // Insert a chi value at timestamp
    function insert(address yield, uint t, uint chi_) public onlyGov {
        require(YieldLike(yield).canInsert()); // only if yield adapter allows gov snapshot inserts
        require(chi[yield][t] == 0); // timestamp should not have an existing snapshot

        chi[yield][t] = chi_; // set input chi value at timestamp

        // update last snapshot timestamp if insert is after current last
        if (lastSnapshot[yield] < t) {
            lastSnapshot[yield] = t;
        }

        emit ChiSnapshot(yield, t, chi_);
    }

    // Issue ZCD and DCC in exchange for dai
    // * User transfers dai balance to Split
    // * User receives ZCD balance equal to the dai balance which we'll refer to as the notional amount
    // * User receives DCC balance equal to the pie balance of the DSR deposit (pie = dai notional amount / current chi value)
    function issue(address yield, address usr, uint start, uint end, uint pie) external approved(usr) untilFinal(yield, start) {
        require(start <= now <= end); // Assets can only be issued with future maturity

        uint dai = YieldLike(yield).lock(usr, chi[yield][start], pie); // transfer notional amount of balance from user to yield adapter, input is in pie terms

        mintZCD(yield, usr, end, dai); // Mint ZCD balance for dai amount at end. dai is 45 decimal fixed point number.
        mintDCC(yield, usr, start, end, pie); // Mint DCC balance for pie value between now and end timestamps. pie is 18 decimal fixed point number.
    }

    // Redeem ZCD for dai after maturity
    // * User transfers ZCD balance to Split
    // * User receives dai balance equal to the ZCD balance
    // * User receives DSR earnt on this dai balance after end until redemption if a valid snapshot is present
    // * User can input end timestamp for snap when gov has inserted a chi value to not lose any dai
    function redeem(address yield, address usr, uint end, uint snap, uint dai) external approved(usr) untilFinal(yield, end) {
        require((end <= snap) && (snap <= now)); // Redemption can happen only after end timestamp is past. Snap timestamp needs to be after end but before now.

        uint chiLast = chi[yield][lastSnapshot[yield]]; // last chi value
        uint chiSnap = chi[yield][snap]; // chi value at snap timestamp
        require(chiSnap != 0); // ensure a valid chi snapshot exists before calculating any DSR earnt
        uint pie = dai / chiSnap; // rad / ray -> wad // Calculate pie assuming user redeemed dai in the past at end timestamp and deposited it in Pot at snap timestamp

        burnZCD(yield, usr, end, dai); // Burn ZCD balance

        YieldLike(yield).unlock(usr, chiLast, pie); // transfer notional amount of balance from yield adapter to user, input is in pie terms
    }

    // Claim dai earnt by DCC balance from the Dai Savings Rate
    // * User transfers DCC balance to Split
    // * User receives dai earnt from DSR by this pie balance beween start and snap timestamps
    // * DCC balance burnt for the time period between start and snap timestamps
    // * User receives DCC balance with new class for remaining time period between snap and end timestamps
    // * User can input end timestamp for snap when gov has inserted a chi value to not lose any dai
    function claim(address yield, address usr, uint start, uint end, uint snap, uint pie) external approved(usr) untilFinal(yield, snap) {
        require((start <= snap) && (snap <= end));

        uint chiLast = chi[yield][lastSnapshot[yield]]; // last chi value
        uint chiStart = chi[yield][start]; // chi value at start timestamp
        uint chiSnap = chi[yield][snap]; // chi value at snap timestamp

        require((chiStart != 0) && (chiSnap != 0) && (chiSnap > chiStart));

        burnDCC(yield, usr, start, end, pie); // Burn entire DCC balance

        // Mint new DCC balance for remaining time period between snap and end if present
        if (snap != end) {
            mintDCC(yield, usr, snap, end, rdiv(rmul(pie, chiStart), chiSnap)); // Division rounds down and new balance might be slightly lower
        }

        // dai earnt by deposit as savings between two chi values is moved out. Deposit remains in Pot.
        uint pieOut = mulu(pie, subu(chiSnap, chiStart)) / chiLast; // wad * ray / ray -> wad

        YieldLike(yield).unlock(usr, chiLast, pieOut);  // Dai earnt sent to DCC owner
    }

    // Rewind start timestamp of DCC balance to a past snapshot timestamp (opposite of claim which forwards start timestamp to a future snapshot)
    // * User transfers DCC balance
    // * User transfers dai balance to cover the additional savings they will be entitled to after rewind
    // * User receives DCC balance at new class with start timestamp set to an earlier chi snapshot
    function rewind(address yield, address usr, uint start, uint end, uint snap, uint pie) external approved(usr) untilFinal(yield, lastSnapshot[yield]) {
        require((snap <= start) && (start <= end));

        uint chiLast = chi[yield][lastSnapshot[yield]]; // last chi value
        uint chiSnap = chi[yield][snap];
        uint chiStart = chi[yield][start];

        require((chiSnap != 0) && (chiStart != 0) && (chiSnap < chiStart));

        uint notional = mulu(pie, chiStart); // notional amount in dai earning DSR from start for current dcc balance. wad * ray -> rad
        uint pieSnap = notional / chiSnap; // pie value for the same notional amount if deposited at the earlier snap timestamp. rad / ray -> wad

        // New total dai amount at start timestamp with earlier deposit = notional amount + dai earnt from dsr between snap and start timestamps
        uint total = mulu(pieSnap, chiStart); // wad * ray -> rad 

        burnDCC(yield, usr, start, end, pie); // Burn old DCC balance between start and end timestamps

        // New DCC balance is higher to reflect the same dai notional amount earning DSR starting from an earlier timestamp
        mintDCC(yield, usr, snap, end, pieSnap); // Mint new DCC balance between snap and end timestamps.

        // Difference between new total and old notional amount at the start timestamp, in pie terms at current chi value
        // uint pieIn = subu(total, notional) / chiLast; // (rad - rad) / ray -> wad

        YieldLike(yield).lock(usr, chiLast, subu(total, notional) / chiLast); // Collect dai from user for this adjustment
    }

    // Withdraw ZCD and DCC before maturity to dai
    // * User transfers ZCD balance with an end timestamp
    // * User transfers DCC balance with savings claimed until now and the same end timestamp as ZCD
    // * User receives dai from Split equal to both their dai notional amounts
    function withdraw(address yield, address usr, uint end, uint pie) external approved(usr) untilFinal(yield, lastSnapshot[yield]) {
        uint chiLast = chi[yield][lastSnapshot[yield]]; // last chi value
        uint dai = YieldLike(yield).unlock(usr, chiLast, pie); // transfer notional amount to user

        burnZCD(yield, usr, end, dai);
        burnDCC(yield, usr, lastSnapshot[yield], end, pie); // DCC balance needs to be claimed from its start until last timestamp
    }

    // Slice a DCC balance at a future timestamp into contiguous DCC and FutureDCC balances
    // * User transfers DCC balance with t1 and t3 timestamps
    // * User receives DCC balance with t1 and t2 timestamps
    // * User receives FutureDCC balance that can be converted later to regular DCC balance with t2 and t3 timestamps
    function slice(address yield, address usr, uint t1, uint t2, uint t3, uint pie) external approved(usr) {
        require(t1 < t2 && t2 < t3); // slice timestamp t2 needs to be between t1 and t3

        burnDCC(yield, usr, t1, t3, pie);
        mintDCC(yield, usr, t1, t2, pie);
        mintFutureDCC(yield, usr, t1, t2, t3, pie); // Earns DSR between t2 and t3 timestamps on the original dai notional amount (pie * chi[t1])
    }

    // Merge continguous DCC and FutureDCC balances into a DCC balance
    // * User transfers a DCC balance with t2 and t3 timestamps
    // * User transfers a FutureDCC with t1, t3 and t4 timestamps
    // * User receives a DCC balance with t2 and t4 timestamps
    function merge(address yield, address usr, uint t1, uint t2, uint t3, uint t4, uint pie) external approved(usr) {
        require(t1 <= t2 && t2 < t3 && t3 < t4); // t1 can equal t2
        uint futurePie = (t1 == t2) ? pie : mulu(pie, chi[yield][t2]) / chi[yield][t1]; // FutureDCC balance that needs to be burnt if t1 and t2 are not equal

        burnDCC(yield, usr, t2, t3, pie);
        burnFutureDCC(yield, usr, t1, t3, t4, futurePie);
        mintDCC(yield, usr, t2, t4, pie);
    }

    // Slice a FutureDCC balance into two contiguous FutureDCC balances
    // * User transfers FutureDCC balance with t1, t2 and t4 timestamps
    // * User receives FutureDCC balance with t1, t2 and t3 timestamps
    // * User receives FutureDCC balance with t1, t3 and t4 timestamps
    function sliceFuture(address yield, address usr, uint t1, uint t2, uint t3, uint t4, uint pie) external approved(usr) {
        require(t1 < t2 && t2 < t3 && t3 < t4);

        burnFutureDCC(yield, usr, t1, t2, t4, pie);
        mintFutureDCC(yield, usr, t1, t2, t3, pie);
        mintFutureDCC(yield, usr, t1, t3, t4, pie);
    }

    // Merge two continguous FutureDCC balances into a FutureDCC balance
    // * User transfers FutureDCC balance with t1, t2 and t3 timestamps
    // * User transfers FutureDCC balance with t1, t3 and t4 timestamps
    // * User receives FutureDCC balance with t1, t2 and t4 timestamps
    function mergeFuture(address yield, address usr, uint t1, uint t2, uint t3, uint t4, uint pie) external approved(usr) {
        require(t1 < t2 && t2 < t3 && t3 < t4);

        burnFutureDCC(yield, usr, t1, t2, t3, pie);
        burnFutureDCC(yield, usr, t1, t3, t4, pie);
        mintFutureDCC(yield, usr, t1, t2, t4, pie);
    }

    // Convert FutureDCC balance into a regular DCC balance once a chi snapshot becomes available after sliced timestamp
    // * User transfers FutureDCC balance with t1, t2 and t4 timestamps
    // * User receives DCC balance with t3 and t4 timestamps
    // * t3 is the closest timestamp at which a chi snapshot is available after t2
    function convert(address yield, address usr, uint t1, uint t2, uint t3, uint t4, uint pie) external approved(usr) untilFinal(yield, t3) {
        require(t1 < t2 && t2 <= t3 && t3 < t4); // t2 can also be equal to t3 if the sliced timestamp has a chi snapshot

        require(chi[yield][t1] != 0); // chi value at t1 is used to calculate original dai notional amount
        require(chi[yield][t3] != 0); // chi value snapshot needs to exist to create DCC balance with start timestamp set to t3

        uint newpie = mulu(pie, chi[yield][t1]) / chi[yield][t3]; // original dai notional amount normalized with chi value at t3 timestamp for new DCC balance

        burnFutureDCC(yield, usr, t1, t2, t4, pie);
        mintDCC(yield, usr, t3, t4, newpie); // savings earnt between t2 to t3 are lost if they aren't equal
    }
}