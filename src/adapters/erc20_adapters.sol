pragma solidity 0.5.12;

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

    event NewZCDToken(bytes32 indexed class, address token);

    constructor(uint256 chainId_, address splitdsr_) public {
        chainId = chainId_;
        split = SplitDSRLike(splitdsr_);
    }

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    modifier approved(address usr) {
        require(either(msg.sender == usr, split.approvals(usr, msg.sender) == true));
        _;
    }

    // Deploy an ERC20 token contract for a ZCD class
    function deployToken(bytes32 class) public returns (address) {
        require(address(tokens[class]) == address(0), "zcd/token-exists");

        ERC20 token = new ERC20(chainId, string(abi.encodePacked("ZCD ", class)), "ZCD", "1", 45);
        tokens[class] = address(token);

        emit NewZCDToken(class, address(token));

        return address(token);
    }

    function join(address usr, bytes32 class, uint dai) external approved(usr) {
        require(address(tokens[class]) != address(0), "zcd/token-not-deployed");

        split.moveZCD(usr, address(this), class, dai);
        ERC20(tokens[class]).mint(usr, dai);
    }

    function exit(address usr, bytes32 class, uint dai) external approved(usr) {
        require(address(tokens[class]) != address(0), "zcd/token-not-deployed");

        ERC20(tokens[class]).burn(usr, dai);
        split.moveZCD(address(this), usr, class, dai);
    }
}

contract DCPAdapterERC20 {
    SplitDSRLike split;
    uint256 chainId;
    mapping(bytes32 => address) public tokens;

    event NewDCPToken(bytes32 indexed class, address token);

    constructor(uint256 chainId_, address splitdsr_) public {
        chainId = chainId_;
        split = SplitDSRLike(splitdsr_);
    }

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    modifier approved(address usr) {
        require(either(msg.sender == usr, split.approvals(usr, msg.sender) == true));
        _;
    }

    // Deploy an ERC20 token contract for a DCP/FutureDCP class
    function deployToken(bytes32 class) public returns (address) {
        require(address(tokens[class]) == address(0), "dcp/token-exists");

        ERC20 token = new ERC20(chainId, string(abi.encodePacked("DCP ", class)), "DCP", "1", 18);
        tokens[class] = address(token);

        emit NewDCPToken(class, address(token));

        return address(token);
    }

    function join(address usr, bytes32 class, uint pie) external approved(usr) {
        require(address(tokens[class]) != address(0), "dcp/token-not-deployed");

        split.moveDCP(usr, address(this), class, pie);
        ERC20(tokens[class]).mint(usr, pie);
    }

    function exit(address usr, bytes32 class, uint pie) external approved(usr) {
        require(address(tokens[class]) != address(0), "dcp/token-not-deployed");

        ERC20(tokens[class]).burn(usr, pie);
        split.moveDCP(address(this), usr, class, pie);
    }
}