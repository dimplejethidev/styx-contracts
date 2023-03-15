// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPairFactory {
    function isPair(address) external view returns (bool);

    function pairCodeHash() external view returns (bytes32);
}

interface IPair {
    function getAmountOut(uint256, address) external view returns (uint256);

    function swap(uint256, uint256, address, bytes calldata) external;
}
