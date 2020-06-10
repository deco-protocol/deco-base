pragma solidity 0.5.12;

import "./nf_token.sol";

contract SplitDSRLike {
    function approvals(address, address) external returns (bool);
    function moveZCD(address, address, bytes32, uint) external;
    function moveDCC(address, address, bytes32, uint) external;
}

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

// Base ERC721 Token contract for ZCDAdapterERC721 and DCCAdapterERC721
contract SplitNFT is NFToken, LibNote {
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

contract ZCDAdapterERC721 {
    SplitDSRLike split;
    SplitNFT zcdnft;

    constructor(address splitdsr_) public {
        split = SplitDSRLike(splitdsr_);
        zcdnft = new SplitNFT();
    }

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    modifier approved(address usr) {
        require(either(msg.sender == usr, split.approvals(usr, msg.sender) == true));
        _;
    }

    function exit(address src, address dst, bytes32 class, uint dai) external approved(src) {
        split.moveZCD(src, address(this), class, dai); // Move ZCD from src address to adapter
        zcdnft.mint(dst, class, dai); // Mint ZCD ERC721 token to dst address
    }

    function join(address src, address dst, uint tokenId_) external approved(src) {
        require(src == zcdnft.ownerOf(tokenId_));

        bytes32 class = zcdnft.class(tokenId_);
        uint dai = zcdnft.amount(tokenId_);

        zcdnft.burn(tokenId_); // Burn ZCD ERC721 from src address
        split.moveZCD(address(this), dst, class, dai); // Move ZCD balance from adapter to dst address
    }
}

contract DCCAdapterERC721 {
    SplitDSRLike split;
    SplitNFT dccnft;

    constructor(address splitdsr_) public {
        split = SplitDSRLike(splitdsr_);
        dccnft = new SplitNFT();
    }

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    modifier approved(address usr) {
        require(either(msg.sender == usr, split.approvals(usr, msg.sender) == true));
        _;
    }

    function exit(address src, address dst, bytes32 class, uint pie) external approved(src) {
        split.moveDCC(src, address(this), class, pie); // Move DCC from src address to adapter
        dccnft.mint(dst, class, pie);  // Mint DCC ERC721 token to dst address
    }

    function join(address src, address dst, uint tokenId_) external approved(src) {
        require(src == dccnft.ownerOf(tokenId_));

        bytes32 class = dccnft.class(tokenId_);
        uint pie = dccnft.amount(tokenId_);

        dccnft.burn(tokenId_); // Burn DCC ERC721 from src address
        split.moveDCC(address(this), dst, class, pie); // Move DCC balance from adapter to dst address
    }
}