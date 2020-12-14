pragma solidity 0.5.12;

import "./erc20.sol";
import "./strings.sol";
import "../interfaces/CoreLike.sol";

contract ZeroAdapterERC20 {
    using Strings for uint;

    CoreLike core;
    uint256 chainId;
    mapping(bytes32 => address) public tokens;

    event NewZeroToken(bytes32 indexed class, address token);

    constructor(uint256 chainId_, address core_) public {
        chainId = chainId_;
        core = CoreLike(core_);
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
        require(either(msg.sender == usr, core.approvals(usr, msg.sender) == true));
        _;
    }

    function deployToken(uint maturity) public returns (address) {
        bytes32 class = keccak256(abi.encodePacked(maturity));
        require(address(tokens[class]) == address(0), "zero/token-exists");

        ERC20 token = new ERC20(chainId, string(abi.encodePacked(maturity.toString())), "ZERO", "1", 18);
        tokens[class] = address(token);

        emit NewZeroToken(class, address(token));

        return address(token);
    }

    function exit(address src, address dst, bytes32 class, uint zbal_) external approved(src) {
        require(address(tokens[class]) != address(0), "zero/token-not-deployed");

        core.moveZero(src, address(this), class, toRad(zbal_));
        ERC20(tokens[class]).mint(dst, zbal_);
    }

    function join(address src, address dst, bytes32 class, uint zbal_) external approved(src) {
        require(address(tokens[class]) != address(0), "zero/token-not-deployed");

        ERC20(tokens[class]).burn(src, zbal_);
        core.moveZero(address(this), dst, class, toRad(zbal_));
    }
}

contract ClaimAdapterERC20 {
    using Strings for uint;

    CoreLike core;
    uint256 chainId;
    mapping(bytes32 => address) public tokens;

    event NewClaimToken(bytes32 indexed class, address token);

    constructor(uint256 chainId_, address core_) public {
        chainId = chainId_;
        core = CoreLike(core_);
    }

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }

    modifier approved(address usr) {
        require(either(msg.sender == usr, core.approvals(usr, msg.sender) == true));
        _;
    }

    function deployToken(uint issuance, uint maturity) public returns (address) {
        bytes32 class = keccak256(abi.encodePacked(issuance, maturity));
        require(address(tokens[class]) == address(0), "claim/token-exists");

        ERC20 token = new ERC20(chainId, string(abi.encodePacked(issuance.toString(), " ", maturity.toString())), "CLAIM", "1", 18);
        tokens[class] = address(token);

        emit NewClaimToken(class, address(token));

        return address(token);
    }

    function deployToken(uint issuance, uint activation, uint maturity) public returns (address) {
        bytes32 class = keccak256(abi.encodePacked(issuance, activation, maturity));
        require(address(tokens[class]) == address(0), "futureclaim/token-exists");

        ERC20 token = new ERC20(chainId, string(abi.encodePacked(issuance.toString(), " ", activation.toString(), " ", maturity.toString())), "FCLAIM", "1", 18);
        tokens[class] = address(token);

        emit NewClaimToken(class, address(token));

        return address(token);
    }

    function exit(address src, address dst, bytes32 class, uint cbal_) external approved(src) {
        require(address(tokens[class]) != address(0), "claim/token-not-deployed");

        core.moveClaim(src, address(this), class, cbal_);
        ERC20(tokens[class]).mint(dst, cbal_);
    }

    function join(address src, address dst, bytes32 class, uint cbal_) external approved(src) {
        require(address(tokens[class]) != address(0), "claim/token-not-deployed");

        ERC20(tokens[class]).burn(src, cbal_);
        core.moveClaim(address(this), dst, class, cbal_);
    }
}