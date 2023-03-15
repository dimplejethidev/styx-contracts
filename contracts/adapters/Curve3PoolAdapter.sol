// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {IERC20} from "../interfaces/IERC20.sol";
import {SafeERC20} from "../libs/SafeERC20.sol";
import {ICurvePool128} from "../interfaces/adapters/ICurvePool128.sol";
import {StyxAdapter} from "../shared/StyxAdapter.sol";

contract Curve3PoolAdapter is StyxAdapter {
    using SafeERC20 for IERC20;

    address public immutable POOL;
    mapping(address => int128) public tokenIndex;
    mapping(address => bool) public isPoolToken;

    constructor(
        string memory _name,
        address _pool,
        uint256 _swapGasEstimate
    ) StyxAdapter(_name, _swapGasEstimate) {
        POOL = _pool;
        _setPoolTokens(_pool);
    }

    /*//////////////////////////////////////////////////////////////
                                 UTILS
    //////////////////////////////////////////////////////////////*/

    // Mapping indicator which tokens are included in the pool
    function _setPoolTokens(address _pool) internal {
        for (uint256 i = 0; true; i++) {
            try ICurvePool128(_pool).coins(i) returns (address token) {
                _approveToken(_pool, token, int128(int256(i)));
            } catch {
                break;
            }
        }
    }

    function _approveToken(
        address _pool,
        address _token,
        int128 _index
    ) internal {
        IERC20(_token).safeApprove(_pool, UINT_MAX);
        tokenIndex[_token] = _index;
        isPoolToken[_token] = true;
    }

    /*//////////////////////////////////////////////////////////////
                                 QUERIES
    //////////////////////////////////////////////////////////////*/

    function _query(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut
    ) internal view override returns (uint256) {
        if (!_validArgs(_amountIn, _tokenIn, _tokenOut)) return 0;
        uint256 amountOut = _getDySafe(_amountIn, _tokenIn, _tokenOut);
        // Account for possible rounding error
        return amountOut > 0 ? amountOut - 1 : 0;
    }

    function _validArgs(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut
    ) internal view returns (bool) {
        return
            _amountIn != 0 &&
            _tokenIn != _tokenOut &&
            isPoolToken[_tokenIn] &&
            isPoolToken[_tokenOut];
    }

    function _getDySafe(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut
    ) internal view returns (uint256) {
        try
            ICurvePool128(POOL).get_dy(
                tokenIndex[_tokenIn],
                tokenIndex[_tokenOut],
                _amountIn
            )
        returns (uint256 amountOut) {
            return amountOut;
        } catch {
            return 0;
        }
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
        ICurvePool128(POOL).exchange(
            tokenIndex[_tokenIn],
            tokenIndex[_tokenOut],
            _amountIn,
            _amountOut
        );
        // Confidently transfer amount-out
        _returnTo(_tokenOut, _amountOut, _to);
    }
}
