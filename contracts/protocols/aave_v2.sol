pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

interface AaveProtocolDataProvider {
    function getUserReserveData(address asset, address user) external view returns (
        uint256 currentATokenBalance,
        uint256 currentStableDebt,
        uint256 currentVariableDebt,
        uint256 principalStableDebt,
        uint256 scaledVariableDebt,
        uint256 stableBorrowRate,
        uint256 liquidityRate,
        uint40 stableRateLastUpdated,
        bool usageAsCollateralEnabled
    );

    function getReserveConfigurationData(address asset) external view returns (
        uint256 decimals,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidationBonus,
        uint256 reserveFactor,
        bool usageAsCollateralEnabled,
        bool borrowingEnabled,
        bool stableBorrowRateEnabled,
        bool isActive,
        bool isFrozen
    );

    function getReserveData(address asset) external view returns (
        uint256 availableLiquidity,
        uint256 totalStableDebt,
        uint256 totalVariableDebt,
        uint256 liquidityRate,
        uint256 variableBorrowRate,
        uint256 stableBorrowRate,
        uint256 averageStableBorrowRate,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex,
        uint40 lastUpdateTimestamp
    );
}

interface AaveLendingPool {
    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralETH,
        uint256 totalDebtETH,
        uint256 availableBorrowsETH,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );
}

interface AaveAddressProvider {
    function getLendingPool() external view returns (address);
    function getPriceOracle() external view returns (address);
}

interface AavePriceOracle {
    function getAssetPrice(address _asset) external view returns(uint256);
    function getAssetsPrices(address[] calldata _assets) external view returns(uint256[] memory);
    function getSourceOfAsset(address _asset) external view returns(uint256);
    function getFallbackOracle() external view returns(uint256);
}

contract DSMath {

    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "math-not-safe");
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        z = x - y <= x ? x - y : 0;
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "math-not-safe");
    }

    uint constant WAD = 10 ** 18;
    uint constant RAY = 10 ** 27;

    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, y), RAY / 2) / RAY;
    }

    function wmul(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, y), WAD / 2) / WAD;
    }

    function rdiv(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, RAY), y / 2) / y;
    }

    function wdiv(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, WAD), y / 2) / y;
    }

}

contract AaveHelpers is DSMath {
    /**
     * @dev get Aave Provider Address
    */
    function getAaveAddressProvider() internal pure returns (address) {
        return 0x652B2937Efd0B5beA1c8d54293FC1289672AFC6b; // Kovan
    }

    /**
     * @dev get Aave Protocol Data Provider
    */
    function getAaveProtocolDataProvider() internal pure returns (address) {
        return 0x744C1aaA95232EeF8A9994C4E0b3a89659D9AB79; // Kovan
    }

    struct AaveUserTokenData {
        uint tokenPrice;
        uint supplyBalance;
        uint stableBorrowBalance;
        uint variableBorrowBalance;
        uint supplyRate;
        uint stableBorrowRate;
        uint variableBorrowRate;
        AaveTokenData aaveTokenData;
    }

    struct AaveUserData {
        uint totalCollateralETH;
        uint totalBorrowsETH;
        uint availableBorrowsETH;
        uint currentLiquidationThreshold;
        uint ltv;
        uint healthFactor;
    }

    struct AaveTokenData {
        uint ltv;
        uint threshold;
        uint reserveFactor;
        bool usageAsCollEnabled;
        bool borrowEnabled;
        bool stableBorrowEnabled;
        bool isActive;
        bool isFrozen;
    }

    function collateralData(
        AaveProtocolDataProvider aaveData,
        address token
    ) internal view returns (AaveTokenData memory aaveTokenData) {
        (
            ,
            aaveTokenData.ltv,
            aaveTokenData.threshold,
            ,
            aaveTokenData.reserveFactor,
            aaveTokenData.usageAsCollEnabled,
            aaveTokenData.borrowEnabled,
            aaveTokenData.stableBorrowEnabled,
            aaveTokenData.isActive,
            aaveTokenData.isFrozen
        ) = aaveData.getReserveConfigurationData(token);
    }

    function getTokenData(
        AaveProtocolDataProvider aaveData,
        address user,
        address token,
        uint price
    ) internal view returns(AaveUserTokenData memory tokenData) {
        (
            tokenData.supplyBalance,
            tokenData.stableBorrowBalance,
            tokenData.variableBorrowBalance,
            ,,,,,
        ) = aaveData.getUserReserveData(token, user);

        (
            ,,,
            tokenData.supplyRate,
            tokenData.variableBorrowRate,
            tokenData.stableBorrowRate,
            ,,,
        ) = aaveData.getReserveData(token);

        AaveTokenData memory aaveTokenData = collateralData(aaveData, token);

        tokenData.tokenPrice = price;
        tokenData.aaveTokenData = aaveTokenData;

        // tokenData = AaveUserTokenData(
        //     price,
        //     supplyBal,
        //     stableDebtBal,
        //     variableDebtBal,
        //     liquidityRate,
        //     stableBorrowRate,
        //     variableBorrowRate,
        //     aaveTokenData
        // );
    }

    function getUserData(AaveLendingPool aave, address user)
    internal view returns (AaveUserData memory userData) {
        (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = aave.getUserAccountData(user);

        userData = AaveUserData(
            totalCollateralETH,
            totalDebtETH,
            availableBorrowsETH,
            currentLiquidationThreshold,
            ltv,
            healthFactor
        );
    }
}

contract Resolver is AaveHelpers {
    function getPosition(address user, address[] memory tokens) public view returns(AaveUserTokenData[] memory, AaveUserData memory) {
        AaveAddressProvider addrProvider = AaveAddressProvider(getAaveAddressProvider());
        // AavePriceOracle priceOracle = AavePriceOracle(addrProvider.getPriceOracle());
        // AaveProtocolDataProvider aaveData = AaveProtocolDataProvider(getAaveProtocolDataProvider());
        // AaveLendingPool aave = AaveLendingPool(addrProvider.getLendingPool());

        AaveUserTokenData[] memory tokensData = new AaveUserTokenData[](tokens.length);
        uint[] memory tokenPrices = AavePriceOracle(addrProvider.getPriceOracle()).getAssetsPrices(tokens);

        for (uint i = 0; i < tokens.length; i++) {
            tokensData[i] = getTokenData(AaveProtocolDataProvider(getAaveProtocolDataProvider()), user, tokens[i], tokenPrices[i]);
        }

        return (tokensData, getUserData(AaveLendingPool(addrProvider.getLendingPool()), user));
    }
}

contract InstaAaveResolver is Resolver {
    string public constant name = "Aave-v2-Resolver";
}