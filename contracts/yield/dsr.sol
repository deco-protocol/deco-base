/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.7.6;

import "../lib/DSMath.sol";
import "../interfaces/ChaiLike.sol";
import "../interfaces/PotLike.sol";
import "../interfaces/CoreLike.sol";

contract DSR is DSMath {
    CoreLike public core; // core contract address
    bool public canSnapshot; // public snapshot allowed
    bool public canInsert; // gov only insert allowed
    bool public canOverwrite; // amp value overwrite allowed

    ChaiLike public chai; // chai
    PotLike public pot; // pot

    uint public closeTimestamp; // yield adapter close timestamp
    mapping (uint => uint) public ratio; // maturity timestamp => balance cashout ratio [ray]

    constructor(address core_, address chai_) {
        core = CoreLike(core_);
        chai = ChaiLike(chai_);
        pot = PotLike(chai.pot());

        canSnapshot = true; // allow snaposhot
        canInsert = true; // allow insert
        canOverwrite = false; // disallow overwrite
        closeTimestamp = uint(-1); // initialized to MAX_UINT, updated after close
    }

    modifier onlyCore() {
        require(msg.sender == address(core));
        _;
    }

    modifier onlyGov() {
        require(msg.sender == core.gov());
        _;
    }

    modifier afterClose(uint time) {
        require(closeTimestamp < uint(-1)); // neeeds to be closed
        require(closeTimestamp < time); // processes only if input timestamp is greater than close
        _;
    }

    function snapshot() public returns (uint) {
        return pot.drip(); // retrieve amp value from pot
    }

    function lock(address usr, uint amp, uint cbal_) public onlyCore returns (uint) {
        require(chai.transferFrom(usr, address(this), cbal_)); // transfer cbal amount of chai from usr
        return mulu(cbal_, amp); // return notional amount
    }

    function unlock(address usr, uint amp, uint cbal_) public onlyCore returns (uint) {
        require(chai.transferFrom(address(this), usr, cbal_)); // transfer cbal amount of chai to usr
        return mulu(cbal_, amp); // return notional amount
    }

    function close() external {
        require(pot.live() == 0); // pot needs to be caged for close to succeed
        require(closeTimestamp == uint(-1)); // can be closed only once

        snapshot();
        closeTimestamp = block.timestamp; // set close timestamp
    }

    // --- Governance ---
    function calculate(uint maturity, uint ratio_) public onlyGov afterClose(maturity) {
        ratio[maturity] = ratio_;
        // ex: 0.015 gives 0.985 to zero balance at this maturity and 0.015 to claim balance
    }

    // --- Zero and Claim Cash Out Functions ---
    function zero(uint maturity, uint zbal_) public view afterClose(maturity) returns (uint) {
        require(ratio[maturity] != 0); // cashout ratio needs to be set for maturity
        return rmul(zbal_, subu(RAY, ratio[maturity])); // yield token value of notional amount in zero
    }

    function claim(uint maturity, uint zbal_) public view afterClose(maturity) returns (uint) {
        require(ratio[maturity] != 0); // cashout ratio needs to be set for maturity
        return rmul(zbal_, ratio[maturity]); // yield token value of notional amount in claim
    }

    function cashZero(address usr, uint maturity, uint zbal_) external afterClose(maturity) {
        core.burnZero(address(this), usr, maturity, zbal_); // burn balance

        uint cash = zero(maturity, zbal_); // get yield token value

        uint latestAmpTimestamp = core.latestAmpTimestamp(address(this));
        uint latestAmp = core.amp(address(this), latestAmpTimestamp); // last amp value
        uint cbalOut = cash / latestAmp;

        unlock(usr, latestAmp, cbalOut); // transfer yield token to user
    }

    function cashClaim(address usr, uint maturity, uint cbal_) external afterClose(maturity) {
        // yield earnt before close needs to be claimed prior to cashing out
        core.burnClaim(address(this), usr, closeTimestamp, maturity, cbal_);

        uint zbal_ = mulu(cbal_, core.amp(address(this), closeTimestamp));
        uint cash = claim(maturity, zbal_); // get yield token value

        uint latestAmpTimestamp = core.latestAmpTimestamp(address(this));
        uint latestAmp = core.amp(address(this), latestAmpTimestamp); // last amp value
        uint cbalOut = cash / latestAmp;

        unlock(usr, latestAmp, cbalOut); // transfer yield token to user
    }

    function cashFutureClaim(address usr, uint issuance, uint activation, uint maturity, uint cbal_) external afterClose(activation) {
        core.burnFutureClaim(address(this), usr, issuance, activation, maturity, cbal_);

        uint zbal_ = mulu(cbal_, core.amp(address(this), issuance)); // calculate notional amount
        uint cash = subu(claim(maturity, zbal_), claim(activation, zbal_)); // yield token value using difference

        uint latestAmpTimestamp = core.latestAmpTimestamp(address(this));
        uint latestAmp = core.amp(address(this), latestAmpTimestamp); // last amp value
        uint cbalOut = cash / latestAmp;

        unlock(usr, latestAmp, cbalOut); // transfer yield token to user
    }
}