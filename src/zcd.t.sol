pragma solidity ^0.5.6;

import "ds-test/test.sol";
import {Dai} from "dss/dai.sol";
import {DaiJoin} from "dss/join.sol";
import {Vat} from "dss/vat.sol";
import {Pot} from "dss/pot.sol";

import "./dcp.sol";
import "./zcd.sol";

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
 
    function split(uint wad) public {
        dcp.split(wad);
    }

    function merge(uint wad) public {
        dcp.merge(wad);
    }

    function claim(address usr) public {
        dcp.claim(usr);
    }

    function transferDCP(address src, address dst, uint wad) public {
        dcp.transferFrom(src, dst, wad);
    }

    function transferZCD(address src, address dst, uint wad) public {
        zcd.transferFrom(src, dst, wad);
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
        dcp = new DCP(address(dai), address(join), address(pot),99);
        zcd = dcp.zcd();

        // setup auth among contracts
    }

    function test_split_dai() public {
        // take dai, split to dcp and zcd
        // assertEq(100 ether, 100 ether);
    }


    function test_merge_dai() public {
        // take dcp, zcd, merge to dai
        //assertEq(100 ether, 100 ether);
    }

    function test_claim_dai() public {
        // claim dai after y duration in pot, check dai balance increases by x
        //assertEq(100 ether, 100 ether);
    }

    function test_transfer_dai() public {
        // two addresses with existing dcp balances, transfer dcp from one to another
        // check if dai balance has increased on both
        //assertEq(100 ether, 100 ether);
    }

}
