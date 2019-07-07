pragma solidity ^0.5.6;

import "ds-test/test.sol";

import "./Zcd.sol";

contract ZcdTest is DSTest {
    Zcd zcd;

    function setUp() public {
        zcd = new Zcd();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
