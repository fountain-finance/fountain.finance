// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

interface IFountainV1 {
    function previousMpIds(uint256 mpId) external view returns (uint256);

    function latestMpIds(address owner) external view returns (uint256);

    function redistributionPool(address sustainer)
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
        address want
    );
    event ConfigureMp(
        uint256 indexed id,
        address indexed owner,
        uint256 indexed target,
        uint256 duration,
        address want
    );
    event SustainMp(
        uint256 indexed id,
        address indexed owner,
        address indexed sustainer
    );
    event CollectRedistributions(address indexed sustainer, uint256 amount);
    event CollectSustainements(address indexed owner, uint256 amount);

    function getMp(uint256 mpId)
        external
        view
        returns (
            address want,
            uint256 target,
            uint256 start,
            uint256 duration,
            uint256 sustainerCount,
            uint256 balance
        );

    function getUpcomingMp(address owner)
        external
        view
        returns (
            address want,
            uint256 target,
            uint256 start,
            uint256 duration,
            uint256 sustainerCount,
            uint256 balance
        );

    function getActiveMp(address owner)
        external
        view
        returns (
            address want,
            uint256 target,
            uint256 start,
            uint256 duration,
            uint256 sustainerCount,
            uint256 balance
        );

    function getUpcomingMpId(address owner) external view returns (uint256 id);

    function getActiveMpId(address owner) external view returns (uint256 id);

    function getSustainmentBalance(address owner)
        external
        view
        returns (uint256 amount);

    function getSustainment(uint256 mpId, address sustainer)
        external
        view
        returns (uint256 amount);

    function getTrackedRedistribution(uint256 mpId, address sustainer)
        external
        view
        returns (uint256 amount);

    function getRedistributionBalance(address sustainer)
        external
        view
        returns (uint256 amount);

    function configureMp(
        uint256 target,
        uint256 duration,
        address want
    ) external returns (uint256 mpId);

    function sustain(address owner, uint256 amount)
        external
        returns (uint256 mpId);

    function collectRedistributions(uint256 amount)
        external
        returns (bool success);

    function collectRedistributionsFromAddress(uint256 amount, address from)
        external
        returns (bool success);

    function collectRedistributionsFromAddresses(
        uint256 amount,
        address[] calldata from
    ) external returns (bool success);

    function collectSustainments(uint256 amount)
        external
        returns (bool success);
}
