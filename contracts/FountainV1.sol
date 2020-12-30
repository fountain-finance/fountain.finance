// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

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

contract FountainV1 is IFountainV1 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice Possible states that a Money pool may be in
    /// @dev immutable once the Money pool receives some sustainment.
    /// @dev entirely mutable until they become active.
    enum MpState {Upcoming, Active, Redistributing}

    /// @notice The Money pool structure represents a project stewarded by an address, and accounts for which addresses have helped sustain the project.
    struct MoneyPool {
        // The address who defined this Money pool and who has access to its sustainments.
        address owner;
        // The addresses who own Money pools that this Money pool depends on.
        // Surplus from this Money pool will first go towards the sustainability of dependent's current MPs.
        address[] dependencies;
        // The token that this Money pool can be funded with.
        IERC20 want;
        // The amount that represents sustainability for this Money pool.
        uint256 target;
        // The running amount that's been contributed to sustaining this Money pool.
        uint256 balance;
        // The time when this Money pool will become active.
        uint256 start;
        // The number of days until this Money pool's redistribution is added to the redistributionPool.
        uint256 duration;
        // Helper to verify this Money pool exists.
        bool exists;
        // Indicates if surplus funds have been redistributed for each sustainer address
        mapping(address => bool) hasRedistributed;
        // The addresses who have helped to sustain this Money pool.
        // NOTE: Using arrays may be bad practice and/or expensive
        address[] sustainers;
        // The amount each address has contributed to the sustaining of this Money pool.
        mapping(address => uint256) sustainments;
        // The amount that will be redistributed to each address as a
        // consequence of abundant sustainment of this Money pool once it expires.
        mapping(address => uint256) redistributionTracker;
        // The Money pool's version.
        uint8 version;
    }

    // Wrap the sustain transaction in a lock to prevent reentrency.
    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "Fountain: locked");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    // --- public properties --- //

    // The official record of all Money pools ever created
    mapping(uint256 => MoneyPool) public mps;

    // The funds that have accumulated to sustain each address's Money pools.
    mapping(address => uint256) public sustainabilityPool;

    /// @notice A mapping from Money pool id's the the id of the previous MP for the same owner.
    mapping(uint256 => uint256) public override previousMpIds;

    /// @notice The latest Money pool for each owner address
    mapping(address => uint256) public override latestMpIds;

    // The amount that has been redistributed to each address as a consequence of surplus.
    mapping(address => uint256) public override redistributionPool;

    // The total number of Money pools created, which is used for issuing Money pool IDs.
    // Money pools should have an ID > 0.
    uint256 public override mpCount;

    // List of addresses sustained by each sustainer
    mapping(address => address[]) public sustainedAddressesBySustainer;

    // The contract currently only supports sustainments in dai.
    IERC20 public dai;

    // --- events --- //

    /// This event should trigger when a Money pool is first initialized.
    event InitializeMp(uint256 indexed id, address indexed owner);

    // This event should trigger when a Money pool's state changes to active.
    event ActivateMp(
        uint256 indexed id,
        address indexed owner,
        uint256 indexed target,
        uint256 duration,
        IERC20 want
    );

    /// This event should trigger when a Money pool is configured.
    event ConfigureMp(
        uint256 indexed id,
        address indexed owner,
        uint256 indexed target,
        uint256 duration,
        IERC20 want
    );

    /// This event should trigger when a Money pool is sustained.
    event SustainMp(
        uint256 indexed id,
        address indexed owner,
        address indexed beneficiary,
        address sustainer,
        uint256 amount
    );

    /// This event should trigger when redistributions are collected.
    event CollectRedistributions(address indexed sustainer, uint256 amount);

    /// This event should trigger when sustainments are collected.
    event CollectSustainements(address indexed owner, uint256 amount);

    // --- external views --- //

    /// @dev The properties of the given Money pool.
    /// @param _mpId The ID of the Money pool to get the properties of.
    /// @return want The token the Money pool wants.
    /// @return target The amount of the want token this Money pool is targeting.
    /// @return start The time when this Money pool started.
    /// @return duration The duration of this Money pool.
    /// @return sustainerCount The number of addresses that have sustained this Money pool.
    /// @return balance The balance of the Money pool. Returns 0 if the Money pool isn't owned by the message sender.
    function getMp(uint256 _mpId)
        external
        view
        override
        returns (
            IERC20 want,
            uint256 target,
            uint256 start,
            uint256 duration,
            uint256 sustainerCount,
            uint256 balance
        )
    {
        return _mpProperties(_mpId);
    }

    /// @dev The Money pool that's next up for an owner.
    /// @param _owner The owner of the Money pool being looked for.
    /// @return want The token the Money pool wants.
    /// @return target The amount of the want token this Money pool is targeting.
    /// @return start The time when this Money pool started.
    /// @return duration The duration of this Money pool.
    /// @return sustainerCount The number of addresses that have sustained this Money pool.
    /// @return balance The balance of the Money pool. Returns 0 if the Money pool isn't owned by the message sender.
    function getUpcomingMp(address _owner)
        external
        view
        override
        returns (
            IERC20 want,
            uint256 target,
            uint256 start,
            uint256 duration,
            uint256 sustainerCount,
            uint256 balance
        )
    {
        return _mpProperties(_upcomingMpId(_owner));
    }

    /// @dev The currently active Money pool for an owner.
    /// @param _owner The owner of the money pool being looked for.
    /// @return want The token the Money pool wants.
    /// @return target The amount of the want token this Money pool is targeting.
    /// @return start The time when this Money pool started.
    /// @return duration The duration of this Money pool.
    /// @return sustainerCount The number of addresses that have sustained this Money pool.
    /// @return balance The balance of the Money pool. Returns 0 if the Money pool isn't owned by the message sender.
    function getActiveMp(address _owner)
        external
        view
        override
        returns (
            IERC20 want,
            uint256 target,
            uint256 start,
            uint256 duration,
            uint256 sustainerCount,
            uint256 balance
        )
    {
        return _mpProperties(_activeMpId(_owner));
    }

    /// @dev The ID of the Money pool that's next up for an owner.
    /// @param _owner The owner of the Money pool being looked for.
    /// @return id The ID of the upcoming Money pool.
    function getUpcomingMpId(address _owner)
        external
        view
        override
        returns (uint256)
    {
        return _upcomingMpId(_owner);
    }

    /// @dev The ID of the currently active Money pool for an owner.
    /// @param _owner The owner of the money pool being looked for.
    /// @return id The active Money pool's ID.
    function getActiveMpId(address _owner)
        external
        view
        override
        returns (uint256)
    {
        return _activeMpId(_owner);
    }

    /// @dev The amount of sustainments accessible.
    /// @param owner The owner to get the amount for.
    /// @return amount The amount.
    function getSustainmentBalance(address owner)
        external
        view
        override
        returns (uint256)
    {
        return sustainabilityPool[owner];
    }

    /// @dev The amount of sustainments in a Money pool that were contributed by the given address.
    /// @param _mpId The ID of the Money pool to get a contribution for.
    /// @param _sustainer The address of the sustainer to get an amount for.
    /// @return amount The amount.
    function getSustainment(uint256 _mpId, address _sustainer)
        external
        view
        override
        returns (uint256)
    {
        MoneyPool memory _mp = mps[_mpId];
        require(_mp.exists, "Fountain::getSustainment: Money pool not found");
        require(
            _mp.owner == msg.sender || _state(_mpId) != MpState.Active,
            "Fountain::getSustainment: Only the owner of an Money pool can get sustainments."
        );
        return mps[_mpId].sustainments[_sustainer];
    }

    /// @dev The amount of redistribution in a Money pool that can be claimed by the given address.
    /// @param _mpId The ID of the Money pool to get a redistribution amount for.
    /// @param _sustainer The address of the sustainer to get an amount for.
    /// @return amount The amount.
    function getTrackedRedistribution(uint256 _mpId, address _sustainer)
        external
        view
        override
        returns (uint256)
    {
        return _trackedRedistribution(_mpId, _sustainer);
    }

    /// @dev The amount of redistribution accessible.
    /// @param sustainer The sustainer to get the amount for.
    /// @return amount The amount.
    function getRedistributionBalance(address sustainer)
        external
        view
        override
        returns (uint256)
    {
        return redistributionPool[sustainer];
    }

    // --- external transactions --- //

    constructor(IERC20 _dai) public {
        dai = _dai;
        mpCount = 0;
    }

    /// @dev Configures the sustainability target and duration of the sender's current Money pool if it hasn't yet received sustainments, or
    /// @dev sets the properties of the Money pool that will take effect once the current Money pool expires.
    /// @param _target The sustainability target to set.
    /// @param _duration The duration to set.
    /// @param _want The token that the Money pool wants.
    /// @return mpId The ID of the Money pool that was successfully configured.
    function configureMp(
        uint256 _target,
        uint256 _duration,
        IERC20 _want
    ) external override returns (uint256) {
        require(
            _duration >= 1,
            "Fountain::configureMp: A Money Pool must be at least one day long"
        );
        require(
            _want == dai,
            "Fountain::configureMp: For now, a Money Pool can only be funded with dai"
        );
        require(
            _target > 0,
            "Fountain::configureMp: A Money Pool target must be a positive number"
        );

        uint256 _mpId = _mpIdToConfigure(msg.sender);
        MoneyPool storage _mp = mps[_mpId];
        _mp.target = _target;
        _mp.duration = _duration;
        _mp.want = _want;

        if (previousMpIds[_mpId] == 0) emit InitializeMp(mpCount, msg.sender);
        emit ConfigureMp(mpCount, msg.sender, _target, _duration, _want);

        return _mpId;
    }

    /// @dev Contribute a specified amount to the sustainability of the specified address's active Money pool.
    /// @dev If the amount results in surplus, redistribute the surplus proportionally to sustainers of the Money pool.
    /// @param _owner The owner of the Money pool to sustain.
    /// @param _amount Amount of sustainment.
    /// @return mpId The ID of the Money pool that was successfully sustained.
    function sustain(address _owner, uint256 _amount)
        external
        override
        returns (uint256)
    {
        return _sustain(_owner, _amount, _owner);
    }

    /// @dev Overloaded from above with the addition of:
    /// @param _owner The owner of the Money pool to sustain.
    /// @param _amount Amount of sustainment.
    /// @param _beneficiary The address to associate with this sustainment. The mes.sender is making this sustainment on the beneficiary's behalf.
    /// @return mpId The ID of the Money pool that was successfully sustained.
    function sustain(
        address _owner,
        uint256 _amount,
        address _beneficiary
    ) external override returns (uint256) {
        return _sustain(_owner, _amount, _beneficiary);
    }

    /// @dev A message sender can collect what's been redistributed to it by Money pools once they have expired.
    /// @param _amount The amount to collect.
    /// @return success If the collecting was a success.
    function collectRedistributions(uint256 _amount)
        external
        override
        returns (bool)
    {
        // Iterate over all of sender's sustained addresses to make sure
        // redistribution has completed for all redistributable Money pools
        address[] memory _sustainedAddresses =
            sustainedAddressesBySustainer[msg.sender];

        for (uint256 i = 0; i < _sustainedAddresses.length; i++)
            _redistributeMp(_sustainedAddresses[i]);

        _performCollectRedistributions(_amount);
        return true;
    }

    /// @dev A message sender can collect what's been redistributed to it by a specific Money pool once it's expired.
    /// @param _amount The amount to collect.
    /// @param _from The Money pool to collect from.
    /// @return success If the collecting was a success.
    function collectRedistributionsFromAddress(uint256 _amount, address _from)
        external
        override
        returns (bool)
    {
        _redistributeMp(_from);
        _performCollectRedistributions(_amount);
        return true;
    }

    /// @dev A message sender can collect what's been redistributed to it by specific Money pools once they have expired.
    /// @param _amount The amount to collect.
    /// @param _from The Money pools to collect from.
    /// @return success If the collecting was a success.
    function collectRedistributionsFromAddresses(
        uint256 _amount,
        address[] calldata _from
    ) external override returns (bool) {
        for (uint256 i = 0; i < _from.length; i++) _redistributeMp(_from[i]);

        _performCollectRedistributions(_amount);
        return true;
    }

    /// @dev A message sender can collect funds that have been used to sustain it's Money pools.
    /// @param _amount The amount to collect.
    /// @return success If the collecting was a success.
    function collectSustainments(uint256 _amount)
        external
        override
        returns (bool)
    {
        require(
            sustainabilityPool[msg.sender] >= _amount,
            "Fountain::collectSustainments: This address doesn't have enough to collect this much."
        );

        dai.safeTransferFrom(address(this), msg.sender, _amount);

        sustainabilityPool[msg.sender] = sustainabilityPool[msg.sender].sub(
            _amount
        );

        emit CollectSustainements(msg.sender, _amount);

        return true;
    }

    // --- private --- //

    /// @dev Contribute a specified amount to the sustainability of the specified address's active Money pool.
    /// @dev If the amount results in surplus, redistribute the surplus proportionally to sustainers of the Money pool.
    /// @param _owner The owner of the Money pool to sustain.
    /// @param _amount Amount of sustainment.
    /// @param _beneficiary The address to associate with this sustainment. The mes.sender is making this sustainment on the beneficiary's behalf.
    /// @return mpId The ID of the Money pool that was successfully sustained.
    function _sustain(
        address _owner,
        uint256 _amount,
        address _beneficiary
    ) private lock returns (uint256) {
        require(
            _amount > 0,
            "Fountain::sustain: The sustainment amount should be positive"
        );

        uint256 _mpId = _mpIdToSustain(_owner);
        MoneyPool storage _currentMp = mps[_mpId];

        require(
            _currentMp.exists,
            "Fountain::sustain: Money pool owner not found"
        );

        bool _wasInactive = _currentMp.balance == 0;

        // Save if the message sender is contributing to this Money pool for the first time.
        bool _isNewSustainer = _currentMp.sustainments[_beneficiary] == 0;

        // The amount that should be reserved for the sustainability of the Money pool.
        // If the Money pool is already sustainable, set to 0.
        // If the Money pool is not yet sustainable even with the amount, set to the amount.
        // Otherwise set to the portion of the amount it'll take for sustainability to be reached
        uint256 _sustainabilityAmount;
        if (_currentMp.balance.add(_amount) <= _currentMp.target) {
            _sustainabilityAmount = _amount;
        } else if (_currentMp.balance >= _currentMp.target) {
            _sustainabilityAmount = 0;
        } else {
            _sustainabilityAmount = _currentMp.target.sub(_currentMp.balance);
        }

        // TODO: Not working.`Returned error: VM Exception while processing transaction: revert`
        //https://ethereum.stackexchange.com/questions/60028/testing-transfer-of-tokens-with-truffle
        // Got it working in tests using MockContract, but need to verify it works in testnet.
        // Move the full sustainment amount to this address.
        require(
            _currentMp.want.transferFrom(msg.sender, address(this), _amount),
            "Fountain::sustain: ERC20 transfer failed"
        );

        // Increment the funds that can be collected from sustainability.
        sustainabilityPool[_owner] = sustainabilityPool[_owner].add(
            _sustainabilityAmount
        );

        // Increment the sustainments to the Money pool made by the message sender.
        _currentMp.sustainments[_beneficiary] = _currentMp.sustainments[
            _beneficiary
        ]
            .add(_amount);

        // Increment the total amount contributed to the sustainment of the Money pool.
        _currentMp.balance = _currentMp.balance.add(_amount);

        // Add the message sender as a sustainer of the Money pool if this is the first sustainment it's making to it.
        if (_isNewSustainer) _currentMp.sustainers.push(_beneficiary);

        // Add this address to the sustainer's list of sustained addresses
        sustainedAddressesBySustainer[_beneficiary].push(_owner);

        // Emit events.
        emit SustainMp(
            _mpId,
            _currentMp.owner,
            _beneficiary,
            msg.sender,
            _amount
        );

        if (_wasInactive)
            // Emit an event since since is the first sustainment being made towards this Money pool.
            // NOTE: will emitting this event make the first sustainment of a MP significantly more costly in gas?
            emit ActivateMp(
                mpCount,
                _currentMp.owner,
                _currentMp.target,
                _currentMp.duration,
                _currentMp.want
            );

        return _mpId;
    }

    /// @dev The properties of the given Money pool.
    /// @param _mpId The ID of the Money pool to get the properties of.
    /// @return want The token the Money pool wants.
    /// @return target The amount of the want token this Money pool is targeting.
    /// @return start The time when this Money pool started.
    /// @return duration The duration of this Money pool.
    /// @return sustainerCount The number of addresses that have sustained this Money pool.
    /// @return balance The balance of the Money pool.
    function _mpProperties(uint256 _mpId)
        private
        view
        returns (
            IERC20,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        MoneyPool memory _mp = mps[_mpId];
        require(_mp.exists, "Fountain::_mpProperties: Money pool not found");

        return (
            _mp.want,
            _mp.target,
            _mp.start,
            _mp.duration,
            _mp.sustainers.length,
            _mp.balance
        );
    }

    /// @dev Executes the collection of redistributed funds.
    /// @param _amount The amount to collect.
    function _performCollectRedistributions(uint256 _amount) private {
        require(
            redistributionPool[msg.sender] >= _amount,
            "Fountain::_performCollectRedistributions: This address doesn't have enough to collect this much."
        );

        dai.safeTransferFrom(address(this), msg.sender, _amount);

        redistributionPool[msg.sender] = redistributionPool[msg.sender].sub(
            _amount
        );

        emit CollectRedistributions(msg.sender, _amount);
    }

    /// @dev The sustainability of a Money pool cannot be updated if there have been sustainments made to it.
    /// @param _owner The address who owns the Money pool to look for.
    /// @return id The resulting ID.
    function _mpIdToConfigure(address _owner) private returns (uint256) {
        // Allow active moneyPool to be updated if it has no sustainments
        uint256 _mpId = _activeMpId(_owner);
        if (_mpId != 0 && mps[_mpId].balance == 0) return _mpId;

        // Cannot update active moneyPool, check if there is a upcoming moneyPool
        _mpId = _upcomingMpId(_owner);
        if (_mpId != 0) return _mpId;

        // No upcoming moneyPool found, clone the latest moneyPool
        _mpId = latestMpIds[_owner];

        if (_mpId != 0) return _createMpFromId(_mpId, now);

        _mpId = _initMpId(_owner);
        MoneyPool storage _mp = mps[_mpId];
        _mp.start = now;

        return _mpId;
    }

    /// @dev Only active Money pools can be sustained.
    /// @param _owner The address who owns the Money pool to look for.
    /// @return id The resulting ID.
    function _mpIdToSustain(address _owner) private returns (uint256) {
        // Check if there is an active moneyPool
        uint256 _mpId = _activeMpId(_owner);
        if (_mpId != 0) return _mpId;

        // No active moneyPool found, check if there is an upcoming moneyPool
        _mpId = _upcomingMpId(_owner);
        if (_mpId != 0) return _mpId;

        // No upcoming moneyPool found, clone the latest moneyPool
        _mpId = latestMpIds[_owner];

        require(_mpId > 0, "Fountain::mpIdToSustain: Money pool not found");

        MoneyPool memory _latestMp = mps[_mpId];
        // Use a start date that's a multiple of the duration.
        // This creates the effect that there have been scheduled Money pools ever since the `latest`, even if `latest` is a long time in the past.
        uint256 _start =
            _determineModuloStart(
                _latestMp.start.add(_latestMp.duration),
                _latestMp.duration
            );

        return _createMpFromId(_mpId, _start);
    }

    /// @dev Proportionally allocate the specified amount to the contributors of the specified Money pool,
    /// @dev meaning each sustainer will receive a portion of the specified amount equivalent to the portion of the total
    /// @dev amount contributed to the sustainment of the Money pool that they are responsible for.
    /// @param _mpId The ID of the Money pool to update.
    function _updateTrackedRedistribution(uint256 _mpId, address _sustainer)
        private
    {
        MoneyPool storage _mp = mps[_mpId];

        //Store the updated redistribution in the Money pool.
        _mp.redistributionTracker[_sustainer] = _trackedRedistribution(
            _mpId,
            _sustainer
        );
    }

    /// @dev Take any tracked redistribution in the given moneyPool and
    /// @dev add them to the redistribution pool.
    /// @param _owner The Money pool address to redistribute.
    function _redistributeMp(address _owner) private {
        uint256 _mpId = latestMpIds[_owner];
        require(_mpId > 0, "Fountain::redistributeMp: Money Pool not found");
        MoneyPool storage _mp = mps[_mpId];

        // Iterate through all Money pools for this address. For each iteration,
        // if the Money pool has a state of redistributing and it has not yet
        // been redistributed for the current sustainer, then process the
        // redistribution. Iterate until a Money pool is found that has already
        // been redistributed for this sustainer. This logic should skip Active
        // and Upcoming Money pools.
        // Short circuits by testing `moneyPool.redistributed` to limit number
        // of iterations since all previous Money pools must have already been
        // redistributed.
        address sustainer = msg.sender;
        while (_mpId > 0 && !_mp.hasRedistributed[sustainer]) {
            if (_state(_mpId) == MpState.Redistributing) {
                _updateTrackedRedistribution(_mpId, sustainer);
                redistributionPool[sustainer] = redistributionPool[sustainer]
                    .add(_mp.redistributionTracker[sustainer]);
                _mp.hasRedistributed[sustainer] = true;
            }
            _mpId = previousMpIds[_mpId];
            _mp = mps[_mpId];
        }
    }

    /// @dev The state the Money pool for the given ID is in.
    /// @param _mpId The ID of the Money pool to get the state of.
    /// @return state The state.
    function _state(uint256 _mpId) private view returns (MpState) {
        require(
            mpCount >= _mpId && _mpId > 0,
            "Fountain::_state: Invalid Money pool ID"
        );
        MoneyPool memory _mp = mps[_mpId];
        require(_mp.exists, "Fountain::_state: Invalid Money Pool");

        if (_hasMpExpired(_mp)) return MpState.Redistributing;
        if (_hasMpStarted(_mp)) return MpState.Active;
        return MpState.Upcoming;
    }

    /// @dev Returns a copy of the given Money pool with reset sustainments.
    /// @param _baseMpId The ID of the Money pool to base the new Money pool on.
    /// @param _start The start date to use for the new Money pool.
    /// @return newMpId The new Money pool's ID.
    function _createMpFromId(uint256 _baseMpId, uint256 _start)
        private
        returns (uint256)
    {
        MoneyPool storage _currentMp = mps[_baseMpId];
        require(
            _currentMp.exists,
            "Fountain::createMpFromId: Invalid Money pool"
        );

        uint256 id = _initMpId(_currentMp.owner);
        // Must create structs that have mappings using this approach to avoid
        // the RHS creating a memory-struct that contains a mapping.
        // See https://ethereum.stackexchange.com/a/72310
        MoneyPool storage _mp = mps[id];
        _mp.target = _currentMp.target;
        _mp.start = _start;
        _mp.duration = _currentMp.duration;
        _mp.want = _currentMp.want;

        previousMpIds[id] = _baseMpId;

        latestMpIds[_currentMp.owner] = mpCount;

        return mpCount;
    }

    /// @notice Initializes a Money pool to be sustained for the sending address.
    /// @param _owner The owner of the money pool being initialized.
    /// @return id The initialized Money pool's ID.
    function _initMpId(address _owner) private returns (uint256) {
        mpCount++;
        // Must create structs that have mappings using this approach to avoid
        // the RHS creating a memory-struct that contains a mapping.
        // See https://ethereum.stackexchange.com/a/72310
        MoneyPool storage _newMp = mps[mpCount];
        _newMp.owner = _owner;
        _newMp.balance = 0;
        _newMp.exists = true;
        _newMp.version = 1;

        previousMpIds[mpCount] = latestMpIds[_owner];

        latestMpIds[_owner] = mpCount;

        return mpCount;
    }

    /// @dev The amount of redistribution in a Money pool that can be claimed by the given address.
    /// @param _mpId The ID of the Money pool to get a redistribution amount for.
    /// @param _sustainer The address of the sustainer to get an amount for.
    /// @return amount The amount.
    function _trackedRedistribution(uint256 _mpId, address _sustainer)
        private
        view
        returns (uint256)
    {
        MoneyPool storage _mp = mps[_mpId];

        // Return 0 if there's no surplus.
        if (!_mp.exists || _mp.target >= _mp.balance) return 0;

        uint256 surplus = _mp.balance.sub(_mp.target);

        // Calculate their share of the sustainment for the the given sustainer.
        // allocate a proportional share of the surplus, overwriting any previous value.
        uint256 _balanceProportion =
            _mp.sustainments[_sustainer].div(_mp.balance);

        return surplus.mul(_balanceProportion);
    }

    /// @dev The currently active Money pool for an owner.
    /// @param _owner The owner of the money pool being looked for.
    /// @return id The active Money pool's ID.
    function _activeMpId(address _owner) private view returns (uint256) {
        uint256 _mpId = latestMpIds[_owner];
        if (_mpId == 0) return 0;

        // An Active moneyPool must be either the latest moneyPool or the
        // moneyPool immediately before it.
        if (_state(_mpId) == MpState.Active) return _mpId;

        _mpId = previousMpIds[_mpId];
        if (_mpId > 0 && _state(_mpId) == MpState.Active) return _mpId;

        return 0;
    }

    /// @dev The Money pool that's next up for an owner.
    /// @param _owner The owner of the money pool being looked for.
    /// @return id The ID of the upcoming Money pool.
    function _upcomingMpId(address _owner) private view returns (uint256) {
        uint256 _mpId = latestMpIds[_owner];
        if (_mpId == 0) return 0;
        // There is no upcoming Money pool if the latest Money pool is not upcoming
        if (_state(_mpId) != MpState.Upcoming) return 0;
        return _mpId;
    }

    /// @dev Check to see if the given Money pool has started.
    /// @param _mp The Money pool to check.
    /// @return hasStarted The boolean result.
    function _hasMpStarted(MoneyPool memory _mp) private view returns (bool) {
        return now >= _mp.start;
    }

    /// @dev Check to see if the given MoneyPool has expired.
    /// @param _mp The Money pool to check.
    /// @return hasExpired The boolean result.
    function _hasMpExpired(MoneyPool memory _mp) private view returns (bool) {
        return now > _mp.start.add(_mp.duration.mul(1 days));
    }

    /// @dev Returns the date that is the nearest multiple of duration from oldEnd.
    /// @param _oldEnd The most recent end date to calculate from.
    /// @param _duration The duration to use for the calculation.
    /// @return start The date.
    function _determineModuloStart(uint256 _oldEnd, uint256 _duration)
        private
        view
        returns (uint256)
    {
        // Use the old end if the current time is still within the duration.
        if (_oldEnd.add(_duration) > now) return _oldEnd;
        // Otherwise, use the closest multiple of the duration from the old end.
        uint256 _distanceToStart = (now.sub(_oldEnd)).mod(_duration);
        return now.sub(_distanceToStart);
    }
}
