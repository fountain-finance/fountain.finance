// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./libraries/MoneyPool.sol";
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
        require(lock1 == 1, "Fountain::sustainOwner LOCKED");
        lock1 = 0;
        _;
        lock1 = 1;
    }
    modifier lockCollect() {
        require(lock2 == 1, "Fountain::collectRedistributions: LOCKED");
        lock2 = 0;
        _;
        lock2 = 1;
    }
    modifier lockTap() {
        require(lock3 == 1, "Fountain:: tapSustainments LOCKED");
        lock3 = 0;
        _;
        lock3 = 1;
    }

    // --- private properties --- //

    /// @dev The official record of all Money pools ever created
    mapping(uint256 => MoneyPool.Data) private mps;

    /// @dev List of owners sustained by each sustainer
    mapping(address => address[]) private sustainedOwners;

    /// @dev Map of whether or not an address has sustained another owner.
    mapping(address => mapping(address => bool)) private sustainedOwnerTracker;

    // --- public properties --- //

    /// @notice A mapping from Money pool number's the the numbers of the previous Money pool for the same owner.
    mapping(uint256 => uint256) public override previousMpNumber;

    /// @notice The latest Money pool for each owner address
    mapping(address => uint256) public override latestMpNumber;

    /// @notice The total number of Money pools created, which is used for issuing Money pool numbers.
    /// @dev Money pools should have a number > 0.
    uint256 public override mpCount;

    /// @notice The contract currently only supports sustainments in dai.
    IERC20 public dai;

    // --- events --- //

    // --- external views --- //

    /**  
        @notice The properties of the given Money pool.
        @param _mpNumber The number of the Money pool to get the properties of.
        @return number The number of the Money pool.
        @return owner The owner of the Money pool.
        @return want The token the Money pool wants.
        @return target The amount of the want token this Money pool is targeting.
        @return start The time when this Money pool started.
        @return duration The duration of this Money pool measured in seconds.
        @return total The total amount passed through the Money pool. Returns 0 if the Money pool isn't owned by the message sender.
    */
    function getMp(uint256 _mpNumber)
        external
        view
        override
        returns (
            uint256 number,
            address owner,
            IERC20 want,
            uint256 target,
            uint256 start,
            uint256 duration,
            uint256 total
        )
    {
        MoneyPool.Data memory _mp = mps[_mpNumber];
        require(_mp.number > 0, "Fountain::getMp: NOT_FOUND");
        return _mp._properties();
    }

    /**
        @notice The Money pool that's next up for an owner.
        @param _owner The owner of the Money pool being looked for.
        @return number The number of the Money pool.
        @return owner The owner of the Money pool.
        @return want The token the Money pool wants.
        @return target The amount of the want token this Money pool is targeting.
        @return start The time when this Money pool started.
        @return duration The duration of this Money pool measured in seconds.
        @return total The total amount passed through the Money pool. Returns 0 if the Money pool isn't owned by the message sender.
    */
    function getUpcomingMp(address _owner)
        external
        view
        override
        returns (
            uint256 number,
            address owner,
            IERC20 want,
            uint256 target,
            uint256 start,
            uint256 duration,
            uint256 total
        )
    {
        MoneyPool.Data memory _mp = _upcomingMp(_owner);
        require(_mp.number > 0, "Fountain::getUpcomingMp: NOT_FOUND");
        return _mp._properties();
    }

    /**
        @notice The properties of the Money pool that would be currently accepting sustainments.
        @param _owner The owner of the money pool being looked for.
        @return number The number of the Money pool.
        @return owner The owner of the Money pool.
        @return want The token the Money pool wants.
        @return target The amount of the want token this Money pool is targeting.
        @return start The time when this Money pool started.
        @return duration The duration of this Money pool measured in seconds.
        @return total The total amount passed through the Money pool. Returns 0 if the Money pool isn't owned by the message sender.
    */
    function getCurrentMp(address _owner)
        external
        view
        override
        returns (
            uint256 number,
            address owner,
            IERC20 want,
            uint256 target,
            uint256 start,
            uint256 duration,
            uint256 total
        )
    {
        MoneyPool.Data memory _mp = _activeMp(_owner);
        if (_mp.number > 0) return _mp._properties();

        require(
            latestMpNumber[_owner] > 0,
            "Fountain::getCurrentMp: NOT_FOUND"
        );

        _mp = mps[latestMpNumber[_owner]];
        return (
            mpCount + 1,
            _mp.owner,
            _mp.want,
            _mp.target,
            _mp._determineNextStart(),
            _mp.duration,
            0
        );
    }

    /**
        @notice The amount in a Money pool that was contributed by the given address.
        @param _mpNumber The number of the Money pool to get a contribution for.
        @param _sustainer The address of the sustainer to get an amount for.
        @return amount The amount.
    */
    function getSustainment(uint256 _mpNumber, address _sustainer)
        external
        view
        override
        returns (uint256)
    {
        require(_mpNumber > 0, "Fountain::getSustainment:: NOT_FOUND");
        return mps[_mpNumber].sustainments[_sustainer];
    }

    /**
        @notice The amount left to be withdrawn by the Money pool's owner.
        @param _mpNumber The number of the Money pool to get the available sustainment from.
        @return amount The amount.
    */
    function getTappableAmount(uint256 _mpNumber)
        external
        view
        override
        returns (uint256)
    {
        require(_mpNumber > 0, "Fountain::getTappableAmount:: NOT_FOUND");
        return mps[_mpNumber]._tappableAmount();
    }

    /** 
        @notice The amount of redistribution in a Money pool that can be claimed by the given address.
        @param _mpNumber The number of the Money pool to get a redistribution amount for.
        @param _sustainer The address of the sustainer to get an amount for.
        @return amount The amount.
    */
    function getTrackedRedistribution(uint256 _mpNumber, address _sustainer)
        external
        view
        override
        returns (uint256)
    {
        MoneyPool.Data storage _mp = mps[_mpNumber];
        require(
            _mp.number > 0,
            "Fountain::getTrackedRedistribution:: NOT_FOUND"
        );
        return _mp._trackedRedistribution(_sustainer);
    }

    // --- external transactions --- //

    constructor(IERC20 _dai) public {
        dai = _dai;
        mpCount = 0;
    }

    /**
        @notice Configures the sustainability target and duration of the sender's current Money pool if it hasn't yet received sustainments, or
        sets the properties of the Money pool that will take effect once the current Money pool expires.
        @param _target The sustainability target to set.
        @param _duration The duration to set, measured in seconds.
        @param _want The token that the Money pool wants.
        @return mpNumber The number of the Money pool that was successfully configured.
    */
    function configureMp(
        uint256 _target,
        uint256 _duration,
        IERC20 _want
    ) external override returns (uint256) {
        require(_duration >= 1, "Fountain::configureMp: TOO_SHORT");
        require(_want == dai, "Fountain::configureMp: UNSUPPORTED_WANT");
        require(_target > 0, "Fountain::configureMp: BAD_TARGET");

        MoneyPool.Data storage _mp = _mpToConfigure(msg.sender);
        _mp._configure(_target, _duration, _want);

        emit ConfigureMp(
            _mp.number,
            _mp.owner,
            _mp.target,
            _mp.duration,
            _mp.want
        );

        return _mp.number;
    }

    /** 
        @notice Sustain an owner's active Money pool.
        @param _owner The owner of the Money pool to sustain.
        @param _amount Amount of sustainment.
        @param _beneficiary The address to associate with this sustainment. This is usually mes.sender, but can be something else if the sender is making this sustainment on the beneficiary's behalf.
        @return mpNumber The number of the Money pool that was successfully sustained.
    */

    function sustainOwner(
        address _owner,
        uint256 _amount,
        address _beneficiary
    ) external override lockSustain returns (uint256) {
        require(_amount > 0, "Fountain::sustain: BAD_AMOUNT");

        // Find the Money pool that this sustainment should go to.
        MoneyPool.Data storage _mp = _mpToSustain(_owner);
        _mp._sustain(_amount, _beneficiary);

        _mp.want.safeTransferFrom(msg.sender, address(this), _amount);

        // Add this address to the sustainer's list of sustained owners
        if (sustainedOwnerTracker[_beneficiary][_owner] == false) {
            sustainedOwners[_beneficiary].push(_owner);
            sustainedOwnerTracker[_beneficiary][_owner] == true;
        }

        emit SustainMp(
            _mp.number,
            _mp.owner,
            _beneficiary,
            msg.sender,
            _amount
        );

        return _mp.number;
    }

    /** 
        @notice A message sender can collect what's been redistributed to it by Money pools once they have expired.
        @return _amount If amount collected.
    */
    function collectAllRedistributions()
        external
        override
        lockCollect
        returns (uint256 _amount)
    {
        require(
            sustainedOwners[msg.sender].length > 0,
            "Fountain::collectAll: NOTHING_TO_COLLECT"
        );
        // Iterate over all of sender's sustained addresses to make sure
        // redistribution has completed for all redistributable Money pools
        _amount = _redistributeAmount(msg.sender, sustainedOwners[msg.sender]);
        _performCollectRedistributions(msg.sender, _amount);
    }

    /**
        @notice A message sender can collect what's been redistributed to it by a specific Money pool once it's expired.
        @param _owner The Money pool owner to collect from.
        @return _amount The amount collected.
     */
    function collectRedistributionsFromOwner(address _owner)
        external
        override
        lockCollect
        returns (uint256 _amount)
    {
        require(
            sustainedOwners[msg.sender].length > 0,
            "Fountain::collectFromOwner: NOTHING_TO_COLLECT"
        );
        // Iterate over all of sender's sustained addresses to make sure
        _amount = _redistributeAmount(msg.sender, _owner);
        _performCollectRedistributions(msg.sender, _amount);
    }

    /** 
        @notice A message sender can collect what's been redistributed to it by specific Money pools once they have expired.
        @param _owners The Money pools owners to collect from.
        @return _amount If the amount collected.
    */
    function collectRedistributionsFromOwners(address[] calldata _owners)
        external
        override
        lockCollect
        returns (uint256 _amount)
    {
        require(
            sustainedOwners[msg.sender].length > 0,
            "Fountain::collectFromOwners: NOTHING_TO_COLLECT"
        );
        _amount = _redistributeAmount(msg.sender, _owners);
        _performCollectRedistributions(msg.sender, _amount);
    }

    /**
        @notice A message sender can tap into funds that have been used to sustain it's Money pools.
        @param _mpNumber The number of the Money pool to tap.
        @param _amount The amount to tap.
        @param _beneficiary The address to transfer the funds to.
        @return success If the collecting was a success.
    */
    function tapMp(
        uint256 _mpNumber,
        uint256 _amount,
        address _beneficiary
    ) external override lockTap returns (bool) {
        MoneyPool.Data storage _mp = mps[_mpNumber];
        require(
            _mp.owner == msg.sender,
            "Fountain::collectSustainment: UNAUTHORIZED"
        );
        require(
            _mp._tappableAmount() >= _amount,
            "Fountain::collectSustainment: INSUFFICIENT_FUNDS"
        );

        _mp._tap(_amount);
        _mp.want.safeTransfer(_beneficiary, _amount);

        emit TapMp(_mpNumber, msg.sender, _beneficiary, _amount, _mp.want);

        return true;
    }

    // --- private transactions --- //

    /** 
        @notice Executes the collection of redistributed funds.
        @param _sustainer The sustainer address to redistribute to.
        @param _amount The amount to collect.
    */
    function _performCollectRedistributions(address _sustainer, uint256 _amount)
        private
    {
        dai.safeTransfer(_sustainer, _amount);
        emit CollectRedistributions(_sustainer, _amount);
    }

    /** 
        @notice The Money pool that is configurable for this owner.
        @dev The sustainability of a Money pool cannot be updated if there have been sustainments made to it.
        @param _owner The address who owns the Money pool to look for.
        @return _mp The resulting Money pool.
    */
    function _mpToConfigure(address _owner)
        private
        returns (MoneyPool.Data storage _mp)
    {
        // Allow active moneyPool to be updated if it has no sustainments
        _mp = _activeMp(_owner);
        if (_mp.number > 0 && _mp.total == 0) return _mp;

        // Cannot update active moneyPool, check if there is a upcoming moneyPool
        _mp = _upcomingMp(_owner);
        if (_mp.number > 0) return _mp;

        // No upcoming moneyPool found, clone the latest moneyPool
        _mp = mps[latestMpNumber[_owner]];

        MoneyPool.Data storage _newMp = _initMp(_owner, now);
        if (_mp.number > 0) _newMp._clone(_mp);
        return _newMp;
    }

    /** 
        @notice The Money pool that is accepting sustainments for this owner.
        @dev Only active Money pools can be sustained.
        @param _owner The address who owns the Money pool to look for.
        @return _mp The resulting Money pool.
    */
    function _mpToSustain(address _owner)
        private
        returns (MoneyPool.Data storage _mp)
    {
        // Check if there is an active moneyPool
        _mp = _activeMp(_owner);
        if (_mp.number > 0) return _mp;

        // No active moneyPool found, check if there is an upcoming moneyPool
        _mp = _upcomingMp(_owner);
        if (_mp.number > 0) return _mp;

        // No upcoming moneyPool found, clone the latest moneyPool
        _mp = mps[latestMpNumber[_owner]];

        require(_mp.number > 0, "Fountain::_mpToSustain: NOT_FOUND");

        // Use a start date that's a multiple of the duration.
        // This creates the effect that there have been scheduled Money pools ever since the `latest`, even if `latest` is a long time in the past.
        MoneyPool.Data storage _newMp =
            _initMp(_mp.owner, _mp._determineNextStart());
        _newMp._clone(_mp);
        return _newMp;
    }

    /** 
        @notice Record the redistribution the amount that should be redistributed to the given sustainer by the given owners' Money pools.
        @param _sustainer The sustainer address to redistribute to.
        @param _owners The Money pool owners to redistribute from.
        @return _amount The amount that has been redistributed.
    */
    function _redistributeAmount(address _sustainer, address[] memory _owners)
        private
        returns (uint256 _amount)
    {
        _amount = 0;
        for (uint256 i = 0; i < _owners.length; i++)
            _amount = _amount.add(_redistributeAmount(_sustainer, _owners[i]));
    }

    /** 
        @notice Record the redistribution the amount that should be redistributed to the given sustainer by the given owner's Money pools.
        @dev Iterate through all Money pools for this owner address. For each iteration,
        if the Money pool has a state of redistributing and it has not yet
        been redistributed for the current sustainer, then process the
        redistribution. Iterate until a Money pool is found that has already
        been redistributed for this sustainer. This logic should skip Active
        and Upcoming Money pools.
        Short circuits by testing `moneyPool.hasRedistributed` to limit number
        of iterations since all previous Money pools must have already been
        redistributed.
        @param _sustainer The sustainer address to redistribute to.
        @param _owner The Money pool owner to redistribute from.
        @return _amount The amount that has been redistributed.
    */
    function _redistributeAmount(address _sustainer, address _owner)
        private
        returns (uint256 _amount)
    {
        _amount = 0;
        uint256 _mpNumber = latestMpNumber[_owner];
        MoneyPool.Data storage _mp = mps[_mpNumber];
        require(_mp.number > 0, "Fountain::_redistributeAmount: NOT_FOUND");

        while (_mp.number > 0 && !_mp.hasRedistributed[_sustainer]) {
            if (_mp._state() == MoneyPool.State.Redistributing) {
                _amount = _amount.add(_mp._trackedRedistribution(_sustainer));
                _mp.hasRedistributed[_sustainer] = true;
            }
            _mpNumber = previousMpNumber[_mpNumber];
            _mp = mps[_mpNumber];
        }
    }

    /** 
        @notice Initializes a Money pool to be sustained for the sending address.
        @param _owner The owner of the Money pool being initialized.
        @param _start The start time for the new Money pool.
        @return _newMp The initialized Money pool.
    */
    function _initMp(address _owner, uint256 _start)
        private
        returns (MoneyPool.Data storage _newMp)
    {
        mpCount++;
        _newMp = mps[mpCount];
        _newMp._init(_owner, _start, mpCount);
        previousMpNumber[mpCount] = latestMpNumber[_owner];
        latestMpNumber[_owner] = mpCount;
    }

    // --- private views --- //

    /** 
        @notice The currently active Money pool for an owner.
        @param _owner The owner of the money pool being looked for.
        @return _mp The active Money pool.
    */
    function _activeMp(address _owner)
        private
        view
        returns (MoneyPool.Data storage _mp)
    {
        _mp = mps[latestMpNumber[_owner]];
        if (_mp.number == 0) return mps[0];

        // An Active moneyPool must be either the latest moneyPool or the
        // moneyPool immediately before it.
        if (_mp._state() == MoneyPool.State.Active) return _mp;

        _mp = mps[previousMpNumber[_mp.number]];
        if (_mp.number == 0 || _mp._state() != MoneyPool.State.Active)
            return mps[0];
    }

    /** 
        @notice The Money pool that's next up for an owner.
        @param _owner The owner of the money pool being looked for.
        @return _mp The upcoming Money pool.
    */
    function _upcomingMp(address _owner)
        private
        view
        returns (MoneyPool.Data storage _mp)
    {
        _mp = mps[latestMpNumber[_owner]];
        if (_mp.number == 0) return mps[0];

        // There is no upcoming Money pool if the latest Money pool is not upcoming
        if (_mp._state() != MoneyPool.State.Upcoming) return mps[0];
    }
}
