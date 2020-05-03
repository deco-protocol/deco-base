pragma solidity 0.5.12;

import "./nf_token.sol";

contract SplitDSRLike {
    function approvals(address, address) external returns (bool);
    function moveZCD(address, address, bytes32, uint) external;
    function moveDCP(address, address, bytes32, uint) external;
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

contract ZCDNFToken is NFToken, LibNote {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address guy) external note auth { wards[guy] = 1; }
    function deny(address guy) external note auth { wards[guy] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "not-authorized");
        _;
    }

    constructor() public {
        wards[msg.sender] = 1;
    }

    mapping(uint256 => bytes32) public class;
    mapping(uint256 => uint) public amount; // rad
    uint tokenId;

    event NewZCDToken(uint256 indexed tokenId_, bytes32 indexed class_, uint amount_);

    function mint(address usr, bytes32 class_, uint amount_) public auth {
        super._mint(usr, tokenId);
        class[tokenId] = class_;
        amount[tokenId] = amount_;
        emit NewZCDToken(tokenId, class_, amount_);

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
    ZCDNFToken zcdnft;

    constructor(address splitdsr_) public {
        split = SplitDSRLike(splitdsr_);
        zcdnft = new ZCDNFToken();
    }

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    modifier approved(address usr) {
        require(either(msg.sender == usr, split.approvals(usr, msg.sender) == true));
        _;
    }

    function join(address usr, bytes32 class, uint dai) external approved(usr) {
        split.moveZCD(usr, address(this), class, dai);
        zcdnft.mint(usr, class, dai);
    }

    function exit(address usr, uint tokenId_) external approved(usr) {
        require(usr == zcdnft.ownerOf(tokenId_));

        bytes32 class = zcdnft.class(tokenId_);
        uint dai = zcdnft.amount(tokenId_);

        zcdnft.burn(tokenId_);
        split.moveZCD(address(this), usr, class, dai);
    }
}

contract DCPNFToken is NFToken, LibNote {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address guy) external note auth { wards[guy] = 1; }
    function deny(address guy) external note auth { wards[guy] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "not-authorized");
        _;
    }

    constructor() public {
        wards[msg.sender] = 1;
    }

    mapping(uint256 => bytes32) public class;
    mapping(uint256 => uint) public amount; // wad
    uint tokenId;

    event NewDCPToken(uint256 indexed tokenId_, bytes32 indexed class_, uint amount_);

    function mint(address usr, bytes32 class_, uint amount_) public auth {
        super._mint(usr, tokenId);
        class[tokenId] = class_;
        amount[tokenId] = amount_;
        emit NewDCPToken(tokenId, class_, amount_);

        tokenId++;
    }

    function burn(uint tokenId_) public auth {
        super._burn(tokenId_);

        delete class[tokenId_];
        delete amount[tokenId_];
    }
}

contract DCPAdapterERC721 {
    SplitDSRLike split;
    DCPNFToken dcpnft;

    constructor(address splitdsr_) public {
        split = SplitDSRLike(splitdsr_);
        dcpnft = new DCPNFToken();
    }

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    modifier approved(address usr) {
        require(either(msg.sender == usr, split.approvals(usr, msg.sender) == true));
        _;
    }

    function join(address usr, bytes32 class, uint pie) external approved(usr) {
        split.moveDCP(usr, address(this), class, pie);
        dcpnft.mint(usr, class, pie);
    }

    function exit(address usr, uint tokenId_) external approved(usr) {
        require(usr == dcpnft.ownerOf(tokenId_));

        bytes32 class = dcpnft.class(tokenId_);
        uint pie = dcpnft.amount(tokenId_);

        dcpnft.burn(tokenId_);
        split.moveDCP(address(this), usr, class, pie);
    }
}