
/** SPDX-License-Identifier: MIT
    @author J. W.
    @title BEP21.sol
*/

pragma solidity 0.8.21;

/** @dev Interface of the BEP20 standard. @custom:ref https://github.com/bnb-chain/BEPs/blob/master/BEPs/BEP20.md */
interface IBEP20 {

    event Approval (address indexed owner, address indexed spender, uint Lunari); 
    event Transfer (address indexed from, address indexed to, uint Lunari);

    function decimals() external view returns (uint8);             /// @dev Returns the token decimals.
    function getOwner() external view returns (address payable);   /// @dev Returns the BEP-20 token owner.
    function name()     external view returns (string memory);     /// @dev Returns the token name.
    function symbol()   external view returns (string memory);     /// @dev Returns the token symbol.
    function totalSupply() external view returns (uint);           /// @dev Returns the (current) amount of unburned tokens in existence.
    
    function allowance(address holder, address spender) external view returns (uint remaining);   /// @dev Returns the spender allowance allocated by holder.
    function approve(address spender, uint Lunari) external returns (bool success);               /// @dev Allocates an allowance to `spender` from caller.
    function balanceOf(address account) external view returns (uint Lunari);                      /// @dev Returns the token balance of a given address.
    function transfer(address to, uint Lunari) external returns (bool success);                   /// @dev Transfers balance from caller to `to`.
    function transferFrom(address from, address to, uint Lunari) external returns (bool success); /// @dev Transfers an approved balance from `from` to `to`.

}

/** @dev Interface extending the BEP20 standard. */
interface IBEP21 is IBEP20 {

    error InsufficientBalance(uint by);
    error InsufficientAllowance(uint attempted, uint allowance);
    error InvalidApproval();
    error InvalidTransfer();
    error InvalidBalance();
    error InvalidTransferAmount();

    event Burn(address indexed from, uint indexed amount);             /// @dev Default burn address is 0x000000000000000000000000000000000000dEaD.

    function getThis()       external view returns (address payable);  /// @dev Returns the token contract address `address(this)`. {immutable}
    function releaseDate()   external view returns (uint40);           /// @dev Returns the token blockchain genesis date in UNIX epoch time. {immutable}
    function releaseSupply() external view returns (uint);             /// @dev Returns the initial token supply at creation, with decimals. {immutable | constant}
    function version()       external view returns (string memory);    /// @dev Returns the token contract build version.
    function burn(uint Lunari) external returns (bool success);        /// @dev Burns the specified amount from caller's account. Reduces total supply.

}

abstract contract Context {

    function _msgSender() internal view virtual returns (address payable) { 
        return payable(msg.sender);
    }
    function _msgData() internal view virtual returns (bytes calldata) { 
        return msg.data;
    }
    function _txOrigin() internal view virtual returns (address payable) {
        return payable(tx.origin);
    }

}

/** @dev Contract module which provides an intermediate access control mechanism, where there is an account (an owner)
    that can be granted exclusive access to specific functions. By default, the owner account will be the one that deploys the contract.
    This can later be changed with {transferOwnership}. This module is used through inheritance. 
    It will make available the modifier `onlyOwner`, which can be applied to your functions to restrict their use to the owner.
    @custom:version 3.1
 */ 
