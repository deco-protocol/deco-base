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

contract ZCDTest is DSTest {
    
}
