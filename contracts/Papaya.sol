// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

import { SafeERC20, IERC20 } from "@1inch/solidity-utils/contracts/libraries/SafeERC20.sol";
import { EnumerableMap } from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import { PermitAndCall } from "@1inch/solidity-utils/contracts/mixins/PermitAndCall.sol";
import { BySig, EIP712 } from "@1inch/solidity-utils/contracts/mixins/BySig.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SignedMath } from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import { Context } from "@openzeppelin/contracts/utils/Context.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Multicall } from "@openzeppelin/contracts/utils/Multicall.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import { IStreamReceiver } from "./interfaces/IStreamReceiver.sol";
import { IStreamInteraction } from "./interfaces/IStreamInteraction.sol";
import "./interfaces/IPapaya.sol";
import "./library/UserLib.sol";

// NOTE: Default settings for projectId are stored in projectAdmin[projectId].settings
contract Papaya is IPapaya, EIP712, Ownable, PermitAndCall, BySig, Multicall {
    using SafeERC20 for IERC20;
    using UserLib for UserLib.User;
    using Address for address payable;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    uint16 public constant FLOOR = 10000;
    uint16 public constant MAX_PROTOCOL_FEE = FLOOR * 20 / 100;

    uint256 public constant APPROX_LIQUIDATE_GAS = 140000;
    uint256 public constant APPROX_SUBSCRIPTION_GAS = 10000;
    uint8 public constant SUBSCRIPTION_THRESHOLD = 100;

    AggregatorV3Interface public immutable COIN_PRICE_FEED;
    AggregatorV3Interface public immutable TOKEN_PRICE_FEED;

    IERC20 public immutable TOKEN;
    uint256 public immutable DECIMALS_SCALE;

    uint256 public totalSupply;
    mapping(address account => UserLib.User) public users;

    address public immutable streamNFT;
    uint32 private _subscriptionId;
    mapping(uint256 encodeId => SubActors) public encodedSubscribers;
    mapping(address account => EnumerableMap.AddressToUintMap) private _subscriptions;

    // TODO: v2 should allow multiple subscriptions among 2 users by casting uint256 to storage slot of EnumerableSet
    //Была мысль попытаться вообще перейти на половину адреса, тогда можно отказаться от мапилки с овнерами
    mapping(uint80 projectId => address owner) public projectOwners;
    mapping(uint80 projectId => Settings) public defaultSettings;
    mapping(uint80 projectId => mapping(address account => Settings)) public userSettings;

    modifier onlyValidSettings(Settings calldata settings) {
        if (settings.projectFee > MAX_PROTOCOL_FEE) revert WrongPercent();
        _;
    }

    modifier onlyNotSender(address account) {
        if (_msgSender() == account) revert NotLegal();
        _;
    }

    modifier onlyStream() {
        if (_msgSender() != address(streamNFT)) revert NotLegal();
        _;
    }

    constructor(
        address CHAIN_PRICE_FEED_,
        address TOKEN_PRICE_FEED_,
        address TOKEN_,
        address streamNFT_
    )
        Ownable(_msgSender())
        EIP712(type(Papaya).name, "1")
    {
        COIN_PRICE_FEED = AggregatorV3Interface(CHAIN_PRICE_FEED_);
        TOKEN_PRICE_FEED = AggregatorV3Interface(TOKEN_PRICE_FEED_);
        TOKEN = IERC20(TOKEN_);
        DECIMALS_SCALE = 10 ** (18 - IERC20Metadata(TOKEN_).decimals());
        streamNFT = streamNFT_;
    }

    function name() external view returns (string memory) {
        return string.concat("Streaming ", IERC20Metadata(address(TOKEN)).name());
    }

    function symbol() external view returns (string memory) {
        return string.concat("pp", IERC20Metadata(address(TOKEN)).symbol());
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function rescueFunds(IERC20 token, uint256 amount) external onlyOwner {
        if (address(token) == address(0)) {
            payable(_msgSender()).sendValue(amount);
        } else {
            if (token == TOKEN && amount > TOKEN.balanceOf(address(this)) - totalSupply / DECIMALS_SCALE) {
                revert UserLib.InsufficialBalance();
            }
            token.safeTransfer(owner(), amount);
        }
    }

    function setDefaultSettings(Settings calldata settings)
        external
        onlyValidSettings(settings)
    {
        uint80 projectId = uint80(uint160(_msgSender()));

        defaultSettings[projectId] = settings;

        emit SetDefaultSettings(projectId, settings.projectFee);
    }

    function setSettingsForUser(address user, Settings calldata settings)
        external
        onlyValidSettings(settings)
    {
        uint80 projectId = uint80(uint160(_msgSender()));

        userSettings[projectId][user] = settings;
        emit SetSettingsForUser(projectId, user, settings.projectFee);
    }

    function balanceOf(address account) external view returns (uint256) {
        return uint256(SignedMath.max(users[account].balanceOf(), int(0)));
    }

    function subscriptions(address from, address to) external view returns (bool, uint256 encodedRates) {
        return _subscriptions[from].tryGet(to);
    }

    function subscriptionActors(uint256 subscriptionId) external view returns (address author, address user) {
        author = encodedSubscribers[subscriptionId].author;
        user = encodedSubscribers[subscriptionId].subscriber;
    }

    function allSubscriptions(address from) external view returns(address[] memory to, uint256[] memory encodedRates) {
        EnumerableMap.AddressToUintMap storage user_subscriptions = _subscriptions[from];
        to = user_subscriptions.keys();
        encodedRates = new uint256[](to.length);

        for (uint256 i; i < to.length; i++) {
            encodedRates[i] = user_subscriptions.get(to[i]);
        }
    }

    function deposit(uint256 amount, bool isPermit2) external {
        _deposit(TOKEN, _msgSender(), _msgSender(), amount, isPermit2);
    }

    function depositFor(uint256 amount, address to, bool isPermit2) external {
        _deposit(TOKEN, _msgSender(), to, amount, isPermit2);
    }

    function _deposit(IERC20 token, address from, address to, uint256 amount, bool usePermit2) internal virtual {
        _update(address(0), to, amount * DECIMALS_SCALE);

        if(usePermit2) {
            token.safeTransferFromPermit2(from, address(this), amount);
        } else {
            token.safeTransferFrom(from, address(this), amount);
        }
    }

    function withdraw(uint256 amount) external {
        _withdraw(TOKEN, _msgSender(), _msgSender(), amount);
    }

    function withdrawTo(address to, uint256 amount) external {
        _withdraw(TOKEN, _msgSender(), to, amount);
    }

    function _withdraw(IERC20 token, address from, address to, uint256 amount) internal {
        //Erasing non significant decimals
        _update(from, address(0), amount / DECIMALS_SCALE * DECIMALS_SCALE);
        token.safeTransfer(to, amount / DECIMALS_SCALE);
    }

    function pay(address receiver, uint256 amount) external {
        _update(_msgSender(), receiver, amount);
    }

    function subscribe(address author, uint96 subscriptionRate, uint80 projectId) external {
        subscribe(author, subscriptionRate, projectId, msg.data[:0]);
    }

    function subscribe(address author, uint96 subscriptionRate, uint80 projectId, bytes calldata data)
        public
        onlyNotSender(author)
    {
        (bool success, uint256 encodedRates) = _subscriptions[_msgSender()].tryGet(author);
        if (success) {
            // If already subscribed, unsubscribe to be able to subscribe again
            _unsubscribeEffects(_msgSender(), author, encodedRates, true);
        }

        if (_subscriptions[_msgSender()].length() == SUBSCRIPTION_THRESHOLD) revert ExcessOfSubscriptions();

        Settings storage settings = userSettings[projectId][author];
        if (settings.initialized == false) {
            settings = defaultSettings[projectId];
        }

        _subscribeEffects(_msgSender(), author, subscriptionRate, settings.projectFee, projectId, data, true);
    }

    function unsubscribe(address author) external {
        (bool success, uint256 encodedRates) = _subscriptions[_msgSender()].tryGet(author);
        if (!success) revert NotSubscribed();

        _unsubscribeEffects(_msgSender(), author, encodedRates, true);
    }

    function liquidate(address account, address[] calldata authors) external onlyNotSender(account) {
        UserLib.User storage user = users[account];
        if (!user.isLiquidatable(_liquidationThreshold(_subscriptions[account].length()))) revert NotLiquidatable();

        EnumerableMap.AddressToUintMap storage user_subscriptions = _subscriptions[account];
        for (uint256 i; i < authors.length; i++) {
            uint256 encodedRates = user_subscriptions.get(authors[i]);
            _unsubscribeEffects(account, authors[i], encodedRates, true);
        }

        if (user.isLiquidatable(_liquidationThreshold(_subscriptions[account].length()))) revert NotLegal();

        int256 balance = user.drainBalance(users[_msgSender()], _liquidationThreshold(authors.length));

        emit Transfer(account, _msgSender(), uint256(SignedMath.max(int256(0), balance)));
        emit Liquidated(account, _msgSender());
    }

    function onStreamTransfered(
        address from,
        address to,
        uint256 tokenId
    ) external onlyStream {
        if(from != address(0)) {
            address subscriber = encodedSubscribers[tokenId].subscriber;
            (uint96 rate, , uint80 projectId,) = _decodeRates(tokenId);

            _unsubscribeEffects(subscriber, from, tokenId, false);

            Settings storage settings = userSettings[projectId][to];
            if (settings.initialized == false) {
                settings = defaultSettings[projectId];
            }

            _subscribeEffects(subscriber, to, rate, settings.projectFee, projectId, msg.data[:0], false);
        }
    }

    function _liquidationThreshold(uint256 subscriptionAmount) internal view returns (int256) {
        (, int256 tokenPrice, , , ) = TOKEN_PRICE_FEED.latestRoundData();
        (, int256 coinPrice, , , ) = COIN_PRICE_FEED.latestRoundData();

        uint256 expectedNativeAssetCost = _gasPrice() *
            (APPROX_LIQUIDATE_GAS + APPROX_SUBSCRIPTION_GAS * subscriptionAmount);

        uint256 executionPrice = expectedNativeAssetCost * uint256(coinPrice);

        return int256(executionPrice) / tokenPrice;
    }

    function _subscribeEffects(
        address user,
        address author,
        uint96 rate,
        uint16 fee,
        uint80 projectId,
        bytes calldata data,
        bool isStream
    ) internal {
        uint256 encodedRates = _encodeRates(rate, fee, projectId, _subscriptionId++);
        uint96 incomeRate = rate * (FLOOR - fee) / FLOOR;
        users[user].increaseOutgoingRate(rate, _liquidationThreshold(_subscriptions[user].length()));
        users[author].increaseIncomeRate(incomeRate);
        users[projectOwners[projectId]].increaseIncomeRate(rate - incomeRate);
        _subscriptions[user].set(author, encodedRates);

        encodedSubscribers[encodedRates] = SubActors(author, user);

        if(isStream) {
            IStreamInteraction(streamNFT).safeMint(author, encodedRates, data);
        }

        emit StreamCreated(user, author, encodedRates);
    }

    function _unsubscribeEffects(address user, address author, uint256 encodedRates, bool isStream) internal {
        (uint96 rate, uint16 fee, uint80 projectId, ) = _decodeRates(encodedRates);
        address admin = projectOwners[projectId];
        uint96 incomeRate = rate * (FLOOR - fee) / FLOOR;

        users[user].decreaseOutgoingRate(rate);
        users[author].decreaseIncomeRate(incomeRate, _liquidationThreshold(_subscriptions[author].length()));
        users[admin].decreaseIncomeRate(rate - incomeRate, _liquidationThreshold(_subscriptions[admin].length()));
        _subscriptions[user].remove(author);

        delete encodedSubscribers[encodedRates];

        if(isStream) {
            IStreamInteraction(streamNFT).burn(encodedRates);
        }

        emit StreamRevoked(user, author, encodedRates);
    }

    function _update(address from, address to, uint256 amount) private {
        if (from == to || amount == 0) return;

        if (from == address(0)) {
            totalSupply += amount;
        }
        else {
            users[from].decreaseBalance(amount, _liquidationThreshold(_subscriptions[from].length()));
        }

        if (to == address(0)) {
            totalSupply -= amount;
        }
        else {
            users[to].increaseBalance(amount);
        }

        emit Transfer(from, to, amount);
    }

    function _encodeRates(
        uint96 rate,
        uint16 fee,
        uint80 projectId,
        uint64 subscriptionId
    ) internal pure returns (uint256 encodedRates) {
        return uint256(rate)
            | (uint256(fee) << 96)
            | (uint256(projectId) << 112)
            | (uint256(subscriptionId) << 192);
    }

    function _decodeRates(
        uint256 encodedRates
    ) internal pure returns (
        uint96 rate,
        uint16 fee,
        uint80 projectId,
        uint64 subscriptionId
    ) {
        rate = uint96(encodedRates);
        fee = uint16(encodedRates >> 96);
        projectId = uint80(encodedRates >> 112);
        subscriptionId = uint64(encodedRates >> 192);
    }

    function _chargeSigner(address signer, address relayer, address token, uint256 amount, bytes calldata /* extraData */) internal override {
        if (token != address(TOKEN)) revert WrongToken();
        _update(signer, relayer, amount);
    }

    function _msgSender() internal view override(Context, BySig) returns (address) {
        return super._msgSender();
    }

    function _gasPrice() internal view virtual returns (uint256) {
        return block.basefee;
    }
}
