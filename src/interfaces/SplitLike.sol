pragma solidity 0.5.12;

interface SplitLike {
    function vat() external returns (address);
    function gov() external returns (address);

    function chi(address,uint) external returns (uint);
    function lastSnapshot(address) external returns (uint);

    function mintZCD(address yield, address usr, uint end, uint dai) external;
    function burnZCD(address yield, address usr, uint end, uint dai) external;
    function mintDCC(address yield, address usr, uint start, uint end, uint pie) external;
    function burnDCC(address yield, address usr, uint start, uint end, uint pie) external;
    function mintFutureDCC(address yield, address usr, uint start, uint slice, uint end, uint pie) external;
    function burnFutureDCC(address yield, address usr, uint start, uint slice, uint end, uint pie) external;
}