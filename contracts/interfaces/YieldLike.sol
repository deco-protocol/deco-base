/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.7.6;

interface YieldLike {
    function core() external returns (address);
    function canSnapshot() external returns (bool);
    function canInsert() external returns (bool);
    function canOverwrite() external returns (bool);

    function closeTimestamp() external returns (uint);
    function ratio(uint) external returns (uint);

    function snapshot() external returns (uint);

    function lock(address, uint, uint) external returns (uint);
    function unlock(address, uint, uint) external returns (uint);

    function close() external;

    function calculate(uint, uint) external;
    function zero(uint, uint) external returns (uint);
    function claim(uint, uint) external returns (uint);

    function cashZero(address, uint, uint) external;
    function cashClaim(address, uint, uint) external;
    function cashFutureClaim(address, uint, uint, uint, uint) external;
}
    