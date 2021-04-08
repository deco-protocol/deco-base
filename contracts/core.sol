/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.7.6;

import "./lib/DSMath.sol";
import "./interfaces/ChaiLike.sol";
import "./interfaces/PotLike.sol";

contract Core is DSMath {
    address public gov; // governance
    ChaiLike public chai; // chai
    PotLike public pot; // pot

    // user address => zero class => zero balance [rad: 45 decimal fixed point number]
    mapping(address => mapping(bytes32 => uint256)) public zBal;
    // user address => claim class => claim balance [wad: 18 decimal fixed point number]
    mapping(address => mapping(bytes32 => uint256)) public cBal;
    // zero class => total zero supply [rad]
    mapping(bytes32 => uint256) public totalSupply;

    mapping(uint256 => uint256) public amp; // amp timestamp => amp value [ray: 27 decimal fixed point number]
    uint256 public latestAmpTimestamp; // latest amp timestamp

    // balance address => approved address => approval status
    mapping(address => mapping(address => bool)) public approvals;

    mapping(uint256 => uint256) public ratio; // maturity timestamp => balance cashout ratio [ray]
    uint256 public closeTimestamp; // yield adapter close timestamp

    event MintZero(
        address indexed usr,
        bytes32 indexed class_,
        uint256 maturity,
        uint256 zbal
    );
    event BurnZero(
        address indexed usr,
        bytes32 indexed class_,
        uint256 maturity,
        uint256 zbal
    );
    event MintClaim(
        address indexed usr,
        bytes32 indexed class_,
        uint256 issuance,
        uint256 maturity,
        uint256 cbal
    );
    event BurnClaim(
        address indexed usr,
        bytes32 indexed class_,
        uint256 issuance,
        uint256 maturity,
        uint256 cbal
    );
    event MintFutureClaim(
        address indexed usr,
        bytes32 indexed class_,
        uint256 issuance,
        uint256 activation,
        uint256 maturity,
        uint256 cbal
    );
    event BurnFutureClaim(
        address indexed usr,
        bytes32 indexed class_,
        uint256 issuance,
        uint256 activation,
        uint256 maturity,
        uint256 cbal
    );

    event MoveZero(
        address indexed src,
        address indexed dst,
        bytes32 indexed class_,
        uint256 zbal
    );
    event MoveClaim(
        address indexed src,
        address indexed dst,
        bytes32 indexed class_,
        uint256 cbal
    );

    event NewAmp(uint256 indexed time, uint256 amp);
    event Approval(address indexed sender, address indexed usr, bool approval);

    constructor(address chai_) {
        gov = msg.sender;
        chai = ChaiLike(chai_);
        pot = PotLike(chai.pot());

        closeTimestamp = uint256(-1); // initialized to MAX_UINT, updated after close
    }

    // --- User Approval Modifier ---
    modifier approved(address usr) {
        require(
            either(msg.sender == usr, approvals[usr][msg.sender] == true),
            "user/not-authorized"
        );
        _;
    }

    // --- Governance Modifiers ---
    modifier onlyGov() {
        require(msg.sender == gov, "gov/not-authorized");
        _;
    }

    // --- Close Modifiers ---
    modifier untilClose(uint256 time) {
        // restrict core to only work with maturity timestamps before close
        require(time <= closeTimestamp, "after-close");
        _;
    }

    modifier afterClose(uint256 time) {
        require(closeTimestamp < uint256(-1), "not-closed"); // neeeds to be closed
        require(closeTimestamp < time, "before-close"); // processes only if input timestamp is greater than close
        _;
    }

    // --- User Approvals ---
    function approve(address usr, bool approval) external {
        approvals[msg.sender][usr] = approval;
        emit Approval(msg.sender, usr, approval);
    }

    // --- Internal functions ---
    function lock(
        address usr,
        uint256 amp_,
        uint256 cbal_
    ) internal returns (uint256) {
        // transfer cbal amount of chai from usr
        require(
            chai.transferFrom(usr, address(this), cbal_),
            "transfer-failed"
        );
        return mulu(cbal_, amp_); // return notional amount
    }

    function unlock(
        address usr,
        uint256 amp_,
        uint256 cbal_
    ) internal returns (uint256) {
        // transfer cbal amount of chai to usr
        require(
            chai.transferFrom(address(this), usr, cbal_),
            "transfer-failed"
        );
        return mulu(cbal_, amp_); // return notional amount
    }

    function mintZero(
        address usr,
        uint256 maturity,
        uint256 zbal_
    ) internal {
        // calculate zero class with adapter address and maturity timestamp
        bytes32 class_ = keccak256(abi.encodePacked(maturity));

        zBal[usr][class_] = addu(zBal[usr][class_], zbal_);
        totalSupply[class_] = addu(totalSupply[class_], zbal_);
        emit MintZero(usr, class_, maturity, zbal_);
    }

    function burnZero(
        address usr,
        uint256 maturity,
        uint256 zbal_
    ) internal {
        bytes32 class_ = keccak256(abi.encodePacked(maturity));

        require(zBal[usr][class_] >= zbal_, "zBal/insufficient-balance");

        zBal[usr][class_] = subu(zBal[usr][class_], zbal_);
        totalSupply[class_] = subu(totalSupply[class_], zbal_);
        emit BurnZero(usr, class_, maturity, zbal_);
    }

    function mintClaim(
        address usr,
        uint256 issuance,
        uint256 maturity,
        uint256 cbal_
    ) internal {
        bytes32 class_ = keccak256(abi.encodePacked(issuance, maturity));

        cBal[usr][class_] = addu(cBal[usr][class_], cbal_);
        emit MintClaim(usr, class_, issuance, maturity, cbal_);
    }

    function burnClaim(
        address usr,
        uint256 issuance,
        uint256 maturity,
        uint256 cbal_
    ) internal {
        bytes32 class_ = keccak256(abi.encodePacked(issuance, maturity));

        require(cBal[usr][class_] >= cbal_, "cBal/insufficient-balance");

        cBal[usr][class_] = subu(cBal[usr][class_], cbal_);
        emit BurnClaim(usr, class_, issuance, maturity, cbal_);
    }

    function mintFutureClaim(
        address usr,
        uint256 issuance,
        uint256 activation,
        uint256 maturity,
        uint256 cbal_
    ) internal {
        bytes32 class_ =
            keccak256(abi.encodePacked(issuance, activation, maturity));

        cBal[usr][class_] = addu(cBal[usr][class_], cbal_);
        emit MintFutureClaim(
            usr,
            class_,
            issuance,
            activation,
            maturity,
            cbal_
        );
    }

    function burnFutureClaim(
        address usr,
        uint256 issuance,
        uint256 activation,
        uint256 maturity,
        uint256 cbal_
    ) internal {
        bytes32 class_ =
            keccak256(abi.encodePacked(issuance, activation, maturity));

        require(cBal[usr][class_] >= cbal_, "cBal/insufficient-balance");

        cBal[usr][class_] = subu(cBal[usr][class_], cbal_);
        emit BurnFutureClaim(
            usr,
            class_,
            issuance,
            activation,
            maturity,
            cbal_
        );
    }

    // --- Governance Functions ---
    function updateGov(address newGov) public onlyGov {
        gov = newGov;
    }

    // --- Transfer Functions ---
    function moveZero(
        address src,
        address dst,
        bytes32 class_,
        uint256 zbal_
    ) external approved(src) {
        require(zBal[src][class_] >= zbal_, "zBal/insufficient-balance");

        zBal[src][class_] = subu(zBal[src][class_], zbal_);
        zBal[dst][class_] = addu(zBal[dst][class_], zbal_);

        emit MoveZero(src, dst, class_, zbal_);
    }

    function moveClaim(
        address src,
        address dst,
        bytes32 class_,
        uint256 cbal_
    ) external approved(src) {
        require(cBal[src][class_] >= cbal_, "cBal/insufficient-balance");

        cBal[src][class_] = subu(cBal[src][class_], cbal_);
        cBal[dst][class_] = addu(cBal[dst][class_], cbal_);

        emit MoveClaim(src, dst, class_, cbal_);
    }

    // --- Amp Functions ---
    function snapshot() external {
        // yield adapter to allow anyone to snapshot amp value
        uint256 amp_ = pot.drip(); // retrieve amp value from pot

        amp[block.timestamp] = amp_;
        latestAmpTimestamp = block.timestamp; // update latest amp timestamp

        emit NewAmp(block.timestamp, amp_);
    }

    function insert(uint256 t, uint256 amp_) external onlyGov {
        require(amp[t] == 0, "amp/overwrite-disabled"); // overwriting amp value disabled

        amp[t] = amp_;

        // update latest amp timestamp when inserting after current latest
        if (latestAmpTimestamp < t) {
            latestAmpTimestamp = t;
        }

        emit NewAmp(t, amp_);
    }

    // --- Zero and Claim Functions ---
    function issue(
        address usr,
        uint256 issuance,
        uint256 maturity,
        uint256 cbal_
    ) external approved(usr) untilClose(issuance) {
        // issuance has to be before or until latest, maturity cannot be before latest
        require(
            issuance <= latestAmpTimestamp && latestAmpTimestamp <= maturity,
            "timestamp/invalid"
        );
        // amp value should exist at issuance, take snapshot prior to calling issuance if it is at now
        require(amp[issuance] != 0, "amp/invalid");

        uint256 zbal_ = lock(usr, amp[issuance], cbal_); // lock notional amount of yield token

        // issue equal notional amount of zero and claim
        mintZero(usr, maturity, zbal_); // zbal_ is rad, 45 decimal fixed point number
        mintClaim(usr, issuance, maturity, cbal_); // cbal_ is wad, 18 decimal fixed point number
    }

    function withdraw(
        address usr,
        uint256 maturity,
        uint256 cbal_
    ) external approved(usr) untilClose(latestAmpTimestamp) {
        uint256 latestAmp = amp[latestAmpTimestamp]; // amp value at latest timestamp
        uint256 zbal_ = unlock(usr, latestAmp, cbal_); // notional amount in yield token sent to user

        // burn equal notional amount of zero and claim
        burnZero(usr, maturity, zbal_);
        // cannot burn if not fully collected until latest amp timestamp
        burnClaim(usr, latestAmpTimestamp, maturity, cbal_);
    }

    // --- Zero Functions ---
    function redeem(
        address usr,
        uint256 maturity,
        uint256 collect_,
        uint256 zbal_
    ) external approved(usr) untilClose(maturity) {
        // redemption only after amp value is available after maturity
        // collect claims additionally if available when collect does not equal latest
        require(
            (maturity <= collect_) && (collect_ <= latestAmpTimestamp),
            "timestamp/invalid"
        );

        uint256 latestAmp = amp[latestAmpTimestamp]; // amp value at latest timestamp
        uint256 collectAmp = amp[collect_]; // amp value at collect timestamp
        require(collectAmp != 0, "amp/invalid"); // ensure collect amp value is valid

        // normalize notional amount at collect amp value, and redeem normalized amount at latest amp value
        uint256 cbal_ = zbal_ / collectAmp; // [rad / ray -> wad]
        burnZero(usr, maturity, zbal_);
        unlock(usr, latestAmp, cbal_); // yield token sent to claim balance owner
    }

    // --- Claim Functions ---
    function collect(
        address usr,
        uint256 issuance,
        uint256 maturity,
        uint256 collect_,
        uint256 cbal_
    ) external approved(usr) untilClose(collect_) {
        // claims collection on notional amount can only be between issuance and maturity
        require(
            (issuance <= collect_) && (collect_ <= maturity),
            "timestamp/invalid"
        );

        uint256 latestAmp = amp[latestAmpTimestamp]; // amp value at latest timestamp
        uint256 issuanceAmp = amp[issuance]; // amp value at issuance timestamp
        uint256 collectAmp = amp[collect_]; // amp value at collect timestamp

        require(issuanceAmp != 0, "amp/invalid"); // issuance amp value cannot be 0
        require(collectAmp != 0, "amp/invalid"); // collect amp value cannot be 0
        require(collectAmp > issuanceAmp, "amp/no-difference"); // amp difference should be present

        burnClaim(usr, issuance, maturity, cbal_); // burn entire claim balance

        // mint new claim balance for remaining time period between collect and maturity
        if (collect_ != maturity) {
            mintClaim(
                usr,
                collect_,
                maturity,
                rdiv(rmul(cbal_, issuanceAmp), collectAmp)
            );
            // division rounds down and new balance might be slightly lower
        }

        // move out earnt yield on notional amount between issuance and collect
        uint256 cbalOut =
            mulu(cbal_, subu(collectAmp, issuanceAmp)) / latestAmp; // wad * ray / ray -> wad
        unlock(usr, latestAmp, cbalOut); // yield token sent to claim balance owner
    }

    function rewind(
        address usr,
        uint256 issuance,
        uint256 maturity,
        uint256 collect_,
        uint256 cbal_
    ) external approved(usr) untilClose(latestAmpTimestamp) {
        // collect timestamp needs to be before issuance(rewinding) and maturity after
        require(
            (collect_ <= issuance) && (issuance <= maturity),
            "timestamp/invalid"
        );

        uint256 latestAmp = amp[latestAmpTimestamp]; // amp value at latest timestamp
        uint256 collectAmp = amp[collect_]; // amp value at collect timestamp
        uint256 issuanceAmp = amp[issuance]; // amp value at issuance timestamp

        require(collectAmp != 0, "amp/invalid"); // collect amp value cannot be 0
        require(issuanceAmp != 0, "amp/invalid"); // issuance amp value cannot be 0
        require(collectAmp < issuanceAmp, "amp/no-difference"); // amp difference should be present

        // notional amount of claim balance earning yield since issuance
        uint256 notional = mulu(cbal_, issuanceAmp); // [wad * ray -> rad]
        // claim balance value for the same notional amount if it was deposited earlier at collect timestamp
        uint256 cbalCollect = notional / collectAmp; // [rad / ray -> wad]

        burnClaim(usr, issuance, maturity, cbal_); // burn claim balance
        // mint new claim balance with issuance set to earlier collect timestamp
        mintClaim(usr, collect_, maturity, cbalCollect);

        // total = mulu(cbalCollect, issuanceAmp)
        // [wad * ray -> rad] - total amount at issuance timestamp with earlier deposit
        // collect (total - notional) yield token balance from user for processing rewind
        lock(
            usr,
            latestAmp,
            subu(mulu(cbalCollect, issuanceAmp), notional) / latestAmp
        ); // [(rad - rad) / ray -> wad]
    }

    // ---  Future Claim Functions ---
    function slice(
        address usr,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint256 cbal_
    ) external approved(usr) {
        // t1 - issuance
        // t2 - slice point
        // t3 - maturity
        require(t1 < t2 && t2 < t3, "timestamp/invalid"); // activation timestamp t2 needs to be between t1 and t3

        burnClaim(usr, t1, t3, cbal_); // burn full original claim balance
        mintClaim(usr, t1, t2, cbal_); // mint claim balance

        // mint future claim balance to be activated later at t2
        // using amp value at t1 to calculate notional amount
        mintFutureClaim(usr, t1, t2, t3, cbal_);
    }

    function merge(
        address usr,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint256 t4,
        uint256 cbal_
    ) external approved(usr) {
        // t1 - original issuance of future claim balance
        // t2 - issuance of claim balance
        // t3 - maturity of claim balance
        // t4 - maturity of future claim balance

        // t1 can equal t2 // t2, t3, and t4 need to be in order
        require(t1 <= t2 && t2 < t3 && t3 < t4, "timestamp/invalid");

        // future claim balance that needs to be burnt
        // input claim balance itself if t1 and t2 are equal
        // scale notional amount of claim balance issuance from t2 to t1 when not equal
        uint256 cbalScaled =
            (t1 == t2) ? cbal_ : mulu(cbal_, amp[t2]) / amp[t1];

        burnClaim(usr, t2, t3, cbal_);
        burnFutureClaim(usr, t1, t3, t4, cbalScaled);
        mintClaim(usr, t2, t4, cbal_);
    }

    function activate(
        address usr,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint256 t4,
        uint256 cbal_
    ) external approved(usr) untilClose(t3) {
        // t1 - original issuance of future claim balance
        // t2 - activation point of future claim balance
        // t3 - closest available amp timestamp after t2, t2 and t3 can be equal
        // t4 - maturity of future claim balance
        require(t1 < t2 && t2 <= t3 && t3 < t4, "timestamp/invalid"); // all timestamps are in order
        require(amp[t3] != 0, "amp/invalid"); // amp value required to activate at t3

        // scale notional amount of claim balance issuance from t1 to t3
        uint256 newcbal_ = mulu(cbal_, amp[t1]) / amp[t3];

        burnFutureClaim(usr, t1, t2, t4, cbal_); // burn future claim balance
        mintClaim(usr, t3, t4, newcbal_); // mint claim balance
        // yield earnt between t2 to t3 becomes uncollectable
    }

    function sliceFuture(
        address usr,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint256 t4,
        uint256 cbal_
    ) external approved(usr) {
        require(t1 < t2 && t2 < t3 && t3 < t4, "timestamp/invalid");

        burnFutureClaim(usr, t1, t2, t4, cbal_);
        mintFutureClaim(usr, t1, t2, t3, cbal_);
        mintFutureClaim(usr, t1, t3, t4, cbal_);
    }

    function mergeFuture(
        address usr,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint256 t4,
        uint256 cbal_
    ) external approved(usr) {
        require(t1 < t2 && t2 < t3 && t3 < t4, "timestamp/invalid");

        burnFutureClaim(usr, t1, t2, t3, cbal_);
        burnFutureClaim(usr, t1, t3, t4, cbal_);
        mintFutureClaim(usr, t1, t2, t4, cbal_);
    }

    // --- Governance ---
    function close() external {
        require(pot.live() == 0, "pot/not-caged"); // pot needs to be caged for close to succeed
        require(closeTimestamp == uint256(-1), "closed"); // can be closed only once

        this.snapshot(); // snapshot can be taken
        closeTimestamp = block.timestamp; // set close timestamp
    }

    function calculate(uint256 maturity, uint256 ratio_)
        public
        onlyGov
        afterClose(maturity)
    {
        ratio[maturity] = ratio_;
        // ex: 0.015 gives 0.985 to zero balance at this maturity and 0.015 to claim balance
    }

    // --- Zero and Claim Cash Out Functions ---
    function zero(uint256 maturity, uint256 zbal_)
        public
        view
        afterClose(maturity)
        returns (uint256)
    {
        require(ratio[maturity] != 0, "ratio/not-set"); // cashout ratio needs to be set for maturity
        return rmul(zbal_, subu(RAY, ratio[maturity])); // yield token value of notional amount in zero
    }

    function claim(uint256 maturity, uint256 zbal_)
        public
        view
        afterClose(maturity)
        returns (uint256)
    {
        require(ratio[maturity] != 0, "ratio/not-set"); // cashout ratio needs to be set for maturity
        return rmul(zbal_, ratio[maturity]); // yield token value of notional amount in claim
    }

    function cashZero(
        address usr,
        uint256 maturity,
        uint256 zbal_
    ) external afterClose(maturity) {
        burnZero(usr, maturity, zbal_); // burn balance

        uint256 cash = zero(maturity, zbal_); // get yield token value

        uint256 latestAmp = amp[latestAmpTimestamp]; // last amp value
        uint256 cbalOut = cash / latestAmp;

        unlock(usr, latestAmp, cbalOut); // transfer yield token to user
    }

    function cashClaim(
        address usr,
        uint256 maturity,
        uint256 cbal_
    ) external afterClose(maturity) {
        // yield earnt before close needs to be claimed prior to cashing out
        burnClaim(usr, closeTimestamp, maturity, cbal_);

        uint256 zbal_ = mulu(cbal_, amp[closeTimestamp]);
        uint256 cash = claim(maturity, zbal_); // get yield token value

        uint256 latestAmp = amp[latestAmpTimestamp]; // last amp value
        uint256 cbalOut = cash / latestAmp;

        unlock(usr, latestAmp, cbalOut); // transfer yield token to user
    }

    function cashFutureClaim(
        address usr,
        uint256 issuance,
        uint256 activation,
        uint256 maturity,
        uint256 cbal_
    ) external afterClose(activation) {
        burnFutureClaim(usr, issuance, activation, maturity, cbal_);

        uint256 zbal_ = mulu(cbal_, amp[issuance]); // calculate notional amount
        uint256 cash = subu(claim(maturity, zbal_), claim(activation, zbal_)); // yield token value using difference

        uint256 latestAmp = amp[latestAmpTimestamp]; // last amp value
        uint256 cbalOut = cash / latestAmp;

        unlock(usr, latestAmp, cbalOut); // transfer yield token to user
    }
}
