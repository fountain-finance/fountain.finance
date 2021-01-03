// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFountainV1 {
    function previousMpNumber(uint256 _mpId) external view returns (uint256);

    function latestMpNumber(address _owner) external view returns (uint256);

    function mpCount() external view returns (uint256);

    function getMp(uint256 _mpId)
        external
        view
        returns (
            uint256 number,
            IERC20 want,
            uint256 target,
            uint256 start,
            uint256 duration,
            uint256 balance
        );

    function getUpcomingMp(address _owner)
        external
        view
        returns (
            uint256 number,
            IERC20 want,
            uint256 target,
            uint256 start,
            uint256 duration,
            uint256 balance
        );

    function getActiveMp(address _owner)
        external
        view
        returns (
            uint256 number,
            IERC20 want,
            uint256 target,
            uint256 start,
            uint256 duration,
            uint256 balance
        );

    function getSustainment(uint256 _mpId)
        external
        view
        returns (uint256 amount);

    function getSustainment(uint256 _mpId, address _sustainer)
        external
        view
        returns (uint256 amount);

    function getTrackedRedistribution(uint256 _mpId, address _sustainer)
        external
        view
        returns (uint256 amount);

    function configureMp(
        uint256 _target,
        uint256 _duration,
        IERC20 _want
    ) external returns (uint256 mpId);

    function sustain(
        address _owner,
        uint256 _amount,
        address _beneficiary
    ) external returns (uint256 mpId);

    function collectAllRedistributions() external returns (uint256 amount);

    function collectRedistributionsFromOwner(address _owner)
        external
        returns (uint256 amount);

    function collectRedistributionsFromOwners(address[] calldata _owner)
        external
        returns (uint256 amount);

    function collectSustainments(uint256 _mpId, uint256 _amount)
        external
        returns (bool success);
}
