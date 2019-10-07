pragma solidity ^0.5.10;

import "ds-test/test.sol";
import {Dai} from "dss/dai.sol";
import {DaiJoin} from "dss/join.sol";
import {Vat} from "dss/vat.sol";
import {Pot} from "dss/pot.sol";

import "./dcp.sol";

contract Hevm {
    function warp(uint256) public;
}

contract User {
    DCP dcp;
    ZCD zcd;

    constructor(address dcp_, address zcd_) public {
        dcp = DCP(dcp_);
        zcd = ZCD(zcd_);
    }

    function zcdMove(address src, address dst, uint256 end, uint256 wad) public {
        zcd.move(src, dst, end, wad);
    }

    function dcpMove(address src, address dst, uint256 start, uint256 end, uint256 wad) public {
        dcp.move(src, dst, start, end, wad);
    }
    
    function issue(address usr, uint256 end, uint256 wad) public {
        zcd.issue(usr, end, wad);
    }

    function redeem(address usr, uint256 end, uint256 wad) public {
        zcd.redeem(usr, end, wad);
    }

    function redeem(address usr, uint256 start, uint256 end, uint wad) public {
        zcd.redeem(usr, start, end, wad);
    }

    function claim(bytes32 usrTerms, uint256 time) public {
        dcp.claim(usrTerms, time);
    }

    function split(bytes32 usrTerms, uint256 mid, uint256 wad) public {
        dcp.split(usrTerms, mid, wad);
    }

    function merge(bytes32 usrTerms1, bytes32 usrTerms2, uint256 wad) public {
        dcp.merge(usrTerms1, usrTerms2, wad);
    }
}

contract ZCDTest is DSTest {
    Hevm hevm;

    Dai dai;
    DaiJoin join;
    Vat vat;
    Pot pot;
    ZCD zcd;
    DCP dcp;

    function setUp() public {
        vat = new Vat();
        dai = new Dai(99);
        join = new DaiJoin(address(vat), address(dai));
        pot = new Pot(address(vat));

        zcd = new ZCD(address(dai), address(join), address(pot));
        dcp = zcd.dcp();
    }
}
