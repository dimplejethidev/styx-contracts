// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {Owned} from "../acs/Owned.sol";

/// @title Styx Adapter
/// @author 0xpeche
/// @dev Inspired by Yak
/// @notice Styx Adapter
abstract contract StyxAdapter is Owned {
    using SafeERC20 for IERC20;

    event AdapterSwap(
        address indexed _tokenFrom,
        address indexed _tokenTo,
        uint256 _amountIn,
        uint256 _amountOut
    );
    event UpdatedGasEstimate(address indexed _adapter, uint256 _newEstimate);
    event Recovered(address indexed _asset, uint256 amount);

    uint256 internal constant UINT_MAX = type(uint256).max;
    uint256 public swapGasEstimate;
    string public name;

    constructor(string memory _name, uint256 _gasEstimate) {
        setName(_name);
        setSwapGasEstimate(_gasEstimate);
    }

    function setName(string memory _name) internal {
        require(bytes(_name).length != 0, "adapter/invalid-name");
        name = _name;
    }

    function setSwapGasEstimate(uint256 _estimate) public onlyOwner {
        require(_estimate != 0, "adapter/invalid-gas-estimate");
        swapGasEstimate = _estimate;
        emit UpdatedGasEstimate(address(this), _estimate);
    }

    function query(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut
    ) external view returns (uint256) {
        return _query(_amountIn, _tokenIn, _tokenOut);
    }

    function swap(
        uint256 _amountIn,
        uint256 _amountOut,
        address _fromToken,
        address _toToken,
        address _to
    ) external {
        uint256 toBal0 = IERC20(_toToken).balanceOf(_to);
        _swap(_amountIn, _amountOut, _fromToken, _toToken, _to);
        uint256 diff = IERC20(_toToken).balanceOf(_to) - toBal0;
        require(diff >= _amountOut, "adapter/insuficent-amount-out");
        emit AdapterSwap(_fromToken, _toToken, _amountIn, _amountOut);
    }

    function _returnTo(address _token, uint256 _amount, address _to) internal {
        if (address(this) != _to) IERC20(_token).safeTransfer(_to, _amount);
    }

    function _swap(
        uint256 _amountIn,
        uint256 _amountOut,
        address _fromToken,
        address _toToken,
        address _to
    ) internal virtual;

    function _query(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut
    ) internal view virtual returns (uint256);

    receive() external payable {}
}
