pragma solidity 0.4.24;

import './TimedPresaleCrowdsale.sol';
import '../zeppelin-solidity/contracts/math/SafeMath.sol';
import '../zeppelin-solidity/contracts/crowdsale/emission/MintedCrowdsale.sol';
import './TokenCappedCrowdsale.sol';
import '../zeppelin-solidity/contracts/token/ERC20/PausableToken.sol';

contract OpiriaCrowdsale is TimedPresaleCrowdsale, MintedCrowdsale, TokenCappedCrowdsale {
    using SafeMath for uint256;

    uint256 public presaleWeiLimit;

    address public tokensWallet;

    uint256 public totalBonus = 0;

    bool public hiddenCapTriggered;

    uint16 public additionalBonusPercent = 0;

    mapping(address => uint256) public bonusOf;

    // Crowdsale(uint256 _rate, address _wallet, ERC20 _token)
    constructor(ERC20 _token, uint16 _initialEtherUsdRate, address _wallet, address _tokensWallet,
        uint256 _presaleOpeningTime, uint256 _presaleClosingTime, uint256 _openingTime, uint256 _closingTime
    ) public
    TimedPresaleCrowdsale(_presaleOpeningTime, _presaleClosingTime, _openingTime, _closingTime)
    Crowdsale(_initialEtherUsdRate, _wallet, _token) {
        setEtherUsdRate(_initialEtherUsdRate);
        tokensWallet = _tokensWallet;

        require(PausableToken(token).paused());
    }

    //overridden
    function _getTokenAmount(uint256 _weiAmount) internal view returns (uint256) {
        // 1 ether * etherUsdRate * 10

        return _weiAmount.mul(rate).mul(10);
    }

    function _getBonusAmount(uint256 tokens) internal view returns (uint256) {
        uint16 bonusPercent = _getBonusPercent();
        uint256 bonusAmount = tokens.mul(bonusPercent).div(100);
        return bonusAmount;
    }

    function _getBonusPercent() internal view returns (uint16) {
        if (isPresale()) {
            return 20;
        }
        uint256 daysPassed = (now - openingTime) / 1 days;
        uint16 calcPercent = 0;
        if (daysPassed < 15) {
            // daysPassed will be less than 15 so no worries about overflow here
            calcPercent = (15 - uint8(daysPassed));
        }

        calcPercent = additionalBonusPercent + calcPercent;

        return calcPercent;
    }

    //overridden
    function _processPurchase(address _beneficiary, uint256 _tokenAmount) internal {
        _saveBonus(_beneficiary, _tokenAmount);
        _deliverTokens(_beneficiary, _tokenAmount);

        soldTokens = soldTokens.add(_tokenAmount);
    }

    function _saveBonus(address _beneficiary, uint256 tokens) internal {
        uint256 bonusAmount = _getBonusAmount(tokens);
        if (bonusAmount > 0) {
            totalBonus = totalBonus.add(bonusAmount);
            soldTokens = soldTokens.add(bonusAmount);
            bonusOf[_beneficiary] = bonusOf[_beneficiary].add(bonusAmount);
        }
    }

    //overridden
    function _preValidatePurchase(address _beneficiary, uint256 _weiAmount) internal {
        super._preValidatePurchase(_beneficiary, _weiAmount);
        if (isPresale()) {
            require(_weiAmount >= presaleWeiLimit);
        }

        uint256 tokens = _getTokenAmount(_weiAmount);
        uint256 bonusTokens = _getBonusAmount(tokens);
        require(notExceedingSaleCap(tokens.add(bonusTokens)));
    }

    function setEtherUsdRate(uint16 _etherUsdRate) public onlyOwner {
        rate = _etherUsdRate;

        // the presaleWeiLimit must be $2500 in eth at the defined 'etherUsdRate'
        // presaleWeiLimit = 1 ether / etherUsdRate * 2500
        presaleWeiLimit = uint256(1 ether).mul(2500).div(rate);
    }

    function setAdditionalBonusPercent(uint8 _additionalBonusPercent) public onlyOwner {
        additionalBonusPercent = _additionalBonusPercent;
    }
    /**
    * Send tokens by the owner directly to an address.
    */
    function sendTokensTo(uint256 amount, address to) public onlyOwner {
        require(!isFinalized);
        require(notExceedingSaleCap(amount));

        require(MintableToken(token).mint(to, amount));
        soldTokens = soldTokens.add(amount);

        emit TokenPurchase(msg.sender, to, 0, amount);
    }

    function sendTokensToBatch(uint256[] amounts, address[] recipients) public onlyOwner {
        require(amounts.length == recipients.length);
        for (uint i = 0; i < recipients.length; i++) {
            sendTokensTo(amounts[i], recipients[i]);
        }
    }

    function addBonusBatch(uint256[] amounts, address[] recipients) public onlyOwner {

        for (uint i = 0; i < recipients.length; i++) {
            require(PausableToken(token).balanceOf(recipients[i]) > 0);
            require(notExceedingSaleCap(amounts[i]));

            totalBonus = totalBonus.add(amounts[i]);
            soldTokens = soldTokens.add(amounts[i]);
            bonusOf[recipients[i]] = bonusOf[recipients[i]].add(amounts[i]);
        }
    }

    function unlockTokenTransfers() public onlyOwner {
        require(isFinalized);
        require(now > closingTime + 30 days);
        require(PausableToken(token).paused());
        bonusUnlockTime = now + 30 days;
        PausableToken(token).unpause();
    }


    function distributeBonus(address[] addresses) public onlyOwner {
        require(now > bonusUnlockTime);
        for (uint i = 0; i < addresses.length; i++) {
            if (bonusOf[addresses[i]] > 0) {
                uint256 bonusAmount = bonusOf[addresses[i]];
                _deliverTokens(addresses[i], bonusAmount);
                totalBonus = totalBonus.sub(bonusAmount);
                bonusOf[addresses[i]] = 0;
            }
        }
        if (totalBonus == 0 && reservedTokensClaimStage == 3) {
            MintableToken(token).finishMinting();
        }
    }

    function withdrawBonus() public {
        require(now > bonusUnlockTime);
        require(bonusOf[msg.sender] > 0);

        _deliverTokens(msg.sender, bonusOf[msg.sender]);
        totalBonus = totalBonus.sub(bonusOf[msg.sender]);
        bonusOf[msg.sender] = 0;

        if (totalBonus == 0 && reservedTokensClaimStage == 3) {
            MintableToken(token).finishMinting();
        }
    }


    function finalization() internal {
        super.finalization();

        // mint 25% of total Tokens (13% for development, 5% for company/team, 6% for advisors, 2% bounty) into team wallet
        uint256 toMintNow = totalTokens.mul(25).div(100);

        if (!capIncreased) {
            // if the cap didn't increase (according to whitepaper) mint the 50MM tokens to the team wallet too
            toMintNow = toMintNow.add(50 * 1000 * 1000);
        }
        _deliverTokens(tokensWallet, toMintNow);
    }

    uint8 public reservedTokensClaimStage = 0;

    function claimReservedTokens() public onlyOwner {

        uint256 toMintNow = totalTokens.mul(5).div(100);
        if (reservedTokensClaimStage == 0) {
            require(now > closingTime + 6 * 30 days);
            reservedTokensClaimStage = 1;
            _deliverTokens(tokensWallet, toMintNow);
        }
        else if (reservedTokensClaimStage == 1) {
            require(now > closingTime + 12 * 30 days);
            reservedTokensClaimStage = 2;
            _deliverTokens(tokensWallet, toMintNow);
        }
        else if (reservedTokensClaimStage == 2) {
            require(now > closingTime + 24 * 30 days);
            reservedTokensClaimStage = 3;
            _deliverTokens(tokensWallet, toMintNow);
            if (totalBonus == 0) {
                MintableToken(token).finishMinting();
                MintableToken(token).transferOwnership(owner);
            }
        }
        else {
            revert();
        }
    }

    function increaseCap() public onlyOwner {
        require(!capIncreased);
        require(!isFinalized);
        require(now < openingTime + 5 days);

        capIncreased = true;
        cap = cap.add(50 * 1000 * 1000);
        emit CapIncreased();
    }

    function triggerHiddenCap() public onlyOwner {
        require(!hiddenCapTriggered);
        require(now > presaleOpeningTime);
        require(now < presaleClosingTime);

        presaleClosingTime = now;
        openingTime = now + 24 hours;

        hiddenCapTriggered = true;
    }
}
