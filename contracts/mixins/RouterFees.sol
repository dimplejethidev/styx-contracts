// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../acs/Owned.sol";

contract RouterFees is Owned {
    uint256 public constant FEE_DENOMINATOR = 1e4;
    uint256 public MIN_FEE = 0;
    address public FEE_CLAIMER;

    event UpdatedMinFee(uint256 _oldMinFee, uint256 _newMinFee);
    event UpdatedFeeClaimer(address _oldFeeClaimer, address _newFeeClaimer);

    /*//////////////////////////////////////////////////////////////
                                 SETTERS
    //////////////////////////////////////////////////////////////*/

    function setMinFee(uint256 _fee) external onlyOwner {
        emit UpdatedMinFee(MIN_FEE, _fee);
        MIN_FEE = _fee;
    }

    function setFeeClaimer(address _claimer) public onlyOwner {
        emit UpdatedFeeClaimer(FEE_CLAIMER, _claimer);
        FEE_CLAIMER = _claimer;
    }

    /*//////////////////////////////////////////////////////////////
                                 HELPERS
    //////////////////////////////////////////////////////////////*/

    function _applyFee(
        uint256 _amountIn,
        uint256 _fee
    ) internal view returns (uint256) {
        require(_fee >= MIN_FEE, "router/fee-too-low");
        return (_amountIn * (FEE_DENOMINATOR - _fee)) / FEE_DENOMINATOR;
    }
}
