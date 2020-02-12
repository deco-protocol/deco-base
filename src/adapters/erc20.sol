// Copyright (C) 2017, 2018, 2019 dbrock, rain, mrchico

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.5.10;

contract LibNote {
    event LogNote(
        bytes4   indexed  sig,
        address  indexed  usr,
        bytes32  indexed  arg1,
        bytes32  indexed  arg2,
        bytes             data
    ) anonymous;

    modifier note {
        _;
        assembly {
            // log an 'anonymous' event with a constant 6 words of calldata
            // and four indexed topics: selector, caller, arg1 and arg2
            let mark := msize                         // end of memory ensures zero
            mstore(0x40, add(mark, 288))              // update free memory pointer
            mstore(mark, 0x20)                        // bytes type data offset
            mstore(add(mark, 0x20), 224)              // bytes size (padded)
            calldatacopy(add(mark, 0x40), 0, 224)     // bytes payload
            log4(mark, 288,                           // calldata
                 shl(224, shr(224, calldataload(0))), // msg.sig
                 caller,                              // msg.sender
                 calldataload(4),                     // arg1
                 calldataload(36)                     // arg2
                )
        }
    }
}

contract ERC20 is LibNote {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address guy) external note auth { wards[guy] = 1; }
    function deny(address guy) external note auth { wards[guy] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "not-authorized");
        _;
    }

    // --- ERC20 Data ---
    string  public name;
    string  public symbol;
    string  public version;
    uint8   public decimals;
    uint256 public totalSupply;

    mapping (address => uint)                      public balanceOf;
    mapping (address => mapping (address => uint)) public allowance;
    mapping (address => uint)                      public nonces;

    event Approval(address indexed src, address indexed guy, uint val);
    event Transfer(address indexed src, address indexed dst, uint val);

    // --- Math ---
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }

    // --- EIP712 niceties ---
    bytes32 public DOMAIN_SEPARATOR;
    // bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address holder,address spender,uint256 nonce,uint256 expiry,bool allowed)");
    bytes32 public constant PERMIT_TYPEHASH = 0xea2aa0a1be11a07ed86d755c93467f4f82362b452371d1ba94d1715123511acb;

    constructor(uint256 chainId_, string memory name_, string memory symbol_, string memory version_, uint8 decimals_) public {
        wards[msg.sender] = 1;

        name = name_;
        symbol = symbol_;
        version = version_;
        decimals = decimals_;

        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name)),
            keccak256(bytes(version)),
            chainId_,
            address(this)
        ));
    }

    // --- Token ---
    function transfer(address dst, uint val) external returns (bool) {
        return transferFrom(msg.sender, dst, val);
    }
    function transferFrom(address src, address dst, uint val)
        public returns (bool)
    {
        require(balanceOf[src] >= val, "insufficient-balance");
        if (src != msg.sender && allowance[src][msg.sender] != uint(-1)) {
            require(allowance[src][msg.sender] >= val, "insufficient-allowance");
            allowance[src][msg.sender] = sub(allowance[src][msg.sender], val);
        }
        balanceOf[src] = sub(balanceOf[src], val);
        balanceOf[dst] = add(balanceOf[dst], val);
        emit Transfer(src, dst, val);
        return true;
    }
    function mint(address usr, uint val) external auth {
        balanceOf[usr] = add(balanceOf[usr], val);
        totalSupply    = add(totalSupply, val);
        emit Transfer(address(0), usr, val);
    }
    function burn(address usr, uint val) external {
        require(balanceOf[usr] >= val, "insufficient-balance");
        if (usr != msg.sender && allowance[usr][msg.sender] != uint(-1)) {
            require(allowance[usr][msg.sender] >= val, "insufficient-allowance");
            allowance[usr][msg.sender] = sub(allowance[usr][msg.sender], val);
        }
        balanceOf[usr] = sub(balanceOf[usr], val);
        totalSupply    = sub(totalSupply, val);
        emit Transfer(usr, address(0), val);
    }
    function approve(address usr, uint val) external returns (bool) {
        allowance[msg.sender][usr] = val;
        emit Approval(msg.sender, usr, val);
        return true;
    }

    // --- Alias ---
    function push(address usr, uint val) external {
        transferFrom(msg.sender, usr, val);
    }
    function pull(address usr, uint val) external {
        transferFrom(usr, msg.sender, val);
    }
    function move(address src, address dst, uint val) external {
        transferFrom(src, dst, val);
    }

    // --- Approve by signature ---
    function permit(address holder, address spender, uint256 nonce, uint256 expiry,
                    bool allowed, uint8 v, bytes32 r, bytes32 s) external
    {
        bytes32 digest =
            keccak256(abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH,
                                     holder,
                                     spender,
                                     nonce,
                                     expiry,
                                     allowed))
        ));

        require(holder != address(0), "invalid-address-0");
        require(holder == ecrecover(digest, v, r, s), "invalid-permit");
        require(expiry == 0 || now <= expiry, "permit-expired");
        require(nonce == nonces[holder]++, "invalid-nonce");
        uint val = allowed ? uint(-1) : 0;
        allowance[holder][spender] = val;
        emit Approval(holder, spender, val);
    }
}