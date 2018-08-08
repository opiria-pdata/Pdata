pragma solidity 0.4.24;


import '../zeppelin-solidity/contracts/math/SafeMath.sol';
import '../zeppelin-solidity/contracts/crowdsale/distribution/FinalizableCrowdsale.sol';


contract TokenCappedCrowdsale is FinalizableCrowdsale {
    using SafeMath for uint256;

    uint256 public cap;
    uint256 public totalTokens;
    uint256 public soldTokens = 0;
    bool public capIncreased = false;

    event CapIncreased();

    constructor() public {

        cap = 400 * 1000 * 1000 * 1 ether;
        totalTokens = 750 * 1000 * 1000 * 1 ether;
    }

    function notExceedingSaleCap(uint256 amount) internal view returns (bool) {
        return cap >= amount.add(soldTokens);
    }

    /**
    * Finalization logic. We take the expected sale cap
    * ether and find the difference from the actual minted tokens.
    * The remaining balance and the reserved amount for the team are minted
    * to the team wallet.
    */
    function finalization() internal {
        super.finalization();
    }
}
