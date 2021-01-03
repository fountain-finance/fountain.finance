// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFountainV1 {
    function previousMpNumber(uint256 _mpId)
        external
        view
        returns (uint256 _mpNumber);

    function latestMpNumber(address _owner)
        external
        view
        returns (uint256 _mpNumber);

    function mpCount() external view returns (uint256 _count);

    event ConfigureMp(
        uint256 indexed mpId,
        address indexed owner,
        uint256 indexed target,
        uint256 duration,
        IERC20 want
    );
    event SustainMp(
        uint256 indexed mpId,
        address indexed owner,
        address indexed beneficiary,
        address sustainer,
        uint256 amount
    );
    event Collect(address indexed sustainer, uint256 amount);
    event Tap(
        uint256 indexed mpId,
        address indexed owner,
        uint256 amount,
        address want
    );

    function getMp(uint256 _mpId)
        external
        view
        returns (
            uint256 _number,
            IERC20 _want,
            uint256 _target,
            uint256 _start,
            uint256 _duration,
            uint256 _balance
        );

    function getUpcomingMp(address _owner)
        external
        view
        returns (
            uint256 _number,
            IERC20 _want,
            uint256 _target,
            uint256 _start,
            uint256 _duration,
            uint256 _balance
        );

    function getActiveMp(address _owner)
        external
        view
        returns (
            uint256 _number,
            IERC20 _want,
            uint256 _target,
            uint256 _start,
            uint256 _duration,
            uint256 _balance
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

    function sustain(
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

    function tap(uint256 _mpId, uint256 _amount)
        external
        returns (bool _success);
}
