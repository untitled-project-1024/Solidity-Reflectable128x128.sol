
/* A Reflection Token wrapper on any ERC-20/BEP-20 contract.
*  It stores reflected values as uint128, saving 30% in transfer costs (gas fees) compared to typical reflection contracts.
*  @custom:origin Safemoon.sol (https://github.com/safemoonprotocol/Safemoon.sol/blob/main/Safemoon.sol)
*  @custom:improv J. W.
*  @custom:metadata [@license MIT, @version 3.4, @minpragma 0.8.21]
*  NOTE: Optimal values: decimal of <=12 and supply <= 1 quadrillion (lower decimals and token amounts = higher precision).
*  Currently only supports static or deflationary tokens, i.e. tokens with a starting supply that stays constant or decreases.
*  MAX128: 340282366920938463463374607431768211455
*/
abstract contract Reflectable128x128 is BEP20 { // inherits: Ownable.sol, Context.sol, BEP20.sol

    error INSUFFICIENT_PRECISION(uint128 required, uint128 current);
    error INVALID_STATUS(address account, bool rewardStatus);
    error SUPPLY_OVERFLOW();

    constructor() {
        unchecked {
            uint256 supply = super.totalSupply(); // Need the previous total supply before overriding `totalSupply()` because _rTotal at this point is 0.

            if (supply > MAX128) {
                revert SUPPLY_OVERFLOW();
            }
            if (MAX128 / uint128(supply) < 1e12) {
                revert INSUFFICIENT_PRECISION({ required: 1e12, current: MAX128 / uint128(supply) });
            }

            _tTotal = uint128(supply);
            _rTotal = (MAX128 - (MAX128 % _tTotal)); 

            _balances[owner].rOwned = _rTotal; // Set total supply to owner.
        }
    }

    mapping (address => Account) internal _balances;

    uint128 internal immutable _tTotal;
    uint128 internal _rTotal;
    
    address[] internal _rExcluded;

    struct Account { 
        uint128 rOwned; // 16 bytes
        uint128 tOwned; // 16 bytes
        bool isFeeExempt; // 1 byte
        bool isExcluded;  // 1 byte
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    /// @dev See {IBEP20-balanceOf},
    function balanceOf(address account) public view virtual override returns (uint) { // uint128 => uint256
        return _balances[account].isExcluded ? _balances[account].tOwned : tokenFromReflection(_balances[account].rOwned);
    }

    /// @dev See {IBEP20-totalSupply}.
    function totalSupply() public view virtual override returns (uint) {
        unchecked {
            return releaseSupply /* + mintedTokens */ - balanceOf(address(0xdead));
        }
    }

    /** 
    * NOTE: This function is not unitarily bidirectional. Including an account changes the existing reflections for all accounts,
    * whereas excluding an account merely prevents an account from receiving future rewards, keeping other balances the same.
    * TRUE: includeInReward, FALSE: excludeFromReward 
    */
    function setRewardStatus(address[] /* calldata */ memory accounts, bool include) public virtual onlyOwner {
        uint len = accounts.length;
        unchecked {
            for (uint i; i < len; ++i) {
                _setRewardStatus(accounts[i], include);
            }
        }
    }

    // Sets an account or account set as fee exempt via `transfer()`
    function setFeeExempt(address[] memory accounts, bool isTaxExempt) public virtual onlyOwner {
        uint len = accounts.length;
        unchecked {
            for (uint i; i < len; ++i) {
                _balances[accounts[i]].isFeeExempt = isTaxExempt;
            }
        }
    }

    // Gets tokens owned from a reflection balance.
    function tokenFromReflection(uint128 rAmount) internal view virtual returns (uint128 /* tOwned */) {
        unchecked {
            return (rAmount / getRate());
        }
    }

    // Gets reflections owned from a token balance.
    function reflectionFromToken(uint128 tAmount) internal view virtual returns (uint128 /* rOwned */) {
        unchecked {
            return (tAmount * getRate());
        }
    }

    // Get's the current reflection rate.
    function getRate() internal view virtual returns (uint128 /* currentRate */) { // unchecked division by 0 still reverts
        (uint128 rSupply, uint128 tSupply) = getCurrentSupply(); 
        unchecked { 
            return (rSupply / tSupply);
        }
    }

    // Gets the combined balances of all reflection enabled accounts by subracting all reflection disabled account balances.
    function getCurrentSupply() internal view virtual returns (uint128 rSupply, uint128 tSupply) {

        (rSupply, tSupply) = (_rTotal, _tTotal);

        address[] memory rExcluded = _rExcluded; // copying to memory is cheaper than sloading each index   
        uint256 len = rExcluded.length; 
        address account;
        unchecked {
            for (uint256 i; i < len; ++i) {
                account = rExcluded[i];  
                (uint128 rOwnedAcc, uint128 tOwnedAcc) = (_balances[account].rOwned, _balances[account].tOwned);

                if ((rOwnedAcc > rSupply) || (tOwnedAcc > tSupply)) {
                    return (_rTotal, _tTotal);
                }            
                rSupply -= rOwnedAcc; 
                tSupply -= tOwnedAcc;
            }
            return (rSupply < (_rTotal / _tTotal)) ? (_rTotal, _tTotal) : (rSupply, tSupply);
        }
    }

    // Redistribute `tAmount` to all reflection enabled accounts.
    function reflectToHolders(uint128 tAmount, uint128 rate) internal virtual {
        unchecked {
            _rTotal -= (tAmount * rate);
        }
    }

    /**
    * @dev Combines Safemoon's `_transferStandard()`, `_transferFromExcluded()`, `_transferToExcluded()`, and `_transferBothExcluded()`.
    * NOTE: Requires Solidity 0.8+. Emits a {Transfer} event.
    * @param from The sender address.
    * @param to The receiver address.
    * @param amount The amount to deduct from sender.
    * @param remainder The amount to send to receiver (after fee deduction).
    * @return rate The rate to use for fee transfers {sendFeeTo()} before reflecting to holders.
    * NOTE: This function does not check balance.
    */
    function _transferSupportingFee(address from, address to, uint256 amount, uint256 remainder) internal virtual returns (uint128 rate) { 
        assert(remainder <= amount);

        rate = getRate(); // NOTE: R-values are always T-values * rate (currentRate).

        unchecked {
            _balances[from].rOwned -= (uint128(amount) * rate);
            _balances[to].rOwned += (uint128(remainder) * rate);

            if (_balances[from].isExcluded) { 
                _balances[from].tOwned -= uint128(amount);
            }

            if (_balances[to].isExcluded)  { 
                _balances[to].tOwned += uint128(remainder);
            }
        }
        
        emit Transfer(from, to, remainder);
    }

    /*
    * @dev Sends a fee before reflections.
    */
    function sendFeeTo(address account, uint128 tAmount, uint128 rate) internal virtual {
        if (tAmount > 0) {
            unchecked {
                _balances[account].rOwned += (tAmount * rate);         
                if (_balances[account].isExcluded) { 
                    _balances[account].tOwned += tAmount;
                }
            }
        }
    }

    function _setRewardStatus(address account, bool include) internal virtual {
        if (include != _balances[account].isExcluded) { 
            revert INVALID_STATUS(account, include);
        }
        if (include) { 
            uint256 len = _rExcluded.length;    
            unchecked {
                for (uint256 i; i < len; ++i) {
                    if (_rExcluded[i] == account) {
                        _rExcluded[i] = _rExcluded[len - 1]; // swap with last and pop
                        _rExcluded.pop();
                        _balances[account].tOwned = 0; 
                        _balances[account].isExcluded = false;
                        break;
                    }
                }
            }
        } else { 
            // require(account != 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, 'We can not exclude Uniswap router.');
            // yes we can
            if (_balances[account].rOwned > 0) { 
                _balances[account].tOwned = tokenFromReflection(_balances[account].rOwned);
            }
            _rExcluded.push(account); 
            _balances[account].isExcluded = true;
        }
    }

    // uint8 internal immutable _reflectionTax;
    // function excludeFromReward(address account) public virtual onlyOwner { _setRewardStatus(account, false); }
    // function includeInReward(address account) external virtual onlyOwner { _setRewardStatus(account, true); }
    // function setReflectionTaxPercent(uint percent) public virtual onlyOwner { _reflectionTaxPercent = percent; }
    /* 
    function _transfer(address from, address to, uint amount, bool isFeeExempt) internal virtual override {
        uint256 tReflected; // 0
        if (!(isFeeExempt || _isFeeExempt[from] || _isFeeExempt[to])) {
            tReflected = (amount * _reflectionTax) / 100;
        }
        uint128 rate = _transferSupportingFee(from, to, amount, (amount - tReflected));

        /// NOTE: rate is the same until `reflect()` is called, so no recalculation is necessary
        if (tReflected > 0) { 
            reflectToHolders(uint128(tReflected), rate);
        }
    } 
    */
}
