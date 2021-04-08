/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.7.6;

import "../lib/erc20.sol";
import "../lib/DSMath.sol";
import "./strings.sol";
import "../interfaces/CoreLike.sol";

contract ZeroAdapterERC20 is DSMath {
    using Strings for uint256;

    CoreLike core;
    uint256 chainId;
    mapping(bytes32 => address) public tokens;

    event NewZeroToken(bytes32 indexed class_, address token);

    constructor(uint256 chainId_, address core_) {
        chainId = chainId_;
        core = CoreLike(core_);
    }

    modifier approved(address usr) {
        require(
            either(msg.sender == usr, core.approvals(usr, msg.sender) == true)
        );
        _;
    }

    function deployToken(uint256 maturity) public returns (address) {
        bytes32 class_ = keccak256(abi.encodePacked(maturity));
        require(address(tokens[class_]) == address(0), "zero/token-exists");

        ERC20 token =
            new ERC20(
                chainId,
                string(abi.encodePacked(maturity.toString())),
                "ZERO",
                "1",
                18
            );
        tokens[class_] = address(token);

        emit NewZeroToken(class_, address(token));

        return address(token);
    }

    function exit(
        address src,
        address dst,
        bytes32 class_,
        uint256 zbal_
    ) external approved(src) {
        require(
            address(tokens[class_]) != address(0),
            "zero/token-not-deployed"
        );

        core.moveZero(src, address(this), class_, mulu(zbal_, RAY)); // to rad
        ERC20(tokens[class_]).mint(dst, zbal_);
    }

    function join(
        address src,
        address dst,
        bytes32 class_,
        uint256 zbal_
    ) external approved(src) {
        require(
            address(tokens[class_]) != address(0),
            "zero/token-not-deployed"
        );

        ERC20(tokens[class_]).burn(src, zbal_);
        core.moveZero(address(this), dst, class_, mulu(zbal_, RAY)); // to rad
    }
}

contract ClaimAdapterERC20 is DSMath {
    using Strings for uint256;

    CoreLike core;
    uint256 chainId;
    mapping(bytes32 => address) public tokens;

    event NewClaimToken(bytes32 indexed class_, address token);

    constructor(uint256 chainId_, address core_) {
        chainId = chainId_;
        core = CoreLike(core_);
    }

    modifier approved(address usr) {
        require(
            either(msg.sender == usr, core.approvals(usr, msg.sender) == true)
        );
        _;
    }

    function deployToken(uint256 issuance, uint256 maturity)
        public
        returns (address)
    {
        bytes32 class_ = keccak256(abi.encodePacked(issuance, maturity));
        require(address(tokens[class_]) == address(0), "claim/token-exists");

        ERC20 token =
            new ERC20(
                chainId,
                string(
                    abi.encodePacked(
                        issuance.toString(),
                        " ",
                        maturity.toString()
                    )
                ),
                "CLAIM",
                "1",
                18
            );
        tokens[class_] = address(token);

        emit NewClaimToken(class_, address(token));

        return address(token);
    }

    function deployToken(
        uint256 issuance,
        uint256 activation,
        uint256 maturity
    ) public returns (address) {
        bytes32 class_ =
            keccak256(abi.encodePacked(issuance, activation, maturity));
        require(
            address(tokens[class_]) == address(0),
            "futureclaim/token-exists"
        );

        ERC20 token =
            new ERC20(
                chainId,
                string(
                    abi.encodePacked(
                        issuance.toString(),
                        " ",
                        activation.toString(),
                        " ",
                        maturity.toString()
                    )
                ),
                "FCLAIM",
                "1",
                18
            );
        tokens[class_] = address(token);

        emit NewClaimToken(class_, address(token));

        return address(token);
    }

    function exit(
        address src,
        address dst,
        bytes32 class_,
        uint256 cbal_
    ) external approved(src) {
        require(
            address(tokens[class_]) != address(0),
            "claim/token-not-deployed"
        );

        core.moveClaim(src, address(this), class_, cbal_);
        ERC20(tokens[class_]).mint(dst, cbal_);
    }

    function join(
        address src,
        address dst,
        bytes32 class_,
        uint256 cbal_
    ) external approved(src) {
        require(
            address(tokens[class_]) != address(0),
            "claim/token-not-deployed"
        );

        ERC20(tokens[class_]).burn(src, cbal_);
        core.moveClaim(address(this), dst, class_, cbal_);
    }
}
