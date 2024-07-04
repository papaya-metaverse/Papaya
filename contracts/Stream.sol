// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { IERC165, ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";

import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC721Metadata } from "@openzeppelin/contracts/tokens/ERC721/extentions/IERC721Metadata.sol";
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { IStream } from "./interfaces/IStream.sol";
import { IStreamReceiver } from "./interfaces/IStreamReceiver.sol";
import { IStreamRevoker } from "./interfaces/IStreamRevoker.sol";

import { IPapaya } from "./interfaces/IPapaya.sol";

contract Stream is Context, ERC165, IERC721, IERC721Metadata, IStream {
    address public immutable PAPAYA;

    // Token name
    string private immutable _name;

    // Token symbol
    string private immutable _symbol;

    uint256 constant STREAM_CALL_GAS_LIMIT = 300_000;

    modifier onlyPapaya() {
        if(_msgSender() != papaya_) revert AccessDenied();
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        address PAPAYA_
    ) {
        _name = name_;
        _symbol = symbol_;

        PAPAYA = PAPAYA_;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IStream).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function balanceOf(address owner) public view virtual returns (uint256) {
        return IPapaya(PAPAYA).allSubscriptions(owner).length;
    }

    function ownerOf(uint256 tokenId) public view virtual returns (address) {
        return _owner(tokenId);
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function tokenURI(uint256 tokenId) public view virtual returns (string memory) {
        // _requireOwned(tokenId);

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string.concat(baseURI, tokenId.toString()) : "";
    }

    function _baseURI() internal view virtual returns (string memory) {
        return "";
    }

    function safeMint(address to, uint256 tokenId) external onlyPapaya {
        _safeMint(to, tokenId);
    }

    function burn(uint256 tokenId) external onlyPapaya {
        _burn(tokenId);
    }

    function transferFrom(address from, address to, uint256 tokenId) external {
        address previousOwner = _update(to, tokenId, _msgSender());

        if (previousOwner != from) revert AccessDenied(tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external {
        transferFrom(from, to, tokenId);
    }

    function _safeMint(address to, uint256 tokenId) internal {
        if (to == address(0)) {
            revert IStreamReceiver.IStreamInvalidReceiver(address(0));
        }
        address previousOwner = _update(to, tokenId, address(0));
        if (previousOwner != address(0)) {
            revert IStreamInvalidSender(address(0));
        }
    }

    function _burn(uint256 tokenId) internal {
        _update(address(0), tokenId);
    }

    function _owner(uint256 tokenId) internal returns (address author) {
        (author, ) = IPapaya(PAPAYA).subscriptionActors(tokenId);
    }

    function _update(address to, uint256 tokenId) internal virtual returns (address) {
        address from = _ownerOf(tokenId);

        // Execute the update
        if (from != address(0)) {
            _checkOnERC721Revoked(from, to, tokenId);
        }

        if (to != address(0)) {
            _checkOnERC721Received(address(0), to, tokenId, "");
            IStreamReceiver(PAPAYA).onStreamTransfered(from, to, tokenId);
        }

        emit Transfer(from, to, tokenId);

        return from;
    }

    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory data) private {
        try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, data) returns (bytes4 retval) {
            if (retval != IERC721Receiver.onERC721Received.selector) {
                revert ERC721InvalidReceiver(to);
            }
        } catch (bytes memory reason) {
            if (reason.length == 0) {
                revert ERC721InvalidReceiver(to);
            } else {
                /// @solidity memory-safe-assembly
                assembly {
                        revert(add(32, reason), mload(reason))
                }
            }
        }
    }

    function _checkOnERC721Revoked(
        address from,
        address to,
        uint256 tokenId
    ) private {
        bytes4 selector = IStreamRevoker.onStreamRevoked.selector;
        uint256 gasLimit = STREAM_CALL_GAS_LIMIT;
        assembly ("memory-safe") { // solhint-disable-line no-inline-assembly
            let prt := mload(0x40)
            mstore(ptr, selector)
            mstore(add(ptr, 0x04), from)
            mstore(add(ptr, 0x24), to)
            mstore(add(prt, 0x44), tokenId)

            let gasLeft := gas()
            //Разве не 0х76?
            //Потому что 44 + 32 = 76
            if iszero(call(gasLimit, from, 0, prt, 0x64, 0, 0)) {
                //Зачем умножать на 63, а затем делить на 64?
                //Выравнивание?
                if lt(div(mul(gasLeft, 63), 64), gasLimit) {
                    returndatacopy(ptr, 0, returndatasize())
                    revert(ptr, returndatasize())
                }
            }
        }
    }
}
