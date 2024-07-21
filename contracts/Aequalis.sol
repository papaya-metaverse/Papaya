// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { Context } from "@openzeppelin/contracts/utils/Context.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { BySig, EIP712, ECDSA } from "@1inch/solidity-utils/contracts/mixins/BySig.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import { IPapaya, UserLib } from "./Papaya.sol";

import "./interfaces/IPapayaInteractions.sol";
import "./interfaces/IAequalis.sol";

contract Aequalis is IAequalis, EIP712, BySig {
    using Address for address;

    address immutable PAPAYA;

    mapping(address account => uint256 update) public users;
    uint256 public usersCount;

    constructor(address PAPAYA_) EIP712(type(Aequalis).name, "1"){ PAPAYA = PAPAYA_; }

    function deposit(address signer, SignedCall calldata sig, bytes calldata signature) external {
        if(ECDSA.recoverOrIsValidSignature(signer, hashBySig(sig), signature)) {
            users[signer] = block.timestamp;
            usersCount++;

            PAPAYA.functionDelegateCall(sig.data);
        } else {
            revert WrongSignature();
        }
    }

    function withdraw() external {
        if(users[_msgSender()] == 0) {
            revert WrongSender();
        }

        UserLib.User memory crtUser = IPapayaInteractions(PAPAYA).users(_msgSender());

        uint256 amount = uint256(crtUser.incomeRate) * (block.timestamp - users[_msgSender()]) / usersCount;

        users[_msgSender()] = block.timestamp;

        IPapaya(PAPAYA).pay(_msgSender(), amount);
    }

    function _msgSender() internal view override(BySig) returns (address) {
        return super._msgSender();
    }

    function _chargeSigner(address signer, address relayer, address token, uint256 amount, bytes calldata /* extraData */) internal override {
        revert InvalidAction();
    }

}
