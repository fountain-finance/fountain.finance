// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMpChain {
    function previousMpChain() external view returns (IMpChain);

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

    function trackedRedistribution(uint256 _number, address _sustainer)
        external
        view
        returns (uint256 _amount);

    function canRedistribute(uint256 _number) external view returns (bool);

    function want(uint256 _number) external view returns (IERC20);

    function configure(
        address _owner,
        uint256 _target,
        uint256 _duration,
        IERC20 _want
    ) external returns (uint256 _number);

    function sustain(
        address _owner,
        uint256 _amount,
        address _beneficiary
    ) external returns (uint256 _number);

    function tap(
        uint256 _number,
        address _owner,
        uint256 _amount
    ) external returns (bool);

    function markAsRedistributed(uint256 _number, address _sustainer) external;

    function setPreviousMpChain(IMpChain _mpChain) external;
}
