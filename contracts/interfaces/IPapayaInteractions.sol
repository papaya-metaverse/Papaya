// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import "../library/UserLib.sol";

interface IPapayaInteractions {
    function users(address) external returns (UserLib.User calldata);
}