pragma solidity 0.5.12;

interface PotLike {
    function vat() public returns (address);
    function chi() external returns (uint ray);
    function rho() external returns (uint);
    function live() public returns (uint);
    function drip() public returns (uint);
    function join(uint pie) public;
    function exit(uint pie) public;
}