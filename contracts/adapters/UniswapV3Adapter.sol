// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.0;

import {IERC20} from "../interfaces/IERC20.sol";
import {SafeERC20} from "../libs/SafeERC20.sol";
import {StyxAdapter} from "../shared/StyxAdapter.sol";
import {IUniV3Pool, IUniV3Quoter, IUniV3Factory, QParams} from "../interfaces/adapters/IUniswapV3.sol";

abstract contract UniswapV3likeAdapter is StyxAdapter {
    using SafeERC20 for IERC20;

    uint160 internal constant MAX_SQRT_RATIO =
        1461446703485210103287273052203988822378723970342;
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint256 public quoterGasLimit;
    address public quoter;

    constructor(
        string memory _name,
        uint256 _swapGasEstimate,
        address _quoter,
        uint256 _quoterGasLimit
    ) StyxAdapter(_name, _swapGasEstimate) {
        setQuoterGasLimit(_quoterGasLimit);
        setQuoter(_quoter);
    }

    /*//////////////////////////////////////////////////////////////
                                 UTILS
    //////////////////////////////////////////////////////////////*/

    function setQuoter(address newQuoter) public onlyOwner {
        quoter = newQuoter;
    }

    function setQuoterGasLimit(uint256 newLimit) public onlyOwner {
        require(newLimit != 0, "queryGasLimit can't be zero");
        quoterGasLimit = newLimit;
    }

    /*//////////////////////////////////////////////////////////////
                                 QUERIES
    //////////////////////////////////////////////////////////////*/

    function getQuoteForPool(
        address pool,
        int256 amountIn,
        address tokenIn,
        address tokenOut
    ) external view returns (uint256) {
        QParams memory params;
        params.amountIn = amountIn;
        params.tokenIn = tokenIn;
        params.tokenOut = tokenOut;
        return getQuoteForPool(pool, params);
    }

    function _query(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut
    ) internal view override returns (uint256 quote) {
        QParams memory params = getQParams(_amountIn, _tokenIn, _tokenOut);
        quote = getQuoteForBestPool(params);
    }

    function getQuoteForBestPool(
        QParams memory params
    ) internal view returns (uint256 quote) {
        address bestPool = getBestPool(params.tokenIn, params.tokenOut);
        if (bestPool != address(0)) quote = getQuoteForPool(bestPool, params);
    }

    function getBestPool(
        address token0,
        address token1
    ) internal view virtual returns (address mostLiquid);

    function getQuoteForPool(
        address pool,
        QParams memory params
    ) internal view returns (uint256) {
        (bool zeroForOne, uint160 priceLimit) = getZeroOneAndSqrtPriceLimitX96(
            params.tokenIn,
            params.tokenOut
        );
        (int256 amount0, int256 amount1) = getQuoteSafe(
            pool,
            zeroForOne,
            params.amountIn,
            priceLimit
        );
        return zeroForOne ? uint256(-amount1) : uint256(-amount0);
    }

    function getQuoteSafe(
        address pool,
        bool zeroForOne,
        int256 amountIn,
        uint160 priceLimit
    ) internal view returns (int256 amount0, int256 amount1) {
        bytes memory calldata_ = abi.encodeWithSignature(
            "quote(address,bool,int256,uint160)",
            pool,
            zeroForOne,
            amountIn,
            priceLimit
        );
        (bool success, bytes memory data) = staticCallQuoterRaw(calldata_);
        if (success) (amount0, amount1) = abi.decode(data, (int256, int256));
    }

    function staticCallQuoterRaw(
        bytes memory calldata_
    ) internal view returns (bool success, bytes memory data) {
        (success, data) = quoter.staticcall{gas: quoterGasLimit}(calldata_);
    }

    function getZeroOneAndSqrtPriceLimitX96(
        address tokenIn,
        address tokenOut
    ) internal pure returns (bool zeroForOne, uint160 sqrtPriceLimitX96) {
        zeroForOne = tokenIn < tokenOut;
        sqrtPriceLimitX96 = zeroForOne
            ? MIN_SQRT_RATIO + 1
            : MAX_SQRT_RATIO - 1;
    }

    /*//////////////////////////////////////////////////////////////
                                 SWAP
    //////////////////////////////////////////////////////////////*/

    function _swap(
        uint256 _amountIn,
        uint256 _amountOut,
        address _tokenIn,
        address _tokenOut,
        address _to
    ) internal override {
        QParams memory params = getQParams(_amountIn, _tokenIn, _tokenOut);
        uint256 amountOut = _underlyingSwap(params, new bytes(0));
        require(amountOut >= _amountOut, "Insufficient amountOut");
        _returnTo(_tokenOut, amountOut, _to);
    }

    function getQParams(
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) internal pure returns (QParams memory params) {
        params = QParams({
            amountIn: int256(amountIn),
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: 0
        });
    }

    function _underlyingSwap(
        QParams memory params,
        bytes memory callbackData
    ) internal virtual returns (uint256) {
        address pool = getBestPool(params.tokenIn, params.tokenOut);
        (bool zeroForOne, uint160 priceLimit) = getZeroOneAndSqrtPriceLimitX96(
            params.tokenIn,
            params.tokenOut
        );
        (int256 amount0, int256 amount1) = IUniV3Pool(pool).swap(
            address(this),
            zeroForOne,
            int256(params.amountIn),
            priceLimit,
            callbackData
        );
        return zeroForOne ? uint256(-amount1) : uint256(-amount0);
    }
}

