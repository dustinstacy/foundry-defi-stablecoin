// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
/// @notice This contract is the core of the DSC System. It
/// handles all the logic for mining and redeeming DSC, as
/// well as depositing & withdrawing collateral.
/// @notice This contract is VERY loosely based on the MakerDAO
/// DSS (DAI) system.
///
contract DSCEngine {

}
