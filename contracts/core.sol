/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.7.6;

import "./lib/DSMath.sol";
import "./interfaces/IERC20.sol";

contract Core is DSMath {
    address public gov; // governance

    IERC20 public yToken; // Yield Token Address
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

        closeTimestamp = uint256(-1); // initialized to MAX_UINT, updated when this deco instance is closed
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
    
    /// Restricts functions to only work with maturity timestamps UNTIL close
    /// @dev Regular settlement with withdraw, redeem, and collect
    modifier untilClose(uint256 time) {
        require(time <= closeTimestamp, "after-close");
        _;
    }

    /// Restricts functions to only work with maturity timestamps AFTER close
    /// @dev Settlement of balances with cashZero and cashClaim
    modifier afterClose(uint256 time) {
        require(closeTimestamp < uint256(-1), "not-closed"); // neeeds to be closed
        require(closeTimestamp < time, "before-close"); // processes only if input timestamp is greater than close
        _;
    }

    // --- User Approvals ---

    /// Approve or disapprove another address to manage deco assets of a user
    /// @param usr Target ethereum address
    /// @param approval true to approve, false to disapprove
    /// @dev Binary approval check only for any amount
    function approve(address usr, bool approval) external {
        approvals[msg.sender][usr] = approval;
        emit Approval(msg.sender, usr, approval);
    }

    // --- Internal functions ---

    /// Lock transfers yield token balance from user to deco
    /// @param usr User address
    /// @param frac_ Fraction value to apply on yield token balance
    /// @param tbal_ Yield token transfered
    /// @return amount Notional amount equals the underlying base asset amount backing yield token
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

    /// Unlock transfers yield token balance from deco to user
    /// @param usr User address
    /// @param frac_ Fraction value to apply on yield token balance
    /// @param bal_ Notional amount (underlying base asset amount) being unlocked in equivalent yield token balance
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

    /// Mints zero balance
    /// @param usr User address
    /// @param maturity Maturity timestamp of zero balance to derive its class
    /// @param bal_ Zero balance amount
    function mintZero(
        address usr,
        uint256 maturity,
        uint256 bal_
    ) internal {
        // calculate zero class with maturity timestamp
        bytes32 class_ = keccak256(abi.encodePacked(maturity));

        zBal[usr][class_] = addu(zBal[usr][class_], bal_);
        totalSupply[class_] = addu(totalSupply[class_], bal_);
        emit MintZero(usr, class_, maturity, bal_);
    }

    /// Burns zero balance
    /// @param usr User address
    /// @param maturity Maturity timestamp of zero balance to derive its class
    /// @param bal_ Zero balance amount
    function burnZero(
        address usr,
        uint256 maturity,
        uint256 bal_
    ) internal {
        // calculate zero class with maturity timestamp
        bytes32 class_ = keccak256(abi.encodePacked(maturity));

        require(zBal[usr][class_] >= bal_, "zBal/insufficient-balance");

        zBal[usr][class_] = subu(zBal[usr][class_], bal_);
        totalSupply[class_] = subu(totalSupply[class_], bal_);
        emit BurnZero(usr, class_, maturity, bal_);
    }

    /// Mints claim balance
    /// @param usr User address
    /// @param issuance Issuance timestamp of claim balance to derive its class
    /// @param maturity Maturity timestamp of claim balance to derive its class
    /// @param bal_ Claim balance amount
    function mintClaim(
        address usr,
        uint256 issuance,
        uint256 maturity,
        uint256 bal_
    ) internal {
        // calculate claim class with both issuance and maturity timestamps
        bytes32 class_ = keccak256(abi.encodePacked(issuance, maturity));

        cBal[usr][class_] = addu(cBal[usr][class_], bal_);
        emit MintClaim(usr, class_, issuance, maturity, bal_);
    }

    /// Burns claim balance
    /// @param usr User address
    /// @param issuance Issuance timestamp of claim balance to derive its class
    /// @param maturity Maturity timestamp of claim balance to derive its class
    /// @param bal_ Claim balance amount
    function burnClaim(
        address usr,
        uint256 issuance,
        uint256 maturity,
        uint256 bal_
    ) internal {
        // calculate claim class with both issuance and maturity timestamps
        bytes32 class_ = keccak256(abi.encodePacked(issuance, maturity));

        require(cBal[usr][class_] >= bal_, "cBal/insufficient-balance");

        cBal[usr][class_] = subu(cBal[usr][class_], bal_);
        emit BurnClaim(usr, class_, issuance, maturity, bal_);
    }

    // --- Governance Functions ---

    /// Updates governance
    /// @dev restricted to be executed only by current governance
    /// @param newGov New address to be set as governance
    function updateGov(address newGov) public onlyGov {
        gov = newGov;
    }

    // --- Transfer Functions ---

    /// Transfers user's zero balance
    /// @param src Source address to transfer balance from
    /// @param dst Destination address to transfer balance to
    /// @param class_ Zero balance class
    /// @param bal_ Zero balance amount to transfer
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

    /// Transfers user's claim balance
    /// @param src Source address to transfer balance from
    /// @param dst Destination address to transfer balance to
    /// @param class_ Claim balance class
    /// @param bal_ Claim balance amount to transfer
    /// @dev Can transfer both activated and unactivated (future portion after slice) claim balances
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

    /// Snapshots fraction value of a yield token in a trustless manner for current timestamp
    /// @dev Has to be a public function
    /// @dev Can skip implementation if governance will handle inserting all required fraction values
    /* solhint-disable no-empty-blocks */
    function snapshot() external {
        // allow anyone to snapshot frac value from on-chain when available
    }

    /// Governance inserts a fraction value at a timestamp
    /// @dev Can be executed after close but timestamp cannot fall before close timestamp
    /// @dev Update require statements based on needs of the yield token integration
    function insert(uint256 t, uint256 frac_) external onlyGov untilClose(t) {
        // governance calculates frac value from pricePerShare
        // ex: pricePerShare: 1.25, frac: 1/1.25 = 0.80
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
    /// Issues zero and claim balances in exchange for yield token balance
    /// @param usr User address
    /// @param issuance Issuance timestamp set for claim balance
    /// @param maturity Maturity timestamp set for zero and claim balances
    /// @param tbal_ Yield token amount transferred to deco for issuance
    /// @dev tbal_ amount has same number of decimals as the yield token
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
        // frac value should exist at issuance, take snapshot prior to calling issuance if it is at current timestamp
        require(frac[issuance] != 0, "frac/invalid");

        // lock tbal_ token balance and receive bal_ notional amount of zero and claim
        uint256 bal_ = lock(usr, frac[issuance], tbal_); // tbal_ in token decimals, bal_ in wad

        // issue same notional amount of zero and claim
        mintZero(usr, maturity, bal_);
        mintClaim(usr, issuance, maturity, bal_);
    }

    /// Withdraws zero and claim balances before their maturity
    /// @param usr User address
    /// @param maturity Maturity timestamp of both zero and claim balances
    /// @param bal_ Zero and claim balance amounts need to be equal
    function withdraw(
        address usr,
        uint256 maturity,
        uint256 bal_
    ) external approved(usr) untilClose(latestFracTimestamp) {
        uint256 latestFrac = frac[latestFracTimestamp]; // frac value at latest timestamp

        // burn equal amount of zero and claim balances
        burnZero(usr, maturity, bal_);
        // cannot burn if claim is not fully collected until latest frac timestamp
        burnClaim(usr, latestFracTimestamp, maturity, bal_);

        unlock(usr, latestFrac, bal_); // transfer yield token to usr before maturity
    }

    // --- Zero Functions ---

    /// Redeems a zero balance after maturity
    /// @param usr User address
    /// @param maturity Maturity timestamp
    /// @param collect_ Collect timestamp to pass the zero holder additional yield earnt
    /// @param bal_ Zero balance amount
    /// @dev Redeemption of zero does not lose yield that the redeemable amount can earn starting at maturity
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
        unlock(usr, collectFrac, bal_); // transfer yield token balance
    }

    // --- Claim Functions ---

    /// Collects yield earned by a claim balance
    /// @param usr User address
    /// @param issuance Issuance timestamp with a fraction value present
    /// @param maturity Maturity timestamp
    /// @param collect_ Collect timestamp to claim yield earned until collect
    /// @param bal_ Claim balance amount
    /// @dev Collect can be executed any number of times between issuance and maturity for yield earned so far
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

        // issuance frac value cannot be 0
        // sliced claim balances in this situation can use activate to move issuance to timestamp with frac value      
        require(issuanceFrac != 0, "frac/invalid");
        require(collectFrac != 0, "frac/invalid"); // collect frac value cannot be 0

        require(issuanceFrac > collectFrac, "frac/no-difference"); // frac difference should be present

        burnClaim(usr, issuance, maturity, bal_); // burn current claim balance
        // mint new claim balance to collect yield earned later for remaining time period between collect and maturity
        if (collect_ != maturity) {
            mintClaim(usr, collect_, maturity, bal_);
        }
        unlock(usr, subu(issuanceFrac, collectFrac), bal_); // transfer token balance for collect amount
    }

    /// Rewinds issuance of claim balance back to a past timestamp
    /// @param usr User address
    /// @param issuance Issuance timestamp
    /// @param maturity Maturity timestamp
    /// @param collect_ Collect timestamp in the past with a fraction value
    /// @param bal_ Claim balance amount
    /// @dev Rewind also transfers an additional yield token amount from user to Deco to offset its loss
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
    /// Slices one claim balance into two claim balances at a timestamp
    /// @param usr User address
    /// @param t1 Issuance timestamp
    /// @param t2 Slice point timestamp
    /// @param t3 Maturity timestamp
    /// @param bal_ Claim balance amount
    /// @dev Slice issues two new claim balances, one of which needs to be activated 
    /// @dev in the future at a timestamp with a frac value when one is not present
    function slice(
        address usr,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint256 bal_
    ) external approved(usr) {
        require(t1 < t2 && t2 < t3, "timestamp/invalid"); // timestamp t2 needs to be between t1 and t3

        burnClaim(usr, t1, t3, bal_); // burn original claim balance
        mintClaim(usr, t1, t2, bal_); // mint claim balance
        mintClaim(usr, t2, t3, bal_); // mint claim balance to be activated later at t2
    }

    /// Merges two claim balances with contiguous time periods into one claim balance
    /// @param usr User address
    /// @param t1 Issuance timestamp of first
    /// @param t2 Merge timestamp- maturity timestamp of first and issuance timestamp of second
    /// @param t3 Maturity timestamp of second
    /// @param bal_ Claim balance amount
    function merge(
        address usr,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint256 bal_
    ) external approved(usr) {
        require(t1 < t2 && t2 < t3, "timestamp/invalid"); // timestamp t2 needs to be between t1 and t3

        burnClaim(usr, t1, t2, bal_); // burn first claim balance
        burnClaim(usr, t2, t3, bal_); // burn second claim balance
        mintClaim(usr, t1, t3, bal_); // mint whole
    }

    /// Activates a balance whose issuance timestamp does not have a fraction value set
    /// @param usr User address
    /// @param t1 Issuance timestamp without a fraction value
    /// @param t2 Activation timestamp with a fraction value set
    /// @param t3 Maturity timestamp
    /// @param bal_ Claim balance amount
    /// @dev Yield earnt between issuance and activation becomes uncollectable and is permanently lost
    function activate(
        address usr,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint256 bal_
    ) external approved(usr) untilClose(t3) {
        require(t1 < t2 && t2 < t3, "timestamp/invalid"); // all timestamps are in order

        require(frac[t1] == 0, "frac/valid"); // frac value should be missing at issuance
        require(frac[t2] != 0, "frac/invalid"); // valid frac value required to activate

        burnClaim(usr, t1, t3, bal_); // burn inactive claim balance
        mintClaim(usr, t2, t3, bal_); // mint active claim balance
    }

    // --- Governance ---

    /// Closes this deco instance
    /// @dev Close timestamp automatically set to the latest fraction value captured when close is executed
    /// @dev Setup close trigger conditions and control based on the requirements of the yield token integration
    function close() external onlyGov {
        require(closeTimestamp == uint256(-1), "closed"); // can be closed only once
        closeTimestamp = latestFracTimestamp; // set close timestamp to last known frac value
    }

    /// Stores a ratio value
    /// @param maturity Maturity timestamp to set ratio for
    /// @param ratio_ Ratio value
    /// @dev Yield token balance split ratio is applied to zero and claim balances with maturity after close timestamp
    /// @dev Setup a valuation calculation internally to calculate ratio if possible
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

    /// Determines value of zero with maturity after close timestamp
    /// @param maturity Maturity timestamp of zero balance
    /// @param bal_ Balance amount
    function zero(uint256 maturity, uint256 bal_)
        public
        view
        afterClose(maturity)
        returns (uint256)
    {
        require(ratio[maturity] != 0, "ratio/not-set"); // cashout ratio needs to be set for maturity, > 0
        return wmul(bal_, ratio[maturity]); // yield token value of notional amount in zero
    }

    /// Determines value of claim with maturity after close timestamp
    /// @param maturity Maturity timestamp of claim balance
    /// @param bal_ Balance amount
    /// @dev Issuance of claim needs to be at the close timestamp, which means it has collected yield earned until then
    function claim(uint256 maturity, uint256 bal_)
        public
        view
        afterClose(maturity)
        returns (uint256)
    {
        require(ratio[maturity] != 0, "ratio/not-set"); // cashout ratio needs to be set for maturity
        return wmul(bal_, subu(WAD, ratio[maturity])); // yield token value of notional amount in claim
    }

    /// Exchanges a zero balance with maturity after close timestamp for a yield token balance
    /// @param usr User address
    /// @param maturity Maturity timestamp
    /// @param bal_ Balance amount
    function cashZero(
        address usr,
        uint256 maturity,
        uint256 bal_
    ) external approved(usr) afterClose(maturity) {
        burnZero(usr, maturity, bal_); // burn balance
        unlock(usr, frac[closeTimestamp], zero(maturity, bal_)); // transfer yield token to user
    }

    /// Exchanges a claim balance with maturity after close timestamp for a yield token balance
    /// @param usr User address
    /// @param maturity Maturity timestamp
    /// @param bal_ Balance amount
    /// @dev Issuance of claim needs to be at the close timestamp, which means it has collected yield earned until then 
    /// @dev Any sliced claim balances need to be merged back or they will be permanently locked
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
