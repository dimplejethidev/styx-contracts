// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IWETH.sol";
import "../acs/Owned.sol";

contract RouterAdapters is Owned {
    using SafeERC20 for IERC20;

    address public immutable WNATIVE;
    address public constant NATIVE = address(0);
    address[] public TRUSTED_TOKENS;
    address[] public ADAPTERS;

    event UpdatedTrustedTokens(address[] _newTrustedTokens);
    event UpdatedAdapters(address[] _newAdapters);

    constructor(
        address[] memory _adapters,
        address[] memory _trustedTokens,
        address _wnative
    ) {
        _setAllowanceForWrapping(_wnative);
        setTrustedTokens(_trustedTokens);
        setAdapters(_adapters);
        WNATIVE = _wnative;
    }

    /*//////////////////////////////////////////////////////////////
                                 SETTERS
    //////////////////////////////////////////////////////////////*/

    function _setAllowanceForWrapping(address _wnative) internal {
        IERC20(_wnative).safeApprove(_wnative, type(uint256).max);
    }

    function setTrustedTokens(
        address[] memory _trustedTokens
    ) public onlyOwner {
        emit UpdatedTrustedTokens(_trustedTokens);
        TRUSTED_TOKENS = _trustedTokens;
    }

    function setAdapters(address[] memory _adapters) public onlyOwner {
        emit UpdatedAdapters(_adapters);
        ADAPTERS = _adapters;
    }
}
