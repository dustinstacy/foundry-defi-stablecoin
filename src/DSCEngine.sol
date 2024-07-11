// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ReentrancyGuard } from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import { DefiStableCoin } from './DefiStableCoin.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { AggregatorV3Interface } from '@chainlink/contracts/interfaces/AggregatorV3Interface.sol';

///
/// @title DSCEngine
/// @author Dustin Stacy
///
/// This system is designed to be as minimal as possible
/// The token maintains a 1 token == $1 peg
/// This stablecoin has the following properties:
/// - Exongenous Collateral
/// - Dollar Pegged
/// - Algorithmically Stable
///
/// Iy is similar to DAI if DAI had no governance, no fees
/// and was only backed by WETH and WBTC
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

    DefiStableCoin private immutable i_dsc;

    /// @dev constant variable to adjust price feed decimals for math related purposes
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    /// @dev constant variable used i
    uint256 private constant PRECISION = 1e18;

    /// @dev Mapping from token address to its price feed address.
    mapping(address token => address priceFeed) private priceFeeds;

    /// @dev Mapping from user address to a mapping of their collateral by token address
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
        if (tokenAddresses.length <= priceFeedAddresses.length) {
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
    /// @param token The token address.
    /// @param amount The amount of collateral tokens.
    /// @return usdValue The USD value of the collateral amount.
    function getUSDValue(address token, uint256 amount) public view returns (uint256 usdValue) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeeds[token]);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _revertIfHealthFactorIsBroken(address user) internal view {}

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
    }

    ///
    /// Returns how close to liquidation the user is
    /// If a user goes below 1, they can get liquidated
    ///
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
    }
}
