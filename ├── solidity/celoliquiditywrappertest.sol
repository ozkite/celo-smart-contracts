// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function transfer(address to, uint256 value) external returns (bool);
}

/**
 * @title CeloLiquidityWrapper
 * @dev Wraps existing or new liquidity pool positions into a single, composable NFT or ERC-20
 * Supports both new LP creation and wrapping of existing LP tokens
 */
contract CeloLiquidityWrapper is ERC20, Ownable, ReentrancyGuard, IERC721Receiver {
    // === POOL INFO ===
    struct PoolInfo {
        address tokenA;
        address tokenB;
        address lpToken;
        uint24 fee; // e.g., 3000 = 0.3%
    }

    // === WRAPPED POSITION ===
    struct WrappedPosition {
        uint256 lpAmount;
        uint256 depositTime;
        address creator;
        bool isStaked;
    }

    mapping(uint256 => PoolInfo) public poolInfo;
    mapping(uint256 => WrappedPosition) public wrappedPositions;
    mapping(address => bool) public isPoolManager; // Can create new pools

    uint256 public positionCounter = 0;
    IERC20 public immutable celoToken; // CELO
    IERC20 public immutable stableToken; // cUSD

    // === FACTORY & ROUTER (CeloSwap / Ubeswap) ===
    address public constant FACTORY = 0x9BAb5a731253dE907807795BD29c53A26b178281;
    address public constant ROUTER = 0x10b620b21529698B07C007c42Bcb7Ae5d7D80c21;

    // === EVENTS ===
    event LiquidityWrapped(uint256 indexed positionId, address indexed owner, address lpToken, uint256 amount);
    event LiquidityUnwrapped(uint256 indexed positionId, address indexed owner, uint256 amount);
    event NewPoolCreated(address indexed tokenA, address indexed tokenB, address lpToken);
    event Staked(uint256 indexed positionId, address indexed staker);
    event Unstaked(uint256 indexed positionId, address indexed staker);

    // === MODIFIERS ===
    modifier onlyPoolManager() {
        require(isPoolManager[msg.sender] || msg.sender == owner(), "Not pool manager");
        _;
    }

    // === CONSTRUCTOR ===
    constructor(address _celo, address _stable) ERC20("CeloLiquidityToken", "CLT") {
        celoToken = IERC20(_celo);
        stableToken = IERC20(_stable);
        isPoolManager[owner()] = true;
    }

    // === ADD POOL MANAGER ===
    function addPoolManager(address manager) external onlyOwner {
        isPoolManager[manager] = true;
    }

    // === CREATE NEW POOL & WRAP LIQUIDITY ===
    function createAndWrap(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired
    ) external onlyPoolManager nonReentrant returns (uint256 positionId) {
        // Approve router
        IERC20(tokenA).approve(ROUTER, amountADesired);
        IERC20(tokenB).approve(ROUTER, amountBDesired);

        // Add liquidity
        (uint256 amountA, uint256 amountB, address lpToken) = IUniswapV2Router(ROUTER)
            .addLiquidity(
                tokenA,
                tokenB,
                amountADesired,
                amountBDesired,
                1,
                1,
                address(this),
                block.timestamp + 1000
            );

        // Register pool
        uint256 pid = positionCounter++;
        poolInfo[pid] = PoolInfo({
            tokenA: tokenA,
            tokenB: tokenB,
            lpToken: lpToken,
            fee: 3000 // Default 0.3%
        });

        // Wrap
        _wrap(pid, lpToken, IERC20(lpToken).balanceOf(address(this)));
        emit NewPoolCreated(tokenA, tokenB, lpToken);

        return pid;
    }

    // === WRAP EXISTING LP TOKENS ===
    function wrapExisting(address lpToken, uint256 amount) external nonReentrant returns (uint256 positionId) {
        require(amount > 0, "Amount must be > 0");

        // Transfer LP tokens to contract
        IERC20(lpToken).transferFrom(msg.sender, address(this), amount);

        // Create new position
        uint256 pid = positionCounter++;
        wrappedPositions[pid] = WrappedPosition({
            lpAmount: amount,
            depositTime: block.timestamp,
            creator: msg.sender,
            isStaked: false
        });

        // Mint CLT tokens 1:1 with LP tokens (or use share-based)
        _mint(msg.sender, amount);

        emit LiquidityWrapped(pid, msg.sender, lpToken, amount);
        return pid;
    }

    // === UNWRAP POSITION ===
    function unwrap(uint256 positionId) external nonReentrant {
        WrappedPosition storage pos = wrappedPositions[positionId];
        require(pos.lpAmount > 0, "Invalid position");
        require(msg.sender == tx.origin, "No contracts");

        address lpToken = poolInfo[positionId].lpToken;
        uint256 amount = pos.lpAmount;

        // Burn CLT
        _burn(msg.sender, amount);

        // Transfer LP tokens back
        IERC20(lpToken).transfer(msg.sender, amount);

        emit LiquidityUnwrapped(positionId, msg.sender, amount);
        delete wrappedPositions[positionId];
    }

    // === STAKE WRAPPED POSITION ===
    function stake(uint256 positionId) external nonReentrant {
        WrappedPosition storage pos = wrappedPositions[positionId];
        require(pos.creator == msg.sender, "Not owner");
        require(!pos.isStaked, "Already staked");

        pos.isStaked = true;
        emit Staked(positionId, msg.sender);
    }

    // === UNSTAKE ===
    function unstake(uint256 positionId) external nonReentrant {
        WrappedPosition storage pos = wrappedPositions[positionId];
        require(pos.creator == msg.sender, "Not owner");
        require(pos.isStaked, "Not staked");

        pos.isStaked = false;
        emit Unstaked(positionId, msg.sender);
    }

    // === GET POSITION VALUE ===
    function getPositionValue(uint256 positionId) external view returns (uint256 celoValue, uint256 usdValue) {
        WrappedPosition memory pos = wrappedPositions[positionId];
        if (pos.lpAmount == 0) return (0, 0);

        PoolInfo memory pool = poolInfo[positionId];
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pool.lpToken).getReserves();

        // Simplified: assume token0 is CELO or cUSD
        uint256 totalSupply = IERC20(pool.lpToken).totalSupply();
        uint256 share = (pos.lpAmount * 1e18) / totalSupply;

        uint256 celoPerLp = (reserve0 + reserve1) / totalSupply;
        celoValue = (share * celoPerLp) / 1e18;

        // Assume 1 CELO = 1 USD
        usdValue = celoValue;
    }

    // === ERC721Receiver fallback ===
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // === EMERGENCY WITHDRAW ===
    function emergencyWithdraw(address token) external onlyOwner {
        IERC20(token).transfer(owner(), IERC20(token).balanceOf(address(this)));
    }
}
