pragma solidity 0.5.12;

contract SplitDSRLike {
    function last() external returns (uint);
}

contract ValueDSR {
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
    bool public initialized; // ValueDSR initialization flag
    uint public last; // Last timestamp synchronized from SplitDSR

    mapping (uint => uint) public ratio; // end timestamp => dcp balance cashout ratio [ray]

    constructor() public {
        initialized = false;
        last = uint(-1); // Initialized to MAX_UINT
    }

    // Process function only if end timestamp is greater than last
    modifier validEnd(uint end) {
        require(initialized); // ValueDSR needs to be initialized
        require(last < uint(-1)); // Pot needs to be caged
        require(last < end); // End needs to be greater than last
        _;
    }

    // Initialize ValueDSR contract with SplitDSR address after its deployment
    function init(address split_) public returns (bool) {
        require(!initialized); // ValueDSR can be initialized once

        split = SplitDSRLike(split_);
        initialized = true; // Prevents init from being executed again

        return initialized;
    }

    // Synchronize last value from SplitDSR
    function update() public {
        require(initialized);
        last = split.last();
    }

    // Calculate cashout ratio to split dai between ZCD and DCP at each end timestamp
    function calculate(uint end) public validEnd(end) returns (uint ratio_) {
        ratio_ = mul(15, 10**24); // 0.015
        ratio[end] = ratio_; // All ZCD valued at 0.985 Dai and DCP valued at 0.015 Dai irrespective of end timestamp

        // TODO
        // Implement a proper valuation methodology to compute a better ratio considering
        // their end timestamp and give both zcd and dcp holders a fair dai amount back
    }

    // Value of ZCD balance with end timestamp
    function zcd(uint end, uint dai) public view validEnd(end) returns (uint) {
        require(ratio[end] != 0); // cashout ratio for end required
        return rmul(dai, sub(ONE, ratio[end]));
    }

    // Value of DCP balance with last and end timestamp
    function dcp(uint end, uint dai) public view validEnd(end) returns (uint) {
        require(ratio[end] != 0); // cashout ratio for end required
        return rmul(dai, ratio[end]);
    }
}