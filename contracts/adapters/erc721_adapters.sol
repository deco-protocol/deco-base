/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.7.6;

import "../lib/deed.sol";
import "../interfaces/CoreLike.sol";

contract ZeroAdapterERC721 is DSDeed {
    CoreLike public core;

    // NFT Metadata
    mapping(uint256 => bytes32) public class; // NFT token id => Class
    mapping(uint256 => uint) public amount; // NFT token id => Balance

    event NewToken(uint256 indexed tokenId_, bytes32 indexed class_, uint amount_);


    constructor(address core_) DSDeed("Zero NFT Adapter", "ZERO") {
        core = CoreLike(core_);
    }

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    modifier approved(address usr) {
        require(either(msg.sender == usr, core.approvals(usr, msg.sender) == true));
        _;
    }

    function exit(address src, address dst, bytes32 class_, uint zbal_) external approved(src) {
        core.moveZero(src, address(this), class_, zbal_);
        
        uint256 tokenId = super.mint(dst);

        class[tokenId] = class_;
        amount[tokenId] = zbal_;
        emit NewToken(tokenId, class_, zbal_);
    }

    function join(address src, address dst, uint tokenId_) external approved(src) {
        require(src == this.ownerOf(tokenId_));

        bytes32 class_ = class[tokenId_];
        uint zbal_ = amount[tokenId_];

        super._burn(tokenId_);

        delete class[tokenId_];
        delete amount[tokenId_];

        core.moveZero(address(this), dst, class_, zbal_);
    }
}

contract ClaimAdapterERC721 is DSDeed {
    CoreLike public core;

    // NFT Metadata
    mapping(uint256 => bytes32) public class; // NFT token id => Class
    mapping(uint256 => uint) public amount; // NFT token id => Balance

    event NewToken(uint256 indexed tokenId_, bytes32 indexed class_, uint amount_);


    constructor(address core_) DSDeed("Claim NFT Adapter", "CLAIM") {
        core = CoreLike(core_);
    }

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    modifier approved(address usr) {
        require(either(msg.sender == usr, core.approvals(usr, msg.sender) == true));
        _;
    }

    function exit(address src, address dst, bytes32 class_, uint cbal_) external approved(src) {
        core.moveClaim(src, address(this), class_, cbal_);
        
        uint256 tokenId = super.mint(dst);
        
        class[tokenId] = class_;
        amount[tokenId] = cbal_;
        emit NewToken(tokenId, class_, cbal_);
    }

    function join(address src, address dst, uint tokenId_) external approved(src) {
        require(src == this.ownerOf(tokenId_));

        bytes32 class_ = class[tokenId_];
        uint cbal_ = amount[tokenId_];

        super._burn(tokenId_);

        delete class[tokenId_];
        delete amount[tokenId_];        
        
        core.moveClaim(address(this), dst, class_, cbal_);
    }
}