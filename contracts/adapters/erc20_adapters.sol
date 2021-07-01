/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.7.6;

import "../lib/erc20.sol";
import "../lib/DSMath.sol";
import "../lib/strings.sol";
import "../interfaces/CoreLike.sol";

contract ZeroAdapterERC20 is DSMath {
    using Strings for uint256;

    CoreLike public core;
    uint256 public chainId;
    mapping(bytes32 => address) public tokens;

    event NewZeroToken(bytes32 indexed class_, address token);

    constructor(uint256 chainId_, address core_) {
        chainId = chainId_;
        core = CoreLike(core_);
    }

    modifier approved(address usr) {
        require(
            either(msg.sender == usr, core.approvals(usr, msg.sender) == true), "user/not-authorized"
        );
        _;
    }

    /// Deploys ERC20 token for a class
    /// @param maturity Maturity timestamp
    /// @return token Address of deployed token
    /// @dev Public function anyone can use to deploy an ERC20 token for a particular zero class
    function deployToken(uint256 maturity) public returns (address) {
        bytes32 class_ = keccak256(abi.encodePacked(maturity));
        require(address(tokens[class_]) == address(0), "zero/token-exists");

        ERC20 token =
            new ERC20(
                chainId,
                string(abi.encodePacked("ZERO-Y", " ", maturity.toString())),
                "ZERO-Y",
                "1",
                18
            );
        tokens[class_] = address(token);

        emit NewZeroToken(class_, address(token));

        return address(token);
    }

    /// Converts internal zero balance to its ERC20 token balance
    /// @param src Internal zero balance owner
    /// @param dst ERC20 token balance receiver
    /// @param class_ Zero class
    /// @param zbal_ Zero balance to convert
    /// @dev Adapters respect the internal approvals a user has set
    /// @dev Adapter contract will hold the internal balance while the token balance is in circulation
    /// @dev Balance on adapter contracts cannot be directly used for any deco functions
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

        core.moveZero(src, address(this), class_, zbal_);
        ERC20(tokens[class_]).mint(dst, zbal_);
    }

    /// Converts ERC20 token balance back to internal zero balance
    /// @param src ERC20 token balance owner
    /// @param dst Internal zero balance receiver
    /// @param class_ Zero class
    /// @param zbal_ Zero balance to convert
    /// @dev Adapter contract will release the internal balance it holds to token owner
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
        core.moveZero(address(this), dst, class_, zbal_);
    }
}

contract ClaimAdapterERC20 is DSMath {
    using Strings for uint256;

    CoreLike public core;
    uint256 public chainId;
    mapping(bytes32 => address) public tokens;

    event NewClaimToken(bytes32 indexed class_, address token);

    constructor(uint256 chainId_, address core_) {
        chainId = chainId_;
        core = CoreLike(core_);
    }

    modifier approved(address usr) {
        require(
            either(msg.sender == usr, core.approvals(usr, msg.sender) == true), "user/not-authorized"
        );
        _;
    }

    /// Deploys ERC20 token for a class
    /// @param issuance Issuance timestamp
    /// @param maturity Maturity timestamp
    /// @return token Address of deployed token
    /// @dev Public function anyone can use to deploy an ERC20 token for a particular claim class
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
                        "CLAIM-Y", 
                        " ",
                        issuance.toString(),
                        " ",
                        maturity.toString()
                    )
                ),
                "CLAIM-Y",
                "1",
                18
            );
        tokens[class_] = address(token);

        emit NewClaimToken(class_, address(token));

        return address(token);
    }

    /// Converts internal claim balance to its ERC20 token balance
    /// @param src Internal claim balance owner
    /// @param dst ERC20 token balance receiver
    /// @param class_ Claim class
    /// @param cbal_ Claim balance to convert
    /// @dev Adapters respect the internal approvals a user has set
    /// @dev Adapter contract will hold the internal balance while the token balance is in circulation
    /// @dev Balance on adapter contracts cannot be directly used for any deco functions
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

    /// Converts ERC20 token balance back to internal claim balance
    /// @param src ERC20 token balance owner
    /// @param dst Internal claim balance receiver
    /// @param class_ Claim class
    /// @param cbal_ Claim balance to convert
    /// @dev Adapter contract will release the internal balance it holds to token owner
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
