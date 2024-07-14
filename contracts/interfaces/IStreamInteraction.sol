// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

interface IStreamInteraction {
    error IStreamInvalidSender(address to);
    error AccessDenied();

    function safeMint(address to, uint256 tokenId) external;
    function burn(uint256 tokenId) external;
}
