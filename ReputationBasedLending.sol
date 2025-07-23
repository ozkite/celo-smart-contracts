// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IPassport {
    function getScore(address user) external view returns (uint256);
}

contract ReputationBasedLending {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // === TOKENS ===
    IERC20 public collateralToken; // GLO Dollar
    IERC20 public loanToken;       // e.g., cUSD

    // === PASSPORT VERIFIER ===
    IPassport public gitcoinPassport;
    uint256 public minScore = 30;

    // === LOAN PARAMETERS ===
    uint256 public collateralRatio = 20e16; // 20% (1e18 precision)
    uint256 public loanToValue = 80e16;     // 80% of collateral value

    // === USER LOANS ===
    struct Loan {
        uint256 collateralAmount;
        uint256 loanAmount;
        uint256 startTime;
        bool active;
    }

    mapping(address => Loan) public loans;
    uint256 public totalCollateral;
    uint256 public totalLoans;

    // === EVENTS ===
    event LoanOpened(address indexed borrower, uint256 collateral, uint256 loan);
    event LoanRepaid(address indexed borrower, uint256 loanRepaid);
    event CollateralLiquidated(address indexed borrower, uint256 collateralSeized);

    // === MODIFIER ===
    modifier onlyBorrower(address borrower) {
        require(msg.sender == borrower, "Not borrower");
        _;
    }

    // === CONSTRUCTOR ===
    constructor(
        address _collateralToken,
        address _loanToken,
        address _passportAddress
    ) {
        collateralToken = IERC20(_collateralToken);
        loanToken = IERC20(_loanToken);
        gitcoinPassport = IPassport(_passportAddress);
    }

    // === OPEN LOAN ===
    function openLoan(uint256 collateralAmount) external {
        require(collateralAmount > 0, "Collateral must be > 0");

        // Check Gitcoin Passport Score
        uint256 score = gitcoinPassport.getScore(msg.sender);
        require(score >= minScore, "Gitcoin Passport score too low");

        // Transfer collateral
        collateralToken.safeTransferFrom(msg.sender, address(this), collateralAmount);

        // Calculate loan amount: 80% of collateral value
        uint256 loanAmount = collateralAmount.mul(loanToValue).div(1e18);

        // Update loan
        Loan storage loan = loans[msg.sender];
        require(!loan.active, "Loan already active");

        loan.collateralAmount = collateralAmount;
        loan.loanAmount = loanAmount;
        loan.startTime = block.timestamp;
        loan.active = true;

        // Transfer loan
        loanToken.safeTransfer(msg.sender, loanAmount);

        totalCollateral = totalCollateral.add(collateralAmount);
        totalLoans = totalLoans.add(loanAmount);

        emit LoanOpened(msg.sender, collateralAmount, loanAmount);
    }

    // === REPAY LOAN ===
    function repayLoan() external {
        Loan storage loan = loans[msg.sender];
        require(loan.active, "No active loan");

        loanToken.safeTransferFrom(msg.sender, address(this), loan.loanAmount);

        collateralToken.safeTransfer(msg.sender, loan.collateralAmount);

        totalLoans = totalLoans.sub(loan.loanAmount);
        totalCollateral = totalCollateral.sub(loan.collateralAmount);

        emit LoanRepaid(msg.sender, loan.loanAmount);

        // Reset loan
        delete loans[msg.sender];
    }

    // === LIQUIDATE UNDERCOLLATERALIZED LOAN ===
    function liquidate(address borrower) external {
        Loan storage loan = loans[borrower];
        require(loan.active, "No active loan");

        // In real use, add price oracle check
        // For now, assume liquidation condition is met
        collateralToken.safeTransfer(msg.sender, loan.collateralAmount);

        emit CollateralLiquidated(borrower, loan.collateralAmount);
        delete loans[borrower];
    }

    // === GET USER LOAN VALUE ===
    function getUserLoanValue(address user) external view returns (uint256) {
        return loans[user].loanAmount;
    }

    // === GET PASSPORT SCORE ===
    function getPassportScore(address user) external view returns (uint256) {
        return gitcoinPassport.getScore(user);
    }
}
