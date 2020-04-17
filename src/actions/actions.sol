pragma solidity ^0.5.10;

contract VatLike {
    function can(address, address) public view returns (uint);
    function ilks(bytes32) public view returns (uint, uint, uint, uint, uint);
    function dai(address) public view returns (uint);
    function urns(bytes32, address) public view returns (uint, uint);
    function frob(bytes32, address, address, address, int, int) public;
    function hope(address) public;
    function move(address, address, uint) public;
}

contract JugLike {
    function drip(bytes32) public returns (uint);
}

contract PotLike {
    function vat() public returns (VatLike);
    function chi() external returns (uint ray);
    function rho() external returns (uint);
    function drip() public returns (uint);
    function join(uint pie) public;
    function exit(uint pie) public;
}

contract ValueDSRLike {
    function split() public returns (address);
    function initialized() public returns (bool);
    function zcd(uint,uint) public returns (uint);
    function dcp(uint,uint) public returns (uint);
}

contract SplitDSRLike {
    function vat() public returns (VatLike);
    function pot() public returns (PotLike);
    function value() public returns (ValueDSRLike);
    function last() public returns (uint);
    function zcd(address, bytes32) external returns (uint);
    function dcp(address, bytes32) external returns (uint);
    function chi(uint, uint) external returns (uint);
    function totalSupply() external returns (uint);
    function approvals(address, address) external returns (bool);
    function moveZCD(address, address, bytes32, uint) external;
    function moveDCP(address, address, bytes32, uint) external;
    function snapshot() public returns (uint);
    function issue(address, uint, uint) external;
    function redeem(address, uint, uint, uint) external;
    function claim(address, uint, uint, uint, uint) external;
    function rewind(address, uint, uint, uint, uint) external;
    function withdraw(address, uint, uint) external;
    function slice(address, uint, uint, uint, uint) external;
    function merge(address, uint, uint, uint, uint, uint) external;
    function sliceFuture(address, uint, uint, uint, uint, uint) external;
    function mergeFuture(address, uint, uint, uint, uint, uint) external;
    function convert(address, uint, uint, uint, uint, uint) external;
    function cage() external;
    function cashZCD(address, uint, uint) external;
    function cashDCP(address, uint, uint) external;
    function cashFutureDCP(address, uint, uint, uint, uint) external;
}

contract DaiLike {
    function approve(address, uint) public;
    function transferFrom(address, address, uint) public;
}

contract DaiJoinLike {
    function vat() public returns (VatLike);
    function dai() public returns (DaiLike);
    function join(address, uint) public payable;
    function exit(address, uint) public;
}

contract Common {
    uint256 constant ONE = 10 ** 27;

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "mul-overflow");
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "sub-overflow");
    }

    function rdiv(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, ONE) / y;
    }

    function toInt(uint x) internal pure returns (int y) {
        y = int(x);
        require(y >= 0, "int-overflow");
    }
}

