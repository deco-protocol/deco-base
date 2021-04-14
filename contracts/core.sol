/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.7.6;

import "./lib/DSMath.sol";
import "./interfaces/IERC20.sol";

contract Core is DSMath {
    address public gov; // governance

    IERC20 public yToken; // yToken
    uint256 public tokenDecimals; // yToken decimals

    // user address => zero class => zero balance [wad: 18 decimal fixed point number]
    mapping(address => mapping(bytes32 => uint256)) public zBal;
    // user address => claim class => claim balance [wad]
    mapping(address => mapping(bytes32 => uint256)) public cBal;
    // zero class => total zero supply [wad]
    mapping(bytes32 => uint256) public totalSupply;

    mapping(uint256 => uint256) public frac; // frac timestamp => frac value [wad] ex: 0.85
    uint256 public latestFracTimestamp; // latest frac timestamp

    // balance address => approved address => approval status
    mapping(address => mapping(address => bool)) public approvals;

    mapping(uint256 => uint256) public ratio; // maturity timestamp => balance cashout ratio [wad]
    uint256 public closeTimestamp; // yield adapter close timestamp

    event MintZero(
        address indexed usr,
        bytes32 indexed class_,
        uint256 maturity,
        uint256 bal_
    );
    event BurnZero(
        address indexed usr,
        bytes32 indexed class_,
        uint256 maturity,
        uint256 bal_
    );
    event MintClaim(
        address indexed usr,
        bytes32 indexed class_,
        uint256 issuance,
        uint256 maturity,
        uint256 bal_
    );
    event BurnClaim(
        address indexed usr,
        bytes32 indexed class_,
        uint256 issuance,
        uint256 maturity,
        uint256 bal_
    );

    event MoveZero(
        address indexed src,
        address indexed dst,
        bytes32 indexed class_,
        uint256 bal_
    );
    event MoveClaim(
        address indexed src,
        address indexed dst,
        bytes32 indexed class_,
        uint256 bal_
    );

    event NewFrac(uint256 indexed time, uint256 frac);
    event Approval(address indexed sender, address indexed usr, bool approval);

    constructor(address yToken_) {
        gov = msg.sender;

        yToken = IERC20(yToken_);
        tokenDecimals = yToken.decimals(); // set decimals of yield token
        require(
            tokenDecimals >= 2 && tokenDecimals <= 50,
            "decimals/exceeds-limits"
        );

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
        uint256 frac_,
        uint256 tbal_
    ) internal returns (uint256) {
        // transfer tbal_ amount of yToken balance from usr
        require(
            yToken.transferFrom(usr, address(this), tbal_),
            "transfer-failed"
        );

        uint256 bal_; // wad
        if (tokenDecimals == 18) {
            bal_ = tbal_; // decimals are 18
        } else if (tokenDecimals < 18) {
            bal_ = mulu(tbal_, 10**subu(18, tokenDecimals)); // ex: 18 - 9 = 9 // decimals lower than 18
        } else if (tokenDecimals > 18) {
            bal_ = tbal_ / 10**subu(tokenDecimals, 18); // ex: 25 - 18 = 7 // excess lost // decimals higher than 18
        }
        // can delete if else conditions and use only the correct path during deployment

        return wdiv(bal_, frac_); // return notional amount // ex: 100/0.9=110
    }

    function unlock(
        address usr,
        uint256 frac_,
        uint256 bal_
    ) internal {
        // notional amount * frac = transfer amount // ex: 110 * 0.8 = 88, 110 * 0.1 = 11
        uint256 adjBal_ = wmul(bal_, frac_); // wad

        uint256 tbal_;
        if (tokenDecimals == 18) {
            tbal_ = adjBal_; // decimals are 18
        } else if (tokenDecimals < 18) {
            tbal_ = adjBal_ / 10**subu(18, tokenDecimals); // ex: 18 - 9 = 9 // decimals lower than 18
        } else if (tokenDecimals > 18) {
            tbal_ = mulu(adjBal_, 10**subu(tokenDecimals, 18)); // ex: 25 - 18 = 7 // decimals higher than 18
        }
        // can delete if else conditions and use only the correct path during deployment

        // transfer yToken bal to usr
        require(
            yToken.transferFrom(address(this), usr, tbal_),
            "transfer-failed"
        );
    }

    function mintZero(
        address usr,
        uint256 maturity,
        uint256 bal_
    ) internal {
        // calculate zero class with adapter address and maturity timestamp
        bytes32 class_ = keccak256(abi.encodePacked(maturity));

        zBal[usr][class_] = addu(zBal[usr][class_], bal_);
        totalSupply[class_] = addu(totalSupply[class_], bal_);
        emit MintZero(usr, class_, maturity, bal_);
    }

    function burnZero(
        address usr,
        uint256 maturity,
        uint256 bal_
    ) internal {
        bytes32 class_ = keccak256(abi.encodePacked(maturity));

        require(zBal[usr][class_] >= bal_, "zBal/insufficient-balance");

        zBal[usr][class_] = subu(zBal[usr][class_], bal_);
        totalSupply[class_] = subu(totalSupply[class_], bal_);
        emit BurnZero(usr, class_, maturity, bal_);
    }

    function mintClaim(
        address usr,
        uint256 issuance,
        uint256 maturity,
        uint256 bal_
    ) internal {
        bytes32 class_ = keccak256(abi.encodePacked(issuance, maturity));

        cBal[usr][class_] = addu(cBal[usr][class_], bal_);
        emit MintClaim(usr, class_, issuance, maturity, bal_);
    }

    function burnClaim(
        address usr,
        uint256 issuance,
        uint256 maturity,
        uint256 bal_
    ) internal {
        bytes32 class_ = keccak256(abi.encodePacked(issuance, maturity));

        require(cBal[usr][class_] >= bal_, "cBal/insufficient-balance");

        cBal[usr][class_] = subu(cBal[usr][class_], bal_);
        emit BurnClaim(usr, class_, issuance, maturity, bal_);
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
        uint256 bal_
    ) external approved(src) {
        require(zBal[src][class_] >= bal_, "zBal/insufficient-balance");

        zBal[src][class_] = subu(zBal[src][class_], bal_);
        zBal[dst][class_] = addu(zBal[dst][class_], bal_);

        emit MoveZero(src, dst, class_, bal_);
    }

    function moveClaim(
        address src,
        address dst,
        bytes32 class_,
        uint256 bal_
    ) external approved(src) {
        require(cBal[src][class_] >= bal_, "cBal/insufficient-balance");

        cBal[src][class_] = subu(cBal[src][class_], bal_);
        cBal[dst][class_] = addu(cBal[dst][class_], bal_);

        emit MoveClaim(src, dst, class_, bal_);
    }

    // --- Frac Functions ---
    // function snapshot() external {
    //     // allow anyone to snapshot frac value from on-chain when available
    // }

    function insert(uint256 t, uint256 frac_) external onlyGov untilClose(t) {
        // governance calculates frac value from pricePerShare
        require(frac_ <= WAD, "frac/above-one"); // should be 1 wad or below
        require(frac[t] == 0, "frac/overwrite-disabled"); // overwriting frac value disabled
        require(t <= block.timestamp, "frac/future-timestamp"); // cant insert at a future timestamp

        frac[t] = frac_;

        // update latest frac timestamp when inserting after current latest
        if (latestFracTimestamp < t) {
            latestFracTimestamp = t;
        }

        emit NewFrac(t, frac_);
    }

    // --- Zero and Claim Functions ---
    function issue(
        address usr,
        uint256 issuance,
        uint256 maturity,
        uint256 tbal_
    ) external approved(usr) untilClose(issuance) {
        // issuance has to be before or until latest, maturity cannot be before latest
        require(
            issuance <= latestFracTimestamp && latestFracTimestamp <= maturity,
            "timestamp/invalid"
        );
        // frac value should exist at issuance, take snapshot prior to calling issuance if it is at now
        require(frac[issuance] != 0, "frac/invalid");

        // lock tbal_ token balance and receive bal_ notional amount of zero and claim
        uint256 bal_ = lock(usr, frac[issuance], tbal_); // tbal_ in token decimals, bal_ in wad

        // issue same notional amount of zero and claim
        mintZero(usr, maturity, bal_);
        mintClaim(usr, issuance, maturity, bal_);
    }

    function withdraw(
        address usr,
        uint256 maturity,
        uint256 bal_
    ) external approved(usr) untilClose(latestFracTimestamp) {
        uint256 latestFrac = frac[latestFracTimestamp]; // frac value at latest timestamp

        // burn same notional amount of zero and claim
        burnZero(usr, maturity, bal_);
        // cannot burn if claim is not fully collected until latest frac timestamp
        burnClaim(usr, latestFracTimestamp, maturity, bal_);

        unlock(usr, latestFrac, bal_); // transfer token to usr
    }

    // --- Zero Functions ---
    function redeem(
        address usr,
        uint256 maturity,
        uint256 collect_,
        uint256 bal_
    ) external approved(usr) untilClose(maturity) {
        // redemption at maturity or at next available frac value after maturity
        require(
            (maturity <= collect_) && (collect_ <= latestFracTimestamp),
            "timestamp/invalid"
        );

        uint256 collectFrac = frac[collect_]; // frac value at collect timestamp
        require(collectFrac != 0, "frac/invalid"); // ensure collect frac value is valid

        burnZero(usr, maturity, bal_); // burn zero balance
        unlock(usr, collectFrac, bal_); // transfer token balance
    }

    // --- Claim Functions ---
    function collect(
        address usr,
        uint256 issuance,
        uint256 maturity,
        uint256 collect_,
        uint256 bal_
    ) external approved(usr) untilClose(collect_) {
        // claims collection on notional amount can only be between issuance and maturity
        require(
            (issuance <= collect_) && (collect_ <= maturity),
            "timestamp/invalid"
        );

        uint256 issuanceFrac = frac[issuance]; // frac value at issuance timestamp
        uint256 collectFrac = frac[collect_]; // frac value at collect timestamp

        require(issuanceFrac != 0, "frac/invalid"); // issuance frac value cannot be 0
        require(collectFrac != 0, "frac/invalid"); // collect frac value cannot be 0

        require(issuanceFrac > collectFrac, "frac/no-difference"); // frac difference should be present

        burnClaim(usr, issuance, maturity, bal_); // burn entire claim balance
        // mint new claim balance for remaining time period between collect and maturity
        if (collect_ != maturity) {
            mintClaim(usr, collect_, maturity, bal_);
        }
        unlock(usr, subu(issuanceFrac, collectFrac), bal_); // transfer token balance for collect amount
    }

    function rewind(
        address usr,
        uint256 issuance,
        uint256 maturity,
        uint256 collect_,
        uint256 bal_
    ) external approved(usr) untilClose(latestFracTimestamp) {
        // collect timestamp needs to be before issuance(rewinding) and maturity after
        require(
            (collect_ <= issuance) && (issuance <= maturity),
            "timestamp/invalid"
        );

        uint256 collectFrac = frac[collect_]; // frac value at collect timestamp
        uint256 issuanceFrac = frac[issuance]; // frac value at issuance timestamp

        require(collectFrac != 0, "frac/invalid"); // collect frac value cannot be 0
        require(issuanceFrac != 0, "frac/invalid"); // issuance frac value cannot be 0
        require(collectFrac > issuanceFrac, "frac/no-difference"); // frac difference should be present

        burnClaim(usr, issuance, maturity, bal_); // burn claim balance

        uint256 fracDiff = subu(collectFrac, issuanceFrac);
        lock(usr, fracDiff, wmul(bal_, fracDiff)); // transfer diff for rewind

        // mint new claim balance with issuance set to earlier collect timestamp
        mintClaim(usr, collect_, maturity, bal_);
    }

    // ---  Future Claim Functions ---
    function slice(
        address usr,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint256 bal_
    ) external approved(usr) {
        // t1 - issuance
        // t2 - slice point
        // t3 - maturity
        require(t1 < t2 && t2 < t3, "timestamp/invalid"); // timestamp t2 needs to be between t1 and t3

        burnClaim(usr, t1, t3, bal_); // burn original claim balance
        mintClaim(usr, t1, t2, bal_); // mint claim balance
        mintClaim(usr, t2, t3, bal_); // mint claim balance to be activated later at t2
    }

    function merge(
        address usr,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint256 bal_
    ) external approved(usr) {
        // t1 - issuance
        // t2 - merge point, maturity and issuance
        // t3 - maturity

        require(t1 < t2 && t2 < t3, "timestamp/invalid"); // timestamp t2 needs to be between t1 and t3

        burnClaim(usr, t1, t2, bal_); // burn first claim balance
        burnClaim(usr, t2, t3, bal_); // burn second claim balance
        mintClaim(usr, t1, t3, bal_); // mint whole
    }

    function activate(
        address usr,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint256 bal_
    ) external approved(usr) untilClose(t3) {
        // t1 - issuance
        // t2 - activation point with available frac value
        // t3 - maturity
        require(t1 < t2 && t2 < t3, "timestamp/invalid"); // all timestamps are in order

        require(frac[t1] == 0, "frac/valid"); // frac value should be missing at issuance
        require(frac[t2] != 0, "frac/invalid"); // valid frac value required to activate

        burnClaim(usr, t1, t3, bal_); // burn inactive claim balance
        mintClaim(usr, t2, t3, bal_); // mint claim balance
        // yield earnt between t2 to t3 becomes uncollectable
    }

    // --- Governance ---
    function close() external onlyGov {
        require(closeTimestamp == uint256(-1), "closed"); // can be closed only once
        closeTimestamp = latestFracTimestamp; // set close timestamp to last known frac value
    }

    function calculate(uint256 maturity, uint256 ratio_)
        public
        onlyGov
        afterClose(maturity)
    {
        require(ratio_ <= WAD, "ratio/not-fraction"); // needs to be less than or equal to 1
        // ex: 0.985 gives 0.985 to zero balance at this maturity and 0.015 to claim balance

        require(ratio[maturity] == 0, "ratio/present"); // cannot overwrite existing ratio

        ratio[maturity] = ratio_;
    }

    // --- Zero and Claim Cash Out Functions ---
    function zero(uint256 maturity, uint256 bal_)
        public
        view
        afterClose(maturity)
        returns (uint256)
    {
        require(ratio[maturity] != 0, "ratio/not-set"); // cashout ratio needs to be set for maturity, > 0
        return wmul(bal_, ratio[maturity]); // yield token value of notional amount in zero
    }

    function claim(uint256 maturity, uint256 bal_)
        public
        view
        afterClose(maturity)
        returns (uint256)
    {
        require(ratio[maturity] != 0, "ratio/not-set"); // cashout ratio needs to be set for maturity
        return wmul(bal_, subu(WAD, ratio[maturity])); // yield token value of notional amount in claim
    }

    function cashZero(
        address usr,
        uint256 maturity,
        uint256 bal_
    ) external approved(usr) afterClose(maturity) {
        burnZero(usr, maturity, bal_); // burn balance
        unlock(usr, frac[closeTimestamp], zero(maturity, bal_)); // transfer yield token to user
    }

    function cashClaim(
        address usr,
        uint256 maturity,
        uint256 bal_
    ) external approved(usr) afterClose(maturity) {
        // yield earnt before close needs to be claimed prior to cashing out
        burnClaim(usr, closeTimestamp, maturity, bal_);
        unlock(usr, frac[closeTimestamp], claim(maturity, bal_)); // transfer yield token to user
    }
}
