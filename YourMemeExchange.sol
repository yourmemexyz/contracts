// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./ILP.sol";
import "./YourMemeToken.sol";

contract YourMemeExchange is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    struct Token {
        uint256 initialBalance;
        uint256 balance;
        uint256 availableTokenBalance;
        bool isActive;
        bool isLpCreated;
    }

    address public treasure;
    uint256 public initialBalance;
    uint256 public availableTokenBalance;
    uint256 public createFee;
    uint96 public commissionRate;
    uint96 public finalRate;

    mapping(address => Token) public balances;

    address public lpAddress;
    address public currency;
    address public admin;

    event Create(
        address indexed tokenAddress,
        uint256 initialBalance,
        uint256 availableTokenBalance
    );
    event Close(
        address indexed tokenAddress,
        address indexed pair,
        uint256 poolLiquidityEth,
        uint256 poolLiquidityToken
    );
    event Buy(
        address indexed tokenAddress,
        uint256 amount,
        uint256 price,
        uint256 fee,
        uint256 existingBalance
    );
    event Sell(
        address indexed tokenAddress,
        uint256 amount,
        uint256 price,
        uint256 fee,
        uint256 existingBalance
    );
    event CreateWithFirstBuy(
        address indexed tokenAddress,
        uint256 initialBalance,
        uint256 availableTokenBalance,
        uint256 amount,
        uint256 price,
        uint256 fee,
        uint256 existingBalance
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init_unchained(_msgSender());
        __ReentrancyGuard_init_unchained();
        initialBalance = 50 ether;
        availableTokenBalance = 800000000 ether;
        commissionRate = 100;
        finalRate = 500;
    }

    function setAdmin(address _admin) external onlyOwner {
        admin = _admin;
    }

    function setInitialBalance(uint256 _initialBalance) external onlyOwner {
        require(
            _initialBalance > 0,
            "InitialBalance must be greater than zero"
        );
        initialBalance = _initialBalance;
    }

    function setTreasure(address _treasure) external onlyOwner {
        require(_treasure != address(0x0), "Invalid address");
        treasure = _treasure;
    }

    function setLpAddress(address _lpAddress) external onlyOwner {
        require(_lpAddress != address(0x0), "Invalid address");
        lpAddress = _lpAddress;
    }

    function setCurrency(address _currency) external onlyOwner {
        require(_currency != address(0x0), "Invalid address");
        currency = _currency;
    }

    function setAvailableTokenBalance(
        uint256 _availableTokenBalance
    ) external onlyOwner {
        require(
            _availableTokenBalance > 1 ether,
            "Available token balance must be at least 1 ether"
        );
        availableTokenBalance = _availableTokenBalance;
    }

    function setCommissionRate(uint96 _commissionRate) external onlyOwner {
        commissionRate = _commissionRate;
    }

    function setFinalRate(uint96 _finalRate) external onlyOwner {
        finalRate = _finalRate;
    }

    function getReserve(address tokenAddress) public view returns (uint256) {
        return ERC20(tokenAddress).balanceOf(address(this));
    }

    function getOutputPrice(
        uint256 outputAmount,
        uint256 inputReserve,
        uint256 outputReserve
    ) public pure returns (uint256) {
        require(
            inputReserve > 0 && outputReserve > 0,
            "Reserves must be greater than 0"
        );
        uint256 numerator = inputReserve * outputAmount;
        uint256 denominator = (outputReserve - outputAmount);
        return numerator / denominator + 1;
    }

    function getInputPrice(
        uint256 inputAmount,
        uint256 inputReserve,
        uint256 outputReserve
    ) public pure returns (uint256) {
        require(
            inputReserve > 0 && outputReserve > 0,
            "Reserves must be greater than 0"
        );

        uint256 numerator = inputAmount * outputReserve;
        uint256 denominator = inputReserve + inputAmount;

        return numerator / denominator;
    }

    function createToken(
        string memory name,
        string memory symbol
    ) external returns (ERC20) {
        ERC20 newToken = new YourMemeToken(name, symbol, 1000000000);
        address tokenAddress = address(newToken);
        balances[tokenAddress].balance = initialBalance;
        balances[tokenAddress].initialBalance = initialBalance;
        balances[tokenAddress].availableTokenBalance = availableTokenBalance;
        balances[tokenAddress].isActive = true;
        ILP(tokenAddress).renounceOwnership();
        emit Create(tokenAddress, initialBalance, availableTokenBalance);
        return newToken;
    }

    function createTokenWithBuy(
        string memory name,
        string memory symbol
    ) external payable nonReentrant {
        require(msg.value > 0, "ETH amount must be greater than zero");

        ERC20 newToken = new YourMemeToken(name, symbol, 1000000000);
        address tokenAddress = address(newToken);
        balances[tokenAddress].balance = initialBalance;
        balances[tokenAddress].initialBalance = initialBalance;
        balances[tokenAddress].availableTokenBalance = availableTokenBalance;
        balances[tokenAddress].isActive = true;
        ILP(tokenAddress).renounceOwnership();

        uint256 receivedAmount = (msg.value * 10000) / (10000 + commissionRate);

        uint256 tokenReserveBalance = getReserve(tokenAddress);
        uint256 stopBalance = (1000000000 ether -
            balances[tokenAddress].availableTokenBalance);

        uint256 fee = msg.value - receivedAmount;
        uint256 tokensToReceive = getInputPrice(
            receivedAmount,
            balances[tokenAddress].balance,
            tokenReserveBalance
        );

        uint256 reserveBalanceAfterTxCompleted = (tokenReserveBalance -
            tokensToReceive);

        uint256 refund;
        if (reserveBalanceAfterTxCompleted < stopBalance) {
            tokensToReceive = tokenReserveBalance - stopBalance;
            reserveBalanceAfterTxCompleted = stopBalance;
            receivedAmount = getOutputPrice(
                tokensToReceive,
                balances[tokenAddress].balance,
                tokenReserveBalance
            );
            fee = _getPortionOfBid(receivedAmount, commissionRate);
            require(
                msg.value >= (fee + receivedAmount),
                "insufficient payment"
            );
            refund = msg.value - (fee + receivedAmount);
        }
        balances[tokenAddress].balance += receivedAmount;

        if (reserveBalanceAfterTxCompleted == stopBalance) {
            balances[tokenAddress].isActive = false;
        }

        emit CreateWithFirstBuy(
            tokenAddress,
            initialBalance,
            availableTokenBalance,
            tokensToReceive,
            receivedAmount,
            fee,
            reserveBalanceAfterTxCompleted
        );

        ERC20(tokenAddress).transfer(msg.sender, tokensToReceive);
        sendProtocolFeeToTreasure(fee);
        if (refund > 0) {
            (bool success, ) = payable(msg.sender).call{value: refund}("");
            require(success, "refund is failed");
        }
    }

    function createLP(address tokenAddress) external {
        // require(msg.sender == owner() || msg.sender == admin, "caller is not authorized");

        require(
            !balances[tokenAddress].isLpCreated,
            "LP already created for this token"
        );
        uint256 currentBalance = IERC20(tokenAddress).balanceOf(address(this));

        require(
            currentBalance ==
                (1000000000 ether -
                    balances[tokenAddress].availableTokenBalance),
            "Current balance does not match the expected balance."
        );
        balances[tokenAddress].isLpCreated = true;
        uint256 remaining = balances[tokenAddress].balance -
            balances[tokenAddress].initialBalance;
        uint256 fee = _getPortionOfBid(remaining, finalRate);
        uint256 poolLiquidityEth = remaining - fee;

        IERC20(tokenAddress).approve(lpAddress, currentBalance);
        ILP(lpAddress).addLiquidityETH{value: poolLiquidityEth}(
            tokenAddress,
            false,
            currentBalance,
            currentBalance,
            poolLiquidityEth,
            address(this),
            block.timestamp + 86400
        );
        address pair = ILP(lpAddress).pairFor(tokenAddress, currency, false);
        emit Close(tokenAddress, pair, poolLiquidityEth, currentBalance);
        IERC20(pair).transfer(
            address(0x0000000000000000000000000000000000000000),
            IERC20(pair).balanceOf(address(this))
        );
        sendProtocolFeeToTreasure(fee);
    }

    function ethToTokenSwapInput(
        address tokenAddress,
        uint256 minTokensToReceive,
        uint256 deadline
    ) external payable nonReentrant {
        require(deadline >= block.timestamp, "Deadline is reached");
        require(msg.value > 0, "ETH amount must be greater than zero");
        require(
            minTokensToReceive > 0,
            "Minimum tokens to receive must be greater than zero"
        );

        uint256 receivedAmount = (msg.value * 10000) / (10000 + commissionRate);
        require(balances[tokenAddress].isActive, "Token is not active");

        uint256 tokenReserveBalance = getReserve(tokenAddress);
        uint256 stopBalance = (1000000000 ether -
            balances[tokenAddress].availableTokenBalance);

        uint256 fee = msg.value - receivedAmount;
        uint256 tokensToReceive = getInputPrice(
            receivedAmount,
            balances[tokenAddress].balance,
            tokenReserveBalance
        );
        require(
            tokensToReceive >= minTokensToReceive,
            "Tokens received are less than minimum tokens expected"
        );
        uint256 reserveBalanceAfterTxCompleted = (tokenReserveBalance -
            tokensToReceive);

        uint256 refund;
        if (reserveBalanceAfterTxCompleted < stopBalance) {
            tokensToReceive = tokenReserveBalance - stopBalance;
            reserveBalanceAfterTxCompleted = stopBalance;
            receivedAmount = getOutputPrice(
                tokensToReceive,
                balances[tokenAddress].balance,
                tokenReserveBalance
            );
            fee = _getPortionOfBid(receivedAmount, commissionRate);
            require(
                msg.value >= (fee + receivedAmount),
                "insufficient payment"
            );
            refund = msg.value - (fee + receivedAmount);
        }
        balances[tokenAddress].balance += receivedAmount;

        if (reserveBalanceAfterTxCompleted == stopBalance) {
            balances[tokenAddress].isActive = false;
        }

        emit Buy(
            tokenAddress,
            tokensToReceive,
            receivedAmount,
            fee,
            reserveBalanceAfterTxCompleted
        );
        ERC20(tokenAddress).transfer(msg.sender, tokensToReceive);
        sendProtocolFeeToTreasure(fee);
        if (refund > 0) {
            (bool success, ) = payable(msg.sender).call{value: refund}("");
            require(success, "refund is failed");
        }
    }

    function tokenToEthSwapInput(
        address tokenAddress,
        uint256 tokensToSwap,
        uint256 minEthToReceive,
        uint256 deadline
    ) external nonReentrant {
        require(deadline >= block.timestamp, "deadline is reached");
        require(
            minEthToReceive > 0,
            "Minimum ETH to receive must be greater than zero"
        );
        require(tokensToSwap > 0, "Tokens to swap must be greater than zero");
        require(balances[tokenAddress].isActive, "Token is not active");

        uint256 tokenReserveBalance = getReserve(tokenAddress);
        uint256 ethToReceive = getInputPrice(
            tokensToSwap,
            tokenReserveBalance,
            balances[tokenAddress].balance
        );

        require(
            (balances[tokenAddress].balance -
                balances[tokenAddress].initialBalance) >= ethToReceive,
            "Not enough balance for token swap"
        );
        balances[tokenAddress].balance -= ethToReceive;
        require(
            ethToReceive >= minEthToReceive,
            "ETH received is less than minimum ETH expected"
        );

        ERC20(tokenAddress).transferFrom(
            msg.sender,
            address(this),
            tokensToSwap
        );
        uint256 fee = _getPortionOfBid(ethToReceive, commissionRate);
        uint256 payment = ethToReceive - fee;
        emit Sell(
            tokenAddress,
            tokensToSwap,
            payment,
            fee,
            tokenReserveBalance + tokensToSwap
        );
        payable(msg.sender).transfer(payment);
        sendProtocolFeeToTreasure(fee);
    }

    function getEthToTokenInputPrice(
        address tokenAddress,
        uint256 ethSold
    ) external view returns (uint256) {
        require(ethSold > 0, "ETH amount must be greater than zero");
        uint256 tokenReserveBalance = getReserve(tokenAddress);

        return
            getInputPrice(
                ethSold,
                balances[tokenAddress].balance,
                tokenReserveBalance
            );
    }

    function getTokenToEthInputPrice(
        address tokenAddress,
        uint256 tokensSold
    ) external view returns (uint256) {
        require(tokensSold > 0, "Tokens sold must be greater than zero");
        uint256 tokenReserveBalance = getReserve(tokenAddress);
        return
            getInputPrice(
                tokensSold,
                tokenReserveBalance,
                balances[tokenAddress].balance
            );
    }

    function sendProtocolFeeToTreasure(uint256 _fee) internal {
        if (_fee > 0) {
            (bool success, ) = treasure.call{value: _fee}("");
            require(success, "transfer to treasure is failed");
        }
    }

    function _getPortionOfBid(
        uint256 _totalBid,
        uint256 _percentage
    ) internal pure returns (uint256) {
        return (_totalBid * _percentage) / 10000;
    }
}
