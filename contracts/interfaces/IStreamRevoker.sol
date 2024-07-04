// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

interface IStreamRevoker {
    error InvalidStreamRevoker();

    function onStreamRevoked(
        address from,
        address to,
        uint256 tokenId
    ) external;
}