contract UniswapV3Adapter is UniswapV3likeAdapter {
    using SafeERC20 for IERC20;

    address immutable FACTORY;
    mapping(uint24 => bool) public isFeeAmountEnabled;
    uint24[] public feeAmounts;

    constructor(
        string memory _name,
        uint256 _swapGasEstimate,
        uint256 _quoterGasLimit,
        address _quoter,
        address _factory
    ) UniswapV3likeAdapter(_name, _swapGasEstimate, _quoter, _quoterGasLimit) {
        addDefaultFeeAmounts();
        FACTORY = _factory;
    }

    function addDefaultFeeAmounts() internal {
        addFeeAmount(500);
        addFeeAmount(3000);
        addFeeAmount(10000);
    }

    function enableFeeAmounts(uint24[] calldata _amounts) external onlyOwner {
        for (uint256 i; i < _amounts.length; ++i) enableFeeAmount(_amounts[i]);
    }

    function enableFeeAmount(uint24 _fee) internal {
        require(!isFeeAmountEnabled[_fee], "Fee already enabled");
        if (IUniV3Factory(FACTORY).feeAmountTickSpacing(_fee) == 0)
            revert("Factory doesn't support fee");
        addFeeAmount(_fee);
    }

    function addFeeAmount(uint24 _fee) internal {
        isFeeAmountEnabled[_fee] = true;
        feeAmounts.push(_fee);
    }

    function getBestPool(
        address token0,
        address token1
    ) internal view override returns (address mostLiquid) {
        uint128 deepestLiquidity;
        for (uint256 i; i < feeAmounts.length; ++i) {
            address pool = IUniV3Factory(FACTORY).getPool(
                token0,
                token1,
                feeAmounts[i]
            );
            if (pool == address(0)) continue;
            uint128 liquidity = IUniV3Pool(pool).liquidity();
            if (liquidity > deepestLiquidity) {
                deepestLiquidity = liquidity;
                mostLiquid = pool;
            }
        }
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata
    ) external {
        if (amount0Delta > 0) {
            IERC20(IUniV3Pool(msg.sender).token0()).transfer(
                msg.sender,
                uint256(amount0Delta)
            );
        } else {
            IERC20(IUniV3Pool(msg.sender).token1()).transfer(
                msg.sender,
                uint256(amount1Delta)
            );
        }
    }
}
