// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct QParams {
    address tokenIn;
    address tokenOut;
    int256 amountIn;
    uint24 fee;
}

interface IUniV3Pool {
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function liquidity() external view returns (uint128);
}

interface IUniV3Quoter {
    function quoteExactInputSingle(
        QParams memory params
    ) external view returns (uint256);

    function quote(
        address,
        bool,
        int256,
        uint160
    ) external view returns (int256, int256);
}

interface IUniV3Factory {
    function feeAmountTickSpacing(uint24) external view returns (int24);

    function getPool(address, address, uint24) external view returns (address);
}
