pragma solidity ^0.5.10;

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
    bool public initialized; // valueDSR initialization flag
    uint public last; // emergency shutdown timestamp

    mapping (uint => uint) public ratio; // end timestamp => dcp balance cashout ratio [ray]

    constructor() public {
        initialized = false;
        last = uint(-1); // emergency shutdown timestamp initialized to MAX_UINT
    }

    // --- Emergency Shutdown Modifier ---
    modifier validEnd(uint end) {
        require(initialized); // ValueDSR needs to be initialized
        require(last < uint(-1)); // Pot needs to be caged
        require(last < end); // end needs to be after emergency shutdown timestamp
        _;
    }

    // Initialize ValueDSR contract
    function init(address split_) public returns (bool) {
        require(!initialized); // can only be executed once

        split = SplitDSRLike(split_); // sets the split protocol address
        initialized = true; // locks the init function from being executed again

        return initialized;
    }

    // Update last value after emergency shutdown is triggered
    function update() public {
        require(initialized);
        last = split.last(); // synchronizing last value locally will avoid calls to split contract
    }

    // Calculate cashout ratio for an end timestamp
    function calculate(uint end) public validEnd(end) returns (uint ratio_) {
        ratio_ = mul(15, 10**24); // 0.015
        ratio[end] = ratio_;

        // TODO 
        // Use a sophisticated valuation methodology to compute a better ratio for 
        // all end timestamps to give both zcd and dcp holders a fair dai value back
    }

    // Value of ZCD balance at calculated cashout ratio for end
    function zcd(uint end, uint dai) public validEnd(end) returns (uint) {
        require(ratio[end] != 0); // cashout ratio for class required
        return rmul(dai, sub(ONE, ratio[end])); // all zcd valued at 98.5% of dai
    }

    // Value of DCP balance at calculated cashout ratio for end
    function dcp(uint end, uint dai) public validEnd(end) returns (uint) {
        require(ratio[end] != 0); // cashout ratio for class required
        return rmul(dai, ratio[end]); // all dcp valued at 1.5% of dai
    }
}