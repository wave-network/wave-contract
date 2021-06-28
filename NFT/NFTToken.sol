// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";


contract WaveNFTToken is ERC721, ERC721Enumerable, ERC721URIStorage, Pausable, AccessControl {
    using Counters for Counters.Counter;
    using SafeMath for uint256;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant OFFICAL_MINTER_ROLE = keccak256("OFFICAL_MINTER_ROLE");

    Counters.Counter private _tokenIdCounter;
    address public transationFeeReceiever;
    string public payableSymbol;
    bytes32 payableSymbolKeccack;

    struct WaveNFT {
        address createdBy;
        bool forSale;
        string tokenURI;
        mapping (string => uint256) priceInContract;
        mapping (string => bool) symbolPriceExists;
    }
    struct SymbolContract {
        address contractAddress;
        ERC20 ERC20PublicContract;
    }
    mapping (uint256 => WaveNFT) tokenIdToWaveNFT;
    mapping (string => SymbolContract) public symbolToSymbolContract;

    event WaveNFTCreation(address indexed holder, uint256 indexed _tokenId, uint256 price, bool forSale, string symbol);
    event WaveNFTForSale(uint256 indexed _tokenId, uint256 price, string symbol);
    event WaveNFTNotForSale(uint256 indexed _tokenId);
    event WaveNFTSold(address indexed newHolder, uint256 indexed _tokenId, uint256 price, string symbol);


    modifier mustBeValidToken(uint256 _tokenId) {
        require(_tokenId >= 1 && _tokenId <= totalSupply(), "tokenId must exists");
        _;
    }

    modifier mustBeTokenOwner(uint256 _tokenId) {
        require(ownerOf(_tokenId) == msg.sender, "tokenId must belong to the owner");
        _;
    }

    modifier mustBeForSale(uint256 _tokenId) {
        require(tokenIdToWaveNFT[_tokenId].forSale == true, "tokenId must be for sale");
        _;
    }
    
    modifier mustHaveTransationFeeReceiever() {
        require(transationFeeReceiever != address(0), "transationFeeReceiever not yet exists");
        _;
    }
    
    modifier mustHaveSymbolExists(string memory symbol) {
        if (keccak256(abi.encode(symbol)) != payableSymbolKeccack) {
            require(symbolToSymbolContract[symbol].contractAddress != address(0), "such ERC20 token not supported");
        }
        _;
    }
    
    modifier mustSymbolPriceExists(string memory symbol, uint256 _tokenId) {
        require(tokenIdToWaveNFT[_tokenId].symbolPriceExists[symbol] == true, "no symbol price");
        _;
    }
    
    modifier mustBeValidAddress(address _address) {
        require(_address != address(0) && _address != address(this), "please set a valid address");
        _;
    }

    constructor(string memory _payableSymbol) ERC721("WaveNFT", "WAV2") {
        payableSymbol = _payableSymbol;
        payableSymbolKeccack = keccak256(abi.encode(payableSymbol));
        
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(PAUSER_ROLE, msg.sender);
        _setupRole(OFFICAL_MINTER_ROLE, msg.sender);
    }
    
    
    function addERC20PublicContract(string memory symbol, address contractAddress) 
        public
        mustBeValidAddress(contractAddress)
    {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        require(contractAddress != address(0), "address(0) is invalid");
        
        symbolToSymbolContract[symbol] = SymbolContract({
            contractAddress: contractAddress,
            ERC20PublicContract: ERC20(contractAddress)
        });
    }

    // safeMint will fail due to same event emission on remix: https://github.com/ethereum/remix-project/issues/1242
    // every one can mint but some people mint officical recognized NFTs
    function safeMint(uint256 price, bool forSale, string memory _tokenURI, string memory symbol) 
        public 
        whenNotPaused
        mustHaveSymbolExists(symbol)
        returns
        (uint256)
    {
        require(price > 0, "price must bigger than zero");
        _tokenIdCounter.increment();

        uint256 _newTokenId = _tokenIdCounter.current();

        _safeMint(msg.sender, _newTokenId);
        _setTokenURI(_newTokenId, _tokenURI);
        
        WaveNFT storage newWaveNFT = tokenIdToWaveNFT[_newTokenId];
        
        newWaveNFT.forSale = forSale;
        newWaveNFT.tokenURI = _tokenURI;
        newWaveNFT.createdBy = msg.sender;
        newWaveNFT.priceInContract[symbol] = price;
        newWaveNFT.symbolPriceExists[symbol] = true; 
        
        if (forSale == true) {
            approve(address(this), _newTokenId);
        }
        emit WaveNFTCreation(msg.sender, _newTokenId, price, forSale, symbol);

        return _newTokenId;
    }
    

    function setTokenforSale(uint256 _tokenId, uint256 price, string memory symbol)
        external
        whenNotPaused
        mustBeValidToken(_tokenId)
        mustBeTokenOwner(_tokenId)
        mustHaveSymbolExists(symbol)
    {
        // delegate contract the right to sell 
        require(price > 0, "price must bigger than zero");
        approve(address(this), _tokenId);
        
        tokenIdToWaveNFT[_tokenId].priceInContract[symbol] = price;
        tokenIdToWaveNFT[_tokenId].forSale = true;
        tokenIdToWaveNFT[_tokenId].symbolPriceExists[symbol] = true;

        emit WaveNFTForSale(_tokenId, price, symbol);
    }
    
    function setTransationFeeReceiever(address _transationFeeReceiever)
        external
        mustBeValidAddress(_transationFeeReceiever)
        whenNotPaused
    {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender));
        transationFeeReceiever = _transationFeeReceiever;
    }
    
    function buyTokenViaSend (uint256 _tokenId)
        public
        payable
        whenNotPaused
        mustBeValidToken(_tokenId)
        mustBeForSale(_tokenId)
        mustHaveTransationFeeReceiever
        mustSymbolPriceExists(payableSymbol, _tokenId)
        returns (bool)
    {   
        address buyer = msg.sender;
        require(buyer != ownerOf(_tokenId) && buyer != address(0) && buyer != address(this), "invalid buyer");
        uint256 forSalePrice = tokenIdToWaveNFT[_tokenId].priceInContract[payableSymbol];
        require(forSalePrice > 0, "price zero not supported");        
        require(msg.value >= forSalePrice, "buying amount must be higher than token forSalePrice");
        
        uint256 transationFee = uint256(msg.value).mul(5).div(100);

        payable(ownerOf(_tokenId)).transfer(uint256(msg.value).sub(transationFee));
        if (transationFee != 0) {
            payable(transationFeeReceiever).transfer(transationFee);
        }
        
        this.safeTransferFrom(ownerOf(_tokenId), buyer, _tokenId);

        tokenIdToWaveNFT[_tokenId].priceInContract[payableSymbol] = msg.value;
        tokenIdToWaveNFT[_tokenId].forSale = false;
        emit WaveNFTSold(buyer, _tokenId, forSalePrice, payableSymbol);
        return true;
        
    } 

    function buyToken(uint256 _tokenId, uint256 amount, string memory symbol)
        external
        whenNotPaused
        mustBeValidToken(_tokenId)
        mustBeForSale(_tokenId)
        mustHaveTransationFeeReceiever
        mustSymbolPriceExists(symbol, _tokenId)
        returns (bool)
    {
        require(msg.sender != ownerOf(_tokenId) && msg.sender != address(0) && msg.sender != address(this), "invalid buyer");
        
        require(symbolToSymbolContract[symbol].contractAddress != address(0), "contract not exists");
        ERC20 ERC20PublicContract = symbolToSymbolContract[symbol].ERC20PublicContract;

        uint256 forSalePrice = tokenIdToWaveNFT[_tokenId].priceInContract[symbol];
        require(forSalePrice > 0, "price zero not supported");
        
        require(amount >= forSalePrice, "buying amount should higher than forSalePrice");
        require(ERC20PublicContract.allowance(msg.sender, address(this)) >= amount, "must set allowance");
        
        uint256 transationFee = amount.mul(5).div(100);
        require(
            ERC20PublicContract.transferFrom(msg.sender, ownerOf(_tokenId), amount.sub(transationFee))
            && ERC20PublicContract.transferFrom(msg.sender, transationFeeReceiever, transationFee),
            "Both transcations must be successful"
        );
        
        this.safeTransferFrom(ownerOf(_tokenId), msg.sender, _tokenId);

        tokenIdToWaveNFT[_tokenId].priceInContract[symbol] = amount;
        tokenIdToWaveNFT[_tokenId].forSale = false;
        emit WaveNFTSold(msg.sender, _tokenId, forSalePrice, symbol);
        return true;
    }
    

    function removeForSale(uint256 _tokenId)
        external
        whenNotPaused
        mustBeValidToken(_tokenId)
        mustBeForSale(_tokenId)
        mustBeTokenOwner(_tokenId)
    {
        // destory approval
        approve(address(0), _tokenId);
        tokenIdToWaveNFT[_tokenId].forSale = false;

        emit WaveNFTNotForSale(_tokenId);
    }
    
    function getWaveNFTInfo(uint256 _tokenId, string memory symbol)
        external
        view
        mustBeValidToken(_tokenId)
        mustHaveSymbolExists(symbol)
        returns(uint256, bool, string memory, bool, address)
    {
        return (
            tokenIdToWaveNFT[_tokenId].priceInContract[symbol],
            tokenIdToWaveNFT[_tokenId].forSale, 
            tokenIdToWaveNFT[_tokenId].tokenURI,
            tokenIdToWaveNFT[_tokenId].symbolPriceExists[symbol],
            tokenIdToWaveNFT[_tokenId].createdBy
        );
    }
    
    
    function pause() public {
        require(hasRole(PAUSER_ROLE, msg.sender));
        _pause();
    }

    function unpause() public {
        require(hasRole(PAUSER_ROLE, msg.sender));
        _unpause();
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId)
        internal
        whenNotPaused
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}