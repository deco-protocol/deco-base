pragma solidity ^0.5.10;

import "ds-test/test.sol";
import {Dai} from "dss/dai.sol";
import {DaiJoin} from "dss/join.sol";
import {Vat} from "dss/vat.sol";
import {Pot} from "dss/pot.sol";
import "../split.sol";
import {ValueDSR} from "../value.sol";

contract Hevm {
    function warp(uint256) public;
}

contract User {
    SplitDSR split;
    ValueDSR value;

    constructor(SplitDSR split_, ValueDSR value_) public {
        split = split_;
        value = value_;
    }
}

contract SplitDSRTest is DSTest {
    Hevm hevm;

    Vat vat;
    Pot pot;
    Dai dai;
    DaiJoin adapter;

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
    }

    function test_issue_zcd_and_dcp() public {
        uint val = rdiv(10 ether, pot.drip());

        split.issue(self, day(2), val);

        bytes32 zcdClass = keccak256(abi.encodePacked(day(2)));
        bytes32 dcpClass = keccak256(abi.encodePacked(day(1), day(2)));

        assertEq(split.zcd(self, zcdClass), mul(val, pot.drip()));
        assertEq(split.dcp(self, dcpClass), val);
    }

    function test_withdraw_dai_before_expiry() public {
        uint val = rdiv(10 ether, pot.drip());
        
        split.issue(self, day(3), val);
        hevm.warp(day(2));
        
        bytes32 zcdClass = keccak256(abi.encodePacked(day(3)));
        bytes32 dcpClass1 = keccak256(abi.encodePacked(day(1), day(3)));
        bytes32 dcpClass2 = keccak256(abi.encodePacked(day(2), day(3)));

        split.claim(self, day(1), day(3), now);
        split.withdraw(self, day(3), split.dcp(self, dcpClass2));
        
        assertEq(wad(split.zcd(self, zcdClass)), 1 wei); // dcp balance 1 wei lower after claim due to rounding
        assertEq(split.dcp(self, dcpClass1), 0 ether);
        assertEq(split.dcp(self, dcpClass2), 0 ether);
        assertEq(wad(vat.dai(self)), wad(mul(val, pot.drip())) + 90 ether - 2 wei);
    }

    function test_redeem_zcd() public {
        uint val = rdiv(10 ether, pot.drip());

        split.issue(self, day(2), val);

        bytes32 zcdClass = keccak256(abi.encodePacked(day(2)));
        bytes32 dcpClass = keccak256(abi.encodePacked(day(1), day(2)));

        hevm.warp(day(4));
        split.redeem(self, day(2), split.zcd(self, zcdClass) / pot.drip());

        assertEq(wad(split.zcd(self, zcdClass)), 0);
        assertEq(split.dcp(self, dcpClass), val);
    }

    function test_slice_convert_claim_dcp() public {
        uint chi_1 = pot.drip();
        uint val = rdiv(10 ether, chi_1);

        split.issue(self, day(20), val);

        bytes32 class1 = keccak256(abi.encodePacked(day(1), day(20)));
        assertEq(split.dcp(self, class1), val);

        split.slice(self, day(1), day(5), day(20), val);
        bytes32 class2 = keccak256(abi.encodePacked(day(1), day(5)));
        bytes32 class3 = keccak256(abi.encodePacked(day(1), day(5), day(20)));
        assertEq(split.dcp(self, class2), val);
        assertEq(split.dcp(self, class3), val);

        hevm.warp(day(5));
        split.claim(self, day(1), day(5), now);
        assertEq(split.dcp(self, class1), 0);

        hevm.warp(day(6));
        uint chi_6 = split.snapshot();
        uint val_6 = (mul(val, chi_1) / chi_6);
        split.convert(self, day(1), day(5), day(6), day(20));
        bytes32 class4 = keccak256(abi.encodePacked(day(6), day(20)));
        assertEq(split.dcp(self, class4), val_6);

        hevm.warp(day(7));
        uint chi_7 = split.snapshot();
        uint val_7 = (mul(val_6, chi_6) / chi_7);
        split.claim(self, day(6), day(20), now);
        bytes32 class5 = keccak256(abi.encodePacked(day(7), day(20)));
        assertEq(split.dcp(self, class4), 0);
        assertEq(split.dcp(self, class5), val_7);
    }

    function test_slice_claim_merge_dcp() public {
        uint chi_1 = pot.drip();
        uint val_1 = rdiv(10 ether, chi_1);

        split.issue(self, day(20), val_1);

        bytes32 class1 = keccak256(abi.encodePacked(day(1), day(20)));
        assertEq(split.dcp(self, class1), val_1);

        split.slice(self, day(1), day(5), day(20), val_1);
        bytes32 class2 = keccak256(abi.encodePacked(day(1), day(5)));
        bytes32 class3 = keccak256(abi.encodePacked(day(1), day(5), day(20)));
        assertEq(split.dcp(self, class2), val_1);
        assertEq(split.dcp(self, class3), val_1);

        hevm.warp(day(2));
        uint chi_2 = split.snapshot();
        uint val_2 = (mul(val_1, chi_1) / chi_2);
        split.claim(self, day(1), day(5), now);
        bytes32 class4 = keccak256(abi.encodePacked(day(2), day(5)));
        assertEq(split.dcp(self, class1), 0);
        assertEq(split.dcp(self, class4), val_2 - 1 wei);

        split.merge(self, day(1), day(2), day(5), day(20), split.dcp(self, class4));
        bytes32 class5 = keccak256(abi.encodePacked(day(2), day(20)));
        assertEq(split.dcp(self, class3), 2 wei);
        assertEq(split.dcp(self, class4), 0);
        assertEq(split.dcp(self, class5), val_2 - 1 wei);
    }

    function test_slice_merge_future_dcp() public {
        uint chi_1 = pot.drip();
        uint val = rdiv(10 ether, chi_1);

        split.issue(self, day(20), val);
        bytes32 class1 = keccak256(abi.encodePacked(day(1), day(20)));
        
        split.slice(self, day(1), day(5), day(20), val);
        bytes32 class2 = keccak256(abi.encodePacked(day(1), day(5)));
        bytes32 class3 = keccak256(abi.encodePacked(day(1), day(5), day(20)));
        
        split.sliceFuture(self, day(1), day(5), day(11), day(20), val);
        bytes32 class4 = keccak256(abi.encodePacked(day(1), day(5), day(11)));
        bytes32 class5 = keccak256(abi.encodePacked(day(1), day(11), day(20)));
        assertEq(split.dcp(self, class1), 0);
        assertEq(split.dcp(self, class2), val);
        assertEq(split.dcp(self, class3), 0);
        assertEq(split.dcp(self, class4), val);
        assertEq(split.dcp(self, class5), val);

        split.mergeFuture(self, day(1), day(5), day(11), day(20), val);
        assertEq(split.dcp(self, class3), val);
        assertEq(split.dcp(self, class4), 0);
        assertEq(split.dcp(self, class5), 0);
    }
}