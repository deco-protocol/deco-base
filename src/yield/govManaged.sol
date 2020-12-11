pragma solidity 0.5.12;

import "../lib/DSMath.sol";
import "../interfaces/SplitLike.sol";

contract GovManaged is DSMath {
    SplitLike public split; // Split contract address
    bool public canSnapshot;
    bool public canInsert;

    uint public final; 

    mapping (uint => uint) public ratio; // end timestamp => dcc balance cashout ratio [ray]

    constructor(address split_, address pot_) public {
        split = SplitLike(split_);
        canSnapshot = false;
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

    // no snapshot function, only governance can insert values

    function lock(address usr, uint chi, uint pie) public onlySplit returns (uint) {
        uint dai = mul(pie, chi); // Calculate dai amount with pie input. pie is the equivalent normalized dai balance stored in Pot at current chi value: pie * chi = dai

        // move token balance from user to yield adapter

        return dai;
    }

    function unlock(address usr, uint chi, uint pie) public onlySplit returns (uint) {
        uint dai = mul(pie, chi); // Calculate dai amount with pie input. pie is the equivalent normalized dai balance stored in Pot at current chi value: pie * chi = dai

        // move token balance from yield adapter to user

        return dai;
    }

    // Emergency Shutdown processing in ValueDSR before ZCD and DCC balances with end timestamps after final can be cashed
    // * Anyone can execute cage() once to set final timestamp in this DSR Yield Adapter
    // * Governance has to execute calculate for all future end timestamps and set ratio of dai payout between zcd and dcc of the maturity timestamp

    // Shutdown Yield adapter
    function cage(uint timestamp) external {
        require(final == uint(-1)); // final timestamp can be set only once
        require(split.chi(address(this), timestamp) != 0); // ensure snapshot exists at shutdown timestamp
        final = timestamp; // set final timestamp
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