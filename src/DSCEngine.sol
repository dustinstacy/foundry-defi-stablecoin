// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ReentrancyGuard } from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { AggregatorV3Interface } from '@chainlink/contracts/interfaces/AggregatorV3Interface.sol';
import { DefiStableCoin } from './DefiStableCoin.sol';

/// @title DSCEngine
/// @author Dustin Stacy
///
/// This system is designed to be as minimal as possible.
/// The token maintains a 1 token == $1 peg.
/// This stablecoin has the following properties:
/// - Exongenous Collateral.
/// - Dollar Pegged.
/// - Algorithmically Stable.
///
///
/// It is similar to DAI if DAI had no governance, no fees
/// and was only backed by WETH and WBTC.
///
/// Our DSC system should always be "overcollateralized".
/// At no point, should the value of all collateral <=
/// the $ backed value of all the DSC.
///
/// This contract is the core of the DSC System. It
/// handles all the logic for minting and redeeming DSC, as
/// well as depositing & withdrawing collateral.
contract DSCEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @dev Instance of the DefiStableCoin contract used for interacting with the DSC token.
    DefiStableCoin private immutable i_dsc;

    /// @dev Used to adjust decimals of price feed results.
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    /// @dev Used to adjust decimals to relative USD value.
    uint256 private constant PRECISION = 1e18;

    /// @dev Threshold percentage for triggering account liquidation.
    uint256 private constant LIQUIDATION_THRESHOLD = 50;

    /// @dev Precision factor used for calculating liquidation threshold percentage.
    uint256 private constant LIQUIDATION_PRECISION = 100;

    /// @dev Minimum acceptable health factor to avoid liquidation.
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    /// @dev Mapping from token address to its price feed address.
    mapping(address token => address priceFeed) private priceFeeds;

    /// @dev Mapping from user address to a mapping of their collateral by token address.
    mapping(address user => mapping(address token => uint256 amount)) private collateralDeposited;

    /// @dev Mapping from user address to their minted DSC balances.
    mapping(address user => uint256 amountDSCMinted) private dscMinted;

    /// @dev Array of all supported collateral tokens.
    address[] private collateralTokens;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Emitted when collateral is deposited.
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Emitted when attempting to perform an action with an amount that must be more than zero.
    error DSCEngine__AmountMustBeMoreThanZero();

    /// @dev Emitted when attempting to use array arguments that are not the same length
    error DSCEngine__ArraysMustBeSameLength();

    /// @dev Emitted when an unallowed token address is passed as an argument
    error DSCEngine__TokenNotAllowed();

    /// @dev Emitted when a token transfer is unsuccesful
    error DSCEngine__TransferFailed();

    /// @dev Emitted if user's health factor is broken
    error DSCEngine__BreaksHealthFactor();

    /// @dev Emitted if minting is unsuccesful
    error DSCEngine__MintFailed();

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Ensures that the amount passed is more than zero.
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__AmountMustBeMoreThanZero();
        }
        _;
    }

    /// @dev Ensures that the token is allowed for collateral
    modifier isAllowedToken(address token) {
        if (priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @param tokenAddresses Array of collateral token addresses.
    /// @param priceFeedAddresses Array of corresponding price feed addresses.
    /// @param dscAddress Address of the DefiStableCoin contract.
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__ArraysMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DefiStableCoin(dscAddress);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function depositCollateralAndMintDSC() external {}

    /// @param tokenCollateralAddress the address of the token to deposit as collateral
    /// @param amountCollateral the amount of collateral to deposit
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) external moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant {
        collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /// @param amountDSCToMint The amount of defi stablecoin to mint
    /// @notice they must have more collateral value than minimum threshold
    function mintDSC(uint256 amountDSCToMint) external moreThanZero(amountDSCToMint) nonReentrant {
        dscMinted[msg.sender] += amountDSCToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Function to calculate the total value of collateral deposited by a user in USD.
    /// @param user The user's address.
    /// @return totalCollateralValueInUSD Total value of collateral in USD.
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUSD) {
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            address token = collateralTokens[i];
            uint256 amount = collateralDeposited[user][token];
            totalCollateralValueInUSD += getUSDValue(token, amount);
        }
        return totalCollateralValueInUSD;
    }

    /// @dev Function to calculate the USD value of a given amount of collateral.
    /// @notice Retrieves the latest price from the Chainlink price feed using `latestRoundData()`,
    /// which returns a value with 8 decimals. To increase precision, `ADDITIONAL_FEED_PRECISION`
    /// is used to scale the price to 18 decimals before dividing by `PRECISION` to obtain the USD value.
    /// @param token The token address.
    /// @param amount The amount of collateral tokens.
    /// @return usdValue The USD value of the collateral amount.
    function getUSDValue(address token, uint256 amount) public view returns (uint256 usdValue) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeeds[token]);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /// @return Array of token addresses allowed as collateral.
    function getCollateralTokens() public view returns (address[] memory) {
        return collateralTokens;
    }

    /// @param token Token to get the price feed address of.
    /// @return Token's price feed address.
    function getPriceFeedAddress(address token) public view returns (address) {
        return priceFeeds[token];
    }

    /// @param user User address to retrieve deposited collateral information from.
    /// @param token Token to get the amount deposited of.
    /// @return Amount of collateral deposited by the user.
    function getCollateralDeposited(address user, address token) public view returns (uint256) {
        return collateralDeposited[user][token];
    }

    /// @param user User address to retrieve minted defi stablecoin amount from.
    /// @return Amount of DSC minted by the user.
    function getDSCMinted(address user) public view returns (uint256) {
        return dscMinted[user];
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor();
        }
    }

    /*//////////////////////////////////////////////////////////////
                           PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @param user The user's address.
    /// @return totalDSCMinted Total DSC minted by the user.
    /// @return collateralValueInUSD Total collateral value in USD.
    function _getAccountInformation(
        address user
    ) private view returns (uint256 totalDSCMinted, uint256 collateralValueInUSD) {
        totalDSCMinted = dscMinted[user];
        collateralValueInUSD = getAccountCollateralValue(user);
        return (totalDSCMinted, collateralValueInUSD);
    }

    /// @dev Calculates the health factor of a user's account in the DSCEngine contract.
    /// @notice The health factor indicates how close the user is to liquidation.
    /// A health factor below 1 signifies the user is eligible for liquidation.
    /// @param user The address of the user account.
    /// @return healthFactor The calculated health factor.
    function _healthFactor(address user) private view returns (uint256 healthFactor) {
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return healthFactor = (collateralAdjustedForThreshold * PRECISION) / totalDSCMinted;
    }
}
