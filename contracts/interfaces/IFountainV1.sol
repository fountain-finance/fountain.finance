// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFountainV1 {
    function previousMpIds(uint256 _mpId) external view returns (uint256);

    function latestMpIds(address _owner) external view returns (uint256);

    function redistributionPool(address _sustainer)
        external
        view
        returns (uint256 amount);

    function mpCount() external view returns (uint256);

    event InitializeMp(uint256 indexed id, address indexed owner);
    event ActivateMp(
        uint256 indexed id,
        address indexed owner,
        uint256 indexed target,
        uint256 duration,
        IERC20 want
    );
    event ConfigureMp(
        uint256 indexed id,
        address indexed owner,
        uint256 indexed target,
        uint256 duration,
        IERC20 want
    );
    event SustainMp(
        uint256 indexed id,
        address indexed owner,
        address indexed sustainer
    );
    event CollectRedistributions(address indexed sustainer, uint256 amount);
    event CollectSustainements(address indexed owner, uint256 amount);

    function getMp(uint256 _mpId)
        external
        view
        returns (
            IERC20 want,
            uint256 target,
            uint256 start,
            uint256 duration,
            uint256 sustainerCount,
            uint256 balance
        );

    function getUpcomingMp(address _owner)
        external
        view
        returns (
            IERC20 want,
            uint256 target,
            uint256 start,
            uint256 duration,
            uint256 sustainerCount,
            uint256 balance
        );

    function getActiveMp(address _owner)
        external
        view
        returns (
            IERC20 want,
            uint256 target,
            uint256 start,
            uint256 duration,
            uint256 sustainerCount,
            uint256 balance
        );

    function getUpcomingMpId(address _owner) external view returns (uint256 id);

    function getActiveMpId(address _owner) external view returns (uint256 id);

    function getSustainmentBalance() external view returns (uint256 amount);

    function getSustainment(uint256 _mpId, address _sustainer)
        external
        view
        returns (uint256 amount);

    function getTrackedRedistribution(uint256 _mpId, address _sustainer)
        external
        view
        returns (uint256 amount);

    function getRedistributionBalance() external view returns (uint256 amount);

    function configureMp(
        uint256 _target,
        uint256 _duration,
        IERC20 _want
    ) external returns (uint256 mpId);

    function sustain(address _owner, uint256 _amount)
        external
        returns (uint256 mpId);

    function sustain(
        address _owner,
        uint256 _amount,
        address _beneficiary
    ) external returns (uint256 mpId);

    function collectRedistributions(uint256 _amount)
        external
        returns (bool success);

    function collectRedistributionsFromAddress(uint256 _amount, address _from)
        external
        returns (bool success);

    function collectRedistributionsFromAddresses(
        uint256 _amount,
        address[] calldata _from
    ) external returns (bool success);

    function collectSustainments(uint256 _amount)
        external
        returns (bool success);
}
