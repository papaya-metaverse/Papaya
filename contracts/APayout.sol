// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;
import {SafeERC20} from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";
import "./interfaces/ILendingPool.sol";
import "./library/UserLib.sol";
import "./Payout.sol";

interface AToken {
    function UNDERLYING_ASSET_ADDRESS() external view returns (IERC20);
}

contract APayout is Payout {
    using SafeERC20 for IERC20;
    using UserLib for UserLib.User;

    ILendingPool public immutable LENDING_POOL;
    IERC20 public immutable UNDERLYING_TOKEN;

    uint16 public refferal;

    constructor(
        address admin,
        address protocolSigner_,
        address protocolWallet_,
        address CHAIN_PRICE_FEED_,
        address TOKEN_PRICE_FEED_,
        address TOKEN_,
        uint8 TOKEN_DECIMALS_,
        ILendingPool LENDING_POOL_
    ) Payout (
        admin,
        protocolSigner_,
        protocolWallet_,
        CHAIN_PRICE_FEED_,
        TOKEN_PRICE_FEED_,
        TOKEN_,
        TOKEN_DECIMALS_
    ) {
        LENDING_POOL = LENDING_POOL_;
        UNDERLYING_TOKEN = AToken(TOKEN_).UNDERLYING_ASSET_ADDRESS();
    }

    function updateRefferal(uint16 refferal_) external onlyOwner {
        refferal = refferal_;
    }

    function depositUnderlying(address from, address to, uint amount, bool usePermit2) external {
        super._deposit(UNDERLYING_TOKEN, from, to, amount, usePermit2);

        UNDERLYING_TOKEN.forceApprove(address(LENDING_POOL), amount);
        LENDING_POOL.deposit(address(UNDERLYING_TOKEN), amount, address(this), refferal);
    }
    //NOTE Поиграться с трансферами, можно попробовать сделать все в один заход
    function withdrawUnderlying(uint256 amount) external {
        LENDING_POOL.withdraw(address(UNDERLYING_TOKEN), amount, msg.sender); //NOTE Проверить так ли работает

        _withdraw(UNDERLYING_TOKEN, amount, msg.sender);
    }
}
