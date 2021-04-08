/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.7.6;

interface PotLike {
    function vat() external returns (address);

    function chi() external returns (uint256 ray);

    function rho() external returns (uint256);

    function live() external returns (uint256);

    function drip() external returns (uint256);

    function join(uint256 pie) external;

    function exit(uint256 pie) external;
}
