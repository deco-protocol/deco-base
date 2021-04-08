/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.7.6;

interface CoreLike{
    function gov() external returns (address);
    function zBal(address, bytes32) external returns (uint);
    function cBal(address, bytes32) external returns (uint);
    function totalSupply(bytes32) external returns (uint);
    
    function yields(address) external returns (bool);
    function amp(address, uint) external returns (uint);
    function latestAmpTimestamp(address) external returns (uint);

    function approvals(address, address) external returns (bool);

    function enableYieldAdapter(address) external;
    function approve(address, bool) external;

    function mintZero(address, address, uint, uint) external;
    function burnZero(address, address, uint, uint) external;
    function mintClaim(address, address, uint, uint, uint) external;
    function burnClaim(address, address, uint, uint, uint) external;
    function mintFutureClaim(address, address, uint, uint, uint, uint) external;
    function burnFutureClaim(address, address, uint, uint, uint, uint) external;

    function updateGov(address) external;

    function moveZero(address, address, bytes32, uint) external;
    function moveClaim(address, address, bytes32, uint) external;

    function snapshot(address) external;
    function insert(address, uint, uint) external;

    function issue(address, address, uint, uint, uint) external;
    function withdraw(address, address, uint, uint) external;
    function redeem(address, address, uint, uint, uint) external;
    function collect(address, address, uint, uint, uint, uint) external;
    function rewind(address, address, uint, uint, uint, uint) external;
    function slice(address, address, uint, uint, uint, uint) external;
    function merge(address, address, uint, uint, uint, uint, uint) external;
    function activate(address, address, uint, uint, uint, uint, uint) external;
    function sliceFuture(address, address, uint, uint, uint, uint, uint) external;
    function mergeFuture(address, address, uint, uint, uint, uint, uint) external;
}