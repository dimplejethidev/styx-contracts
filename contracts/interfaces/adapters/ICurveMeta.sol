// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMetaPool {
    function get_dy_underlying(
        int128,
        int128,
        uint256
    ) external view returns (uint256);

    function exchange_underlying(int128, int128, uint256, uint256) external;

    function coins(uint256) external view returns (address);
}

interface IBasePool {
    function coins(uint256) external view returns (address);
}
