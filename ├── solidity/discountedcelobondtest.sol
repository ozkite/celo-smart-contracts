// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract DiscountedCeloBond is Ownable {
    using SafeERC20 for IERC20;

    // === TOKENS ===
    IERC20 public constant CELOR = IERC20(0x471EcE3750Da237f93B8E339c536989b8978a438); // CELO on Celo
    IERC20 public constant cUSD = IERC20(0x765De81684586Fae26300Gc7aEd2Df4Aed21EdC9); // cUSD

    // === BOND PARAMETERS ===
    uint256 public constant DISCOUNT_RATE = 30; // 30% discount
    uint256 public constant BOND_DURATION = 365 days; // 12 months
    uint256 public bondStart;
    uint256 public bondEnd;

    // === PRICING ===
    uint256 public celoPriceInCUSD; // e.g., 1 CELO = 1.2 cUSD (set by owner)
    bool public priceSet = false;

    // === USER BONDS ===
    struct Bond {
        uint256 amount; // CELO to receive
        uint256 paid;   // cUSD or CELO paid
        uint256 purchaseTime;
        bool redeemed;
    }

    mapping(address => Bond) public bonds;
    uint256 public totalBonds;
    uint256 public totalRaised;

    // === EVENTS ===
    event BondPurchased(address indexed user, uint256 celoAmount, uint256 paidAmount, uint256 timestamp);
    event BondRedeemed(address indexed user, uint256 amount);
    event PriceSet(uint256 price);
    event Withdraw(address indexed token, address indexed to, uint256 amount);

    // === MODIFIERS ===
    modifier bondActive() {
        require(block.timestamp >= bondStart && block.timestamp < bondEnd, "Bond not active");
        _;
    }

    modifier bondEnded() {
        require(block.timestamp >= bondEnd, "Bond not yet ended");
        _;
    }

    // === CONSTRUCTOR ===
    constructor() {
        bondStart = block.timestamp;
        bondEnd = bondStart + BOND_DURATION;
    }

    // === SET MARKET PRICE (Owner Only) ===
    function setCELOPrice(uint256 priceInCUSD) external onlyOwner {
        require(!priceSet, "Price already set");
        celoPriceInCUSD = priceInCUSD;
        priceSet = true;
        emit PriceSet(priceInCUSD);
    }

    // === PURCHASE BOND WITH cUSD ===
    function purchaseWithcUSD(uint256 celoAmount) external bondActive {
        require(priceSet, "Price not set");

        // Calculate discounted price
        uint256 effectivePrice = celoPriceInCUSD * (100 - DISCOUNT_RATE) / 100; // 30% off
        uint256 totalcUSD = celoAmount * effectivePrice / 1e18;

        require(totalcUSD > 0, "Invalid amount");

        cUSD.safeTransferFrom(msg.sender, address(this), totalcUSD);

        // Record bond
        Bond storage bond = bonds[msg.sender];
        require(bond.amount == 0, "Already has a bond"); // One bond per user (simplified)

        bond.amount = celoAmount;
        bond.paid = totalcUSD;
        bond.purchaseTime = block.timestamp;
        bond.redeemed = false;

        totalBonds += celoAmount;
        totalRaised += totalcUSD;

        emit BondPurchased(msg.sender, celoAmount, totalcUSD, block.timestamp);
    }

    // === PURCHASE BOND WITH CELO (Alternative) ===
    function purchaseWithCELO(uint256 celoAmount) external bondActive {
        require(priceSet, "Price not set");

        uint256 effectivePrice = celoPriceInCUSD * (100 - DISCOUNT_RATE) / 100;
        uint256 valueInCELO = (celoAmount * effectivePrice) / celoPriceInCUSD;

        require(valueInCELO > 0, "Invalid amount");

        CELOR.safeTransferFrom(msg.sender, address(this), valueInCELO);

        Bond storage bond = bonds[msg.sender];
        require(bond.amount == 0, "Already has a bond");

        bond.amount = celoAmount;
        bond.paid = valueInCELO;
        bond.purchaseTime = block.timestamp;
        bond.redeemed = false;

        totalBonds += celoAmount;
        totalRaised += valueInCELO;

        emit BondPurchased(msg.sender, celoAmount, valueInCELO, block.timestamp);
    }

    // === REDEEM BOND AFTER 12 MONTHS ===
    function redeem() external bondEnded {
        Bond storage bond = bonds[msg.sender];
        require(bond.amount > 0, "No bond to redeem");
        require(!bond.redeemed, "Already redeemed");

        bond.redeemed = true;
        CELOR.safeTransfer(msg.sender, bond.amount);

        emit BondRedeemed(msg.sender, bond.amount);
    }

    // === WITHDRAW FUNDS (After bond ends) ===
    function withdraw(address token, address to, uint256 amount) external onlyOwner {
        require(block.timestamp >= bondEnd, "Bond period not over");
        IERC20(token).safeTransfer(to, amount);
        emit Withdraw(token, to, amount);
    }

    // === GET BOND VALUE ===
    function getBondValue(address user) external view returns (uint256 amount, uint256 paid, bool canRedeem) {
        Bond memory bond = bonds[user];
        return (bond.amount, bond.paid, (block.timestamp >= bondEnd && !bond.redeemed));
    }
}
