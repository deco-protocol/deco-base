pragma solidity ^0.5.10;
pragma experimental ABIEncoderV2;

import {ZCD} from "./zcd.sol";

contract TokenLike {
    function mint(address usr, uint wad) public;
    function burn(address usr, uint wad) public;
    function transferFrom(address src, address dst, uint wad) public returns (bool);
}

contract AdapterLike {
    function join(address usr, uint wad) public;
    function exit(address usr, uint wad) public;
}

contract PotLike {
    function chi() external returns (uint);
    function drip() public;
    function join(uint wad) public;
    function exit(uint wad) public;
}

contract DCP {
// --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external auth { wards[usr] = 1; }
    function deny(address usr) external auth { wards[usr] = 0; }
    modifier auth { require(wards[msg.sender] == 1); _; }

    mapping(address => mapping (address => uint)) public can;
    function hope(address usr) external { can[msg.sender][usr] = 1; }
    function nope(address usr) external { can[msg.sender][usr] = 0; }
    function wish(address bit, address usr) internal view returns (bool) {
        return either(bit == usr, can[bit][usr] == 1);
    }

    function either(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := or(x, y)}
    }
    function both(bool x, bool y) internal pure returns (bool z) {
        assembly{ z := and(x, y)}
    }

    // --- Math ---
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    // Contract addresses
    TokenLike public dai;
    AdapterLike public adapter;
    PotLike public pot;
    ZCD public zcd;

    constructor(address dai_, address adapter_, address pot_, address zcd_) public {
        wards[msg.sender] = 1;

        dai = TokenLike(dai_);
        adapter = AdapterLike(adapter_);
        pot = PotLike(pot_);
        zcd = ZCD(zcd_);
    }

    // Terms of a DCP bond  
    struct Terms {
        address owner; // bond owner
        uint256 start; // can claim DSR after start time
        uint256 end; // can claim DSR before end time
    }

    // save value of chi at a particular time to process claims later
    mapping (uint256 => uint256) public chiSnapshot;

    mapping (bytes32 => Terms) public terms;
    mapping (bytes32 => uint256) public balanceOf;
    mapping (bytes32 => uint256) public chiPaid; // track paid out DSR through claim

    event Move(address src, address dst, uint start, uint256 end, uint256 wad);

    // Transfer an bond amount between two users
    function move( 
        address src, 
        address dst, 
        uint256 start, 
        uint256 end, 
        uint256 wad
    ) 
        external 
        returns (bool)
    {
        require(wish(src, msg.sender));

        bytes32 srcTerms = keccak256(abi.encodePacked(src, start, end));
        bytes32 dstTerms = keccak256(abi.encodePacked(dst, start, end));

        require(balanceOf[srcTerms] >= wad, "dcp/insufficient-balance");

        claim(srcTerms);
        claim(dstTerms);

        balanceOf[srcTerms] = sub(balanceOf[srcTerms], wad);
        balanceOf[dstTerms] = add(balanceOf[dstTerms], wad);

        terms[dstTerms].owner = dst;
        terms[dstTerms].start = start;
        terms[dstTerms].end = end;

        emit Move(src, dst, start, end, wad);
        return true;
    }

    function mint(address usr, uint256 start, uint256 end, uint256 wad) public auth {
        bytes32 usrTerms = keccak256(abi.encodePacked(usr, start, end));

        terms[usrTerms].owner = usr;
        terms[usrTerms].start = start;
        terms[usrTerms].end = end;

        balanceOf[usrTerms] = add(balanceOf[usrTerms], wad);
        emit Move(address(0), usr, start, end, wad);
    }

    function burn(address usr, uint256 start, uint256 end, uint256 wad) public auth {
        bytes32 usrTerms = keccak256(abi.encodePacked(usr, start, end));

        require(balanceOf[usrTerms] >= wad, "dcp/insufficient-balance");

        balanceOf[usrTerms] = sub(balanceOf[usrTerms], wad);
        emit Move(usr, address(0), start, end, wad);
    }

    // snapshot chi to process future claim payments
    function snapshot() public {
        pot.drip();
        uint chi_ = pot.chi();
        chiSnapshot[now] = chi_;
    }

    // activate a DCP bond to claim DSR if it wasn't during issuance
    function activate(bytes32 usrTerms, uint256 time) public {
        uint256 start = terms[usrTerms].start;
        uint256 end = terms[usrTerms].end;

        require(start <= time && time <= end);
        require(chiPaid[usrTerms] == 0);

        chiPaid[usrTerms] = chiSnapshot[time];
    }

    function activate(bytes32 usrTerms) public {
        snapshot();
        activate(usrTerms, now);
    }

    // claim coupon payments
    function claim(bytes32 usrTerms, uint256 time) public {
        address usr = terms[usrTerms].owner;
        uint256 start = terms[usrTerms].start;
        uint256 end = terms[usrTerms].end;

        require(start <= time && time <= end);
        require(chiPaid[usrTerms] != 0);

        uint chi_ = chiSnapshot[time];
        require(chi_ > chiPaid[usrTerms]);

        if (!(chiPaid[usrTerms] == 0 || chiPaid[usrTerms] == 0)) {
            uint daiBalance = mul(chiPaid[usrTerms], sub(chi_, chiPaid[usrTerms]));

            pot.exit(daiBalance / chi_);
            adapter.exit(usr, daiBalance);
            require(dai.transferFrom(address(zcd), usr, daiBalance));
        }

        chiPaid[usrTerms] = chi_;
    }

    // claim coupon payments now
    function claim(bytes32 usrTerms) public {
        snapshot();
        claim(usrTerms, now);
    }

    // split one DCP bond into two
    function split(bytes32 usrTerms, uint256 mid, uint256 wad) public {
        address usr = terms[usrTerms].owner;
        uint256 start = terms[usrTerms].start;
        uint256 end = terms[usrTerms].end;

        require(wish(usr, msg.sender));

        claim(usrTerms);

        require(start > mid && mid > end);

        burn(usr, start, end, wad);

        mint(usr, start, mid, wad);
        mint(usr, mid+1, end, wad);
    }

    // merge two DCP bonds into one
    function merge(bytes32 usrTerms1, bytes32 usrTerms2, uint256 wad) public {
        address usr1 = terms[usrTerms1].owner;
        uint256 start1 = terms[usrTerms1].start;
        uint256 end1 = terms[usrTerms1].end;

        address usr2 = terms[usrTerms2].owner;
        uint256 start2 = terms[usrTerms2].start;
        uint256 end2 = terms[usrTerms2].end;

        require(wish(usr1, msg.sender));
        require(wish(usr2, msg.sender));

        require(end1+1 == start2);

        claim(usrTerms1);
        claim(usrTerms2);

        burn(usr1, start1, end1, wad);
        burn(usr2, start2, end2, wad);

        mint(usr1, start1, end2, wad);
    }
}