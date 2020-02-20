pragma solidity ^0.5.10;

import "./erc20.sol";

contract SplitDSRLike {
    function approvals(address, address) external returns (bool);
    function moveZCD(address, address, bytes32, uint) external;
    function moveDCP(address, address, bytes32, uint) external;
}

contract ZCDAdapterERC20 {
    SplitDSRLike split;
    uint256 chainId;
    mapping(bytes32 => address) public tokens;

    constructor(uint256 chainId_, address splitdsr_) public {
        chainId = chainId_;
        split = SplitDSRLike(splitdsr_);
    }

    // --- Lib ---
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    modifier approved(address usr) {
        require(either(msg.sender == usr, split.approvals(usr, msg.sender) == true));
        _;
    }

    function deployToken(uint end) public {
        bytes32 class = keccak256(abi.encodePacked(end));

        ERC20 token = new ERC20(chainId, string(abi.encodePacked("ZCD ", class)), "ZCD", "1", 45);
        tokens[class] = address(token);
    }

    function join(address usr, uint end, uint dai) external approved(usr) {
        bytes32 class = keccak256(abi.encodePacked(end));

        ERC20(tokens[class]).mint(usr, dai);
        split.moveZCD(usr, address(this), class, dai);
    }

    function exit(address usr, uint end, uint dai) external approved(usr) {
        bytes32 class = keccak256(abi.encodePacked(end));

        ERC20(tokens[class]).burn(usr, dai);
        split.moveZCD(address(this), usr, class, dai);
    }
}

contract DCPAdapterERC20 {
    SplitDSRLike split;
    uint256 chainId;
    mapping(bytes32 => address) public tokens;

    constructor(uint256 chainId_, address splitdsr_) public {
        chainId = chainId_;
        split = SplitDSRLike(splitdsr_);
    }

    // --- Lib ---
    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    modifier approved(address usr) {
        require(either(msg.sender == usr, split.approvals(usr, msg.sender) == true));
        _;
    }

    function deployToken(uint start, uint end) public {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        ERC20 token = new ERC20(chainId, string(abi.encodePacked("DCP ", class)), "DCP", "1", 18);
        tokens[class] = address(token);
    }

    function join(address usr, uint start, uint end, uint pie) external approved(usr) {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        ERC20(tokens[class]).mint(usr, pie);
        split.moveDCP(usr, address(this), class, pie);
    }

    function exit(address usr, uint start, uint end, uint pie) external approved(usr) {
        bytes32 class = keccak256(abi.encodePacked(start, end));

        ERC20(tokens[class]).burn(usr, pie);
        split.moveDCP(address(this), usr, class, pie);
    }
}