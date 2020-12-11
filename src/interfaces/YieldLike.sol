pragma solidity 0.5.12;

interface YieldLike {
    function split() external returns (address);
    function canSnapshot() external returns (bool);
    function canInsert() external returns (bool);
    function final() external returns (uint);
    function snapshot() external returns (uint);

    function lock(address usr, uint chi, uint pie) external returns (uint);
    function unlock(address usr, uint chi, uint pie) external returns (uint);
}