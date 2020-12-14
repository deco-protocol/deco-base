pragma solidity 0.5.12;

import "./nf_token.sol";
import "../interfaces/CoreLike.sol";

contract LibNote {
    event LogNote(
        bytes4   indexed  sig,
        address  indexed  usr,
        bytes32  indexed  arg1,
        bytes32  indexed  arg2,
        bytes             data
    ) anonymous;

    modifier note {
        _;
        assembly {
            // log an 'anonymous' event with a constant 6 words of calldata
            // and four indexed topics: selector, caller, arg1 and arg2
            let mark := msize                         // end of memory ensures zero
            mstore(0x40, add(mark, 288))              // update free memory pointer
            mstore(mark, 0x20)                        // bytes type data offset
            mstore(add(mark, 0x20), 224)              // bytes size (padded)
            calldatacopy(add(mark, 0x40), 0, 224)     // bytes payload
            log4(mark, 288,                           // calldata
                 shl(224, shr(224, calldataload(0))), // msg.sig
                 caller,                              // msg.sender
                 calldataload(4),                     // arg1
                 calldataload(36)                     // arg2
                )
        }
    }
}

// Base ERC721 Token contract for ZAdapterERC721 and CAdapterERC721
contract NFT is NFToken, LibNote {
    // --- Contract Auth ---
    mapping (address => uint) public wards;
    function rely(address guy) external note auth { wards[guy] = 1; }
    function deny(address guy) external note auth { wards[guy] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "not-authorized");
        _;
    }

    constructor() public {
        wards[msg.sender] = 1; // give adapter auth permissions
    }

    // NFT Metadata
    mapping(uint256 => bytes32) public class; // NFT token id => Class
    mapping(uint256 => uint) public amount; // NFT token id => Balance
    uint tokenId; // Total tokens minted

    event NewToken(uint256 indexed tokenId_, bytes32 indexed class_, uint amount_);

    function mint(address usr, bytes32 class_, uint amount_) public auth {
        super._mint(usr, tokenId);
        class[tokenId] = class_;
        amount[tokenId] = amount_;
        emit NewToken(tokenId, class_, amount_);

        tokenId++;
    }

    function burn(uint tokenId_) public auth {
        super._burn(tokenId_);

        delete class[tokenId_];
        delete amount[tokenId_];
    }
}

contract ZeroAdapterERC721 {
    CoreLike core;
    NFT zNft;

    constructor(address core_) public {
        core = CoreLike(core_);
        zNft = new NFT();
    }

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    modifier approved(address usr) {
        require(either(msg.sender == usr, core.approvals(usr, msg.sender) == true));
        _;
    }

    function exit(address src, address dst, bytes32 class, uint zbal_) external approved(src) {
        core.moveZero(src, address(this), class, zbal_);
        zNft.mint(dst, class, zbal_);
    }

    function join(address src, address dst, uint tokenId_) external approved(src) {
        require(src == zNft.ownerOf(tokenId_));

        bytes32 class = zNft.class(tokenId_);
        uint zbal_ = zNft.amount(tokenId_);

        zNft.burn(tokenId_);
        core.moveZero(address(this), dst, class, zbal_);
    }
}

contract ClaimAdapterERC721 {
    CoreLike core;
    NFT cNft;

    constructor(address core_) public {
        core = CoreLike(core_);
        cNft = new NFT();
    }

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    modifier approved(address usr) {
        require(either(msg.sender == usr, core.approvals(usr, msg.sender) == true));
        _;
    }

    function exit(address src, address dst, bytes32 class, uint cbal_) external approved(src) {
        core.moveClaim(src, address(this), class, cbal_);
        cNft.mint(dst, class, cbal_);
    }

    function join(address src, address dst, uint tokenId_) external approved(src) {
        require(src == cNft.ownerOf(tokenId_));

        bytes32 class = cNft.class(tokenId_);
        uint cbal_ = cNft.amount(tokenId_);

        cNft.burn(tokenId_);
        core.moveClaim(address(this), dst, class, cbal_);
    }
}