pragma solidity ^0.5.10;

import "ds-test/test.sol";
import {Dai} from "dss/dai.sol";
import {DaiJoin} from "dss/join.sol";
import {Vat} from "dss/vat.sol";
import {Pot} from "dss/pot.sol";
import "../zcd.sol";

contract Hevm {
    function warp(uint256) public;
}

contract User {
    ZCD zcd;

    constructor(ZCD zcd_) public {
        zcd = zcd_;
    }
}

contract ZCDTest is DSTest {
    Hevm hevm;

    Vat vat;
    Pot pot;
    Dai dai;
    DaiJoin adapter;

    ZCD zcd;

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

        zcd = new ZCD(address(pot));

        vat.hope(address(pot));
        vat.hope(address(adapter));
        vat.hope(address(zcd));

        dai.approve(address(adapter), uint(-1));
        dai.approve(address(zcd), uint(-1));

        vat.suck(self, self, rad(200 ether));
        adapter.exit(address(this), 100 ether);

        pot.file("dsr", uint(RATE)); // file at DATE
        hevm.warp(day(1));
    }

    function test_issue_zcd_and_dcp() public {
        uint val = rdiv(10 ether, pot.drip());

        zcd.issue(self, day(2), val);

        bytes32 zcdClass = keccak256(abi.encodePacked(day(2)));
        bytes32 dcpClass = keccak256(abi.encodePacked(day(1), day(2)));

        assertEq(zcd.zcd(self, zcdClass), mul(val, pot.drip()));
        assertEq(zcd.dcp(self, dcpClass), val);
    }

    function test_withdraw_dai_before_expiry() public {
        uint val = rdiv(10 ether, pot.drip());
        
        zcd.issue(self, day(3), val);
        hevm.warp(day(2));
        
        bytes32 zcdClass = keccak256(abi.encodePacked(day(3)));
        bytes32 dcpClass1 = keccak256(abi.encodePacked(day(1), day(3)));
        bytes32 dcpClass2 = keccak256(abi.encodePacked(day(2), day(3)));

        zcd.claim(self, day(1), day(3), now);
        zcd.withdraw(self, day(3), zcd.dcp(self, dcpClass2));
        
        assertEq(wad(zcd.zcd(self, zcdClass)), 1 wei); // dcp balance 1 wei lower after claim due to rounding
        assertEq(zcd.dcp(self, dcpClass1), 0 ether);
        assertEq(zcd.dcp(self, dcpClass2), 0 ether);
        assertEq(wad(vat.dai(self)), wad(mul(val, pot.drip())) + 90 ether - 2 wei);
    }

    function test_redeem_zcd() public {
        uint val = rdiv(10 ether, pot.drip());

        zcd.issue(self, day(2), val);

        bytes32 zcdClass = keccak256(abi.encodePacked(day(2)));
        bytes32 dcpClass = keccak256(abi.encodePacked(day(1), day(2)));

        hevm.warp(day(4));
        zcd.redeem(self, day(2), zcd.zcd(self, zcdClass) / pot.drip());

        assertEq(wad(zcd.zcd(self, zcdClass)), 0);
        assertEq(zcd.dcp(self, dcpClass), val);
    }
}