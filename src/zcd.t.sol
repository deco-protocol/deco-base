pragma solidity ^0.5.6;

import "ds-test/test.sol";

import "./dsr.sol";
import "./zcd.sol";

contract ZCDTest is DSTest {

    function setUp() public {
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
