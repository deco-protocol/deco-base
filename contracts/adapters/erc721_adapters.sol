/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.7.6;

import "../lib/deed.sol";
import "../interfaces/CoreLike.sol";

contract ZeroAdapterERC721 is DSDeed {
    CoreLike public core;

    // NFT Metadata
    mapping(uint256 => bytes32) public class; // NFT token id => Class
    mapping(uint256 => uint256) public amount; // NFT token id => Balance

    event NewToken(
        uint256 indexed tokenId_,
        bytes32 indexed class_,
        uint256 amount_
    );

    constructor(address core_) DSDeed("ZERO-Y", "ZERO-Y") {
        core = CoreLike(core_);
    }

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly {
            z := or(x, y)
        }
    }

    modifier approved(address usr) {
        require(
            either(msg.sender == usr, core.approvals(usr, msg.sender) == true), "user/not-authorized"
        );
        _;
    }

    /// Converts internal zero balance to an NFT
    /// @param src Internal zero balance owner
    /// @param dst NFT receiver
    /// @param class_ Zero class
    /// @param zbal_ Zero balance to convert
    function exit(
        address src,
        address dst,
        bytes32 class_,
        uint256 zbal_
    ) external approved(src) {
        core.moveZero(src, address(this), class_, zbal_);

        uint256 tokenId = _mint(dst, "");

        // set NFT metadata
        class[tokenId] = class_;
        amount[tokenId] = zbal_;

        emit NewToken(tokenId, class_, zbal_);
    }

    /// Converts NFT back to internal zero balance
    /// @param src ERC20 token balance owner
    /// @param dst Internal zero balance receiver
    /// @param tokenId_ NFT token id
    /// @dev Adapter contract will release the internal balance it holds to NFT owner
    function join(
        address src,
        address dst,
        uint256 tokenId_
    ) external approved(src) {
        require(src == this.ownerOf(tokenId_));

        bytes32 class_ = class[tokenId_];
        uint256 zbal_ = amount[tokenId_];

        _burn(tokenId_);

        delete class[tokenId_];
        delete amount[tokenId_];

        core.moveZero(address(this), dst, class_, zbal_);
    }
}

contract ClaimAdapterERC721 is DSDeed {
    CoreLike public core;

    // NFT Metadata
    mapping(uint256 => bytes32) public class; // NFT token id => Class
    mapping(uint256 => uint256) public amount; // NFT token id => Balance

    event NewToken(
        uint256 indexed tokenId_,
        bytes32 indexed class_,
        uint256 amount_
    );

    constructor(address core_) DSDeed("CLAIM-Y", "CLAIM-Y") {
        core = CoreLike(core_);
    }

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly {
            z := or(x, y)
        }
    }

    modifier approved(address usr) {
        require(
            either(msg.sender == usr, core.approvals(usr, msg.sender) == true), "user/not-authorized"
        );
        _;
    }

    /// Converts internal claim balance to an NFT
    /// @param src Internal claim balance owner
    /// @param dst NFT receiver
    /// @param class_ Claim class
    /// @param cbal_ Claim balance to convert
    function exit(
        address src,
        address dst,
        bytes32 class_,
        uint256 cbal_
    ) external approved(src) {
        core.moveClaim(src, address(this), class_, cbal_);

        uint256 tokenId = _mint(dst, "");

        class[tokenId] = class_;
        amount[tokenId] = cbal_;

        emit NewToken(tokenId, class_, cbal_);
    }

    /// Converts NFT back to internal claim balance
    /// @param src ERC20 token balance owner
    /// @param dst Internal claim balance receiver
    /// @param tokenId_ NFT token id
    /// @dev Adapter contract will release the internal balance it holds to NFT owner
    function join(
        address src,
        address dst,
        uint256 tokenId_
    ) external approved(src) {
        require(src == this.ownerOf(tokenId_));

        bytes32 class_ = class[tokenId_];
        uint256 cbal_ = amount[tokenId_];

        _burn(tokenId_);

        delete class[tokenId_];
        delete amount[tokenId_];

        core.moveClaim(address(this), dst, class_, cbal_);
    }
}
