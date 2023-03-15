// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20} from "./interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {Owned} from "./acs/Owned.sol";
import {IAdapter} from "./interfaces/IAdapter.sol";
import {RouterAdapters} from "./mixins/RouterAdapters.sol";
import {RouterRecover} from "./mixins/RouterRecover.sol";
import {RouterFees} from "./mixins/RouterFees.sol";
import {IAllowanceTransfer} from "./interfaces/IAllowanceTransfer.sol";
import {BytesManipulation} from "./libs/BytesManipulation.sol";

/// @title Styx Router
/// @author 0xpeche
/// @dev Inspired by Yak
/// @notice Styx Router
contract StyxRouter is Owned, RouterAdapters, RouterRecover, RouterFees {
    using SafeERC20 for IERC20;

    IAllowanceTransfer internal immutable PERMIT2;

    event Swap(
        address indexed _tokenIn,
        address indexed _tokenOut,
        uint256 _amountIn,
        uint256 _amountOut
    );

    struct Query {
        address adapter;
        address tokenIn;
        address tokenOut;
        uint256 amountOut;
    }

    struct Offer {
        bytes amounts;
        bytes adapters;
        bytes path;
        uint256 gasEstimate;
    }

    struct FormattedOffer {
        uint256[] amounts;
        address[] adapters;
        address[] path;
        uint256 gasEstimate;
    }

    struct Trade {
        uint256 amountIn;
        uint256 amountOut;
        address[] path;
        address[] adapters;
    }

    constructor(
        address[] memory _adapters,
        address[] memory _trustedTokens,
        address _feeClaimer,
        address _wnative,
        address _permit2
    ) RouterAdapters(_adapters, _trustedTokens, _wnative) {
        setFeeClaimer(_feeClaimer);
        PERMIT2 = IAllowanceTransfer(_permit2);
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function _wrap(uint256 _amount) internal {
        IWETH(WNATIVE).deposit{value: _amount}();
    }

    function _unwrap(uint256 _amount) internal {
        IWETH(WNATIVE).withdraw(_amount);
    }

    /**
     * @notice Return tokens to user
     * @dev Pass address(0) for NATIVE
     * @param _token address
     * @param _amount tokens to return
     * @param _to address where funds should be sent to
     */
    function _returnTokensTo(
        address _token,
        uint256 _amount,
        address _to
    ) internal {
        if (address(this) != _to) {
            if (_token == NATIVE) {
                payable(_to).transfer(_amount);
            } else {
                IERC20(_token).safeTransfer(_to, _amount);
            }
        }
    }

    /**
     * @notice Makes a deep copy of Offer struct
     * @param _queries queries
     */
    function _cloneOffer(
        Offer memory _queries
    ) internal pure returns (Offer memory) {
        return
            Offer(
                _queries.amounts,
                _queries.adapters,
                _queries.path,
                _queries.gasEstimate
            );
    }

    /**
     * @notice Appends Query elements to Offer struct
     * @param _queries queries
     */
    function _addQuery(
        Offer memory _queries,
        uint256 _amount,
        address _adapter,
        address _tokenOut,
        uint256 _gasEstimate
    ) internal pure {
        _queries.path = BytesManipulation.mergeBytes(
            _queries.path,
            BytesManipulation.toBytes(_tokenOut)
        );
        _queries.amounts = BytesManipulation.mergeBytes(
            _queries.amounts,
            BytesManipulation.toBytes(_amount)
        );
        _queries.adapters = BytesManipulation.mergeBytes(
            _queries.adapters,
            BytesManipulation.toBytes(_adapter)
        );
        _queries.gasEstimate += _gasEstimate;
    }

    /**
     * @notice Converts byte-arrays to an array of integers
     * @param _amounts amounts
     */
    function _formatAmounts(
        bytes memory _amounts
    ) internal pure returns (uint256[] memory) {
        // Format amounts
        uint256 chunks = _amounts.length / 32;
        uint256[] memory amountsFormatted = new uint256[](chunks);
        for (uint256 i = 0; i < chunks; i++) {
            amountsFormatted[i] = BytesManipulation.bytesToUint256(
                i * 32 + 32,
                _amounts
            );
        }
        return amountsFormatted;
    }

    /**
     * @notice Converts byte-array to an array of addresses
     * @param _addresses addresses
     */
    function _formatAddresses(
        bytes memory _addresses
    ) internal pure returns (address[] memory) {
        uint256 chunks = _addresses.length / 32;
        address[] memory addressesFormatted = new address[](chunks);
        for (uint256 i = 0; i < chunks; i++) {
            addressesFormatted[i] = BytesManipulation.bytesToAddress(
                i * 32 + 32,
                _addresses
            );
        }
        return addressesFormatted;
    }

    /**
     * @notice Formats elements in the Offer object from byte-arrays to integers and addresses
     * @param _queries addresses
     */
    function _formatOffer(
        Offer memory _queries
    ) internal pure returns (FormattedOffer memory) {
        return
            FormattedOffer(
                _formatAmounts(_queries.amounts),
                _formatAddresses(_queries.adapters),
                _formatAddresses(_queries.path),
                _queries.gasEstimate
            );
    }

    /*//////////////////////////////////////////////////////////////
                                 QUERIES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Query single adapter
     * @param _amountIn amount token in
     * @param _tokenIn address token in
     * @param _tokenOut address token out
     * @param _index adapter index
     */
    function queryAdapter(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut,
        uint8 _index
    ) external view returns (uint256) {
        IAdapter _adapter = IAdapter(ADAPTERS[_index]);
        uint256 amountOut = _adapter.query(_amountIn, _tokenIn, _tokenOut);
        return amountOut;
    }

    /**
     * @notice Query specified adapters
     * @param _amountIn amount token in
     * @param _tokenIn address token in
     * @param _tokenOut address token out
     * @param _options adapters
     */
    function queryNoSplit(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut,
        uint8[] calldata _options
    ) public view returns (Query memory) {
        Query memory bestQuery;
        for (uint8 i; i < _options.length; i++) {
            address _adapter = ADAPTERS[_options[i]];
            uint256 amountOut = IAdapter(_adapter).query(
                _amountIn,
                _tokenIn,
                _tokenOut
            );
            if (i == 0 || amountOut > bestQuery.amountOut) {
                bestQuery = Query(_adapter, _tokenIn, _tokenOut, amountOut);
            }
        }
        return bestQuery;
    }

    /**
     * @notice Query all adapters
     * @param _amountIn amount token in
     * @param _tokenIn address token in
     * @param _tokenOut address token out
     */
    function queryNoSplit(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut
    ) public view returns (Query memory) {
        Query memory bestQuery;
        for (uint8 i; i < ADAPTERS.length; i++) {
            address _adapter = ADAPTERS[i];
            uint256 amountOut = IAdapter(_adapter).query(
                _amountIn,
                _tokenIn,
                _tokenOut
            );
            if (i == 0 || amountOut > bestQuery.amountOut) {
                bestQuery = Query(_adapter, _tokenIn, _tokenOut, amountOut);
            }
        }
        return bestQuery;
    }

    /**
     * @notice Return path with best returns between two tokens
     * @param _amountIn amount token in
     * @param _tokenIn address token in
     * @param _tokenOut address token out
     * @param _maxSteps max hops
     * @param _gasPrice gas price
     */
    function findBestPathWithGas(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut,
        uint256 _maxSteps,
        uint256 _gasPrice
    ) external view returns (FormattedOffer memory) {
        require(_maxSteps > 0 && _maxSteps < 5, "router/invalid-max-steps");
        Offer memory queries;
        queries.amounts = BytesManipulation.toBytes(_amountIn);
        queries.path = BytesManipulation.toBytes(_tokenIn);
        uint256 gasPriceInExitTkn = _gasPrice > 0
            ? getGasPriceInExitTkn(_gasPrice, _tokenOut)
            : 0;
        queries = _findBestPath(
            _amountIn,
            _tokenIn,
            _tokenOut,
            _maxSteps,
            queries,
            gasPriceInExitTkn
        );
        if (queries.adapters.length == 0) {
            queries.amounts = "";
            queries.path = "";
        }
        return _formatOffer(queries);
    }

    /**
     * @notice Find the market price between gas-asset(native) and token-out and express gas price in token-out
     * @param _gasPrice amount token in
     * @param _tokenOut address token out
     */
    function getGasPriceInExitTkn(
        uint256 _gasPrice,
        address _tokenOut
    ) internal view returns (uint256 price) {
        FormattedOffer memory gasQuery = findBestPath(
            1e18,
            WNATIVE,
            _tokenOut,
            2
        );
        if (gasQuery.path.length != 0) {
            // Leave result in nWei to preserve precision for assets with low decimal places
            price =
                (gasQuery.amounts[gasQuery.amounts.length - 1] * _gasPrice) /
                1e9;
        }
    }

    /**
     * @notice Return path with best returns between two tokens
     * @param _amountIn amount token in
     * @param _tokenIn address token in
     * @param _tokenOut address token out
     * @param _maxSteps max hops
     */
    function findBestPath(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut,
        uint256 _maxSteps
    ) public view returns (FormattedOffer memory) {
        require(_maxSteps > 0 && _maxSteps < 5, "router/invalid-max-steps");
        Offer memory queries;
        queries.amounts = BytesManipulation.toBytes(_amountIn);
        queries.path = BytesManipulation.toBytes(_tokenIn);
        queries = _findBestPath(
            _amountIn,
            _tokenIn,
            _tokenOut,
            _maxSteps,
            queries,
            0
        );
        // If no paths are found return empty struct
        if (queries.adapters.length == 0) {
            queries.amounts = "";
            queries.path = "";
        }
        return _formatOffer(queries);
    }

    function _findBestPath(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut,
        uint256 _maxSteps,
        Offer memory _queries,
        uint256 _tknOutPriceNwei
    ) internal view returns (Offer memory) {
        Offer memory bestOption = _cloneOffer(_queries);
        uint256 bestAmountOut;
        uint256 gasEstimate;
        bool withGas = _tknOutPriceNwei != 0;

        // First check if there is a path directly from tokenIn to tokenOut
        Query memory queryDirect = queryNoSplit(_amountIn, _tokenIn, _tokenOut);

        if (queryDirect.amountOut != 0) {
            if (withGas) {
                gasEstimate = IAdapter(queryDirect.adapter).swapGasEstimate();
            }
            _addQuery(
                bestOption,
                queryDirect.amountOut,
                queryDirect.adapter,
                queryDirect.tokenOut,
                gasEstimate
            );
            bestAmountOut = queryDirect.amountOut;
        }
        // Only check the rest if they would go beyond step limit (Need at least 2 more steps)
        if (_maxSteps > 1 && _queries.adapters.length / 32 <= _maxSteps - 2) {
            // Check for paths that pass through trusted tokens
            for (uint256 i = 0; i < TRUSTED_TOKENS.length; i++) {
                if (_tokenIn == TRUSTED_TOKENS[i]) {
                    continue;
                }
                // Loop through all adapters to find the best one for swapping tokenIn for one of the trusted tokens
                Query memory bestSwap = queryNoSplit(
                    _amountIn,
                    _tokenIn,
                    TRUSTED_TOKENS[i]
                );
                if (bestSwap.amountOut == 0) {
                    continue;
                }
                // Explore options that connect the current path to the tokenOut
                Offer memory newOffer = _cloneOffer(_queries);
                if (withGas) {
                    gasEstimate = IAdapter(bestSwap.adapter).swapGasEstimate();
                }
                _addQuery(
                    newOffer,
                    bestSwap.amountOut,
                    bestSwap.adapter,
                    bestSwap.tokenOut,
                    gasEstimate
                );
                newOffer = _findBestPath(
                    bestSwap.amountOut,
                    TRUSTED_TOKENS[i],
                    _tokenOut,
                    _maxSteps,
                    newOffer,
                    _tknOutPriceNwei
                ); // Recursive step
                address tokenOut = BytesManipulation.bytesToAddress(
                    newOffer.path.length,
                    newOffer.path
                );
                uint256 amountOut = BytesManipulation.bytesToUint256(
                    newOffer.amounts.length,
                    newOffer.amounts
                );
                // Check that the last token in the path is the tokenOut and update the new best option if neccesary
                if (_tokenOut == tokenOut && amountOut > bestAmountOut) {
                    if (newOffer.gasEstimate > bestOption.gasEstimate) {
                        uint256 gasCostDiff = (_tknOutPriceNwei *
                            (newOffer.gasEstimate - bestOption.gasEstimate)) /
                            1e9;
                        uint256 priceDiff = amountOut - bestAmountOut;
                        if (gasCostDiff > priceDiff) {
                            continue;
                        }
                    }
                    bestAmountOut = amountOut;
                    bestOption = newOffer;
                }
            }
        }
        return bestOption;
    }

    /// @notice Performs a transferFrom on Permit2
    /// @param token The token to transfer
    /// @param from The address to transfer from
    /// @param to The recipient of the transfer
    /// @param amount The amount to transfer
    function permit2TransferFrom(
        address token,
        address from,
        address to,
        uint160 amount
    ) internal {
        PERMIT2.transferFrom(from, to, amount, token);
    }

    /*//////////////////////////////////////////////////////////////
                                 SWAPS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Execute ERC20-ERC20 Swap
     * @param _trade amount token in
     * @param _to address token in
     * @param _fee address token out
     * @param permitSingle permit
     * @param signature signature
     */
    function swap(
        Trade calldata _trade,
        address _to,
        uint256 _fee,
        IAllowanceTransfer.PermitSingle memory permitSingle,
        bytes calldata signature
    ) public {
        PERMIT2.permit(msg.sender, permitSingle, signature);
        _swap(_trade, msg.sender, _to, _fee);
    }

    /**
     * @notice Execute NATIVE-ERC20 Swap
     * @param _trade amount token in
     * @param _to address token in
     * @param _fee address token out
     * @param permitSingle permit
     * @param signature signature
     */
    function swapFromNative(
        Trade calldata _trade,
        address _to,
        uint256 _fee,
        IAllowanceTransfer.PermitSingle memory permitSingle,
        bytes calldata signature
    ) external payable {
        PERMIT2.permit(msg.sender, permitSingle, signature);
        require(_trade.path[0] == WNATIVE, "router/wrong-path");
        _wrap(_trade.amountIn);
        _swap(_trade, msg.sender, _to, _fee);
    }

    /**
     * @notice Execute ERC20-NATIVE Swap
     * @param _trade amount token in
     * @param _to address token in
     * @param _fee address token out
     * @param permitSingle permit
     * @param signature signature
     */
    function swapToNative(
        Trade calldata _trade,
        address _to,
        uint256 _fee,
        IAllowanceTransfer.PermitSingle memory permitSingle,
        bytes calldata signature
    ) external payable {
        PERMIT2.permit(msg.sender, permitSingle, signature);
        require(
            _trade.path[_trade.path.length - 1] == WNATIVE,
            "router/wrong-path"
        );
        uint256 returnAmount = _swap(_trade, msg.sender, _to, _fee);
        _unwrap(returnAmount);
        _returnTokensTo(NATIVE, returnAmount, _to);
    }

    /**
     * @notice Execute Swap
     * @param _trade amount token in
     * @param _to address token in
     * @param _fee address token out
     */
    function _swap(
        Trade calldata _trade,
        address _from,
        address _to,
        uint256 _fee
    ) internal returns (uint256) {
        uint256[] memory amounts = new uint256[](_trade.path.length);
        msg.sender != FEE_CLAIMER ? require(_fee > 0) : _fee = 0;
        if (_fee > 0 || MIN_FEE > 0) {
            // Transfer fees to the claimer account and decrease initial amount
            amounts[0] = _applyFee(_trade.amountIn, _fee);
            permit2TransferFrom(
                _trade.path[0],
                _from,
                FEE_CLAIMER,
                uint160(_trade.amountIn - amounts[0])
            );
        } else {
            amounts[0] = _trade.amountIn;
        }
        permit2TransferFrom(
            _trade.path[0],
            _from,
            _trade.adapters[0],
            uint160(amounts[0])
        );
        // Get amounts that will be swapped
        uint8 i;
        do {
            amounts[i + 1] = IAdapter(_trade.adapters[i]).query(
                amounts[i],
                _trade.path[i],
                _trade.path[i + 1]
            );
            unchecked {
                ++i;
            }
        } while (i < _trade.adapters.length);

        require(
            amounts[amounts.length - 1] >= _trade.amountOut,
            "router/output-too-low"
        );

        i = 0;
        do {
            // All adapters should transfer output token to the following target
            // All targets are the adapters, expect for the last swap where tokens are sent out
            address targetAddress = i < _trade.adapters.length - 1
                ? _trade.adapters[i + 1]
                : _to;
            IAdapter(_trade.adapters[i]).swap(
                amounts[i],
                amounts[i + 1],
                _trade.path[i],
                _trade.path[i + 1],
                targetAddress
            );
            unchecked {
                ++i;
            }
        } while (i < _trade.adapters.length);

        emit Swap(
            _trade.path[0],
            _trade.path[_trade.path.length - 1],
            _trade.amountIn,
            amounts[amounts.length - 1]
        );
        return amounts[amounts.length - 1];
    }
}
