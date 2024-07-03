// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC721ReceiverExtend } from "./interfaces/IERC721ReceiverExtend.sol";
import { IStream, IERC721 } from "./interfaces/IStream.sol";

contract Stream is IStream, ERC721, Ownable {
    modifier onlyApproved(address streamOwner) {
        if(!isApprovedForAll(streamOwner, owner())){
            _setApprovalForAll(streamOwner, owner(), true);
        }
        _;
    }

    // modifier onlyPapaya() {
        // if(_msgSender() != papaya_) revert AccessDenied();
        // _;
    // }

    //onlyApproved надо исправить, лучше оставить бекдор для папайи
    constructor(
        string memory name_,
        string memory symbol_,
        address owner_
    ) ERC721(name_, symbol_) Ownable(owner_) {}

    function safeMint(address to, uint256 tokenId) external onlyOwner {
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId) external onlyOwner {
        _burn(tokenId);
        _checkOnERC721Revoked(ownerOf(tokenId), address(0), tokenId, ""); //Это нужно перенести в апдейт
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        super._update(to, tokenId, auth);
        _callOwner(from, to, tokenId, "");
    }

    function _checkOnERC721Revoked( //Переделать исходя из идеи что стрим буквально не идет, а не по факту существования
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private {
        uint g0 = gasleft();
        try
            IERC721ReceiverExtend(from).onERC721Revoked/*{gaslimit: }*/(
                _msgSender(),
                from,
                tokenId,
                data
            )
        returns (bytes4 retval) {
            // if (retval != IERC721ReceiverExtend.onERC721Revoked.selector) {
            //     revert IERC721ReceiverExtend.ERC721InvalidRevoker(from);
            // }
        } catch (bytes memory reason) {
            uint g1 = gasleft();
            if(g0 - g1 < 300_000) {
                revert IERC721ReceiverExtend.ERC721InvalidRevoker(from);
            }
            // if (reason.length == 0) {
            //     revert IERC721ReceiverExtend.ERC721InvalidRevoker(from);
            // } else {
            //     /// @solidity memory-safe-assembly
            //     assembly {
            //         revert(add(32, reason), mload(reason))
            //     }
            // }
        }
    }

    function _callOwner(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private {
        IERC721ReceiverExtend(owner()).onERC721Received( //Переписать метод, чтобы не дергать стандарт
            to,
            from,
            tokenId,
            data
        );
    }
}
