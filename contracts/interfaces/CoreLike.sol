/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.7.6;

interface CoreLike{
    function gov() external returns (address);
    function zBal(address usr, bytes32 class_) external returns (uint rad_);
    function cBal(address usr, bytes32 class_) external returns (uint wad_);
    function totalSupply(bytes32 class_) external returns (uint rad_);
    
    function amp(uint timestamp_) external returns (uint amp_);
    function latestAmpTimestamp() external returns (uint timestamp_);

    function closeTimestamp() external returns (uint timestamp_);
    function ratio(uint timestamp_) external returns (uint ratio_);

    function approvals(address usr, address approved) external returns (bool);
    function approve(address usr, bool approval) external;

    function updateGov(address newGov) external;

    function moveZero(address src, address dst, bytes32 class_, uint zbal_) external;
    function moveClaim(address src, address dst, bytes32 class_, uint cbal_) external;

    function snapshot() external;
    function insert(uint t, uint amp_) external;

    function issue(address usr, uint issuance, uint maturity, uint cbal_) external;
    function withdraw(address usr, uint maturity, uint cbal_) external;
    function redeem(address usr, uint maturity, uint collect_, uint zbal_) external;
    function collect(address usr, uint issuance, uint maturity, uint collect_, uint cbal_) external;
    function rewind(address usr, uint issuance, uint maturity, uint collect_, uint cbal_) external;
    function slice(address usr, uint t1, uint t2, uint t3, uint cbal_) external;
    function merge(address usr, uint t1, uint t2, uint t3, uint t4, uint cbal_) external;
    function activate(address usr, uint t1, uint t2, uint t3, uint t4, uint cbal_) external;
    function sliceFuture(address usr, uint t1, uint t2, uint t3, uint t4, uint cbal_) external;
    function mergeFuture(address usr, uint t1, uint t2, uint t3, uint t4, uint cbal_) external;

    function close() external;

    function calculate(uint maturity, uint ratio_) external;
    function zero(uint maturity, uint zbal_) external returns (uint);
    function claim(uint maturity, uint zbal_) external returns (uint);

    function cashZero(address usr, uint maturity, uint zbal_) external;
    function cashClaim(address usr, uint maturity, uint cbal_) external;
    function cashFutureClaim(address usr, uint issuance, uint activation, uint maturity, uint cbal_) external;
}