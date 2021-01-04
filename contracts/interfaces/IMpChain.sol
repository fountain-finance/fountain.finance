// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../libraries/MoneyPool.sol";

interface IMpChain {
    function previousNumber(uint256 _number) external view returns (uint256);

    function latestNumber(address _owner) external view returns (uint256);

    function length() external view returns (uint256 _count);

    function hasRedistributed(uint256 _number, address _sustainer)
        external
        view
        returns (bool);

    function sustainments(uint256 _number, address _sustainer)
        external
        view
        returns (uint256 _amount);

    function mp(uint256 _number) external view returns (MoneyPool.Data memory);

    function upcomingMp(address _owner)
        external
        view
        returns (MoneyPool.Data memory _mp);

    function activeMp(address _owner)
        external
        view
        returns (MoneyPool.Data memory _mp);

    function latestMp(address _owner)
        external
        view
        returns (MoneyPool.Data memory _mp);

    function previousMp(uint256 _number)
        external
        view
        returns (MoneyPool.Data memory _mp);

    function tappableAmount(uint256 _number)
        external
        view
        returns (uint256 _amount);

    function trackedRedistribution(uint256 _number, address _sustainer)
        external
        view
        returns (uint256 _amount);

    function markAsRedistributed(uint256 _number, address _sustainer) external;

    function configure(
        address _owner,
        uint256 _target,
        uint256 _duration,
        IERC20 _want
    ) external returns (MoneyPool.Data memory _mp);

    function sustain(
        address _owner,
        uint256 _amount,
        address _beneficiary
    ) external returns (MoneyPool.Data memory _mp);

    function tap(
        uint256 _number,
        address _owner,
        uint256 _amount
    ) external returns (MoneyPool.Data memory _mp);
}
