// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./libraries/MoneyPool.sol";
import "./interfaces/IFountainV1.sol";

/**

@title Fountain

Create a Money pool (MP) that'll be used to sustain your project, and specify what its sustainability target is.
Maybe your project is providing a service or public good, maybe it's being a YouTuber, engineer, or artist -- or anything else.
Anyone with your address can help sustain your project, and once you're sustainable any additional contributions are redistributed back your sustainers.

Each Money pool is like a tier of the fountain, and the predefined cost to pursue the project is like the bounds of that tier's pool.

An address can only be associated with one active Money pool at a time, as well as a mutable one queued up for when the active Money pool expires.
If a Money pool expires without one queued, the current one will be cloned and sustainments at that time will be allocated to it.
It's impossible for a Money pool's sustainability or duration to be changed once there has been a sustainment made to it.
Any attempts to do so will just create/update the message sender's queued MP.

You can collect funds of yours from the sustainers pool (where Money pool surplus is distributed) or from the sustainability pool (where Money pool sustainments are kept) at anytime.

Future versions will introduce Money pool dependencies so that your project's surplus can get redistributed to the MP of projects it is composed of before reaching sustainers.

The basin of the Fountain should always be the sustainers of projects.

*/

/// @notice The contract managing the state of all Money pools.
contract FountainV1 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using MoneyPool for MoneyPool.Data;

    // Wrap the sustain and collect transactions in unique locks to prevent reentrency.
    uint8 private lock1 = 1;
    uint8 private lock2 = 1;
    uint8 private lock3 = 1;
    modifier lockSustain() {
        require(lock1 == 1, "Fountain: sustainment locked");
        lock1 = 0;
        _;
        lock1 = 1;
    }
    modifier lockCollectRedistribution() {
        require(lock2 == 1, "Fountain: collect redistribution locked");
        lock2 = 0;
        _;
        lock2 = 1;
    }
    modifier lockCollectSustainment() {
        require(lock3 == 1, "Fountain: collect sustainment locked");
        lock3 = 0;
        _;
        lock3 = 1;
    }

    // --- private properties --- //

    // The official record of all Money pools ever created
    mapping(uint256 => MoneyPool.Data) private mps;

    // List of owners sustained by each sustainer
    mapping(address => address[]) private sustainedOwners;

    // Map of whether or not an address has sustained another owner.
    mapping(address => mapping(address => bool)) private sustainedOwnerTracker;

    // --- public properties --- //

    /// @notice A mapping from Money pool number's the the numbers of the previous Money pool for the same owner.
    mapping(uint256 => uint256) public previousMpNumber;

    /// @notice The latest Money pool for each owner address
    mapping(address => uint256) public latestMpNumber;

    // The total number of Money pools created, which is used for issuing Money pool numbers.
    // Money pools should have an number > 0.
    uint256 public mpCount;

    // The contract currently only supports sustainments in dai.
    IERC20 public dai;

    // --- events --- //

    /// This event should trigger when redistributions are collected.
    event CollectRedistributions(address indexed sustainer, uint256 amount);

    /// This event should trigger when sustainments are collected.
    event CollectSustainments(
        uint256 indexed mpNumber,
        address indexed owner,
        uint256 amount,
        IERC20 want
    );

    // --- external views --- //

    /// @dev The properties of the given Money pool.
    /// @param _mpNumber The number of the Money pool to get the properties of.
    /// @return number The number of the Money pool.
    /// @return want The token the Money pool wants.
    /// @return target The amount of the want token this Money pool is targeting.
    /// @return start The time when this Money pool started.
    /// @return duration The duration of this Money pool measured in seconds.
    /// @return total The total amount passed through the Money pool. Returns 0 if the Money pool isn't owned by the message sender.
    function getMp(uint256 _mpNumber)
        external
        view
        returns (
            uint256 number,
            IERC20 want,
            uint256 target,
            uint256 start,
            uint256 duration,
            uint256 total
        )
    {
        MoneyPool.Data memory _mp = mps[_mpNumber];
        require(_mp.exists, "Fountain::_mpProperties: Money pool not found");
        return _mp._properties();
    }

    /// @dev The Money pool that's next up for an owner.
    /// @param _owner The owner of the Money pool being looked for.
    /// @return id The number of the Money pool.
    /// @return want The token the Money pool wants.
    /// @return target The amount of the want token this Money pool is targeting.
    /// @return start The time when this Money pool started.
    /// @return duration The duration of this Money pool measured in seconds.
    /// @return total The total amount passed through the Money pool. Returns 0 if the Money pool isn't owned by the message sender.
    function getUpcomingMp(address _owner)
        external
        view
        returns (
            uint256 id,
            IERC20 want,
            uint256 target,
            uint256 start,
            uint256 duration,
            uint256 total
        )
    {
        MoneyPool.Data memory _mp = _upcomingMp(_owner);
        require(_mp.exists, "Fountain::_mpProperties: Money pool not found");
        return _mp._properties();
    }

    /// @dev The currently active Money pool for an owner.
    /// @param _owner The owner of the money pool being looked for.
    /// @return number The number of the Money pool.
    /// @return want The token the Money pool wants.
    /// @return target The amount of the want token this Money pool is targeting.
    /// @return start The time when this Money pool started.
    /// @return duration The duration of this Money pool measured in seconds.
    /// @return total The total amount passed through the Money pool. Returns 0 if the Money pool isn't owned by the message sender.
    function getActiveMp(address _owner)
        external
        view
        returns (
            uint256 number,
            IERC20 want,
            uint256 target,
            uint256 start,
            uint256 duration,
            uint256 total
        )
    {
        MoneyPool.Data memory _mp = _activeMp(_owner);
        require(_mp.exists, "Fountain::_mpProperties: Money pool not found");
        return _mp._properties();
    }

    /// @dev The amount of sustainments in a Money pool that were contributed by the given address.
    /// @param _mpNumber The number of the Money pool to get a contribution for.
    /// @param _sustainer The address of the sustainer to get an amount for.
    /// @return amount The amount.
    function getSustainment(uint256 _mpNumber, address _sustainer)
        external
        view
        returns (uint256)
    {
        return mps[_mpNumber].sustainments[_sustainer];
    }

    /// @dev The amount of redistribution in a Money pool that can be claimed by the given address.
    /// @param _mpNumber The number of the Money pool to get a redistribution amount for.
    /// @param _sustainer The address of the sustainer to get an amount for.
    /// @return amount The amount.
    function getTrackedRedistribution(uint256 _mpNumber, address _sustainer)
        external
        view
        returns (uint256)
    {
        return _trackedRedistribution(_mpNumber, _sustainer);
    }

    // --- external transactions --- //

    constructor(IERC20 _dai) public {
        dai = _dai;
        mpCount = 0;
    }

    /// @dev Configures the sustainability target and duration of the sender's current Money pool if it hasn't yet received sustainments, or
    /// @dev sets the properties of the Money pool that will take effect once the current Money pool expires.
    /// @param _target The sustainability target to set.
    /// @param _duration The duration to set, measured in seconds.
    /// @param _want The token that the Money pool wants.
    /// @return mpNumber The number of the Money pool that was successfully configured.
    function configureMp(
        uint256 _target,
        uint256 _duration,
        IERC20 _want
    ) external returns (uint256) {
        require(
            _duration >= 1,
            "Fountain::configureMp: A Money Pool must be at least one day long"
        );
        require(
            _want == dai,
            "Fountain::configureMp: A Money Pool can only want DAI for now"
        );
        require(
            _target > 0,
            "Fountain::configureMp: A Money Pool target must be a positive number"
        );

        MoneyPool.Data storage _mp = _mpToConfigure(msg.sender);
        _mp._configure(_target, _duration, _want);

        return _mp.number;
    }

    /// @dev Overloaded from above with the addition of:
    /// @param _owner The owner of the Money pool to sustain.
    /// @param _amount Amount of sustainment.
    /// @param _beneficiary The address to associate with this sustainment. This is usually mes.sender, but can be something else if the sender is making this sustainment on the beneficiary's behalf.
    /// @return mpNumber The number of the Money pool that was successfully sustained.
    function sustain(
        address _owner,
        uint256 _amount,
        address _beneficiary
    ) external lockSustain returns (uint256) {
        require(
            _amount > 0,
            "Fountain::sustain: The sustainment amount should be positive"
        );

        // Find the Money pool that this sustainment should go to.
        MoneyPool.Data storage _mp = _mpToSustain(_owner);

        _mp._sustain(_amount, _beneficiary);

        // Add this address to the sustainer's list of sustained owners
        if (sustainedOwnerTracker[_beneficiary][_owner] == false) {
            sustainedOwners[_beneficiary].push(_owner);
            sustainedOwnerTracker[_beneficiary][_owner] == true;
        }
        return _mp.number;
    }

    /// @dev A message sender can collect what's been redistributed to it by Money pools once they have expired.
    /// @return amount If the collecting was a success.
    function collectAllRedistributions()
        external
        lockCollectRedistribution
        returns (uint256)
    {
        // Iterate over all of sender's sustained addresses to make sure
        // redistribution has completed for all redistributable Money pools
        uint256 _amount =
            _redistributeAmount(msg.sender, sustainedOwners[msg.sender]);

        _performCollectRedistributions(msg.sender, _amount);
        return _amount;
    }

    /// @dev A message sender can collect what's been redistributed to it by a specific Money pool once it's expired.
    /// @param _owner The Money pool owner to collect from.
    /// @return success If the collecting was a success.
    function collectRedistributionsFromOwner(address _owner)
        external
        lockCollectRedistribution
        returns (uint256)
    {
        uint256 _amount = _redistributeAmount(msg.sender, _owner);
        _performCollectRedistributions(msg.sender, _amount);
        return _amount;
    }

    /// @dev A message sender can collect what's been redistributed to it by specific Money pools once they have expired.
    /// @param _owners The Money pools owners to collect from.
    /// @return success If the collecting was a success.
    function collectRedistributionsFromOwners(address[] calldata _owners)
        external
        lockCollectRedistribution
        returns (uint256)
    {
        uint256 _amount = _redistributeAmount(msg.sender, _owners);
        _performCollectRedistributions(msg.sender, _amount);
        return _amount;
    }

    /// @dev A message sender can collect specific funds that have been used to sustain it's Money pools.
    /// @param _mpNumber The number of the Money pool to tap.
    /// @param _amount The amount to tap.
    /// @return success If the collecting was a success.
    function collectSustainments(uint256 _mpNumber, uint256 _amount)
        external
        lockCollectSustainment
        returns (bool)
    {
        MoneyPool.Data storage _mp = mps[_mpNumber];
        require(
            _mp.owner == msg.sender,
            "Fountain::collectSustainments: Money pools can only be tapped by their owner"
        );

        _mp._tap(_amount);
        _mp.want.safeTransfer(msg.sender, _amount);

        emit CollectSustainments(_mpNumber, msg.sender, _amount, _mp.want);

        return true;
    }

    // --- private --- //

    /// @dev Executes the collection of redistributed funds.
    /// @param _sustainer The sustainer address to redistribute to.
    /// @param _amount The amount to collect.
    function _performCollectRedistributions(address _sustainer, uint256 _amount)
        private
    {
        dai.safeTransfer(_sustainer, _amount);
        emit CollectRedistributions(_sustainer, _amount);
    }

    /// @dev The sustainability of a Money pool cannot be updated if there have been sustainments made to it.
    /// @param _owner The address who owns the Money pool to look for.
    /// @return _mp The resulting Money pool.
    function _mpToConfigure(address _owner)
        private
        returns (MoneyPool.Data storage _mp)
    {
        // Allow active moneyPool to be updated if it has no sustainments
        _mp = _activeMp(_owner);
        if (_mp.exists && _mp.total == 0) return _mp;

        // Cannot update active moneyPool, check if there is a upcoming moneyPool
        _mp = _upcomingMp(_owner);
        if (_mp.exists) return _mp;

        // No upcoming moneyPool found, clone the latest moneyPool
        _mp = mps[latestMpNumber[_owner]];
        if (_mp.exists) return _createMpFromMp(_mp, now);

        _mp = _initMp(_owner, now);
        return _mp;
    }

    /// @dev Only active Money pools can be sustained.
    /// @param _owner The address who owns the Money pool to look for.
    /// @return _mp The resulting Money pool.
    function _mpToSustain(address _owner)
        private
        returns (MoneyPool.Data storage _mp)
    {
        // Check if there is an active moneyPool
        _mp = _activeMp(_owner);
        if (_mp.exists) return _mp;

        // No active moneyPool found, check if there is an upcoming moneyPool
        _mp = _upcomingMp(_owner);
        if (_mp.exists) return _mp;

        // No upcoming moneyPool found, clone the latest moneyPool
        _mp = mps[latestMpNumber[_owner]];

        require(
            _mp.exists,
            "Fountain::mpNumberToSustain: Money pool not found"
        );

        // Use a start date that's a multiple of the duration.
        // This creates the effect that there have been scheduled Money pools ever since the `latest`, even if `latest` is a long time in the past.
        uint256 _start = _mp._determineNextStart();

        return _createMpFromMp(_mp, _start);
    }

    /// @dev Take the amount that should be redistributed to the given sustainer by the given owner's Money pools.
    /// @param _sustainer The sustainer address to redistribute to.
    /// @param _owners The Money pool owners to redistribute from.
    /// @return _amount The amount that has been redistributed.
    function _redistributeAmount(address _sustainer, address[] memory _owners)
        private
        returns (uint256)
    {
        uint256 _amount = 0;
        for (uint256 i = 0; i < _owners.length; i++)
            _amount = _amount.add(_redistributeAmount(_sustainer, _owners[i]));

        return _amount;
    }

    /// @dev Take the amount that should be redistributed to the given sustainer by the given owner's Money pools.
    /// @param _sustainer The sustainer address to redistribute to.
    /// @param _owner The Money pool owner to redistribute from.
    /// @return _amount The amount that has been redistributed.
    function _redistributeAmount(address _sustainer, address _owner)
        private
        returns (uint256)
    {
        uint256 _amount = 0;
        uint256 _mpNumber = latestMpNumber[_owner];
        require(
            _mpNumber > 0,
            "Fountain::_getRedistributionAmount: Money Pool not found"
        );
        MoneyPool.Data storage _mp = mps[_mpNumber];

        // Iterate through all Money pools for this owner address. For each iteration,
        // if the Money pool has a state of redistributing and it has not yet
        // been redistributed for the current sustainer, then process the
        // redistribution. Iterate until a Money pool is found that has already
        // been redistributed for this sustainer. This logic should skip Active
        // and Upcoming Money pools.
        // Short circuits by testing `moneyPool.hasRedistributed` to limit number
        // of iterations since all previous Money pools must have already been
        // redistributed.
        while (_mpNumber > 0 && !_mp.hasRedistributed[_sustainer]) {
            if (_mp._state() == MoneyPool.State.Redistributing) {
                _amount = _amount.add(
                    _trackedRedistribution(_mpNumber, _sustainer)
                );
                _mp.hasRedistributed[_sustainer] = true;
            }
            _mpNumber = previousMpNumber[_mpNumber];
            _mp = mps[_mpNumber];
        }

        return _amount;
    }

    /// @dev Returns a copy of the given Money pool with reset sustainments.
    /// @param _baseMp The Money pool to base the new Money pool on.
    /// @param _start The start date to use for the new Money pool.
    /// @return _mp The new Money pool's id.
    function _createMpFromMp(MoneyPool.Data memory _baseMp, uint256 _start)
        private
        returns (MoneyPool.Data storage _mp)
    {
        _mp = _initMp(_baseMp.owner, _start);
        _mp._clone(_baseMp);
    }

    /// @notice Initializes a Money pool to be sustained for the sending address.
    /// @param _owner The owner of the Money pool being initialized.
    /// @param _start The start time for the new Money pool.
    /// @return _newMp The initialized Money pool.
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

    /// @dev The amount of redistribution in a Money pool that can be claimed by the given address.
    /// @param _mpNumber The number of the Money pool to get a redistribution amount for.
    /// @param _sustainer The address of the sustainer to get an amount for.
    /// @return amount The amount.
    function _trackedRedistribution(uint256 _mpNumber, address _sustainer)
        private
        view
        returns (uint256)
    {
        MoneyPool.Data storage _mp = mps[_mpNumber];

        // Return 0 if there's no surplus.
        if (!_mp.exists || _mp.target >= _mp.total) return 0;

        uint256 surplus = _mp.total.sub(_mp.target);

        // Calculate their share of the sustainment for the the given sustainer.
        // allocate a proportional share of the surplus, overwriting any previous value.
        uint256 _proportionOfTotal =
            _mp.sustainments[_sustainer].div(_mp.total);

        return surplus.mul(_proportionOfTotal);
    }

    /// @dev The currently active Money pool for an owner.
    /// @param _owner The owner of the money pool being looked for.
    /// @return _mp The active Money pool.
    function _activeMp(address _owner)
        private
        view
        returns (MoneyPool.Data storage _mp)
    {
        _mp = mps[latestMpNumber[_owner]];
        if (!_mp.exists) return mps[0];

        // An Active moneyPool must be either the latest moneyPool or the
        // moneyPool immediately before it.
        if (_mp._state() == MoneyPool.State.Active) return _mp;

        _mp = mps[previousMpNumber[_mp.number]];
        if (_mp.exists && _mp._state() == MoneyPool.State.Active) return _mp;

        return mps[0];
    }

    /// @dev The Money pool that's next up for an owner.
    /// @param _owner The owner of the money pool being looked for.
    /// @return _mp The upcoming Money pool.
    function _upcomingMp(address _owner)
        private
        view
        returns (MoneyPool.Data storage _mp)
    {
        _mp = mps[latestMpNumber[_owner]];
        if (!_mp.exists) return mps[0];

        // There is no upcoming Money pool if the latest Money pool is not upcoming
        if (_mp._state() != MoneyPool.State.Upcoming) return mps[0];
        return _mp;
    }
}
