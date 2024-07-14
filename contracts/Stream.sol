// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import { IStreamInteraction } from "./interfaces/IStreamInteraction.sol";
import { IStreamReceiver } from "./interfaces/IStreamReceiver.sol";
import { IStreamRevoker } from "./interfaces/IStreamRevoker.sol";

import { IPapaya } from "./interfaces/IPapaya.sol";
//Что надо сделать, надо допилить под стандарт, чтобы были операторы и все остальное говно
contract Stream is ERC721, IStreamInteraction {
    address public immutable PAPAYA;

    uint256 constant STREAM_CALL_GAS_LIMIT = 300_000;

    modifier onlyPapaya() {
        if(_msgSender() != PAPAYA) revert AccessDenied();
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        address PAPAYA_
    ) ERC721(name_, symbol_) {
        PAPAYA = PAPAYA_;
    }

    function balanceOf(address owner) public view virtual override(ERC721) returns (uint256) {
        (address[] memory to, ) = IPapaya(PAPAYA).allSubscriptions(owner);
        return to.length;
    }

    function ownerOf(uint256 tokenId) public view virtual override(ERC721) returns (address) {
        return _owner(tokenId);
    }

    function tokenURI(uint256 tokenId) public view virtual override(ERC721) returns (string memory) {
        return _baseURI();
    }

    function _baseURI() internal view virtual override(ERC721) returns (string memory) {
        return "";
    }

    function safeMint(address to, uint256 tokenId) external onlyPapaya {
        _safeMint(to, tokenId, "");
    }

    function burn(uint256 tokenId) external onlyPapaya {
        _burn(tokenId);
    }

    function getApproved(uint256 tokenId) public view virtual override(ERC721) returns (address) {
        return _getApproved(tokenId);
    }

    function _safeMint(address to, uint256 tokenId, bytes memory data) internal virtual override(ERC721) {
        if (to == address(0)) {
            revert IStreamReceiver.IStreamInvalidReceiver(address(0));
        }
        address previousOwner = _update(to, tokenId, address(0));
        if (previousOwner != address(0)) {
            revert IStreamInvalidSender(address(0));
        }
    }

    function _owner(uint256 tokenId) internal view returns (address author) {
        (author, ) = IPapaya(PAPAYA).subscriptionActors(tokenId);
    }

    function _update(address to, uint256 tokenId, address auth) internal virtual override(ERC721) returns (address) {
        // Execute the update
        address from = super._update(to, tokenId, auth);

        if (from != address(0)) {
            _checkOnERC721Revoked(from, to, tokenId);
        }

        if (to != address(0)) {
            IStreamReceiver(PAPAYA).onStreamTransfered(from, to, tokenId);
        }

        return from;
    }

    function _checkOnERC721Revoked(
        address from,
        address to,
        uint256 tokenId
    ) private {
        bytes4 selector = IStreamRevoker.onStreamRevoked.selector;
        uint256 gasLimit = STREAM_CALL_GAS_LIMIT;
        assembly ("memory-safe") { // solhint-disable-line no-inline-assembly
            let ptr := mload(0x40)
            mstore(ptr, selector)
            mstore(add(ptr, 0x04), from)
            mstore(add(ptr, 0x24), to)
            mstore(add(ptr, 0x44), tokenId)

            let gasLeft := gas()
            if iszero(call(gasLimit, from, 0, ptr, 0x64, 0, 0)) {
                if lt(div(mul(gasLeft, 63), 64), gasLimit) {
                    returndatacopy(ptr, 0, returndatasize())
                    revert(ptr, returndatasize())
                }
            }
        }
    }
}
