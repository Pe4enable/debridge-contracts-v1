// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./LendingPool.sol";
import "./LendingPoolAddressesProvider.sol";
import "./AaveProtocolDataProvider.sol";
import "./IncentivesController.sol";
import "./MockAToken.sol";
import "../../interfaces/IStrategy.sol";
import "../../periphery/BaseStrategyController.sol";

contract MockAaveController is BaseStrategyController {

    using SafeERC20 for IERC20;

    address public lendingPoolProvider;
    address public protocolDataProvider;

    constructor(
        address _lendingPoolProvider,
        address _protocolDataProvider
    ) {
        lendingPoolProvider = _lendingPoolProvider;
        protocolDataProvider = _protocolDataProvider;
    }

    function lendingPool() public view returns (address) {
        return LendingPoolAddressesProvider(lendingPoolProvider).getLendingPool();
    }

    function strategyToken(address _token) public view override returns (address) {
        (address newATokenAddress,,) =
        AaveProtocolDataProvider(protocolDataProvider).getReserveTokensAddresses(_token);
        return newATokenAddress;
    }

    function updateReserves(address _account, address _token)
        external
        view
        override
        returns (uint256)
    {
        return IERC20(_token).balanceOf(_account);
    }

    function deposit(address _token, uint256 _amount) external override {
        address lendPool = lendingPool();
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(_token).safeApprove(lendPool, 0);
        IERC20(_token).safeApprove(lendPool, _amount);

        LendingPool(lendPool).deposit(
        _token,
        _amount,
        msg.sender,
        0 // referral code
        );
    }

    function withdrawAll(address _token) external override {
        withdraw(_token, type(uint256).max);
    }

    function withdraw(address _token, uint256 _amount) public override {
        address lendPool = lendingPool();
        address aToken = strategyToken(_token);
        IERC20(aToken).safeApprove(lendPool, 0);
        IERC20(aToken).safeApprove(lendPool, _amount);
        uint256 maxAmount = IERC20(aToken).balanceOf(msg.sender);

        uint256 userBalance = IERC20(aToken).balanceOf(msg.sender);
        uint256 amountToWithdraw = _amount;

        if (_amount == type(uint256).max || _amount > userBalance) {
            amountToWithdraw = userBalance;
        }

        IERC20(aToken).transferFrom(msg.sender, address(this), amountToWithdraw);

        uint256 amountWithdrawn = LendingPool(lendPool).withdraw(
            _token,
            amountToWithdraw,
            msg.sender
        );

        _collectProtocolToken(aToken, amountToWithdraw/maxAmount);

        require(
        amountWithdrawn == amountToWithdraw ||
        (amountToWithdraw == type(uint256).max && maxAmount == IERC20(_token).balanceOf(aToken)),
        "Didn't withdraw requested amount"
        );
    }

    // Collect stkAAVE
    function _collectProtocolToken(address _token, uint256 _amount) internal {
        address[] memory assets = new address[](1);
        assets[0] = address(_token);
        IncentivesController incentivesController = MockAToken(_token).getIncentivesController();
        uint256 rewardsBalance = incentivesController.getRewardsBalance(assets, address(this));
        incentivesController.claimRewards(assets, _amount*rewardsBalance, address(this));
    }
}
