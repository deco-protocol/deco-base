/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.7.6;

interface ChaiLike {
    function vat() external view returns (address);
    function pot() external view returns (address);
    function daiJoin() external view returns (address);
    function daiToken() external view returns (address);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function version() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function allowance(address, address) external view returns (uint256);
    function nonces(address) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external view returns (bytes32);
    function transfer(address, uint256) external;
    function move(address, address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
    function approve(address, uint256) external returns (bool);
    function permit(address, address, uint256, uint256, bool, uint8, bytes32, bytes32) external;

    function dai(address) external returns (uint);
    function join(address, uint) external;
    function exit(address, uint) external;
    function draw(address, uint) external;
}