contract SplitDSRProxyActions is Common {
    // Move ERC20 Dai balance to Vat.dai
    function moveERC20DaiToVat(address daiJoin_, address usr, uint wad) public {
        DaiJoinLike(daiJoin_).dai().transferFrom(usr, address(this), wad); // Ensure DSProxy contract is approved by usr
        DaiJoinLike(daiJoin_).dai().approve(daiJoin_, wad); // Approve DaiJoin adapter to withdraw from DSProxy's Dai token balance
        DaiJoinLike(daiJoin_).join(usr, wad); // DaiJoin burns Dai ERC20 balance and issues usr a Vat.dai balance
    }

    // Move entire Vat.dai balance to Dai ERC20 token
    function moveAllVatDaiToERC20(address daiJoin_, address usr) public {
        VatLike vat = DaiJoinLike(daiJoin_).vat();

        uint bal = vat.dai(usr); // Read total usr's Vat.dai balance
        vat.move(usr, address(this), bal); // Ensure DSProxy is approved by usr in Vat to move Vat.dai balance

        if (vat.can(address(this), address(daiJoin_)) == 0) {
            vat.hope(daiJoin_); // DSProxy allows DaiJoin adapter to move its Vat.dai balance
        }

        // Dai ERC20 balance received could be slightly lower due to rounding down in the division to calculate a wad value
        DaiJoinLike(daiJoin_).exit(usr, (bal / ONE)); // Transfer Vat.dai balance to adapter and mint Dai ERC20 balance for usr
    }

    // Move entire Vat.dai balance to Pot balance of DSProxy
    function moveAllVatDaiToDSR(address pot_, address usr) public {
        VatLike vat = PotLike(pot_).vat();

        uint bal = vat.dai(usr); // Read total usr's Vat.dai balance
        vat.move(usr, address(this), bal); // Ensure DSProxy is approved by usr in Vat to move Vat.dai balance

        if (vat.can(address(this), address(pot_)) == 0) {
            vat.hope(pot_); // DSProxy allows Pot(DSR contract) to move its Vat.dai balance
        }

        uint pie = bal / PotLike(pot_).drip(); // Execute drip before joining, calculate pie value
        PotLike(pot_).join(pie); // (pie * chi) could be slightly lower than bal because division in previous step rounds down
    }

    // Calculate Pie value and Issue ZCD & DCP using Vat.dai balance of usr
    function calcAndIssueFromVat(address split_, address usr, uint end, uint wad) public {
        uint pie = rdiv(wad, SplitDSRLike(split_).snapshot()); // Calculate Pie
        SplitDSRLike(split_).issue(usr, end, pie); // Issue ZCD & DCP
    }

    // Calculate Pie value and Issue ZCD & DCP using ERC20 Dai balance of usr
    function calcAndIssueFromERC20(address split_, address daiJoin_, address usr, uint end, uint wad) public {
        moveERC20DaiToVat(daiJoin_, usr, wad); // Get Vat.dai balance
        calcAndIssueFromVat(split_, usr, end, wad); // Issue ZCD & DCP using Vat.dai balance
    }

    // Calculate Pie value and Issue ZCD & DCP using DSR pie balance of DSProxy
    function calcAndIssueFromDSR(address split_, address pot_, address usr, uint end, uint pie) public {
        PotLike(pot_).exit(pie); // Exit pie balance to Vat.dai
        SplitDSRLike(split_).issue(usr, end, pie); // Issue ZCD & DCP using Vat.dai balance
    }

    // Redeem already takes wad instead of pie as input

    // Calculate Pie value and Redeem ZCD to ERC20 Dai balance of usr
    function calcAndRedeemToERC20(address split_, address daiJoin_, address usr, uint end, uint time, uint wad) public {
        SplitDSRLike(split_).redeem(usr, end, time, wad); // Redeem ZCD after maturity to Vat.dai balance
        moveAllVatDaiToERC20(daiJoin_, usr); // Move entire Vat.dai balance to Dai ERC20 token
    }

    // Calculate Pie value and Redeem ZCD to DSR pie balance of DSProxy
    function calcAndRedeemToDSR(address split_, address pot_, address usr, uint end, uint time, uint wad) public {
        SplitDSRLike(split_).redeem(usr, end, time, wad); // Redeem ZCD after maturity to Vat.dai balance
        moveAllVatDaiToDSR(pot_, usr); // Move all Vat.dai balance to DSProxy's Pot balance
    }

    // Claim DCP savings accrued until now and before expiry to Vat.dai balance
    function claimNowToVat(address split_, address usr, uint start, uint end, uint pie) public {
        SplitDSRLike(split_).claim(usr, start, end, now, pie); // Execute claim at time now. Snapshot for now need not exist and will be captured internally
    }

    // Claim DCP savings accrued until now and before expiry to ERC20 Dai balance
    function claimNowToERC20(address split_, address daiJoin_, address usr, uint start, uint end, uint pie) public {
        claimNowToVat(split_, usr, start, end, pie);
        moveAllVatDaiToERC20(daiJoin_, usr);
    }

    // Claim DCP savings accrued until now and before expiry to DSR Pie balance of DSProxy contract
    function claimNowToDSR(address split_, address pot_, address usr, uint start, uint end, uint pie) public {
        claimNowToVat(split_, usr, start, end, pie);
        moveAllVatDaiToDSR(pot_, usr);
    }

    // Claim DCP savings at Time to Vat.dai balance is the default for claim() in split.sol

    // Claim DCP savings at Snapshot time to ERC20 Dai balance
    function claimAtTimeToERC20(address split_, address daiJoin_, address usr, uint start, uint end, uint time, uint pie) public {
        SplitDSRLike(split_).claim(usr, start, end, time, pie); // Snapshot at time needs to exist
        moveAllVatDaiToERC20(daiJoin_, usr);
    }

    // Claim DCP savings at Snapshot time to DSR Pie balance of DSProxy contract
    function claimAtTimeToDSR(address split_, address pot_, address usr, uint start, uint end, uint time, uint pie) public {
        SplitDSRLike(split_).claim(usr, start, end, time, pie);
        moveAllVatDaiToDSR(pot_, usr);
    }

    // Claim DCP savings accrued and Withdraw Dai using Pie value as input
    function claimAndWithdraw(address split_, address usr, uint start, uint end, uint pie) public {
        SplitDSRLike(split_).claim(usr, start, end, now, pie); // Withdraw cannot be executed until all savings are claimed until now
        bytes32 class = keccak256(abi.encodePacked(now, end));
        uint withdrawPie = SplitDSRLike(split_).dcp(usr, class);
        SplitDSRLike(split_).withdraw(usr, end, withdrawPie); // Merge ZCD and DCP before expiry to withdraw dai
    }

    // Calculate Pie, Claim DCP savings accrued, and Withdraw Dai to Vat.dai balance
    function calcClaimAndWithdrawToVat(address split_, address usr, uint start, uint end, uint wad) public {
        uint pie = rdiv(wad, SplitDSRLike(split_).snapshot());  // Calculate Pie
        claimAndWithdraw(split_, usr, start, end, pie);
    }

    // Calculate Pie, Claim DCP savings accrued, and Withdraw Dai to ERC20 Dai balance
    function calcClaimAndWithdrawToERC20(address split_, address daiJoin_, address usr, uint start, uint end, uint wad) public {
        calcClaimAndWithdrawToVat(split_, usr, start, end, wad);
        moveAllVatDaiToERC20(daiJoin_, usr);
    }

    // Calculate Pie, Claim DCP savings accrued, and Withdraw Dai to DSR Pie balance of DSProxy contract
    function calcClaimAndWithdrawToDSR(address split_, address pot_, address usr, uint start, uint end, uint wad) public {
        calcClaimAndWithdrawToVat(split_, usr, start, end, wad);
        moveAllVatDaiToDSR(pot_, usr);
    }

    // Generate Dai and Issue ZCD
    function generateDaiAndIssueZCD(
        address split_,
        address vat_,
        address jug,
        bytes32 ilk_,
        address usr,
        uint end,
        uint pie
    ) public {
        SplitDSRLike split = SplitDSRLike(split_);
        VatLike vat = VatLike(vat_);

        uint rate = JugLike(jug).drip(ilk_);
        int  dart = toInt(mul(pie, ONE) / rate) + 1; // additional wei to fix precision issues
        vat.frob(ilk_, usr, usr, usr, 0, dart);
        split.issue(usr, end, pie);
    }

    // Claim and payback stability fee
    function claimAndPaybackStabilityFee() public {
        // TODO
    }
}