pragma solidity 0.5.12;

import "../lib/DSMath.sol";
import "../interfaces/SplitLike.sol";

contract GovManaged is DSMath {
    SplitLike public split; // Split contract address
    bool public canSnapshot;
    bool public canInsert;

    uint public close; 

    mapping (uint => uint) public ratio; // end timestamp => dcc balance cashout ratio [ray]

    constructor(address split_, address pot_) public {
        split = SplitLike(split_);
        canSnapshot = false;
        canInsert = true;
        close = uint(-1); // Initialized to MAX_UINT and updated after emergency shutdown is triggered on Pot
    }

    modifier onlySplit() {
        require(msg.sender == address(split));
        _;
    }

    modifier onlyGov() {
        require(msg.sender == split.gov());
        _;
    }

    modifier afterClose(uint time) {
        require(close < time); // processes only if input timestamp is after shutdown timestamp
        _;
    }

    // Process function only if end timestamp is greater than close
    modifier validEnd(uint end) {
        require(close < uint(-1)); // Pot needs to be caged
        require(close < end); // End needs to be greater than close
        _;
    }

    // no snapshot function, only governance can insert values

    function lock(address usr, uint chi, uint pie) public onlySplit returns (uint) {
        uint dai = mulu(pie, chi); // Calculate dai amount with pie input. pie is the equivalent normalized dai balance stored in Pot at current chi value: pie * chi = dai

        // move token balance from user to yield adapter

        return dai;
    }

    function unlock(address usr, uint chi, uint pie) public onlySplit returns (uint) {
        uint dai = mulu(pie, chi); // Calculate dai amount with pie input. pie is the equivalent normalized dai balance stored in Pot at current chi value: pie * chi = dai

        // move token balance from yield adapter to user

        return dai;
    }

    // Emergency Shutdown processing in ValueDSR before ZCD and DCC balances with end timestamps after close can be cashed
    // * Anyone can execute cage() once to set close timestamp in this DSR Yield Adapter
    // * Governance has to execute calculate for all future end timestamps and set ratio of dai payout between zcd and dcc of the maturity timestamp

    // Shutdown Yield adapter
    function cage(uint timestamp) external {
        require(close == uint(-1)); // close timestamp can be set only once
        require(split.chi(address(this), timestamp) != 0); // ensure snapshot exists at shutdown timestamp
        close = timestamp; // set close timestamp
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
        return rmul(dai, subu(RAY, ratio[end]));
    }

    // Value of DCC balance with close and end timestamp
    function dcc(uint end, uint dai) public view validEnd(end) returns (uint) {
        require(ratio[end] != 0); // cashout ratio for end required
        return rmul(dai, ratio[end]);
    }

    // --- User balance with future maturity cash out functions ---
    // Exchange ZCD balance for Dai after emergency shutdown
    // * User transfers ZCD balance with end timestamp greater than close
    // * User receives the dai value reported by ValueDSR
    function cashZCD(address usr, uint end, uint dai) external afterClose(end) {
        split.burnZCD(address(this), usr, end, dai);

        uint cash = zcd(end, dai); // Get value of ZCD balance in dai

        uint lastSnapshotTimestamp = split.lastSnapshot(address(this));
        uint chiLast = split.chi(address(this), lastSnapshotTimestamp); // last chi value
        uint pieOut = cash / chiLast;

        unlock(usr, chiLast, pieOut);
    }

    // Exchange DCC balance for Dai after emergency shutdown
    // * User transfers DCC balance with end timestamp greater than close
    // * User receives the dai value reported by ValueDSR
    function cashDCC(address usr, uint end, uint pie) external afterClose(end) {
        split.burnDCC(address(this), usr, close, end, pie); // Savings earnt until close need to be claimed prior to cashing out

        uint dai = mulu(pie, split.chi(address(this), close));
        uint cash = dcc(end, dai); // Get value of DCC balance in dai

        uint lastSnapshotTimestamp = split.lastSnapshot(address(this));
        uint chiLast = split.chi(address(this), lastSnapshotTimestamp); // last chi value
        uint pieOut = cash / chiLast;

        unlock(usr, chiLast, pieOut);
    }

    // Exchange FutureDCC balance for Dai after emergency shutdown
    // * User transfers FutureDCC balance with slice timestamp greater than close
    // * User receives the dai value reported by ValueDSR
    function cashFutureDCC(address usr, uint start, uint slice, uint end, uint pie) external afterClose(slice) {
        split.burnFutureDCC(address(this), usr, start, slice, end, pie);

        uint dai = mulu(pie, split.chi(address(this), start)); // calculate original dai notional amount

        // FutureDCC value calculated from values in dai reported for DCC balances with end timestamps at slice and end
        uint cash = subu(dcc(end, dai), dcc(slice, dai));

        uint lastSnapshotTimestamp = split.lastSnapshot(address(this));
        uint chiLast = split.chi(address(this), lastSnapshotTimestamp); // last chi value
        uint pieOut = cash / chiLast;

        unlock(usr, chiLast, pieOut);
    }
}