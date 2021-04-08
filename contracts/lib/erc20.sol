// SPDX-License-Identifier: AGPL-3.0-or-later

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

pragma solidity ^0.7.6;

contract ERC20 {
    // --- Auth ---
    mapping(address => uint256) public wards;

    function rely(address guy) external {
        wards[guy] = 1;
    }

    function deny(address guy) external {
        wards[guy] = 0;
    }

    modifier auth {
        require(wards[msg.sender] == 1, "not-authorized");
        _;
    }

    // --- ERC20 Data ---
    string public name;
    string public symbol;
    string public version;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public nonces;

    event Approval(address indexed src, address indexed guy, uint256 val);
    event Transfer(address indexed src, address indexed dst, uint256 val);

    // --- Math ---
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }

    // --- EIP712 niceties ---
    bytes32 public DOMAIN_SEPARATOR;
    // bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address holder,address spender,uint256 nonce,uint256 expiry,bool allowed)");
    bytes32 public constant PERMIT_TYPEHASH =
        0xea2aa0a1be11a07ed86d755c93467f4f82362b452371d1ba94d1715123511acb;

    constructor(
        uint256 chainId_,
        string memory name_,
        string memory symbol_,
        string memory version_,
        uint8 decimals_
    ) public {
        wards[msg.sender] = 1;

        name = name_;
        symbol = symbol_;
        version = version_;
        decimals = decimals_;

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                chainId_,
                address(this)
            )
        );
    }

    // --- Token ---
    function transfer(address dst, uint256 val) external returns (bool) {
        return transferFrom(msg.sender, dst, val);
    }

    function transferFrom(
        address src,
        address dst,
        uint256 val
    ) public returns (bool) {
        require(balanceOf[src] >= val, "insufficient-balance");
        if (src != msg.sender && allowance[src][msg.sender] != uint256(-1)) {
            require(
                allowance[src][msg.sender] >= val,
                "insufficient-allowance"
            );
            allowance[src][msg.sender] = sub(allowance[src][msg.sender], val);
        }
        balanceOf[src] = sub(balanceOf[src], val);
        balanceOf[dst] = add(balanceOf[dst], val);
        emit Transfer(src, dst, val);
        return true;
    }

    function mint(address usr, uint256 val) external auth {
        balanceOf[usr] = add(balanceOf[usr], val);
        totalSupply = add(totalSupply, val);
        emit Transfer(address(0), usr, val);
    }

    function burn(address usr, uint256 val) external auth {
        require(balanceOf[usr] >= val, "insufficient-balance");
        balanceOf[usr] = sub(balanceOf[usr], val);
        totalSupply = sub(totalSupply, val);
        emit Transfer(usr, address(0), val);
    }

    function approve(address usr, uint256 val) external returns (bool) {
        allowance[msg.sender][usr] = val;
        emit Approval(msg.sender, usr, val);
        return true;
    }

    // --- Alias ---
    function push(address usr, uint256 val) external {
        transferFrom(msg.sender, usr, val);
    }

    function pull(address usr, uint256 val) external {
        transferFrom(usr, msg.sender, val);
    }

    function move(
        address src,
        address dst,
        uint256 val
    ) external {
        transferFrom(src, dst, val);
    }

    // --- Approve by signature ---
    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 digest =
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    keccak256(
                        abi.encode(
                            PERMIT_TYPEHASH,
                            holder,
                            spender,
                            nonce,
                            expiry,
                            allowed
                        )
                    )
                )
            );

        require(holder != address(0), "invalid-address-0");
        require(holder == ecrecover(digest, v, r, s), "invalid-permit");
        require(expiry == 0 || block.timestamp <= expiry, "permit-expired");
        require(nonce == nonces[holder]++, "invalid-nonce");
        uint256 val = allowed ? uint256(-1) : 0;
        allowance[holder][spender] = val;
        emit Approval(holder, spender, val);
    }
}
