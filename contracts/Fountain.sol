// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./MpChain.sol";
import "./interfaces/IFountain.sol";

/**

@title Fountain

@notice
Create a Money pool (MP) that'll be used to sustain your project, and specify what its sustainability target is.
Maybe your project is providing a service or public good, maybe it's being a YouTuber, engineer, or artist -- or anything else.
Anyone with your address can help sustain your project, and once you're sustainable any additional contributions are redistributed back your sustainers.

Each Money pool is like a tier of the fountain, and the predefined cost to pursue the project is like the bounds of that tier's pool.

@dev
An address can only be associated with one active Money pool at a time, as well as a mutable one queued up for when the active Money pool expires.
If a Money pool expires without one queued, the current one will be cloned and sustainments at that time will be allocated to it.
It's impossible for a Money pool's sustainability or duration to be changed once there has been a sustainment made to it.
Any attempts to do so will just create/update the message sender's queued MP.

You can collect funds of yours from the sustainers pool (where Money pool surplus is distributed) or from the sustainability pool (where Money pool sustainments are kept) at anytime.

Future versions will introduce Money pool dependencies so that your project's surplus can get redistributed to the MP of projects it is composed of before reaching sustainers.

The basin of the Fountain should always be the sustainers of projects.

*/

/// @notice The contract managing the state of all Money pools.
contract Fountain is IFountain {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using MoneyPool for MoneyPool.Data;

    /// @dev Wrap the sustain and collect transactions in unique locks to prevent reentrency.
    uint8 private lock1 = 1;
    uint8 private lock2 = 1;
    uint8 private lock3 = 1;
    modifier lockSustain() {
        require(lock1 == 1, "Fountain: sustain locked");
        lock1 = 0;
        _;
        lock1 = 1;
    }
    modifier lockCollect() {
        require(lock2 == 1, "Fountain: collect locked");
        lock2 = 0;
        _;
        lock2 = 1;
    }
    modifier lockTap() {
        require(lock3 == 1, "Fountain: tap locked");
        lock3 = 0;
        _;
        lock3 = 1;
    }

    // --- private properties --- //

    MpChain private mpChain;

    /// @dev List of owners contributed to by each sustainer.
    /// @dev This is used to redistribute surplus economically.
    mapping(address => address[]) private sustainedOwners;

    /// @dev Map of whether or not an address has sustained another owner.
    /// @dev This is used to redistribute surplus economically.
    mapping(address => mapping(address => bool)) private sustainedOwnerTracker;

    // --- public properties --- //

    /// @notice The contract currently only supports sustainments in dai.
    IERC20 public dai;

    // --- events --- //

    /// @notice This event should trigger when a Money pool is configured.
    event Configure(
        uint256 indexed mpNumber,
        address indexed owner,
        uint256 indexed target,
        uint256 duration,
        IERC20 want
    );

    /// @notice This event should trigger when a Money pool is sustained.
    event Sustain(
        uint256 indexed mpNumber,
        address indexed owner,
        address indexed beneficiary,
        address sustainer,
        uint256 amount
    );

    /// @notice This event should trigger when redistributions are collected.
    event Collect(address indexed sustainer, uint256 amount);

    /// @notice This event should trigger when sustainments are collected.
    event Tap(
        uint256 indexed mpNumber,
        address indexed owner,
        address indexed beneficiary,
        uint256 amount,
        IERC20 want
    );

    // --- external transactions --- //

    constructor(IERC20 _dai) public {
        dai = _dai;
        mpChain = new MpChain();
    }

    /**
        @notice Configures the sustainability target and duration of the sender's current Money pool if it hasn't yet received sustainments, or
        sets the properties of the Money pool that will take effect once the current Money pool expires.
        @param _target The sustainability target to set.
        @param _duration The duration to set, measured in seconds.
        @param _want The token that the Money pool wants.
        @return _mp The Money pool that was successfully configured.
    */
    function configure(
        uint256 _target,
        uint256 _duration,
        IERC20 _want
    ) external override returns (MoneyPool.Data memory _mp) {
        require(
            _duration >= 1,
            "Fountain::configureMp: A Money Pool must be at least one second long"
        );
        require(
            _want == dai,
            "Fountain::configureMp: A Money Pool can only want DAI for now"
        );
        require(
            _target > 0,
            "Fountain::configureMp: A Money Pool target must be a positive number"
        );

        _mp = mpChain.configure(msg.sender, _target, _duration, _want);

        emit Configure(
            _mp.number,
            _mp.owner,
            _mp.target,
            _mp.duration,
            _mp.want
        );
    }

    /** 
        @notice Sustain an owner's active Money pool.
        @param _owner The owner of the Money pool to sustain.
        @param _amount Amount of sustainment.
        @param _beneficiary The address to associate with this sustainment. This is usually mes.sender, but can be something else if the sender is making this sustainment on the beneficiary's behalf.
        @return _mp The Money pool that was successfully sustained.
    */
    function sustain(
        address _owner,
        uint256 _amount,
        address _beneficiary
    ) external override lockSustain returns (MoneyPool.Data memory _mp) {
        require(
            _amount > 0,
            "Fountain::sustain: The sustainment amount should be positive"
        );

        _mp = mpChain.sustain(_owner, _amount, _beneficiary);
        _mp.want.safeTransferFrom(msg.sender, address(this), _amount);

        // Add this address to the sustainer's list of sustained owners
        if (sustainedOwnerTracker[_beneficiary][_owner] == false) {
            sustainedOwners[_beneficiary].push(_owner);
            sustainedOwnerTracker[_beneficiary][_owner] == true;
        }

        emit Sustain(_mp.number, _mp.owner, _beneficiary, msg.sender, _amount);
    }

    /** 
        @notice A message sender can collect what's been redistributed to it by Money pools once they have expired.
        @dev Iterate over all of sender's sustained addresses to make sure
        redistribution has completed for all redistributable Money pools
        @return amount If the collecting was a success.
    */
    function collectAll() external override lockCollect returns (uint256) {
        uint256 _amount =
            _redistributeAmount(msg.sender, sustainedOwners[msg.sender]);
        require(_amount > 0, "Fountain::collectAll: Nothing to collect");
        dai.safeTransfer(msg.sender, _amount);
        emit Collect(msg.sender, _amount);
        return _amount;
    }

    /**
        @notice A message sender can collect what's been redistributed to it by a specific Money pool once it's expired.
        @param _owner The Money pool owner to collect from.
        @return success If the collecting was a success.
     */
    function collectFromOwner(address _owner)
        external
        override
        lockCollect
        returns (uint256)
    {
        uint256 _amount = _redistributeAmount(msg.sender, _owner);
        require(_amount > 0, "Fountain::collectFromOwner: Nothing to collect");
        dai.safeTransfer(msg.sender, _amount);
        emit Collect(msg.sender, _amount);
        return _amount;
    }

    /** 
        @notice A message sender can collect what's been redistributed to it by specific Money pools once they have expired.
        @param _owners The Money pools owners to collect from.
        @return success If the collecting was a success.
    */
    function collectFromOwners(address[] calldata _owners)
        external
        override
        lockCollect
        returns (uint256)
    {
        uint256 _amount = _redistributeAmount(msg.sender, _owners);
        require(_amount > 0, "Fountain::collectFromOwners: Nothing to collect");
        dai.safeTransfer(msg.sender, _amount);
        emit Collect(msg.sender, _amount);
        return _amount;
    }

    /**
        @notice A message sender can tap into funds that have been used to sustain it's Money pools.
        @param _mpNumber The number of the Money pool to tap.
        @param _amount The amount to tap.
        @param _beneficiary The address to transfer the funds to.
        @return success If the collecting was a success.
    */
    function tap(
        uint256 _mpNumber,
        uint256 _amount,
        address _beneficiary
    ) external override lockTap returns (bool) {
        MoneyPool.Data memory _mp = mpChain.tap(_mpNumber, msg.sender, _amount);
        _mp.want.safeTransfer(_beneficiary, _amount);
        emit Tap(_mpNumber, msg.sender, _beneficiary, _amount, _mp.want);
        return true;
    }

    // --- private transactions --- //

    /** 
        @notice Record the redistribution the amount that should be redistributed to the given sustainer by the given owners' Money pools.
        @param _sustainer The sustainer address to redistribute to.
        @param _owners The Money pool owners to redistribute from.
        @return _amount The amount that has been redistributed.
    */
    function _redistributeAmount(address _sustainer, address[] memory _owners)
        private
        returns (uint256)
    {
        uint256 _amount = 0;
        for (uint256 i = 0; i < _owners.length; i++)
            _amount = _amount.add(_redistributeAmount(_sustainer, _owners[i]));
        return _amount;
    }

    /** 
        @notice Record the redistribution the amount that should be transfered to the given sustainer by the given owner's Money pools.
        @dev 
        Iterate through all Money pools for this owner address. For each iteration,
        if the Money pool has a state of redistributing and it has not yet
        been redistributed for the current sustainer, then process the
        redistribution. Iterate until a Money pool is found that has already
        been redistributed for this sustainer. This logic should skip Active
        and Upcoming Money pools.
        Short circuits by testing if the moneyPool has redistributed in order to limit number
        of iterations since all previous Money pools must have also already been
        redistributed.
        @param _sustainer The sustainer address to redistribute to.
        @param _owner The Money pool owner to redistribute from.
        @return _amount The amount that has been redistributed.
    */
    function _redistributeAmount(address _sustainer, address _owner)
        private
        returns (uint256)
    {
        uint256 _amount = 0;
        MoneyPool.Data memory _mp = mpChain.latestMp(_owner);

        require(
            _mp.number > 0,
            "Fountain::_redistributeAmount: Money Pool not found"
        );

        while (
            _mp.number > 0 && !mpChain.hasRedistributed(_mp.number, _sustainer)
        ) {
            if (_mp._state() == MoneyPool.State.Redistributing) {
                _amount = _amount.add(
                    mpChain.trackedRedistribution(_mp.number, _sustainer)
                );
                mpChain.markAsRedistributed(_mp.number, _sustainer);
            }
            _mp = mpChain.previousMp(_mp.number);
        }

        return _amount;
    }
}
