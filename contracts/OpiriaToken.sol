pragma solidity 0.4.24;

import '../zeppelin-solidity/contracts/token/ERC20/MintableToken.sol';
import '../zeppelin-solidity/contracts/token/ERC20/PausableToken.sol';


contract OpiriaToken is MintableToken, PausableToken {
    string public name = "PDATA";
    string public symbol = "PDATA";
    uint256 public decimals = 18;
}
