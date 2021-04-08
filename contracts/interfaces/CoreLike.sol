/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.7.6;

interface CoreLike {
    function gov() external returns (address);

    function zBal(address usr, bytes32 class_) external returns (uint256 rad_);

    function cBal(address usr, bytes32 class_) external returns (uint256 wad_);

    function totalSupply(bytes32 class_) external returns (uint256 rad_);

    function amp(uint256 timestamp_) external returns (uint256 amp_);

    function latestAmpTimestamp() external returns (uint256 timestamp_);

    function closeTimestamp() external returns (uint256 timestamp_);

    function ratio(uint256 timestamp_) external returns (uint256 ratio_);

    function approvals(address usr, address approved) external returns (bool);

    function approve(address usr, bool approval) external;

    function updateGov(address newGov) external;

    function moveZero(
        address src,
        address dst,
        bytes32 class_,
        uint256 zbal_
    ) external;

    function moveClaim(
        address src,
        address dst,
        bytes32 class_,
        uint256 cbal_
    ) external;

    function snapshot() external;

    function insert(uint256 t, uint256 amp_) external;

    function issue(
        address usr,
        uint256 issuance,
        uint256 maturity,
        uint256 cbal_
    ) external;

    function withdraw(
        address usr,
        uint256 maturity,
        uint256 cbal_
    ) external;

    function redeem(
        address usr,
        uint256 maturity,
        uint256 collect_,
        uint256 zbal_
    ) external;

    function collect(
        address usr,
        uint256 issuance,
        uint256 maturity,
        uint256 collect_,
        uint256 cbal_
    ) external;

    function rewind(
        address usr,
        uint256 issuance,
        uint256 maturity,
        uint256 collect_,
        uint256 cbal_
    ) external;

    function slice(
        address usr,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint256 cbal_
    ) external;

    function merge(
        address usr,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint256 t4,
        uint256 cbal_
    ) external;

    function activate(
        address usr,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint256 t4,
        uint256 cbal_
    ) external;

    function sliceFuture(
        address usr,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint256 t4,
        uint256 cbal_
    ) external;

    function mergeFuture(
        address usr,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint256 t4,
        uint256 cbal_
    ) external;

    function close() external;

    function calculate(uint256 maturity, uint256 ratio_) external;

    function zero(uint256 maturity, uint256 zbal_) external returns (uint256);

    function claim(uint256 maturity, uint256 zbal_) external returns (uint256);

    function cashZero(
        address usr,
        uint256 maturity,
        uint256 zbal_
    ) external;

    function cashClaim(
        address usr,
        uint256 maturity,
        uint256 cbal_
    ) external;

    function cashFutureClaim(
        address usr,
        uint256 issuance,
        uint256 activation,
        uint256 maturity,
        uint256 cbal_
    ) external;
}
