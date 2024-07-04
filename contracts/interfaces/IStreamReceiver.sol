// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

interface IStreamReceiver {
    error IStreamInvalidReceiver(address to);

    function onStreamTransfered(
        address from,
        address to,
        uint256 tokenId
    ) external;
}
