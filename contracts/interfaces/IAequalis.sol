// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

interface IAequalis {
    error InvalidAction();
    error WrongSender();

    function withdraw() external;
}
