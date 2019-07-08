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

pragma solidity >=0.4.24;

import "./zcd.sol";

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

contract DSR {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address guy) public auth { wards[guy] = 1; }
    function deny(address guy) public auth { wards[guy] = 0; }
    modifier auth { require(wards[msg.sender] == 1); _; }

    // Contract addresses
    TokenLike dai;
    AdapterLike adapter;
    PotLike pot;
    ZCD zcd;

    mapping (address => uint) settledChi;

    // --- ERC20 Data ---
    string  public constant name     = "DSR Token";
    string  public constant symbol   = "DSR";
    string  public constant version  = "1";
    uint8   public constant decimals = 18;
    uint256 public totalSupply;

    mapping (address => uint)                      public balanceOf;
    mapping (address => mapping (address => uint)) public allowance;
    mapping (address => uint)                      public nonces;

    event Approval(address indexed src, address indexed guy, uint wad);
    event Transfer(address indexed src, address indexed dst, uint wad);

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

    // --- EIP712 niceties ---
    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public constant PERMIT_TYPEHASH = keccak256(
        "Permit(address holder,address spender,uint256 nonce,uint256 expiry,bool allowed)"
    );

    constructor(address dai_, address adapter_, address pot_, uint256 chainId_) public {
        wards[msg.sender] = 1;
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name)),
            keccak256(bytes(version)),
            chainId_,
            address(this)
        ));

        dai = TokenLike(dai_);
        adapter = AdapterLike(adapter_);
        pot = PotLike(pot_);

        zcd = new ZCD(chainId_);
    }

    // --- Token ---
    function transfer(address dst, uint wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }
    function transferFrom(address src, address dst, uint wad)
        public returns (bool)
    {
        require(balanceOf[src] >= wad, "dsr/insufficient-balance");

        // Claim accumulated savings on addresses before settledChi is reset
        claim(src);
        claim(dst);

        if (src != msg.sender && allowance[src][msg.sender] != uint(-1)) {
            require(allowance[src][msg.sender] >= wad, "dsr/insufficient-allowance");
            allowance[src][msg.sender] = sub(allowance[src][msg.sender], wad);
        }
        balanceOf[src] = sub(balanceOf[src], wad);
        balanceOf[dst] = add(balanceOf[dst], wad);
        emit Transfer(src, dst, wad);
        return true;
    }
    function mint(address usr, uint wad) internal {
        balanceOf[usr] = add(balanceOf[usr], wad);
        totalSupply    = add(totalSupply, wad);
        emit Transfer(address(0), usr, wad);
    }
    function burn(address usr, uint wad) internal {
        require(balanceOf[usr] >= wad, "dsr/insufficient-balance");
        if (usr != msg.sender && allowance[usr][msg.sender] != uint(-1)) {
            require(allowance[usr][msg.sender] >= wad, "dsr/insufficient-allowance");
            allowance[usr][msg.sender] = sub(allowance[usr][msg.sender], wad);
        }
        balanceOf[usr] = sub(balanceOf[usr], wad);
        totalSupply    = sub(totalSupply, wad);
        emit Transfer(usr, address(0), wad);
    }
    function approve(address usr, uint wad) public returns (bool) {
        allowance[msg.sender][usr] = wad;
        emit Approval(msg.sender, usr, wad);
        return true;
    }

    // --- Alias ---
    function push(address usr, uint wad) public {
        transferFrom(msg.sender, usr, wad);
    }
    function pull(address usr, uint wad) public {
        transferFrom(usr, msg.sender, wad);
    }
    function move(address src, address dst, uint wad) public {
        transferFrom(src, dst, wad);
    }

    // --- Approve by signature ---
    function permit(address holder, address spender, uint256 nonce, uint256 expiry,
                    bool allowed, uint8 v, bytes32 r, bytes32 s) public
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
        require(holder == ecrecover(digest, v, r, s), "invalid permit");
        require(expiry == 0 || now <= expiry, "permit expired");
        require(nonce == nonces[holder]++, "invalid nonce");
        uint wad = allowed ? uint(-1) : 0;
        allowance[holder][spender] = wad;
        emit Approval(holder, spender, wad);
    }

    // Lock Dai and issue DSR and ZCD tokens
    function split(uint wad) public {
        uint depositAmt = mul(pot.chi(), wad);

        // Claim accumulated savings dai before changing balances
        claim(msg.sender);

        // Transfer and lock Dai in savings mode
        require(dai.transferFrom(msg.sender, address(this), depositAmt));
        adapter.join(address(this), depositAmt);
        pot.join(wad);

        mint(msg.sender, depositAmt);
        zcd.mint(msg.sender, depositAmt);
    }

    // Redeem equal amount of DSR and ZCD tokens to unlock Dai
    function merge(uint wad) public {
        uint withdrawAmt = mul(pot.chi(), wad);

        // Claim accumulated savings dai before changing balances
        claim(msg.sender);

        burn(msg.sender, withdrawAmt);
        zcd.burn(msg.sender, withdrawAmt);

        // Remove Dai from savings mode and transfer to user
        pot.exit(wad);
        adapter.exit(msg.sender, withdrawAmt);
        require(dai.transferFrom(msg.sender, address(this), withdrawAmt));
    }

    // Deposit Dai accumulated as savings on input address
    function claim(address usr) public {
        uint chi_ = pot.chi();

        if (!(settledChi[usr] == 0 || balanceOf[usr] == 0)) {
            uint daiBalance = mul(balanceOf[usr], sub(chi_, settledChi[usr]));

            pot.exit(daiBalance / chi_);
            adapter.exit(usr, daiBalance);
            require(dai.transferFrom(address(this), usr, daiBalance));
        }

        settledChi[usr] = chi_;
    }

    // handle emergency shutdown
}