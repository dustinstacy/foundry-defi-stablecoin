// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ReentrancyGuard } from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { Calculations } from './libraries/Calculations.sol';
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

    /// @dev Minimum acceptable health factor to avoid liquidation.
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

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

    /// @dev Emitted when collateral is redeemed.
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Emitted when attempting to perform an action with an amount that must be more than zero.
    error DSCEngine__AmountMustBeMoreThanZero();

    /// @dev Emitted when attempting to use array arguments that are not the same length.
    error DSCEngine__ArraysMustBeSameLength();

    /// @dev Emitted when an unallowed token address is passed as an argument.
    error DSCEngine__TokenNotAllowed();

    /// @dev Emitted when a token transfer is unsuccesful.
    error DSCEngine__TransferFailed();

    /// @dev Emitted if user's health factor is broken.
    error DSCEngine__BreaksHealthFactor();

    /// @dev Emitted if minting is unsuccesful.
    error DSCEngine__MintFailed();

    /// @dev Emitted if attempting to liquidate a user that does not have a broken health factor.
    error DSCEngine__HealthFactorNotBroken();

    /// @dev Emitted if health factor is not improved to minimum after liquidation.
    error DSCEngine__HealthFactorNotImproved();

    /// @dev Emitted if a user attempts to burn more than they have
    error DSCEngine__InsufficientBalanceToBurn();

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

    /// @dev Ensures that the token is allowed for collateral.
    modifier isAllowedToken(address token) {
        if (priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
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
                       EXTERNAL & PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @param tokenCollateralAddress The address of the token to deposit as collateral.
    /// @param amountCollateral The amount of collateral to deposit.
    /// @param amountDSCToMint The amount of defi stablecoin to mint.
    /// @notice This function will deposit your collateral and mint DSC in one transaction.
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDSCToMint);
    }

    /// @param tokenCollateralAddress Address of the collateral to redeem.
    /// @param amountCollateral Amount of collateral to redeem.
    /// @param amountDSCToBurn Amount of DSC to burn.
    /// @notice This function burns DSC and redeems underlying collateral in one transaction
    /// @dev `burnDSC` and `redeemCollateral` both run checks to ensure amounts are not 0.
    /// @dev `redeemCollateral` will run a check to ensure user health factor is not broken.
    function redeemCollateralForDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToBurn
    ) external {
        burnDSC(amountDSCToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    /// @param tokenCollateralAddress Address of the collateral to liquidate.
    /// @param user Address of the user to liquidate based on broken health factor.
    /// @param debtToCover Amount of DSC to burn to cover debt.
    /// @notice You can partially liquidate a user.
    function liquidate(
        address tokenCollateralAddress,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorNotBroken();
        }
        uint256 totalCollateralToRedeem = Calculations.calculateTotalCollateralToRedeem(
            priceFeeds[tokenCollateralAddress],
            debtToCover
        );
        _redeemCollateral(user, msg.sender, tokenCollateralAddress, totalCollateralToRedeem);
        _burnDSC(debtToCover, user, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /// @param tokenCollateralAddress The address of the token to deposit as collateral.
    /// @param amountCollateral The amount of collateral to deposit.
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant {
        collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /// @param amountDSCToMint The amount of defi stablecoin to mint.
    /// @notice Minter must have more collateral value than the minimum threshold.
    function mintDSC(uint256 amountDSCToMint) public moreThanZero(amountDSCToMint) nonReentrant {
        dscMinted[msg.sender] += amountDSCToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /// @param amount Amount of DSC to burn.
    /// @notice Calls burn function from the DefiStableCoin contract.
    function burnDSC(uint256 amount) public moreThanZero(amount) {
        if (dscMinted[msg.sender] < amount) {
            revert DSCEngine__InsufficientBalanceToBurn();
        }
        _burnDSC(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /// @param tokenCollateralAddress Address of the collateral to redeem.
    /// @param amountCollateral Amount of collateral to redeem.
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /// @dev Function to calculate the total value of collateral deposited by a user in USD.
    /// @param user The user's address.
    /// @return totalCollateralValueInUSD Total value of collateral in USD.
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUSD) {
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            address token = collateralTokens[i];
            uint256 amount = collateralDeposited[user][token];
            totalCollateralValueInUSD += Calculations.calculateUSDValue(priceFeeds[token], amount);
        }
        return totalCollateralValueInUSD;
    }

    /// @return Array of token addresses allowed as collateral.
    function getCollateralTokens() external view returns (address[] memory) {
        return collateralTokens;
    }

    /// @param token Token to get the price feed address of.
    /// @return Token's price feed address.
    function getPriceFeedAddress(address token) external view returns (address) {
        return priceFeeds[token];
    }

    /// @param user User address to retrieve deposited collateral information from.
    /// @param token Token to get the amount deposited of.
    /// @return Amount of collateral deposited by the user.
    function getCollateralDeposited(address user, address token) external view returns (uint256) {
        return collateralDeposited[user][token];
    }

    /// @param user User address to retrieve minted defi stablecoin amount from.
    /// @return Amount of DSC minted by the user.
    function getDSCMinted(address user) external view returns (uint256) {
        return dscMinted[user];
    }

    /// @param user User address to retrieve the health factor of.
    /// @return User's health factor.
    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    /// @param user User address to retrieve account information of.
    /// @return totalDSCMinted Total amount of DSC minted by the user.
    /// @return collateralValueInUSD Total value of all user collateral in USD.
    function getAccountInformation(
        address user
    ) external view returns (uint256 totalDSCMinted, uint256 collateralValueInUSD) {
        return _getAccountInformation(user);
    }

    /// @return Address of the DSC contract.
    function getDSC() external view returns (address) {
        return address(i_dsc);
    }

    /*//////////////////////////////////////////////////////////////
                       INTERNAL & PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @param amount Amount of DSC to burn
    /// @param onBehalfOf Address of user that will have their DSC returned.
    /// @param dscFrom Address of user that will have their DSC burnt.
    /// @dev Low-level internal function. Do not call unless the calling function is checking
    /// for broken health factors.
    function _burnDSC(uint256 amount, address onBehalfOf, address dscFrom) internal {
        dscMinted[onBehalfOf] -= amount;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amount);
    }

    /// @param from Address to have the collateral redeemed from.
    /// @param to Address to have the collateral redeemed to.
    /// @param tokenCollateralAddress Address of the collateral to redeem.
    /// @param amountCollateral Amount of collateral to redeem.
    /// @notice If statment should be unreachable as the IERC20 should revert on transfer fail.
    /// @dev Low-level internal function. Do not call unless the calling function is checking
    /// for broken health factors.
    function _redeemCollateral(
        address from,
        address to,
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) internal {
        collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /// @param user User address to ensure it meets the minimum health factor.
    /// @notice Reverts the function calling this function if the user's health factor is below 1.
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor();
        }
    }

    /// @param user The address of the user account.
    /// @return healthFactor The calculated health factor.
    function _healthFactor(address user) internal view returns (uint256 healthFactor) {
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
        return healthFactor = Calculations.calculateHealthFactor(totalDSCMinted, collateralValueInUSD);
    }

    /// @param user The user's address.
    /// @return totalDSCMinted Total DSC minted by the user.
    /// @return collateralValueInUSD Total collateral value in USD.
    function _getAccountInformation(
        address user
    ) internal view returns (uint256 totalDSCMinted, uint256 collateralValueInUSD) {
        totalDSCMinted = dscMinted[user];
        collateralValueInUSD = getAccountCollateralValue(user);
        return (totalDSCMinted, collateralValueInUSD);
    }
}
