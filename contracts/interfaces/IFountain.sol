// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFountain {
    function previousMpNumber(uint256 _mpNumber)
        external
        view
        returns (uint256);

    function latestMpNumber(address _owner) external view returns (uint256);

    function mpCount() external view returns (uint256);

    /// @notice This event should trigger when a Money pool is configured.
    event ConfigureMp(
        uint256 indexed mpNumber,
        address indexed owner,
        uint256 indexed target,
        uint256 duration,
        IERC20 want
    );

    /// @notice This event should trigger when a Money pool is sustained.
    event SustainMp(
        uint256 indexed mpNumber,
        address indexed owner,
        address indexed beneficiary,
        address sustainer,
        uint256 amount
    );

    /// @notice This event should trigger when redistributions are collected.
    event CollectRedistributions(address indexed sustainer, uint256 amount);

    /// @notice This event should trigger when sustainments are collected.
    event TapSustainments(
        uint256 indexed mpNumber,
        address indexed owner,
        address indexed beneficiary,
        uint256 amount,
        IERC20 want
    );

    function getMp(uint256 _mpNumber)
        external
        view
        returns (
            uint256,
            address,
            IERC20,
            uint256,
            uint256,
            uint256,
            uint256
        );

    function getUpcomingMp(address _owner)
        external
        view
        returns (
            uint256,
            address,
            IERC20,
            uint256,
            uint256,
            uint256,
            uint256
        );

    function getCurrentMp(address _owner)
        external
        view
        returns (
            uint256,
            address,
            IERC20,
            uint256,
            uint256,
            uint256,
            uint256
        );

    function getSustainment(uint256 _mpNumber, address _sustainer)
        external
        view
        returns (uint256 _amount);

    function getTappableAmount(uint256 _mpNumber)
        external
        view
        returns (uint256 _amount);

    function getTrackedRedistribution(uint256 _mpNumber, address _sustainer)
        external
        view
        returns (uint256 _amount);

    function configureMp(
        uint256 _target,
        uint256 _duration,
        IERC20 _want
    ) external returns (uint256 _mpNumber);

    function sustainOwner(
        address _owner,
        uint256 _amount,
        address _beneficiary
    ) external returns (uint256 _mpNumber);

    function collectAll() external returns (uint256 _amount);

    function collectFromOwner(address _owner)
        external
        returns (uint256 _amount);

    function collectFromOwners(address[] calldata _owner)
        external
        returns (uint256 _amount);

    function tap(
        uint256 _mpNumber,
        uint256 _amount,
        address _beneficiary
    ) external returns (bool _success);
}
