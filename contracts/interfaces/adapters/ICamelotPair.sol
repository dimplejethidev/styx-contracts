// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICamelotPair {
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function stableSwap() external view returns (bool);

    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint16 token0feePercent,
            uint16 token1FeePercent
        );

    function getAmountOut(
        uint amountIn,
        address tokenIn
    ) external view returns (uint);

    function swap(
        uint amount0Out,
        uint amount1Out,
        address to,
        bytes calldata data,
        address referrer
    ) external;

    function swap(
        uint amount0Out,
        uint amount1Out,
        address to,
        bytes calldata data
    ) external;
}
