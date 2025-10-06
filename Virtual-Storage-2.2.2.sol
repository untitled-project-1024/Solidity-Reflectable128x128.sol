
/// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.21;

address payable constant NULL = payable(0);
address payable constant BURN = payable(address(57005));

uint256 constant TRUE = 2;
uint256 constant UNTRUE = 1;
uint256 constant FALSE = 0;

error ERC721OutOfBounds(uint index);
error ERC721NonexistentToken(uint tokenID);


/// @dev A library to implement {ERC721Enumerable} with near-arbitrary numbers of contiguous NFTs (supports burning) in solidity 0.8+
/// @author J. W.
/// @custom:version 2.2.2
/// NOTE: Example contract using 'virtual pixel NFTs' was used as a proof of concept.

library VirtualStorage {

    error ERC721VaultUncreatable();
    error ERC721VaultEmpty();
    error ERC721VaultError404(uint NFT);
    error ERC721VaultDuplicate(uint NFT);
    error ERC721VaultInvalidToken(uint NFT);

    /* /// @dev Offset from zero that all NFT token IDs must start from. Token IDs cannot be less than the offset. Offset cannot be zero.
    uint internal constant offset = 1;
    */
    /// @dev Max NFTs returned from a balance query.
    uint internal constant maxfetch = 50;

    /// @notice A virtual array of all the NFTs stored by the contract. 
    struct TokenVault {
        mapping (uint NFT => uint index) tokenToIndex; 
        mapping (uint index => uint NFT) indexToToken;
        mapping (uint NFT => uint Boolean) isBought;
        uint offset; // immutable
        uint releaseSupply; // immutable
        uint length; 
    }

    /// @notice Initializes virtual storage. Can only be run once. NOTE: `from` must be nonzero and `to` must not be less than `from`.
    // NOTE: it is up to you to ensure that your token IDs do not overlap.

    function create(TokenVault storage Phantom, uint from, uint to) internal {  unchecked  {
        if (Phantom.releaseSupply != 0 || from == 0 || to < from) { 
            revert ERC721VaultUncreatable();
        }
        Phantom.offset = from;
        Phantom.length = Phantom.releaseSupply = (to - from) + 1;
    }}

    function mint(TokenVault storage Phantom, uint amount) internal {}

    function at(TokenVault storage Phantom, uint index) internal view returns (uint tokenID) {  unchecked  {
        if (index >= Phantom.length) {
            revert ERC721OutOfBounds(index);        
        }
        index += Phantom.offset;
        tokenID = Phantom.indexToToken[index]; // defaults to zero
        return (tokenID != 0) ? tokenID : index;
    }}

    function wasCreated(TokenVault storage Phantom, uint tokenID) internal view returns (bool) {  unchecked  {
        return (tokenID >= Phantom.offset) && (tokenID < (Phantom.offset + Phantom.releaseSupply));
    }}

    // WILL NOT revert on invalid tokenID queries
    function contains(TokenVault storage Phantom, uint NFT) internal view returns (bool) {
        return wasCreated(Phantom, NFT) && (Phantom.isBought[NFT] == FALSE);
    }

    // Returns up to 50 TokenIDs owned by `account`. For accounts with more than 100 NFTs, retrieve the events and store them off-chain.
    function retrieve(TokenVault storage Phantom) internal view returns (uint[] memory nfts, uint numberOfNFTS, string memory ErrorMessage) {  unchecked  {
        numberOfNFTS = Phantom.length;
        if (numberOfNFTS <= maxfetch) {
            nfts = new uint[](numberOfNFTS);
            for (uint i; i < numberOfNFTS; ++i) {
                nfts[i] = VirtualStorage.at(Phantom,i);
            }
            return (nfts, numberOfNFTS, "");
        } else {
            return (new uint[](0), numberOfNFTS, "Web3 indexing required.");
        }
        // return array from storage vs memory uint[] storage nfts
    }}
    // retrieve(50) fetchFromStartingIndex(50)

    // If you're carelessly using values at or near ~uint(0), then you deserve what happens.
    function remove(TokenVault storage Phantom, uint tokenID) internal {  unchecked  {
        if (Phantom.length == 0) {
            revert ERC721VaultEmpty();
        }
        if (!contains(Phantom, tokenID)) { // ensure the NFT was created and also exists in virtual storage.
            revert ERC721VaultError404(tokenID);
        }

        // 1. Get the last valid index of of the mapping(s).      
        // 2. What's the stored index of this tokenID? 
        // 3. What's the current tokenID stored at the last virtual index? 
        uint lastIndex = Phantom.offset + (Phantom.length - 1);
        uint currentIndex = Phantom.tokenToIndex[tokenID];  
        uint tokenIDAtLastIndex = Phantom.indexToToken[lastIndex];

        // If currentIndex (tokenToIndex) is 0, it is the default value, where currentIndex IS the token ID.
        if (currentIndex == 0) {
            Phantom.tokenToIndex[tokenID] = currentIndex = tokenID; 
        }
        // If tokenID at last index is 0, tokenIDAtLastIndex is unset, and therefore must match lastIndex
        if (tokenIDAtLastIndex == 0) {
            Phantom.indexToToken[lastIndex] = tokenIDAtLastIndex = lastIndex; 
        }

        // Swap locations in virtual array
        (Phantom.tokenToIndex[tokenIDAtLastIndex], Phantom.indexToToken[currentIndex]) = (currentIndex, tokenIDAtLastIndex);
        (Phantom.tokenToIndex[tokenID], Phantom.indexToToken[lastIndex]) = (lastIndex, tokenID);
        
        Phantom.isBought[tokenID] = TRUE;

        --Phantom.length; // "pop" the array.
    }}

    // In this version, we will only allow adding previously minted virtual tokens back to virtual storage. 
    function add(TokenVault storage Phantom, uint tokenID) internal {  unchecked  {
        if (!wasCreated(Phantom, tokenID)) {
            revert ERC721NonexistentToken(tokenID);
        }
        if (contains(Phantom, tokenID)) {
            revert ERC721VaultDuplicate(tokenID);
        }

        ++Phantom.length;

        uint lastIndex = Phantom.offset + (Phantom.length - 1);

        Phantom.indexToToken[lastIndex] = tokenID;
        Phantom.tokenToIndex[tokenID] = lastIndex;

        Phantom.isBought[tokenID] = FALSE;
    }}

    function transferFromVirtualStorage() internal {}
    function transferToVirtualStorage() internal {}
}

