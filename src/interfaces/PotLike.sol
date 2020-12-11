pragma solidity 0.5.12;

interface PotLike {
    function vat() external returns (address);
    function chi() external returns (uint ray);
    function rho() external returns (uint);
    function live() external returns (uint);
    function drip() external returns (uint);
    function join(uint pie) external;
    function exit(uint pie) external;
}