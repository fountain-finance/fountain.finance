// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../libraries/MoneyPool.sol";

interface IFountain {
    event Configure(
        uint256 indexed mpId,
        address indexed owner,
        uint256 indexed target,
        uint256 duration,
        IERC20 want
    );
    event Sustain(
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
        address indexed beneficiary,
        uint256 amount,
        address want
    );

    function configure(
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

    function tap(
        uint256 _mpId,
        uint256 _amount,
        address _beneficiary
    ) external returns (bool _success);
}