abstract contract ERC721Errors {

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


/// @dev Example contract using VirtualStorage.sol
contract Fractional is Context {

    using VirtualStorage for VirtualStorage.TokenVault;

    address payable public immutable THIS;

    constructor() {
        THIS = payable(address(this));
        TokenVault.create({ from: 1234, to: 812032358201232011199264888 }); // AllTokensIndex.create( InitialNFTSupply );
    }

    /// @notice All tokens owned by address(this)
    VirtualStorage.TokenVault private TokenVault; // VirtualStorage.TokenVault private AllTokensIndex; // All existing tokens.

    error ERC721VaultInvalidBuyer();
    error ERC721VaultMissingToken(uint NFT);

    mapping (uint NFT => address owner) internal owners;
    mapping (address owner => uint[] NFT_Collection)  internal balances;
    mapping (address owner => mapping(uint => uint)) internal keymap;
    
    uint internal constant TOTAL_NFT_SUPPLY = 10;
    uint internal immutable offset = TokenVault.offset;

    // test functions
    function removeFromVirtualStorage(uint NFT) public { 
        TokenVault.remove(NFT);
    }
    function addToVirtualStorage(uint NFT) public { 
        TokenVault.add(NFT);
    }
    function contains(uint NFT) public view returns (bool) {
        return TokenVault.contains(NFT);
    }

    function buyPixelFromTokenVault(uint NFT) public payable returns (bool success) {
        address payable self = _msgSender();
        if (self == THIS) { 
            revert ERC721VaultInvalidBuyer();
        }
        if (TokenVault.contains(NFT)) {
            TokenVault.remove(NFT); 
            // swapStorage(self, tokenID);
            return true;
        } else {
            revert ERC721VaultMissingToken(NFT);
        }
    }

    function retrieveAll() public view returns (uint[] memory nfts, uint, string memory) {
        return TokenVault.retrieve(/*50*/); // retrieveAll(50,100)
    }

    function wasBought(uint NFT) internal view returns (uint) {
       return TokenVault.isBought[NFT];
    }

    /// @notice determines if a token ID was created, virtually or otherwise
    function wasCreated(uint NFT) internal view virtual returns (bool) {
        return TokenVault.wasCreated(NFT);
    }

    function exists(uint NFT) internal view virtual returns (bool) { return (ownerOf(NFT) != NULL); }

    /// @notice Determines the owner of a token. Implicit return.
    function ownerOf(uint NFT) public view /* isPixel(NFT) */ virtual returns (address NFTOwner) {
        if (TokenVault.contains(NFT)) {
            return address(this);
        }
        if ((NFTOwner = owners[NFT]) == NULL) { /// if it's not in the vault and the owner is STILL address(0), the NFT no longer exists or has never existed.
            revert ERC721NonexistentToken(NFT);
        }
    }

    /**
     * @dev See {IERC721Enumerablae-tokenOfOwnerByIndex}.
     */
    function tokenOfOwnerByIndex(address account, uint index) public view returns (uint) {
        if (account == address(this)) {
            return TokenVault.at(index);
        }
        if (index >= balances[account].length) {
            revert ERC721OutOfBounds(index);
        }
        return balances[account][index];
    }

    /**
     * @dev See {IERC721Enumerable-totalSupply}.
     */
    function totalSupply() public pure returns (uint) {
        return TOTAL_NFT_SUPPLY; // return AllTokensIndex.length;
    }

    /**
     * @dev See {IERC721Enumerable-tokenByIndex}.
     */
    function tokenByIndex(uint index) public view returns (uint) {
        if (index >= TOTAL_NFT_SUPPLY) { 
            revert ERC721OutOfBounds(index); // return AllTokensIndex.at(index);
        }
        return index + offset;
    }

    function wasBoughtFromTokenVault(uint tokenID) isPixel(tokenID) internal view returns (bool) {
        return !TokenVault.contains(tokenID);
    } 

    modifier isPixel(uint tokenID) { 
        _checkBounds(tokenID); 
        _;
    }

    function _checkBounds(uint NFT) private view { if (!TokenVault.wasCreated(NFT)) { revert ERC721NonexistentToken(NFT); } }
}
