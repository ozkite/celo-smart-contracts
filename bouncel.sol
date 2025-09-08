// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Bouncelo
 * @dev A turn-based "bounce" game between two players on Celo
 * Only two players can play, and they must take turns.
 */
contract Bouncelo {
    address public playerA;
    address public playerB;
    address public currentPlayer; // Whose turn it is

    uint256 public lastBounceTime;
    uint256 public bounceCount = 0;
    uint256 public constant TIMEOUT = 1 days; // If someone doesn't respond, game ends

    bool public gameEnded = false;

    event Bounce(address from, address to, uint256 amount, uint256 count);
    event GameOver(address winner, string reason);

    constructor(address _playerB) payable {
        require(_playerB != address(0), "Player B is zero address");
        require(msg.value > 0, "Initial bounce amount required");

        playerA = msg.sender;
        playerB = _playerB;
        currentPlayer = playerB; // Player A starts by sending, so Player B goes next
        lastBounceTime = block.timestamp;
    }

    // === BOUNCE FUNCTION ===
    function bounce() external payable {
        require(!gameEnded, "Game already ended");
        require(msg.sender == currentPlayer, "Not your turn");
        require(msg.value == address(this).balance, "Must send all current funds");
        require(block.timestamp < lastBounceTime + TIMEOUT, "Game timeout");

        // Switch player
        address previousPlayer = currentPlayer;
        currentPlayer = (currentPlayer == playerA) ? playerB : playerA;

        // Update time and count
        lastBounceTime = block.timestamp;
        bounceCount++;

        emit Bounce(previousPlayer, currentPlayer, msg.value, bounceCount);
    }

    // === CLAIM WIN IF TIMEOUT ===
    function claimTimeout() external {
        require(!gameEnded, "Game already ended");
        require(block.timestamp >= lastBounceTime + TIMEOUT, "Game not timed out yet");

        gameEnded = true;
        payable(msg.sender).transfer(address(this).balance);
        emit GameOver(msg.sender, "Timeout: other player didn't bounce");
    }

    // === GET BALANCE ===
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // === GET CURRENT PLAYER ===
    function getCurrentPlayer() external view returns (address) {
        return currentPlayer;
    }
}