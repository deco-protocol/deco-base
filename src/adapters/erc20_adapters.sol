pragma solidity 0.5.12;

import "./erc20.sol";

contract SplitDSRLike {
    function approvals(address, address) external returns (bool);
    function moveZCD(address, address, bytes32, uint) external;
    function moveDCC(address, address, bytes32, uint) external;
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

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "mul-overflow");
    }

    function toRad(uint wad) internal pure returns (uint rad) {
        rad = mul(wad, 10 ** 27);
    }

    modifier approved(address usr) {
        require(either(msg.sender == usr, split.approvals(usr, msg.sender) == true));
        _;
    }

    // Deploy an ERC20 token contract for a ZCD class
    function deployToken(bytes32 class) public returns (address) {
        require(address(tokens[class]) == address(0), "zcd/token-exists");

        ERC20 token = new ERC20(chainId, string(abi.encodePacked(class)), "ZCD", "1", 18);
        tokens[class] = address(token);

        emit NewZCDToken(class, address(token));

        return address(token);
    }

    // Exit user's Split ZCD balance to its deployed ZCD ERC20 token
    // * User transfers ZCD balance to adapter
    // * User receives ZCD ERC20 balance
    // * Please note that `dai` in input is a wad number type with 18 decimals unlike Split ZCD
    function exit(address src, address dst, bytes32 class, uint dai) external approved(src) {
        require(address(tokens[class]) != address(0), "zcd/token-not-deployed");

        split.moveZCD(src, address(this), class, toRad(dai)); // Move ZCD from src address to adapter
        ERC20(tokens[class]).mint(dst, dai); // Mint ZCD ERC20 tokens to dst address
    }

    // Join user's ZCD ERC20 token balance to Split
    // * User transfers ZCD ERC20 balance to adapter
    // * User receives ZCD balance in Split
    // * Please note that `dai` in input is a wad number type with 18 decimals unlike Split ZCD
    function join(address src, address dst, bytes32 class, uint dai) external approved(src) {
        require(address(tokens[class]) != address(0), "zcd/token-not-deployed");

        ERC20(tokens[class]).burn(src, dai); // Burn ZCD ERC20 tokens from src address
        split.moveZCD(address(this), dst, class, toRad(dai)); // Move ZCD balance from adapter to dst address
    }
}

contract DCCAdapterERC20 {
    SplitDSRLike split;
    uint256 chainId;
    mapping(bytes32 => address) public tokens;

    event NewDCCToken(bytes32 indexed class, address token);

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

    // Deploy an ERC20 token contract for a DCC/FutureDCC class
    function deployToken(bytes32 class) public returns (address) {
        require(address(tokens[class]) == address(0), "dcc/token-exists");

        ERC20 token = new ERC20(chainId, string(abi.encodePacked(class)), "DCC", "1", 18);
        tokens[class] = address(token);

        emit NewDCCToken(class, address(token));

        return address(token);
    }

    // Exit user's Split DCC/FutureDCC balance to its deployed DCC ERC20 token
    // * User transfers DCC balance to adapter
    // * User receives DCC ERC20 balance
    function exit(address src, address dst, bytes32 class, uint pie) external approved(src) {
        require(address(tokens[class]) != address(0), "dcc/token-not-deployed");

        split.moveDCC(src, address(this), class, pie); // Move DCC from src address to adapter
        ERC20(tokens[class]).mint(dst, pie); // Mint DCC ERC20 tokens to dst address
    }

    // Join user's DCC/FutureDCC ERC20 token balance to Split
    // * User transfers DCC ERC20 balance to adapter
    // * User receives DCC balance in Split
    function join(address src, address dst, bytes32 class, uint pie) external approved(src) {
        require(address(tokens[class]) != address(0), "dcc/token-not-deployed");

        ERC20(tokens[class]).burn(src, pie); // Burn DCC ERC20 tokens from src address
        split.moveDCC(address(this), dst, class, pie); // Move DCC balance from adapter to dst address
    }
}