pragma solidity ^0.5.10;

import "./erc20.sol";

contract ZCDLike {
    function approvals(address, address) external returns (bool);
    function moveZCD(address, address, uint, uint) external;
    function moveDCP(address, address, uint, uint, uint) external;
}

contract ZCDAdapterERC20 {
    ZCDLike zcd;
    uint256 chainId;
    mapping(bytes32 => address) public tokens;

    constructor(uint256 chainId_, address zcd_) public {
        chainId = chainId_;
        zcd = ZCDLike(zcd_);
    }

    // --- Lib ---
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    modifier approved(address usr) {
        require(either(msg.sender == usr, zcd.approvals(usr, msg.sender) == true));
        _;
    }

    function deployToken(uint end) public {
        bytes32 class = keccak256(abi.encodePacked(end));

        ERC20 token = new ERC20(chainId, string(abi.encodePacked("ZCD ", class)), "ZCD", "1", 45);
        tokens[class] = address(token);
    }

    function join(address usr, uint end, uint rad) external approved(usr) {
        bytes32 class = keccak256(abi.encodePacked(end));

        ERC20(tokens[class]).mint(usr, rad);
        zcd.moveZCD(usr, address(this), end, rad);
    }

    function exit(address usr, uint end, uint rad) external approved(usr) {
        bytes32 class = keccak256(abi.encodePacked(end));

        ERC20(tokens[class]).burn(usr, rad);
        zcd.moveZCD(address(this), usr, end, rad);
    }
}

contract DCPAdapterERC20 {
    ZCDLike zcd;
    uint256 chainId;
    mapping(bytes32 => address) public tokens;

    constructor(uint256 chainId_, address zcd_) public {
        chainId = chainId_;
        zcd = ZCDLike(zcd_);
    }

    // --- Lib ---
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    modifier approved(address usr) {
        require(either(msg.sender == usr, zcd.approvals(usr, msg.sender) == true));
        _;
    }

    function deployToken(uint start, uint end) public {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        ERC20 token = new ERC20(chainId, string(abi.encodePacked("DCP ", class)), "DCP", "1", 18);
        tokens[class] = address(token);
    }

    function join(address usr, uint start, uint end, uint wad) external approved(usr) {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        ERC20(tokens[class]).mint(usr, wad);
        zcd.moveDCP(usr, address(this), start, end, wad);
    }

    function exit(address usr, uint start, uint end, uint wad) external approved(usr) {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        ERC20(tokens[class]).burn(usr, wad);
        zcd.moveDCP(address(this), usr, start, end, wad);
    }
}