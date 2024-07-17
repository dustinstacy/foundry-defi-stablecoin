// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { AggregatorV3Interface } from '@chainlink/contracts/interfaces/AggregatorV3Interface.sol';
import { OracleLib, AggregatorV3Interface } from './OracleLib.sol';

/// @title Calculations
/// @author Dustin Stacy
/// @notice This library contains the math functions for the DSCEngine contract
library Calculations {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    using OracleLib for AggregatorV3Interface;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @dev Used to adjust decimals of price feed results.
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    /// @dev Used to adjust decimals to relative USD value.
    uint256 private constant PRECISION = 1e18;

    /// @dev Threshold percentage for triggering account liquidation.
    uint256 private constant LIQUIDATION_THRESHOLD = 50;

    /// @dev Precision factor used for calculating liquidation threshold percentage.
    uint256 private constant LIQUIDATION_PRECISION = 100;

    /// @dev Bonus percentage to be given to a user for liquidating another user.
    uint256 private constant LIQUIDATION_BONUS = 10;

    /// @dev Calculates the health factor of a user's account in the DSCEngine contract.
    /// @notice The health factor indicates how close the user is to liquidation.
    /// A health factor below 1 signifies the user is eligible for liquidation.
    /// @param totalDSCMinted Total DSC minted by the user.
    /// @param collateralValueInUSD The total collateral value in USD
    /// @return healthFactor The calculated health factor.
    function calculateHealthFactor(
        uint256 totalDSCMinted,
        uint256 collateralValueInUSD
    ) external pure returns (uint256 healthFactor) {
        if (totalDSCMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return healthFactor = (collateralAdjustedForThreshold * PRECISION) / totalDSCMinted;
    }

    /// @notice Calulcates the liquidators redemption amount based on debt covered and the liquidation bonus.
    /// @param tokenPriceFeed Price feed address of the token collateral to redeem.
    /// @param debtToCover Amount of debt the liquidator is covering.
    function calculateTotalCollateralToRedeem(
        address tokenPriceFeed,
        uint256 debtToCover
    ) external view returns (uint256 totalCollateralToRedeem) {
        uint256 tokenAmountFromDebtCovered = calculateTokenAmountFromUSD(tokenPriceFeed, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        return totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
    }

    /// @dev Function to calculate the USD value of a given amount of collateral.
    /// @notice Retrieves the latest price from the Chainlink price feed using `staleCheckLatestRoundData()`,
    /// which returns a value with 8 decimals. To increase precision, `ADDITIONAL_FEED_PRECISION`
    /// is used to scale the price to 18 decimals before dividing by `PRECISION` to obtain the USD value.
    /// @param tokenPriceFeed The token price feed address.
    /// @param amount The amount of collateral tokens.
    /// @return usdValue The USD value of the collateral amount.
    function calculateUSDValue(address tokenPriceFeed, uint256 amount) external view returns (uint256 usdValue) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(tokenPriceFeed);
        (, int256 price, , , ) = priceFeed.staleCheckLatestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /// @param tokenPriceFeed Address of token price feed to get amount of based on USD value
    /// @param usdAmountInWei USD value represented in <value>e18, adding 18 decimal places.
    /// @return The quantity of tokens that a USD value would equal of the given token address.
    function calculateTokenAmountFromUSD(address tokenPriceFeed, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(tokenPriceFeed);
        (, int price, , , ) = priceFeed.staleCheckLatestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    /// @return The `ADDITIONAL_FEED_PRECISION` constant.
    function getAdditionaFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    /// @return The `PRECISION` constant.
    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    /// @return The `LIQUIDATION_THRESHOLD` constant
    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    /// @return The `LIQUIDATION_BONUS` constant
    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    /// @return The `LIQUIDATION_PRECISION` constant.
    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }
}
