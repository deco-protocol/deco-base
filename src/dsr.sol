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

contract SplitDSRLike {
    function vat() public returns (VatLike);
    function gov() public returns (address);

    function chi(address,uint) public returns (uint);

    function mintZCD(address yield, address usr, uint end, uint dai) external;
    function burnZCD(address yield, address usr, uint end, uint dai) external;
    function mintDCC(address yield, address usr, uint start, uint end, uint pie) external;
    function burnDCC(address yield, address usr, uint start, uint end, uint pie) external;
    function mintFutureDCC(address yield, address usr, uint start, uint slice, uint end, uint pie) external;
    function burnFutureDCC(address yield, address usr, uint start, uint slice, uint end, uint pie) external;
}

contract DSR {
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

    SplitDSRLike public split; // SplitDSR contract address
    VatLike public vat;
    PotLike public pot;
    bool public canSnapshot;
    bool public canInsert;

    uint public final; // Final timestamp synchronized from SplitDSR

    mapping (uint => uint) public ratio; // end timestamp => dcc balance cashout ratio [ray]

    constructor(address split_, address pot_) public {
        split = SplitDSRLike(split_);

        pot = PotLike(pot_);
        vat = pot.vat();

        vat.hope(address(pot)); // Approve Pot to modify Split's Dai balance within Vat
        canSnapshot = true;
        canInsert = true;
        final = uint(-1); // Initialized to MAX_UINT and updated after emergency shutdown is triggered on Pot
    }

    modifier onlySplit() {
        require(msg.sender == address(split));
        _;
    }

    modifier onlyGov() {
        require(msg.sender == split.gov());
        _;
    }

    modifier afterFinal(uint time) {
        require(final < time); // processes only if input timestamp is after shutdown timestamp
        _;
    }

    // Process function only if end timestamp is greater than final
    modifier validEnd(uint end) {
        require(final < uint(-1)); // Pot needs to be caged
        require(final < end); // End needs to be greater than final
        _;
    }

    function snapshot() public returns (uint) {
        return pot.drip(); // retrieve chi value from pot
    }

    function lock(address usr, uint chi, uint pie) public onlySplit returns (uint) {
        uint dai = mul(pie, chi); // Calculate dai amount with pie input. pie is the equivalent normalized dai balance stored in Pot at current chi value: pie * chi = dai

        vat.move(usr, address(this), dai); // Move dai from usr to Split
        pot.join(pie); // Split deposits dai into Pot

        return dai;
    }

    function unlock(address usr, uint chi, uint pie) public onlySplit returns (uint) {
        uint dai = mul(pie, chi); // Calculate dai amount with pie input. pie is the equivalent normalized dai balance stored in Pot at current chi value: pie * chi = dai

        pot.exit(pie); // pie removed from Pot
        vat.move(address(this), usr, dai); // Total payout to user is redeemed dai + dsr earnt from snap timestamp until now

        return dai;
    }

    // Emergency Shutdown processing in ValueDSR before ZCD and DCC balances with end timestamps after final can be cashed
    // * Anyone can execute cage() once to set final timestamp in this DSR Yield Adapter
    // * Governance has to execute calculate for all future end timestamps and set ratio of dai payout between zcd and dcc of the maturity timestamp

    // Emergency Shutdown Split after Pot is caged
    function cage() external {
        require(pot.live() == 0); // Pot needs to be caged
        require(final == uint(-1)); // final timestamp can be set only once

        snapshot(); // Snapshot is taken at final timestamp
        final = now; // set final timestamp
    }

    // --- Governance ---
    // Calculate cashout ratio to split dai between ZCD and DCC at each end timestamp
    function calculate(uint end, uint ratio_) public onlyGov validEnd(end) {
        ratio[end] = ratio_; // Gov sets a ratio. Ex: 0.015 gives zcd of this maturity 0.985 Dai and DCC 0.015 Dai
    }

    // --- ZCD and DCC Valuation Calculations ---
    // Value of ZCD balance with end timestamp
    function zcd(uint end, uint dai) public view validEnd(end) returns (uint) {
        require(ratio[end] != 0); // cashout ratio for end required
        return rmul(dai, sub(ONE, ratio[end]));
    }

    // Value of DCC balance with final and end timestamp
    function dcc(uint end, uint dai) public view validEnd(end) returns (uint) {
        require(ratio[end] != 0); // cashout ratio for end required
        return rmul(dai, ratio[end]);
    }

    // --- User balance with future maturity cash out functions ---
    // Exchange ZCD balance for Dai after emergency shutdown
    // * User transfers ZCD balance with end timestamp greater than final
    // * User receives the dai value reported by ValueDSR
    function cashZCD(address usr, uint end, uint dai) external afterFinal(end) {
        split.burnZCD(address(this), usr, end, dai);

        uint cash = zcd(end, dai); // Get value of ZCD balance in dai

        uint lastSnapshotTimestamp = split.lastSnapshot(address(this));
        uint chiLast = split.chi(address(this), lastSnapshotTimestamp); // last chi value
        uint pieOut = cash / chiLast;

        unlock(usr, chiLast, pieOut);
    }

    // Exchange DCC balance for Dai after emergency shutdown
    // * User transfers DCC balance with end timestamp greater than final
    // * User receives the dai value reported by ValueDSR
    function cashDCC(address usr, uint end, uint pie) external afterFinal(end) {
        split.burnDCC(address(this), usr, final, end, pie); // Savings earnt until final need to be claimed prior to cashing out

        uint dai = mul(pie, split.chi(address(this), final));
        uint cash = dcc(end, dai); // Get value of DCC balance in dai

        uint lastSnapshotTimestamp = split.lastSnapshot(address(this));
        uint chiLast = split.chi(address(this), lastSnapshotTimestamp); // last chi value
        uint pieOut = cash / chiLast;

        unlock(usr, chiLast, pieOut);
    }

    // Exchange FutureDCC balance for Dai after emergency shutdown
    // * User transfers FutureDCC balance with slice timestamp greater than final
    // * User receives the dai value reported by ValueDSR
    function cashFutureDCC(address usr, uint start, uint slice, uint end, uint pie) external afterFinal(slice) {
        split.burnFutureDCC(address(this), usr, start, slice, end, pie);

        uint dai = mul(pie, split.chi(address(this), start)); // calculate original dai notional amount

        // FutureDCC value calculated from values in dai reported for DCC balances with end timestamps at slice and end
        uint cash = sub(dcc(end, dai), dcc(slice, dai));

        uint lastSnapshotTimestamp = split.lastSnapshot(address(this));
        uint chiLast = split.chi(address(this), lastSnapshotTimestamp); // last chi value
        uint pieOut = cash / chiLast;

        unlock(usr, chiLast, pieOut);
    }
}