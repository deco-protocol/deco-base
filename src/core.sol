pragma solidity 0.5.12;

import "./lib/DSMath.sol";
import "./interfaces/YieldLike.sol";

contract Core is DSMath {
    address public gov; // governance contract

    mapping (address => mapping (bytes32 => uint)) public zBal; // user address => zero class => zero balance [rad: 45 decimal fixed point number]
    mapping (address => mapping (bytes32 => uint)) public cBal; // user address => claim class => claim balance [wad: 18 decimal fixed point number]
    mapping (bytes32 => uint) public totalSupply; // zero class => total zero supply [rad]

    mapping (address => bool) public yields; // yield adapter approval status
    mapping (address => mapping (uint => uint)) public amp; // yield adapter => amp timestamp => amp value [ray: 27 decimal fixed point number]
    mapping (address => uint) public latestAmpTimestamp; // yield adapter => latest amp timestamp

    mapping(address => mapping (address => bool)) public approvals; // balance address => approved address => approval status

    event MintZero(address indexed usr, bytes32 indexed class, address yield, uint maturity, uint zbal);
    event BurnZero(address indexed usr, bytes32 indexed class, address yield, uint maturity, uint zbal);
    event MintClaim(address indexed usr, bytes32 indexed class, address yield, uint issuance, uint maturity, uint cbal);
    event BurnClaim(address indexed usr, bytes32 indexed class, address yield, uint issuance, uint maturity, uint cbal);
    event MintFutureClaim(address indexed usr, bytes32 indexed class, address yield, uint issuance, uint activation, uint maturity, uint cbal);
    event BurnFutureClaim(address indexed usr, bytes32 indexed class, address yield, uint issuance, uint activation, uint maturity, uint cbal);
    event MoveZero(address indexed src, address indexed dst, bytes32 indexed class, uint zbal);
    event MoveClaim(address indexed src, address indexed dst, bytes32 indexed class, uint cbal);
    event NewAmp(address indexed yield, uint indexed time, uint amp);
    event Approval(address indexed sender, address indexed usr, bool approval);

    constructor() public {
        gov = msg.sender;
    }

    // --- User Approval Modifier ---
    modifier approved(address usr) {
        require(either(msg.sender == usr, approvals[usr][msg.sender] == true));
        _;
    }

    // --- Governance Modifiers ---
    modifier onlyGov() {
        require(msg.sender == gov);
        _;
    }

    modifier onlyThisOrYieldAdapter(address yield_) {
        require(msg.sender == address(this) || (msg.sender == yield_ && yields[msg.sender] == true));
        _;
    }

    // --- Close Modifiers ---
    modifier untilClose(address yield, uint time) {
        require(time <= YieldLike(yield).closeTimestamp()); // restrict core to only work with maturity timestamps before close
        _;
    }

    // --- Yield Adapters ---
    function enableYieldAdapter(address yield_) public onlyGov {
        require(YieldLike(yield_).core() == address(this)); // yield adapter configured for this deployment
        yields[yield_] = true; // enable, yield adapters cannot be disabled once enabled
    }

    // --- User Approvals ---
    function approve(address usr, bool approval) external {
        approvals[msg.sender][usr] = approval;
        emit Approval(msg.sender, usr, approval);
    }

    // --- Mint and Burn functions ---
    function mintZero(address yield, address usr, uint maturity, uint zbal_) public onlyThisOrYieldAdapter(yield) {
        bytes32 class = keccak256(abi.encodePacked(yield, maturity)); // calculate zero class with adapter address and maturity timestamp

        zBal[usr][class] = addu(zBal[usr][class], zbal_);
        totalSupply[class] = addu(totalSupply[class], zbal_);
        emit MintZero(usr, class, yield, maturity, zbal_);
    }

    function burnZero(address yield, address usr, uint maturity, uint zbal_) public onlyThisOrYieldAdapter(yield) {
        bytes32 class = keccak256(abi.encodePacked(yield, maturity));

        require(zBal[usr][class] >= zbal_, "zBal/insufficient-balance");

        zBal[usr][class] = subu(zBal[usr][class], zbal_);
        totalSupply[class] = subu(totalSupply[class], zbal_);
        emit BurnZero(usr, class, yield, maturity, zbal_);
    }

    function mintClaim(address yield, address usr, uint issuance, uint maturity, uint cbal_) public onlyThisOrYieldAdapter(yield) {
        bytes32 class = keccak256(abi.encodePacked(yield, issuance, maturity));

        cBal[usr][class] = addu(cBal[usr][class], cbal_);
        emit MintClaim(usr, class, yield, issuance, maturity, cbal_);
    }

    function burnClaim(address yield, address usr, uint issuance, uint maturity, uint cbal_) public onlyThisOrYieldAdapter(yield) {
        bytes32 class = keccak256(abi.encodePacked(yield, issuance, maturity));

        require(cBal[usr][class] >= cbal_, "cBal/insufficient-balance");

        cBal[usr][class] = subu(cBal[usr][class], cbal_);
        emit BurnClaim(usr, class, yield, issuance, maturity, cbal_);
    }

    function mintFutureClaim(address yield, address usr, uint issuance, uint activation, uint maturity, uint cbal_) public onlyThisOrYieldAdapter(yield) {
        bytes32 class = keccak256(abi.encodePacked(yield, issuance, activation, maturity));

        cBal[usr][class] = addu(cBal[usr][class], cbal_);
        emit MintFutureClaim(usr, class, yield, issuance, activation, maturity, cbal_);
    }

    function burnFutureClaim(address yield, address usr, uint issuance, uint activation, uint maturity, uint cbal_) public onlyThisOrYieldAdapter(yield) {
        bytes32 class = keccak256(abi.encodePacked(yield, issuance, activation, maturity));

        require(cBal[usr][class] >= cbal_, "cBal/insufficient-balance");

        cBal[usr][class] = subu(cBal[usr][class], cbal_);
        emit BurnFutureClaim(usr, class, yield, issuance, activation, maturity, cbal_);
    }

    // --- Governance Functions ---
    function updateGov(address newGov) public onlyGov {
        gov = newGov;
    }

    // --- Transfer Functions ---
    function moveZero(address src, address dst, bytes32 class, uint zbal_) external approved(src) {
        require(zBal[src][class] >= zbal_, "zBal/insufficient-balance");

        zBal[src][class] = subu(zBal[src][class], zbal_);
        zBal[dst][class] = addu(zBal[dst][class], zbal_);

        emit MoveZero(src, dst, class, zbal_);
    }

    function moveClaim(address src, address dst, bytes32 class, uint cbal_) external approved(src) {
        require(cBal[src][class] >= cbal_, "cBal/insufficient-balance");

        cBal[src][class] = subu(cBal[src][class], cbal_);
        cBal[dst][class] = addu(cBal[dst][class], cbal_);

        emit MoveClaim(src, dst, class, cbal_);
    }

    // --- Amp Functions ---
    function snapshot(address yield) external {
        require(YieldLike(yield).canSnapshot()); // yield adapter to allow anyone to snapshot amp value
        uint amp_ = YieldLike(yield).snapshot();
        amp[yield][now] = amp_;

        latestAmpTimestamp[yield] = now; // update latest amp timestamp

        emit NewAmp(yield, now, amp_);
    }

    function insert(address yield, uint t, uint amp_) external onlyGov {
        require(YieldLike(yield).canInsert()); // yield adapter to allow governance to insert amp values
        require(amp[yield][t] == 0 || YieldLike(yield).canOverwrite()); // amp value cannot be 0 or overwrite needs to be enabled

        amp[yield][t] = amp_;

        // update latest amp timestamp when inserting after current latest
        if (latestAmpTimestamp[yield] < t) {
            latestAmpTimestamp[yield] = t;
        }

        emit NewAmp(yield, t, amp_);
    }

    // --- Zero+Claim Functions ---
    function issue(address yield, address usr, uint issuance, uint maturity, uint cbal_) external approved(usr) untilClose(yield, issuance) {
        // will not issue if yield adapter is closed
        uint latest = latestAmpTimestamp[yield]; // latest amp timestamp
        require(issuance <= latest && latest <= maturity); // issuance has to be before or until latest, maturity cannot be before latest
        require(amp[yield][issuance] != 0); // amp value should exist at issuance, take snapshot prior to calling issuance if it is at now

        uint zbal_ = YieldLike(yield).lock(usr, amp[yield][issuance], cbal_); // instruct yield adapter to lock notional amount of yield token

        // issue equal notional amount of zero and claim
        mintZero(yield, usr, maturity, zbal_); // zbal_ is rad, 45 decimal fixed point number
        mintClaim(yield, usr, issuance, maturity, cbal_); // cbal_ is wad, 18 decimal fixed point number
    }

    function withdraw(address yield, address usr, uint maturity, uint cbal_) external approved(usr) untilClose(yield, latestAmpTimestamp[yield]) {
        uint latestAmp = amp[yield][latestAmpTimestamp[yield]]; // amp value at latest timestamp
        uint zbal_ = YieldLike(yield).unlock(usr, latestAmp, cbal_); // notional amount in yield token sent to user

        // burn equal notional amount of zero and claim
        burnZero(yield, usr, maturity, zbal_);
        burnClaim(yield, usr, latestAmpTimestamp[yield], maturity, cbal_); // cannot burn if not fully collected until latest amp timestamp
    }

    // --- Zero Functions ---
    function redeem(address yield, address usr, uint maturity, uint collect_, uint zbal_) external approved(usr) untilClose(yield, maturity) {
        uint latest = latestAmpTimestamp[yield]; // latest amp timestamp
        // redemption only after amp value is available after maturity
        // collect claims additionally if available when collect does not equal latest
        require((maturity <= collect_) && (collect_ <= latest));

        uint latestAmp = amp[yield][latest]; // amp value at latest timestamp
        uint collectAmp = amp[yield][collect_]; // amp value at collect timestamp
        require(collectAmp != 0); // ensure collect amp value is valid

        // normalize notional amount at collect amp value, and redeem normalized amount at latest amp value
        uint cbal_ = zbal_ / collectAmp; // [rad / ray -> wad]
        burnZero(yield, usr, maturity, zbal_);
        YieldLike(yield).unlock(usr, latestAmp, cbal_); // yield token sent to claim balance owner
    }

    // --- Claim Functions ---
    function collect(address yield, address usr, uint issuance, uint maturity, uint collect_, uint cbal_) external approved(usr) untilClose(yield, collect_) {
        // claims collection on notional amount can only be between issuance and maturity
        require((issuance <= collect_) && (collect_ <= maturity));

        uint latestAmp = amp[yield][latestAmpTimestamp[yield]]; // amp value at latest timestamp
        uint issuanceAmp = amp[yield][issuance]; // amp value at issuance timestamp
        uint collectAmp = amp[yield][collect_]; // amp value at collect timestamp

        require(issuanceAmp != 0); // issuance amp value cannot be 0
        require(collectAmp != 0); // collect amp value cannot be 0
        require(collectAmp > issuanceAmp); // amp difference should be present

        burnClaim(yield, usr, issuance, maturity, cbal_); // burn entire claim balance

        // mint new claim balance for remaining time period between collect and maturity
        if (collect_ != maturity) {
            mintClaim(yield, usr, collect_, maturity, rdiv(rmul(cbal_, issuanceAmp), collectAmp));
            // division rounds down and new balance might be slightly lower
        }

        // move out earnt yield on notional amount between issuance and collect
        uint cbalOut = mulu(cbal_, subu(collectAmp, issuanceAmp)) / latestAmp; // wad * ray / ray -> wad
        YieldLike(yield).unlock(usr, latestAmp, cbalOut);  // yield token sent to claim balance owner
    }

    function rewind(address yield, address usr, uint issuance, uint maturity, uint collect_, uint cbal_) external approved(usr) untilClose(yield, latestAmpTimestamp[yield]) {
        // collect timestamp needs to be before issuance(rewinding) and maturity after
        require((collect_ <= issuance) && (issuance <= maturity));

        uint latestAmp = amp[yield][latestAmpTimestamp[yield]]; // amp value at latest timestamp
        uint collectAmp = amp[yield][collect_]; // amp value at collect timestamp
        uint issuanceAmp = amp[yield][issuance]; // amp value at issuance timestamp

        require(collectAmp != 0); // collect amp value cannot be 0
        require(issuanceAmp != 0); // issuance amp value cannot be 0
        require(collectAmp < issuanceAmp); // amp difference should be present

        // notional amount of claim balance earning yield since issuance
        uint notional = mulu(cbal_, issuanceAmp); // [wad * ray -> rad]
        // claim balance value for the same notional amount if it was deposited earlier at collect timestamp
        uint cbalCollect = notional / collectAmp; // [rad / ray -> wad]

        burnClaim(yield, usr, issuance, maturity, cbal_); // burn claim balance
        // mint new claim balance with issuance set to earlier collect timestamp
        mintClaim(yield, usr, collect_, maturity, cbalCollect);

        // total = mulu(cbalCollect, issuanceAmp) - [wad * ray -> rad] - total amount at issuance timestamp with earlier deposit
        // collect (total - notional) yield token balance from user for processing rewind
        YieldLike(yield).lock(usr, latestAmp, subu(mulu(cbalCollect, issuanceAmp), notional) / latestAmp); // [(rad - rad) / ray -> wad]
    }

    // ---  Future Claim Functions ---
    function slice(address yield, address usr, uint t1, uint t2, uint t3, uint cbal_) external approved(usr) {
        // t1 - issuance
        // t2 - slice point
        // t3 - maturity
        require(t1 < t2 && t2 < t3); // activation timestamp t2 needs to be between t1 and t3

        burnClaim(yield, usr, t1, t3, cbal_); // burn full original claim balance
        mintClaim(yield, usr, t1, t2, cbal_); // mint claim balance
        
        // mint future claim balance to be activated later at t2
        // using amp value at t1 to calculate notional amount
        mintFutureClaim(yield, usr, t1, t2, t3, cbal_);
    }

    function merge(address yield, address usr, uint t1, uint t2, uint t3, uint t4, uint cbal_) external approved(usr) {
        // t1 - original issuance of future claim balance
        // t2 - issuance of claim balance
        // t3 - maturity of claim balance
        // t4 - maturity of future claim balance
        require(t1 <= t2 && t2 < t3 && t3 < t4); // t1 can equal t2 // t2, t3, and t4 need to be in order

        // future claim balance that needs to be burnt
        // input claim balance itself if t1 and t2 are equal
        // scale notional amount of claim balance issuance from t2 to t1 when not equal
        uint cbalScaled = (t1 == t2) ? cbal_ : mulu(cbal_, amp[yield][t2]) / amp[yield][t1];

        burnClaim(yield, usr, t2, t3, cbal_);
        burnFutureClaim(yield, usr, t1, t3, t4, cbalScaled);
        mintClaim(yield, usr, t2, t4, cbal_);
    }

    function activate(address yield, address usr, uint t1, uint t2, uint t3, uint t4, uint cbal_) external approved(usr) untilClose(yield, t3) {
        // t1 - original issuance of future claim balance
        // t2 - activation point of future claim balance
        // t3 - closest available amp timestamp after t2, t2 and t3 can be equal
        // t4 - maturity of future claim balance
        require(t1 < t2 && t2 <= t3 && t3 < t4); // all timestamps are in order
        require(amp[yield][t3] != 0); // amp value required to activate at t3

        // scale notional amount of claim balance issuance from t1 to t3
        uint newcbal_ = mulu(cbal_, amp[yield][t1]) / amp[yield][t3];

        burnFutureClaim(yield, usr, t1, t2, t4, cbal_); // burn future claim balance
        mintClaim(yield, usr, t3, t4, newcbal_); // mint claim balance
        // yield earnt between t2 to t3 becomes uncollectable
    }

    function sliceFuture(address yield, address usr, uint t1, uint t2, uint t3, uint t4, uint cbal_) external approved(usr) {
        require(t1 < t2 && t2 < t3 && t3 < t4);

        burnFutureClaim(yield, usr, t1, t2, t4, cbal_);
        mintFutureClaim(yield, usr, t1, t2, t3, cbal_);
        mintFutureClaim(yield, usr, t1, t3, t4, cbal_);
    }

    function mergeFuture(address yield, address usr, uint t1, uint t2, uint t3, uint t4, uint cbal_) external approved(usr) {
        require(t1 < t2 && t2 < t3 && t3 < t4);

        burnFutureClaim(yield, usr, t1, t2, t3, cbal_);
        burnFutureClaim(yield, usr, t1, t3, t4, cbal_);
        mintFutureClaim(yield, usr, t1, t2, t4, cbal_);
    }
}