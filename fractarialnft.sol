// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CeloFractionalNFT (ERC-404-Inspired)
 * @dev Hybrid ERC-20 + ERC-721 for fractional NFTs on Celo
 * When a user has >= 1 full token, they get an NFT.
 * If balance drops below, NFT is burned.
 */
contract CeloFractionalNFT is ERC20, ERC721, Ownable {
    uint256 public constant FULL_TOKEN = 1e18; // 1 full unit
    uint256 public nftCounter = 1;
    mapping(address => uint256) public nftIdOf;
    mapping(address => bool) public hasNFT;

    // Track total NFTs minted
    uint256 public totalNFTs = 0;

    event NFTMinted(address indexed owner, uint256 tokenId);
    event NFTBurned(address indexed owner, uint256 tokenId);
    event FractionUpdated(address indexed user, uint256 newBalance);

    constructor() ERC20("Fractional Art", "FRAC") ERC721("FractionalNFT", "FRAC-NFT") {
        // Mint initial supply to deployer
        _mint(msg.sender, 100 * FULL_TOKEN); // 100 tokens
    }

    // === OVERRIDE transfer TO HANDLE NFT LOGIC ===
    function transfer(address to, uint256 amount) public override returns (bool) {
        super.transfer(to, amount);
        _updateNFT(msg.sender);
        _updateNFT(to);
        emit FractionUpdated(msg.sender, balanceOf[msg.sender]);
        emit FractionUpdated(to, balanceOf[to]);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        super.transferFrom(from, to, amount);
        _updateNFT(from);
        _updateNFT(to);
        emit FractionUpdated(from, balanceOf[from]);
        emit FractionUpdated(to, balanceOf[to]);
        return true;
    }

    // === UPDATE NFT STATUS ===
    function _updateNFT(address account) private {
        bool hadNFT = hasNFT[account];
        bool shouldHaveNFT = balanceOf[account] >= FULL_TOKEN;

        if (hadNFT && !shouldHaveNFT) {
            // Burn NFT
            _burn(nftIdOf[account]);
            delete nftIdOf[account];
            hasNFT[account] = false;
            totalNFTs--;
            emit NFTBurned(account, nftIdOf[account]);
        } else if (!hadNFT && shouldHaveNFT) {
            // Mint NFT
            nftIdOf[account] = nftCounter++;
            _safeMint(account, nftIdOf[account]);
            hasNFT[account] = true;
            totalNFTs++;
            emit NFTMinted(account, nftIdOf[account]);
        }
    }

    // === ALLOW OWNER TO MINT MORE ERC-20 TOKENS ===
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
        _updateNFT(to);
    }

    // === GET NFT BALANCE (only 0 or 1) ===
    function balanceOfNFT(address owner) external view returns (uint256) {
        return hasNFT[owner] ? 1 : 0;
    }

    // === GET TOKEN URI (for NFT metadata) ===
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721: URI query for nonexistent token");
        return "https://ipfs.io/ipfs/Qm..."; // Replace with real IPFS link
    }

    // === WITHDRAW STUCK ETH (for Celo) ===
    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }
}