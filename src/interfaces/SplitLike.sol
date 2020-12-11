pragma solidity 0.5.12;

interface SplitLike {
    function vat() public returns (VatLike);
    function gov() public returns (address);

    function chi(address,uint) public returns (uint);

    function mintZCD(address yield, address usr, uint end, uint dai) external;
    function burnZCD(address yield, address usr, uint end, uint dai) external;
    function mintDCC(address yield, address usr, uint start, uint end, uint pie) external;
    function burnDCC(address yield, address usr, uint start, uint end, uint pie) external;
    function mintFutureDCC(address yield, address usr, uint start, uint slice, uint end, uint pie) external;
    function burnFutureDCC(address yield, address usr, uint start, uint slice, uint end, uint pie) external;
}