// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import { IStreamInteraction } from "./interfaces/IStreamInteraction.sol";
import { IStreamReceiver } from "./interfaces/IStreamReceiver.sol";
import { IStreamRevoker } from "./interfaces/IStreamRevoker.sol";

import { IPapaya } from "./interfaces/IPapaya.sol";

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

    function tokenURI(uint256 tokenId) public view virtual override(ERC721) returns (string memory) {
        return _baseURI();
    }

    function _baseURI() internal view virtual override(ERC721) returns (string memory) {
        return "";
    }

    function safeMint(address to, uint256 tokenId, bytes calldata data) external onlyPapaya {
        _safeMint(to, tokenId, data);
    }

    function burn(uint256 tokenId) external onlyPapaya {
        _burn(tokenId);
    }

    function _update(address to, uint256 tokenId, address auth) internal virtual override(ERC721) returns (address) {
        address from = super._update(to, tokenId, auth);

        if(from != address(0)) {
            _onERC721Removed(from, to, tokenId);
        }

        if(from != address(0) && to != address(0)) {
            IStreamReceiver(PAPAYA).onStreamTransfered(from, to, tokenId);
        }

        return from;
    }
//This method prevents reverts
    function _onERC721Removed(
        address from,
        address to,
        uint256 tokenId
    ) private {
        bytes4 selector = IStreamRevoker.onERC721Removed.selector;
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
