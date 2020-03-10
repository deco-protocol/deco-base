pragma solidity ^0.5.10;

import "ds-test/test.sol";
import {Dai} from "dss/dai.sol";
import {DaiJoin} from "dss/join.sol";
import {Vat} from "dss/vat.sol";
import {Pot} from "dss/pot.sol";
import "../split.sol";
import {ValueDSR} from "../value.sol";
import "../adapters/erc20.sol";
import "../adapters/erc20_adapters.sol";

contract Hevm {
    function warp(uint256) public;
}

contract User {
    SplitDSR split;
    ValueDSR value;
    ZCDAdapterERC20 zcdToken;
    DCPAdapterERC20 dcpToken;

    constructor(SplitDSR split_, ValueDSR value_) public {
        split = split_;
        value = value_;
    }
}

contract ERC20AdapterTest is DSTest {
    Hevm hevm;

    Vat vat;
    Pot pot;
    Dai dai;
    DaiJoin adapter;
    ZCDAdapterERC20 zcdAdapter;
    DCPAdapterERC20 dcpAdapter;

    SplitDSR split;
    ValueDSR value;

    address vow;
    address self;

    uint constant DATE = 1574035200;
    uint constant RATE = 1000000564701133626865910626; // 5% / day

    uint constant RAY = 10 ** 27;
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function rad(uint wad_) internal pure returns (uint) {
        return wad_ * RAY;
    }
    function wad(uint rad_) internal pure returns (uint) {
        return rad_ / RAY;
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, y) / RAY;
    }
    function rdiv(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, RAY) / y;
    }
    function rdivup(uint x, uint y) internal pure returns (uint z) {
        // always rounds up
        z = add(mul(x, RAY), sub(y, 1)) / y;
    }

    function day(uint x) internal returns (uint day_) {
        day_ = add(DATE, x);
    }

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(DATE);

        vat = new Vat();
        pot = new Pot(address(vat));
        dai = new Dai(99);
        adapter = new DaiJoin(address(vat), address(dai));
        self = address(this);
        vow = address(bytes20("vow"));

        vat.rely(address(pot));
        dai.rely(address(adapter));
        pot.file("vow", vow);

        value = new ValueDSR();
        split = new SplitDSR(address(pot), address(value));
        value.init(address(split));

        vat.hope(address(pot));
        vat.hope(address(adapter));
        vat.hope(address(split));

        dai.approve(address(adapter), uint(-1));
        dai.approve(address(split), uint(-1));

        vat.suck(self, self, rad(200 ether));
        adapter.exit(address(this), 100 ether);

        pot.file("dsr", uint(RATE)); // file at DATE
        hevm.warp(day(1));

        uint val = rdiv(10 ether, pot.drip());
        split.issue(self, day(10), val);

        zcdAdapter = new ZCDAdapterERC20(99, address(split));
        dcpAdapter = new DCPAdapterERC20(99, address(split));
    }

    function test_deploy_zcdtoken() public {
        bytes32 class = keccak256(abi.encodePacked(day(10)));

        address token = zcdAdapter.deployToken(day(10));
        assertEq(token, zcdAdapter.tokens(class));
    }

    function test_erc20_zcd_join() public {
        bytes32 class = keccak256(abi.encodePacked(day(10)));
        address token = zcdAdapter.deployToken(day(10));

        uint balance = split.zcd(self, class);
        split.approve(address(zcdAdapter), true);

        zcdAdapter.join(self, day(10), balance);

        assertEq(split.zcd(self,class), 0);
        assertEq(ERC20(token).balanceOf(self), balance);
    }

    function testFail_erc20_zcd_join() public {
        bytes32 class = keccak256(abi.encodePacked(day(10)));
        assertEq(zcdAdapter.tokens(class), address(0));

        uint balance = split.zcd(self, class);
        split.approve(address(zcdAdapter), true);

        zcdAdapter.join(self, day(10), balance);
    }

    function test_erc20_zcd_exit() public {
        bytes32 class = keccak256(abi.encodePacked(day(10)));
        address token = zcdAdapter.deployToken(day(10));
        uint balance = split.zcd(self, class);
        split.approve(address(zcdAdapter), true);
        zcdAdapter.join(self, day(10), balance);

        ERC20(token).approve(address(zcdAdapter), uint(-1));
        zcdAdapter.exit(self, day(10), rad(1 ether));

        assertEq(split.zcd(self,class), rad(1 ether));
        assertEq(ERC20(token).balanceOf(self), balance - rad(1 ether));
    }

    function test_deploy_dcptoken() public {
        bytes32 class = keccak256(abi.encodePacked(day(1), day(10)));

        address token = dcpAdapter.deployToken(day(1), day(10));
        assertEq(token, dcpAdapter.tokens(class));
    }

    function test_erc20_dcp_join() public {
        bytes32 class = keccak256(abi.encodePacked(day(1), day(10)));
        address token = dcpAdapter.deployToken(day(1), day(10));

        uint balance = split.dcp(self, class);
        split.approve(address(dcpAdapter), true);

        dcpAdapter.join(self, day(1), day(10), balance);

        assertEq(split.dcp(self,class), 0);
        assertEq(ERC20(token).balanceOf(self), balance);
    }

    function testFail_erc20_dcp_join() public {
        bytes32 class = keccak256(abi.encodePacked(day(1), day(10)));
        assertEq(dcpAdapter.tokens(class), address(0));

        uint balance = split.dcp(self, class);
        split.approve(address(dcpAdapter), true);

        dcpAdapter.join(self, day(1), day(10), balance);
    }

    function test_erc20_dcp_exit() public {
        bytes32 class = keccak256(abi.encodePacked(day(1), day(10)));
        address token = dcpAdapter.deployToken(day(1), day(10));
        uint balance = split.dcp(self, class);
        split.approve(address(dcpAdapter), true);
        dcpAdapter.join(self, day(1), day(10), balance);

        ERC20(token).approve(address(dcpAdapter), uint(-1));
        dcpAdapter.exit(self, day(1), day(10), 1 ether);

        assertEq(split.dcp(self,class), 1 ether);
        assertEq(ERC20(token).balanceOf(self), balance - 1 ether);
    }
}