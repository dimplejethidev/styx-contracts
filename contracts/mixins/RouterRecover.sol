// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IWETH.sol";
import "../acs/Owned.sol";

contract RouterRecover is Owned {
    using SafeERC20 for IERC20;
    event Recovered(address indexed _asset, uint256 amount);

    function recoverERC20(
        address _tokenAddress,
        uint256 _tokenAmount
    ) external onlyOwner {
        IERC20(_tokenAddress).safeTransfer(msg.sender, _tokenAmount);
        emit Recovered(_tokenAddress, _tokenAmount);
    }

    function recoverNATIVE(uint256 _amount) external onlyOwner {
        payable(msg.sender).transfer(_amount);
        emit Recovered(address(0), _amount);
    }
}
