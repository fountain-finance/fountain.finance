// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFountainV1 {
    function previousMpIds(uint256 _mpId) external view returns (uint256);

    function latestMpIds(address _owner) external view returns (uint256);

    function mpCount() external view returns (uint256);

    event InitializeMp(uint256 indexed mpId, address indexed owner);
    event ActivateMp(
        uint256 indexed mpId,
        address indexed owner,
        uint256 indexed target,
        uint256 duration,
        IERC20 want
    );
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
    event CollectRedistributions(address indexed sustainer, uint256 amount);
    event CollectSustainments(
        uint256 indexed mpId,
        address indexed owner,
        uint256 amount,
        address want
    );

    function getMp(uint256 _mpId)
        external
        view
        returns (
            uint256 id,
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
            uint256 id,
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
            uint256 id,
            IERC20 want,
            uint256 target,
            uint256 start,
            uint256 duration,
            uint256 balance
        );

    function getSustainmentBalance(uint256 _mpId)
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

    function collectSustainment(uint256 _mpId, uint256 _amount)
        external
        returns (bool success);
}
