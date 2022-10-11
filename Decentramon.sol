// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract Decentramon is ERC721A, ReentrancyGuard, Ownable {
    using Counters for Counters.Counter;  
    using Address for address;
    using ECDSA for bytes32;
    
    // Starting and stopping sale // Empezar y parar etapas
    bool public saleActive = false;
    bool public whitelistActive = false;
    bool public vipActive = false;
    bool public forsale = true;

    // Reserved for the team, customs, giveaways, collabs and so on // Reservado para equipo y otros
    uint256 public reserved = 1;

    // Price of each token // Precio inicial mint
    
    uint256 public MINT_PRICE = 0.059 ether; // price
    
    //Retirofondos
    address payable public withdrawWallet;
    // Public Sale Key // Key para verificación extra
    string publicKey; // Will change to hash instead of int
    string public baseExtension = ".json";
    // Maximum limit of tokens that can ever exist // Número de Tokens
    mapping(address => uint256) private mintCountMap;
    mapping(address => uint256) private allowedMintCountMap;
    mapping(address => uint256) public walletMints;
    
    
    uint256 public constant MAX_SUPPLY = 111;
    uint256 public constant MINT_LIMIT_PER_WALLET = 1;

    

    function max(uint256 a, uint256 b) private pure returns (uint256) {
    return a >= b ? a : b;
    }

    function allowedMintCount(address minter) public view returns (uint256) {
        if (saleActive || forsale || whitelistActive || vipActive) {
        return (
            max(allowedMintCountMap[minter], MINT_LIMIT_PER_WALLET) -
            mintCountMap[minter]
        );
        }

        return allowedMintCountMap[minter] - mintCountMap[minter];
    }

    function updateMintCount(address minter, uint256 count) private {
        mintCountMap[minter] += count;
    }

    // The base link that leads to the image / video of the token // URL del arte-metadata
    //string public baseTokenURI =;
    string public baseTokenURI = "";


    // List of addresses that have a number of reserved tokens for whitelist // Lista de direcciones para Whitelist y Raffle
    bytes32 private _whitelistMerkleRoot = 0xdd458cd4186c0d96db060cfdd293d2fc1f1d71350fb5d843be57e716e1fd7025;
    bytes32 private _whitelistPayMerkleRoot = 0xdd458cd4186c0d96db060cfdd293d2fc1f1d71350fb5d843be57e716e1fd7025;
    Counters.Counter private supplyCounter;

    constructor() ERC721A ("Decentramon", "DMON") {
        supplyCounter.increment();
    }

    // Override so the openzeppelin tokenURI() method will use this method to create the full tokenURI instead // Reemplazar URI
    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    // Exclusive whitelist minting // Función mint con Whitelist
    

    function mintWHITElist(bytes32[] memory proof, string memory _pass) public payable nonReentrant {
        uint256 quantity = 1;
        uint256 supply = totalSupply();
        require( forsale,                   "Whitelist isn't active" );
        require(
            MerkleProof.verify(
                proof,
                _whitelistMerkleRoot,
                keccak256(abi.encodePacked(msg.sender))
            ),
            "Whitelist validation failed"
        );
        require( keccak256(abi.encodePacked(publicKey)) == keccak256(abi.encodePacked(_pass)), "Key error"); // Key verifying web3 call // Key que "Verifica" la llamada al contract desde la web3
        require( supply + quantity <= MAX_SUPPLY,    "Can't mint more than WL supply" );
        require( supply + quantity <= MAX_SUPPLY,    "Can't mint more than max supply" );
        require( msg.value == MINT_PRICE * quantity,      "Wrong amount of ETH sent" );
        if (allowedMintCount(msg.sender) >= 1) {
        updateMintCount(msg.sender, 1);
        } else {
        revert("Minting limit exceeded");
        }
        _safeMint( msg.sender, quantity);
        
    }

    // Exclusive VIP whitelist minting // Función mint pago con VIPlist

    function mintVIPlist(bytes32[] memory proof, uint256 quantity, string memory _pass) public payable nonReentrant {
        uint256 supply = totalSupply();
        require( forsale,                   "VIPList isn't active" );
        require(
            MerkleProof.verify(
                proof,
                _whitelistPayMerkleRoot,
                keccak256(abi.encodePacked(msg.sender))
            ),
            "VIPList validation failed"
        );
        require( keccak256(abi.encodePacked(publicKey)) == keccak256(abi.encodePacked(_pass)), "Key error"); // Key verifying web3 call // Key que "Verifica" la llamada al contract desde la web3
        require( quantity > 0,            "Can't mint less than one" );
        require( quantity <= 1,            "Can't mint more than reserved" );
        require( supply + quantity <= MAX_SUPPLY,    "Can't mint more than max supply" );
        require( supply + quantity <= MAX_SUPPLY,    "Can't mint more than max supply" );
        require( msg.value == MINT_PRICE * quantity,      "Wrong amount of ETH sent" );
        if (allowedMintCount(msg.sender) >= 1) {
        updateMintCount(msg.sender, 1);
        } else {
        revert("Minting limit exceeded");
        }
        _safeMint( msg.sender, quantity);
    }


    // Standard mint function // Mint normal sin restricción de dirección

    function mint(uint256 quantity) public payable nonReentrant {
        uint256 supply = totalSupply();
        require( quantity > 0,            "Can't mint less than one" );
        require( quantity <= 1,            "Can't mint more than reserved" );
        require( forsale,                "Sale isn't active" );
        require( msg.value == quantity * MINT_PRICE,    "Wrong amount of ETH sent" );
        require( supply + quantity <= MAX_SUPPLY,    "Can't mint more than max supply" );
        reserved -= quantity;
        _safeMint( msg.sender, quantity );
        require(
            walletMints[msg.sender] + quantity <= MINT_LIMIT_PER_WALLET,
            "Exceed Max Wallet"
        );

      
    }

    // Admin minting function to reserve tokens for the team, collabs, customs and giveaways // Función de minteo de los admins
    function mintReserved(uint256 quantity) public onlyOwner {
        // Limited to a publicly set amount
        uint256 supply = totalSupply();
        require( quantity <= reserved, "Can't reserve more than set amount" );
        require( supply + quantity <= MAX_SUPPLY,    "Can't mint more than max supply" );
        reserved -= quantity;
        _safeMint( msg.sender, quantity );
    }


    function setMerkleWHITELIST(bytes32 root2) public onlyOwner {
        _whitelistMerkleRoot = root2;
    }

    function setMerkleVIP(bytes32 root3) public onlyOwner {
        _whitelistPayMerkleRoot = root3;
    }

    // Start and stop whitelist // Función que activa y desactiva el minteo por Whitelist
    function setWhitelistActive(bool val) public onlyOwner {
        whitelistActive = val;
    }

    // Start and stop raffle // Función que activa y desactiva el minteo vip
    function setVipMint(bool val) public onlyOwner {
        vipActive = val;
    }

    // Start and stop sale // Función que activa y desactiva el minteo por venta genérica
    function setSaleActive(bool val) public onlyOwner {
        saleActive = val;
    }

    function setforsale(bool val) public onlyOwner {
        forsale = val;
    }
    // Set new baseURI // Función para setear baseURI
    function setBaseURI(string memory baseURI) public onlyOwner {
        baseTokenURI = baseURI;
    }
    
    //funcion nueva prueba de inicio token id a partir del 1 
    function _startTokenId() internal view override returns (uint256) {
  return 1;
    }

    // Set public key // Función para cambio de key publica
    function setPublicKey(string memory newKey) public onlyOwner {
        publicKey = newKey;
    }

    function withdraw() public onlyOwner {
    
    (bool os, ) = payable(owner()).call{value: address(this).balance}("");
    require(os);
    // =============================================================================
  }


}
