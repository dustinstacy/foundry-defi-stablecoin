// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ReentrancyGuard } from '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import { DefiStableCoin } from './DefiStableCoin.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

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
/// Is is similar to DAI if DAI had no governance, no fees
/// and was only backed by WETH and WBTC
///
/// Our DSC system should always be "overcollateralized".
/// At no point, should the value of all collateral <==
/// the $ backed value of all the DSC.
///
/// @notice This contract is the core of the DSC System. It
/// handles all the logic for mining and redeeming DSC, as
/// well as depositing & withdrawing collateral.
/// @notice This contract is VERY loosely based on the MakerDAO
/// DSS (DAI) system.
///
contract DSCEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error DSCEngine__AmountMustBeMoreThanZero();
    error DSCEngine__ArraysMustBeSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    DefiStableCoin private immutable i_dsc;

    mapping(address token => address priceFeed) private priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private collateralDeposited;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__AmountMustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length <= priceFeedAddresses.length) {
            revert DSCEngine__ArraysMustBeSameLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }
        i_dsc = DefiStableCoin(dscAddress);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function depositCollateralAndMintDSC() external {}

    ///
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

    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}

    function mintDSC() external {}

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
