// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract CeloLendingPool {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // === TOKENS ===
    IERC20 public constant cUSD = IERC20(0x765De81684586Fae26300Gc7aEd2Df4Aed21EdC9); // Replace with real cUSD address
    IERC20 public collateralToken; // e.g., CELO

    // === POOL STATE ===
    uint256 public totalSupplyBalance;
    uint256 public totalBorrowBalance;
    uint256 public reserveFactor = 25e16; // 25% as percentage in 18 decimals

    // === USER DATA ===
    mapping(address => uint256) public supplyBalanceOf;
    mapping(address => uint256) public borrowBalanceOf;
    mapping(address => uint256) public collateralBalanceOf;

    // === PARAMETERS ===
    uint256 public constant COLLATERAL_RATIO = 25e16; // 25% (in 1e18 precision)

    // === EVENTS ===
    event Supply(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Borrow(address indexed user, uint256 amount);
    event Repay(address indexed user, uint256 amount);
    event Liquidate(address indexed borrower, uint256 collateralAmount, uint256 debtCovered);

    // === CONSTRUCTOR ===
    constructor(address _collateralToken) {
        collateralToken = IERC20(_collateralToken);
    }

    // === SUPPLY cUSD TO THE POOL ===
    function supply(uint256 amount) external {
        require(amount > 0, "Cannot supply 0");

        cUSD.safeTransferFrom(msg.sender, address(this), amount);

        supplyBalanceOf[msg.sender] = supplyBalanceOf[msg.sender].add(amount);
        totalSupplyBalance = totalSupplyBalance.add(amount);

        emit Supply(msg.sender, amount);
    }

    // === WITHDRAW SUPPLIED cUSD ===
    function withdraw(uint256 amount) external {
        require(supplyBalanceOf[msg.sender] >= amount, "Insufficient supply balance");

        cUSD.safeTransfer(msg.sender, amount);

        supplyBalanceOf[msg.sender] = supplyBalanceOf[msg.sender].sub(amount);
        totalSupplyBalance = totalSupplyBalance.sub(amount);

        emit Withdraw(msg.sender, amount);
    }

    // === BORROW cUSD AGAINST COLLATERAL ===
    function borrow(uint256 amount) external {
        uint256 userCollateral = collateralBalanceOf[msg.sender];
        uint256 maxBorrow = userCollateral.mul(1e18).div(COLLATERAL_RATIO);

        require(userCollateral > 0, "No collateral provided");
        require(maxBorrow >= borrowBalanceOf[msg.sender].add(amount), "Exceeds collateral limit");

        cUSD.safeTransfer(msg.sender, amount);

        borrowBalanceOf[msg.sender] = borrowBalanceOf[msg.sender].add(amount);
        totalBorrowBalance = totalBorrowBalance.add(amount);

        emit Borrow(msg.sender, amount);
    }

    // === REPAY BORROWED AMOUNT ===
    function repay(uint256 amount) external {
        require(borrowBalanceOf[msg.sender] >= amount, "Exceeds borrow balance");

        cUSD.safeTransferFrom(msg.sender, address(this), amount);

        borrowBalanceOf[msg.sender] = borrowBalanceOf[msg.sender].sub(amount);
        totalBorrowBalance = totalBorrowBalance.sub(amount);

        emit Repay(msg.sender, amount);
    }

    // === LIQUIDATE UNDERCOLLATERALIZED POSITION ===
    function liquidate(address borrower, uint256 amountToCover) external {
        uint256 debt = borrowBalanceOf[borrower];
        require(debt > 0, "No debt to cover");

        uint256 userCollateral = collateralBalanceOf[borrower];
        uint256 requiredCollateral = amountToCover.mul(COLLATERAL_RATIO).div(1e18);

        require(userCollateral >= requiredCollateral, "Not enough collateral");

        // Transfer collateral and reduce debt
        collateralToken.safeTransfer(msg.sender, requiredCollateral);
        borrowBalanceOf[borrower] = borrowBalanceOf[borrower].sub(amountToCover);

        emit Liquidate(borrower, requiredCollateral, amountToCover);
    }

    // === DEPOSIT COLLATERAL ===
    function depositCollateral(uint256 amount) external {
        require(amount > 0, "Cannot deposit 0");

        collateralToken.safeTransferFrom(msg.sender, address(this), amount);
        collateralBalanceOf[msg.sender] = collateralBalanceOf[msg.sender].add(amount);
    }

    // === WITHDRAW COLLATERAL ===
    function withdrawCollateral(uint256 amount) external {
        uint256 currentCollateral = collateralBalanceOf[msg.sender];
        uint256 currentDebt = borrowBalanceOf[msg.sender];
        uint256 minRequiredCollateral = currentDebt.mul(COLLATERAL_RATIO).div(1e18);

        require(currentCollateral.sub(amount) >= minRequiredCollateral, "Withdrawal would undercollateralize debt");

        collateralToken.safeTransfer(msg.sender, amount);
        collateralBalanceOf[msg.sender] = collateralBalanceOf[msg.sender].sub(amount);
    }
}