abstract contract Ownable is Context {

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event AccessLowered(address indexed owner, uint8 indexed access, uint indexed timestamp);

    error NoAccess();
    error Unauthorized();
    error IncorrectPIN();

    /// @dev Initializes the contract setting the deployer as the initial owner.
    constructor() payable { 
        _transferOwnership(_msgSender());
    }

    address payable public owner; // => owner()
    address payable private oldOwner;
    uint8 public ownerAccess = 3; /// @dev Internal variable for tiered owner privileges.

    modifier access(uint8 level) {
        if (ownerAccess < level) { revert NoAccess(); }
        _;
    }

    /// @dev Throws if called by any account other than the owner, or if owner has renounced ownership.
    modifier onlyOwner {
        _checkOwner();
        _;
    }

    /// @dev Throws if PIN does not match the keccak256 encoded hash (hardcoded by owner before deployment).
    modifier passcode(string calldata PIN) {
        _checkPIN(PIN);
        _;
    }

    function _checkOwner() internal view virtual {
        if (_msgSender() != owner || owner == address(0)) { revert Unauthorized(); }
    }

    function _checkPIN(string calldata PIN) internal view virtual {
        if (keccak256(abi.encode(PIN)) != 0x1a3de7f8fee736ca6a61818e30cd3f87f1f33473225476af28ae8c1a0786c7eb) { 
            revert IncorrectPIN();
        }
    }

    /// @dev Lowers access level for the owner. Once lowered it cannot be increased.
    function lowerOwnerAccess() external onlyOwner returns (uint8) {
        emit AccessLowered(owner, ownerAccess-1, block.timestamp);
        return --ownerAccess;
    }

    /** @dev Transfers ownership of the contract to a new account (`newOwner`). Can only be called by the current owner.
     * Will also leave any tokens owned, in possession of the previous owner.
     * Note: transferring to a dead address will leave the contract without an owner (thereby renouncing ownership).
     * Renouncing ownership will effectively leave the contract without an owner, thereby removing any functionality that is only available to the owner.
    */
    function transferOwnership(address newOwner, string calldata PIN) passcode(PIN) external onlyOwner {
        _transferOwnership(newOwner);
    }

    /// @dev Transfers ownership of the contract to a new account (`newOwner`). Internal function without access restriction.
    function _transferOwnership(address newOwner) private {
        (oldOwner, owner) = (payable(owner), payable(newOwner));
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

/** @custom:source OpenZeppelin (ReentrancyGuard.sol), with minor edits. 
    @custom:license MIT
    @dev Contract module that helps prevent reentrant calls to a function. Inheriting from `Idempotent` will make the {idempotent} modifier available, 
    which can be applied to functions to make sure there are no nested (reentrant) calls to them.
*/
abstract contract Idempotent {

    constructor() { status = NOT_ENTERED; }

    // Booleans are more expensive than uint256 or any type that takes up a full word because each write operation
    // emits an extra SLOAD to first read the slot's contents, replace the bits taken up by the boolean, and then write back.
    // This is the compiler's defense against contract upgrades and pointer aliasing, and it cannot be disabled.

    uint private constant NOT_ENTERED = 1; // Setting to 0 increases gas cost back to a boolean.
    uint private constant ENTERED = 2;
    uint private status; 

    error NoReentry(); // Custom errors are cheaper in gas than require(condition, string)
    
    modifier idempotent {

        if (status == ENTERED) { revert NoReentry(); }
        status = ENTERED; // Any calls to {idempotent} after this point will fail.
        _; 
        status = NOT_ENTERED; /// By storing the original value once again, a refund is triggered. See @custom:ref https://eips.ethereum.org/EIPS/eip-2200
    }
}


/** @author J. W.
    @dev Advanced customizable BEP20 token generation framework. @custom:ref https://github.com/bnb-chain/BEPs/blob/master/BEPs/BEP20.md
*/
abstract contract BEP21 is IBEP20, IBEP21, Ownable, Idempotent {

    /// @dev Initializes the token contract metadata via child constructor.
    constructor(TokenData memory Token) {
  
        (NULL, BURN, THIS) = (payable(0), payable(address(57005)), payable(address(this)));

        (_name, _symbol, _version, decimals) = (Token.name, Token.symbol, Token.version, Token.decimals);

        releaseDate = uint40(block.timestamp);
        releaseSupply = balances[_msgSender()] = _totalSupply = _pow10(Token.totalSupply, decimals);

        emit Transfer(NULL, _msgSender(), releaseSupply);
    }

    struct TokenData { 
        bytes32 name; bytes32 symbol; bytes32 version; uint8 decimals; uint totalSupply;
    }
   
    mapping (address holder => mapping (address spender => uint allotment)) internal allowances;
    mapping (address user => uint balance) internal balances;

    /** @custom:ref https://docs.soliditylang.org/en/v0.8.21/contracts.html#getter-functions
     *  NOTE: The Solidity compiler automatically generates external view functions for public variables.
     *  NOTE: Solidity ~0.8.20 does not support immutable strings, so bytes32 is used as a workaround.
     *  NOTE: Encoding immutable bytes32 loses ~200 gas compared to `string public constant name = {name}`, but saves 2000 runtime gas over 
     *  non-immutable implementations, and allows for dynamic customization in child constructor. */

    address payable internal immutable NULL; // 0x0000000000000000000000000000000000000000
    address payable internal immutable BURN; // 0x000000000000000000000000000000000000dEaD
    address payable internal immutable THIS; // 0x(address(this))

    bytes32 private immutable _name; 
    bytes32 private immutable _symbol;
    bytes32 private immutable _version;
    
    uint256 internal _totalSupply;
    
    uint8   public immutable decimals;      /// @dev See {IBEP20-decimals}.
    uint40  public immutable releaseDate;   /// @dev See {IBEP21-releaseDate}.
    uint256 public immutable releaseSupply; /// @dev See {IBEP21-releaseSupply}.

    /// @dev See {IBEP20-totalSupply}.
    function totalSupply() public view virtual returns (uint) { return _totalSupply; }

    /// @dev See {IBEP20-getOwner}.
    function getOwner() public view virtual returns (address payable) { return payable(owner); } 
    
    /// @dev See {IBEP21-getThis}.
    function getThis() public view virtual returns (address payable) { return THIS; }

    /// @dev See {IBEP20-name}.
    function name() public view virtual returns (string memory) { return string(abi.encodePacked(_name)); }

    /// @dev See {IBEP20-symbol}.
    function symbol() public view virtual returns (string memory) { return string(abi.encodePacked(_symbol)); } 

    /// @dev See {IBEP21-version}.
    function version() public view virtual returns (string memory) { return string(abi.encodePacked(_version)); } 


    /// @dev See {IBEP20-allowance}.
    function allowance(address holder, address spender) public view virtual returns (uint remaining) {
        return allowances[holder][spender];
    }

    /// @dev See {IBEP20-approve}.
    function approve(address spender, uint limit) public virtual returns (bool approval) { 
        return _approve(_msgSender(), spender, limit);
    }

    /// @dev See {IBEP20-balanceOf}.
    function balanceOf(address account) public view virtual returns (uint Lunari) { 
        return balances[account]; 
    }

    /// @dev See {IBEP21-burn}.
    function burn(uint Lunari) public virtual idempotent returns (bool success) {
        return _transfer(_msgSender(), BURN, Lunari, true);
    }

    /// @dev Atomic approval decrease. Defacto standard.
    function decreaseAllowance(address spender, uint subtractedValue) public virtual returns (bool success) {
        address sender = _msgSender();
        return _approve(sender, spender, (allowance(sender, spender) - subtractedValue)); 
    }

    /// @dev Atomic approval increase. Defacto standard.
    function increaseAllowance(address spender, uint addedValue) public virtual returns (bool success) {
        address sender = _msgSender();
        return _approve(sender, spender, (allowance(sender, spender) + addedValue));
    }

    /// @dev See {BEP20-transfer}.
    function transfer(address to, uint amount) public virtual idempotent returns (bool success) { 
        return _transfer(_msgSender(), to, amount, false); 
    }

    /// @dev See {BEP20-transferFrom}.
    function transferFrom(address from, address to, uint Lunari) public virtual idempotent returns (bool success) {
        address sender = _msgSender();
        uint limit = allowance(from, sender); // An account can only spend the allowance delegated to it. Default allowance is 0.
        if (Lunari > limit) {
            revert InsufficientAllowance({ attempted: Lunari, allowance: limit });
        }
        unchecked { 
            _approve(from, sender, (limit - Lunari)); // decreaseAllowance(from, Lunari);
        } 
        return _transfer(from, to, Lunari, false);
    }
    
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////// Internal Virtual Implementation Functions ////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function _pow10(uint x, uint8 _decimals) internal pure virtual returns (uint) { 
        unchecked { return x * (10 ** _decimals); }
    }

    /// @dev Internal virtual implementation of `approve()`.
    function _approve(address holder, address spender, uint limit) internal virtual returns (bool) {
        if (holder == NULL || holder == BURN || spender == NULL || spender == BURN) { revert InvalidApproval(); }
        allowances[holder][spender] = limit;
        emit Approval(holder, spender, limit);   
        return true;
    }

    /// @dev Internal virtual implementation of `transfer()`
    function _transfer(address from, address to, uint amount) internal virtual returns (bool) {
        return _transfer(from, to, amount, false);
    }

    /// @dev Internal virtual shadowed implementation of `_transfer()`.
    function _transfer(address from, address to, uint amount, bool) internal virtual returns (bool) {
        _beforeTokenTransfer(from, to, amount);

        balances[from] -= amount;
        balances[to] += amount;

        emit Transfer(from, to, amount);
        _afterTokenTransfer(from, to, amount);
        return true;
    }

    function _beforeTokenTransfer(address from, address to, uint amount) internal virtual {}
    function _afterTokenTransfer (address from, address to, uint amount) internal virtual {}

}


contract YourToken is BEP21 {

    constructor() payable BEP21(
        TokenData({
            name: "YourToken",
            symbol: "YTC",
            version: "1.2.71",
            decimals: 18,
            totalSupply: 1e11
        })
    ) {

    }
}
