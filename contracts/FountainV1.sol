// SPDX-License-Identifier: MIT
// TODO: What license do we release under?
pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

/**

@title Fountain

Create a MoneyPool (MP) that'll be used to sustain your project, and specify what its sustainability target is.
Maybe your project is providing a service or public good, maybe it's being a YouTuber, engineer, or artist -- or anything else.
Anyone with your address can help sustain your project, and once you're sustainable any additional contributions are redistributed back your sustainers.

Each MoneyPool is like a tier of the fountain, and the predefined cost to pursue the project is like the bounds of that tier's pool.

An address can only be associated with one active MoneyPool at a time, as well as a mutable one queued up for when the active MoneyPool expires.
If a MoneyPool expires without one queued, the current one will be cloned and sustainments at that time will be allocated to it.
It's impossible for a MoneyPool's sustainability or duration to be changed once there has been a sustainment made to it.
Any attempts to do so will just create/update the message sender's queued MP.

You can collect funds of yours from the sustainers pool (where MoneyPool surplus is distributed) or from the sustainability pool (where MoneyPool sustainments are kept) at anytime.

Future versions will introduce MoneyPool dependencies so that your project's surplus can get redistributed to the MP of projects it is composed of before reaching sustainers.
We also think it may be best to create a governance token WATER and route ~7% of ecosystem surplus to token holders, ~3% to fountain.finance contributors (which can be run through Fountain itself), and the rest to sustainers.

The basin of the Fountain should always be the sustainers of projects.

*/

contract FountainV1 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice Possible states that a MoneyPool may be in
    /// @dev immutable once the MoneyPool receives some sustainment.
    /// @dev entirely mutable until they become active.
    enum MoneyPoolState {Pending, Active, Redistributing}

    /// @notice The MoneyPool structure represents a MoneyPool stewarded by an address, and accounts for which addresses have contributed to it.
    struct MoneyPool {
        // The address who defined this MoneyPool and who has access to its sustainments.
        address owner;
        // // The addresses who own MoneyPools that this MoneyPool depends on.
        // // Surplus from this MoneyPool will first go towards the sustainability of dependent's current MPs.
        // address[] dependents;
        // The token that this MoneyPool can be funded with.
        address want;
        // The amount that represents sustainability for this MoneyPool.
        uint256 sustainabilityTarget;
        // The running amount that's been contributed to sustaining this MoneyPool.
        uint256 currentSustainment;
        // The time when this MoneyPool will become active.
        uint256 start;
        // The number of days until this MoneyPool's redistribution is added to the redistributionPool.
        uint256 duration;
        // Helper to verify this MoneyPool exists.
        bool exists;
        // ID of the previous MoneyPool
        uint256 previousMoneyPoolId;
        // Indicates if surplus funds have been redistributed for each sustainer address
        mapping(address => bool) redistributed;
        // The addresses who have helped to sustain this MoneyPool.
        // NOTE: Using arrays may be bad practice and/or expensive
        address[] sustainers;
        // The amount each address has contributed to the sustaining of this MoneyPool.
        mapping(address => uint256) sustainmentTracker;
        // The amount that will be redistributed to each address as a
        // consequence of abundant sustainment of this MoneyPool once it resolves.
        mapping(address => uint256) redistributionTracker;
    }

    enum Pool {REDISTRIBUTION, SUSTAINABILITY}

    /// @notice The official record of all MoneyPools ever created
    mapping(uint256 => MoneyPool) public moneyPools;

    /// @notice The latest MoneyPool for each creator address
    mapping(address => uint256) public latestMoneyPoolIds;

    /// @notice List of addresses sustained by each sustainer
    mapping(address => address[]) public sustainedAddressesBySustainer;

    // The amount that has been redistributed to each address as a consequence of surplus.
    mapping(address => uint256) public redistributionPool;

    // The funds that have accumulated to sustain each address's MoneyPools.
    mapping(address => uint256) public sustainabilityPool;

    // The total number of MoneyPools created, which is used for issuing MoneyPool IDs.
    // MoneyPools should have an id > 0, 0 should not be a moneyPoolId.
    uint256 public moneyPoolCount;

    // The contract currently only supports sustainments in DAI.
    address public DAI;

    event InitializeMoneyPool(
        uint256 indexed id,
        address indexed owner,
        uint256 indexed sustainabilityTarget,
        uint256 duration,
        address want
    );

    // This even should trigger when an MP's state changes to active.
    event ActivateMoneyPool(
        uint256 indexed id,
        address indexed owner,
        uint256 indexed sustainabilityTarget,
        uint256 duration,
        address want
    );

    event ConfigureMoneyPool(
        uint256 indexed id,
        address indexed owner,
        uint256 indexed sustainabilityTarget,
        uint256 duration,
        address want
    );

    event SustainMoneyPool(
        uint256 indexed id,
        address indexed sustainer,
        uint256 amount
    );

    event CollectRedistributions(address indexed sustainer, uint256 amount);

    event CollectSustainements(address indexed owner, uint256 amount);

    // --- External getters --- //

    function getSustainerCount(address owner)
        external
        view
        returns (uint256 count)
    {
        require(
            latestMoneyPoolIds[owner] > 0,
            "No MoneyPool found at this address"
        );
        require(
            moneyPools[latestMoneyPoolIds[owner]].exists,
            "No MoneyPool owned by this address"
        );
        return moneyPools[latestMoneyPoolIds[owner]].sustainers.length;
    }

    function getSustainmentTrackerAmount(address owner, address by)
        external
        view
        returns (uint256 amount)
    {
        require(
            latestMoneyPoolIds[owner] > 0,
            "No MoneyPool owned by this address"
        );
        require(
            moneyPools[latestMoneyPoolIds[owner]].exists,
            "No MoneyPool owned by this address"
        );
        return moneyPools[latestMoneyPoolIds[owner]].sustainmentTracker[by];
    }

    function getRedistributionTrackerAmount(address owner, address by)
        external
        view
        returns (uint256 amount)
    {
        require(
            latestMoneyPoolIds[owner] > 0,
            "No MoneyPool owned by this address"
        );
        require(
            moneyPools[latestMoneyPoolIds[owner]].exists,
            "No MoneyPool owned by this address"
        );
        return moneyPools[latestMoneyPoolIds[owner]].redistributionTracker[by];
    }

    constructor(address dai) public {
        DAI = dai;
        moneyPoolCount = 0;
    }

    /// @notice Contribute a specified amount to the sustainability of the specified address's active MoneyPool.
    /// @notice If the amount results in surplus, redistribute the surplus proportionally to sustainers of the MoneyPool.
    /// @param who The owner of the MoneyPool to sustain.
    /// @param amount Amount of sustainment.
    /// @return success If the sustainment was successful.
    function sustain(address who, uint256 amount)
        external
        returns (bool success)
    {
        require(
            amount > 0,
            "Fountain::sustain: The sustainment amount should be positive"
        );

        uint256 moneyPoolId = _moneyPoolIdToSustain(who);
        MoneyPool storage currentMoneyPool = moneyPools[moneyPoolId];

        require(
            currentMoneyPool.exists,
            "Fountain::sustain: MoneyPool owner not found"
        );

        bool wasInactive = currentMoneyPool.currentSustainment == 0;

        // Save if the message sender is contributing to this MoneyPool for the first time.
        bool isNewSustainer = currentMoneyPool.sustainmentTracker[msg.sender] ==
            0;

        // The amount that should be reserved for the sustainability of the MoneyPool.
        // If the MoneyPool is already sustainable, set to 0.
        // If the MoneyPool is not yet sustainable even with the amount, set to the amount.
        // Otherwise set to the portion of the amount it'll take for sustainability to be reached
        uint256 sustainabilityAmount;
        if (
            currentMoneyPool.currentSustainment.add(amount) <=
            currentMoneyPool.sustainabilityTarget
        ) {
            sustainabilityAmount = amount;
        } else if (
            currentMoneyPool.currentSustainment >=
            currentMoneyPool.sustainabilityTarget
        ) {
            sustainabilityAmount = 0;
        } else {
            sustainabilityAmount = currentMoneyPool.sustainabilityTarget.sub(
                currentMoneyPool.currentSustainment
            );
        }

        // TODO: Not working.`Returned error: VM Exception while processing transaction: revert`
        //https://ethereum.stackexchange.com/questions/60028/testing-transfer-of-tokens-with-truffle
        // Got it working in tests using MockContract, but need to verify it works in testnet.
        // Move the full sustainment amount to this address.
        require(
            IERC20(currentMoneyPool.want).transferFrom(
                msg.sender,
                address(this),
                amount
            ),
            "ERC20 transfer failed"
        );

        // Increment the funds that can be collected from sustainability.
        sustainabilityPool[who] = sustainabilityPool[who].add(
            sustainabilityAmount
        );

        // Increment the sustainments to the MoneyPool made by the message sender.
        currentMoneyPool.sustainmentTracker[msg.sender] = currentMoneyPool
            .sustainmentTracker[msg.sender]
            .add(amount);

        // Increment the total amount contributed to the sustainment of the MoneyPool.
        currentMoneyPool.currentSustainment = currentMoneyPool
            .currentSustainment
            .add(amount);

        // Add the message sender as a sustainer of the MoneyPool if this is the first sustainment it's making to it.
        if (isNewSustainer) currentMoneyPool.sustainers.push(msg.sender);

        // Add this address to the sustainer's list of sustained addresses
        sustainedAddressesBySustainer[msg.sender].push(who);

        // Redistribution amounts may have changed for the current MoneyPool.
        _updateTrackedRedistribution(currentMoneyPool);

        // Emit events.
        emit SustainMoneyPool(moneyPoolId, msg.sender, amount);

        if (wasInactive)
            // Emit an event since since is the first sustainment being made towards this MoneyPool.
            emit ActivateMoneyPool(
                moneyPoolCount,
                currentMoneyPool.owner,
                currentMoneyPool.sustainabilityTarget,
                currentMoneyPool.duration,
                currentMoneyPool.want
            );

        return true;
    }

    /// @notice A message sender can collect what's been redistributed to it by MoneyPools once they have expired.
    /// @param amount The amount to collect.
    /// @return success If the collecting was a success.
    function collectRedistributions(uint256 amount)
        external
        returns (bool success)
    {
        // Iterate over all of sender's sustained addresses to make sure
        // redistribution has completed for all redistributable MoneyPools
        address[] storage sustainedAddresses = sustainedAddressesBySustainer[msg
            .sender];
        for (uint256 i = 0; i < sustainedAddresses.length; i++) {
            _redistributeMoneyPool(sustainedAddresses[i]);
        }
        _performCollectRedistributions(amount);
        return true;
    }

    /// @notice A message sender can collect what's been redistributed to it by a specific MoneyPool once it's expired.
    /// @param amount The amount to collect.
    /// @param from The MoneyPool to collect from.
    /// @return success If the collecting was a success.
    function collectRedistributionsFromAddress(uint256 amount, address from)
        external
        returns (bool success)
    {
        _redistributeMoneyPool(from);
        _performCollectRedistributions(amount);
        return true;
    }

    /// @notice A message sender can collect what's been redistributed to it by specific MoneyPools once they have expired.
    /// @param amount The amount to collect.
    /// @param from The MoneyPools to collect from.
    /// @return success If the collecting was a success.
    function collectRedistributionsFromAddresses(
        uint256 amount,
        address[] calldata from
    ) external returns (bool success) {
        for (uint256 i = 0; i < from.length; i++) {
            _redistributeMoneyPool(from[i]);
        }
        _performCollectRedistributions(amount);
        return true;
    }

    /// @notice A message sender can collect funds that have been used to sustain it's MoneyPools.
    /// @param amount The amount to collect.
    /// @return success If the collecting was a success.
    function collectSustainments(uint256 amount)
        external
        returns (bool success)
    {
        require(
            sustainabilityPool[msg.sender] >= amount,
            "This address doesn't have enough to collect this much."
        );

        IERC20(DAI).safeTransferFrom(address(this), msg.sender, amount);

        sustainabilityPool[msg.sender] = sustainabilityPool[msg.sender].sub(
            amount
        );

        emit CollectSustainements(msg.sender, amount);

        return true;
    }

    /// @notice Configures the sustainability target and duration of the sender's current MoneyPool if it hasn't yet received sustainments, or
    /// @notice sets the properties of the MoneyPool that will take effect once the current MoneyPool expires.
    /// @param target The sustainability target to set.
    /// @param duration The duration to set.
    /// @param want The token that the MoneyPool wants.
    /// @return success If the update was successful.
    function configureMoneyPool(
        uint256 target,
        uint256 duration,
        address want
    ) external returns (bool success) {
        require(
            duration >= 1,
            "Fountain::configureMoneyPool: A MoneyPool must be at least one day long"
        );
        require(
            want == DAI,
            "Fountain::configureMoneyPool: For now, a MoneyPool can only be funded with DAI"
        );

        uint256 moneyPoolId = _moneyPoolIdToConfigure(msg.sender);
        MoneyPool storage moneyPool = moneyPools[moneyPoolId];
        moneyPool.sustainabilityTarget = target;
        moneyPool.duration = duration;
        moneyPool.want = want;
        if (moneyPool.previousMoneyPoolId == 0)
            emit InitializeMoneyPool(
                moneyPoolCount,
                msg.sender,
                target,
                duration,
                want
            );

        emit ConfigureMoneyPool(
            moneyPoolCount,
            msg.sender,
            target,
            duration,
            want
        );

        return true;
    }

    // --- private --- //

    /// @notice Initializes a MoneyPool to be sustained for the sending address.
    /// @param owner The owner of the money pool being initialized.
    /// @return id The initialized MoneyPool's id.
    function _initMoneyPoolId(address owner) private returns (uint256 id) {
        moneyPoolCount++;
        // Must create structs that have mappings using this approach to avoid
        // the RHS creating a memory-struct that contains a mapping.
        // See https://ethereum.stackexchange.com/a/72310
        MoneyPool storage newMoneyPool = moneyPools[moneyPoolCount];
        newMoneyPool.owner = owner;
        newMoneyPool.currentSustainment = 0;
        newMoneyPool.start = now;
        newMoneyPool.exists = true;
        newMoneyPool.previousMoneyPoolId = 0;

        latestMoneyPoolIds[owner] = moneyPoolCount;

        return moneyPoolCount;
    }

    /// @dev Executes the collection of redistributed funds.
    /// @param amount The amount to collect.
    function _performCollectRedistributions(uint256 amount) private {
        require(
            redistributionPool[msg.sender] >= amount,
            "This address doesn't have enough to collect this much."
        );

        IERC20(DAI).safeTransferFrom(address(this), msg.sender, amount);

        redistributionPool[msg.sender] = redistributionPool[msg.sender].sub(
            amount
        );

        emit CollectRedistributions(msg.sender, amount);
    }

    /// @dev The sustainability of a MoneyPool cannot be updated if there have been sustainments made to it.
    /// @param owner The address who owns the MoneyPool to look for.
    /// @return id The resulting id.
    function _moneyPoolIdToConfigure(address owner)
        private
        returns (uint256 id)
    {
        // Check if there is an active moneyPool
        uint256 moneyPoolId = _getActiveMoneyPoolId(owner);
        if (
            moneyPoolId != 0 && moneyPools[moneyPoolId].currentSustainment == 0
        ) {
            // Allow active moneyPool to be updated if it has no sustainments
            return moneyPoolId;
        }

        // Cannot update active moneyPool, check if there is a pending moneyPool
        moneyPoolId = _getPendingMoneyPoolId(owner);
        if (moneyPoolId != 0) return moneyPoolId;

        // No pending moneyPool found, clone the latest moneyPool
        moneyPoolId = _getLatestMoneyPoolId(owner);

        if (moneyPoolId != 0) return _createMoneyPoolFromId(moneyPoolId, now);

        return _initMoneyPoolId(owner);
    }

    /// @dev Only active MoneyPools can be sustained.
    /// @param owner The address who owns the MoneyPool to look for.
    /// @return id The resulting id.
    function _moneyPoolIdToSustain(address owner) private returns (uint256 id) {
        // Check if there is an active moneyPool
        uint256 moneyPoolId = _getActiveMoneyPoolId(owner);
        if (moneyPoolId != 0) return moneyPoolId;

        // No active moneyPool found, check if there is a pending moneyPool
        moneyPoolId = _getPendingMoneyPoolId(owner);
        if (moneyPoolId != 0) {
            return moneyPoolId;
        }

        // No pending moneyPool found, clone the latest moneyPool
        moneyPoolId = _getLatestMoneyPoolId(owner);

        require(
            moneyPoolId > 0,
            "Fountain::moneyPoolIdToSustain: MoneyPool not found"
        );

        MoneyPool storage latestMoneyPool = moneyPools[moneyPoolId];
        // Use a start date that's a multiple of the duration.
        // This creates the effect that there have been scheduled MoneyPools ever since the `latest`, even if `latest` is a long time in the past.
        uint256 start = _determineModuloStart(
            latestMoneyPool.start.add(latestMoneyPool.duration),
            latestMoneyPool.duration
        );

        uint256 newMoneyPoolId = _createMoneyPoolFromId(moneyPoolId, start);

        return newMoneyPoolId;
    }

    /// @dev Proportionally allocate the specified amount to the contributors of the specified MoneyPool,
    /// @dev meaning each sustainer will receive a portion of the specified amount equivalent to the portion of the total
    /// @dev amount contributed to the sustainment of the MoneyPool that they are responsible for.
    /// @param mp The MoneyPool to update.
    function _updateTrackedRedistribution(MoneyPool storage mp) private {
        // Return if there's no surplus.
        if (mp.sustainabilityTarget >= mp.currentSustainment) return;

        uint256 surplus = mp.currentSustainment.sub(mp.sustainabilityTarget);

        // For each sustainer, calculate their share of the sustainment and
        // allocate a proportional share of the surplus, overwriting any previous value.
        for (uint256 i = 0; i < mp.sustainers.length; i++) {
            address sustainer = mp.sustainers[i];

            uint256 currentSustainmentProportion = mp
                .sustainmentTracker[sustainer]
                .div(mp.currentSustainment);

            uint256 sustainerSurplusShare = surplus.mul(
                currentSustainmentProportion
            );

            //Store the updated redistribution in the MoneyPool.
            mp.redistributionTracker[sustainer] = sustainerSurplusShare;
        }
    }

    /// @dev Check to see if the given MoneyPool has started.
    /// @param mp The MoneyPool to check.
    /// @return isStarted The boolean result.
    function _isMoneyPoolStarted(MoneyPool storage mp)
        private
        view
        returns (bool isStarted)
    {
        return now >= mp.start;
    }

    /// @dev Check to see if the given MoneyPool has expired.
    /// @param mp The MoneyPool to check.
    /// @return isExpired The boolean result.
    function _isMoneyPoolExpired(MoneyPool storage mp)
        private
        view
        returns (bool isExpired)
    {
        return now > mp.start.add(mp.duration.mul(1 days));
    }

    /// @dev Take any tracked redistribution in the given moneyPool and
    /// @dev add them to the redistribution pool.
    /// @param mpAddress The MoneyPool address to redistribute.
    function _redistributeMoneyPool(address mpAddress) private {
        uint256 moneyPoolId = latestMoneyPoolIds[mpAddress];
        require(
            moneyPoolId > 0,
            "Fountain::redistributeMoneyPool: MoneyPool not found"
        );
        MoneyPool storage moneyPool = moneyPools[moneyPoolId];

        // Iterate through all MoneyPools for this address. For each iteration,
        // if the MoneyPool has a state of redistributing and it has not yet
        // been redistributed for the current sustainer, then process the
        // redistribution. Iterate until a MoneyPool is found that has already
        // been redistributed for this sustainer. This logic should skip Active
        // and Pending MoneyPools.
        // Short circuits by testing `moneyPool.redistributed` to limit number
        // of iterations since all previous MoneyPools must have already been
        // redistributed.
        address sustainer = msg.sender;
        while (moneyPoolId > 0 && !moneyPool.redistributed[sustainer]) {
            if (_state(moneyPoolId) == MoneyPoolState.Redistributing) {
                redistributionPool[sustainer] = redistributionPool[sustainer]
                    .add(moneyPool.redistributionTracker[sustainer]);
                moneyPool.redistributed[sustainer] = true;
            }
            moneyPoolId = moneyPool.previousMoneyPoolId;
            moneyPool = moneyPools[moneyPoolId];
        }
    }

    /// @dev Returns a copy of the given MoneyPool with reset sustainments.
    /// @param moneyPoolId The id of the MoneyPool to base the new MoneyPool on.
    /// @param start The start date to use for the new MoneyPool.
    /// @return newMoneyPoolId The new MoneyPool ID.
    function _createMoneyPoolFromId(uint256 moneyPoolId, uint256 start)
        private
        returns (uint256 newMoneyPoolId)
    {
        MoneyPool storage currentMoneyPool = moneyPools[moneyPoolId];
        require(
            currentMoneyPool.exists,
            "Fountain::createMoneyPoolFromId: Invalid moneyPool"
        );

        moneyPoolCount++;
        // Must create structs that have mappings using this approach to avoid
        // the RHS creating a memory-struct that contains a mapping.
        // See https://ethereum.stackexchange.com/a/72310
        MoneyPool storage moneyPool = moneyPools[moneyPoolCount];
        moneyPool.owner = currentMoneyPool.owner;
        moneyPool.sustainabilityTarget = currentMoneyPool.sustainabilityTarget;
        moneyPool.currentSustainment = 0;
        moneyPool.start = start;
        moneyPool.duration = currentMoneyPool.duration;
        moneyPool.want = currentMoneyPool.want;
        moneyPool.exists = true;
        moneyPool.previousMoneyPoolId = moneyPoolId;

        latestMoneyPoolIds[currentMoneyPool.owner] = moneyPoolCount;

        return moneyPoolCount;
    }

    /// @dev Returns the date that that is the nearest multiple of duration from oldEnd.
    /// @return start The date.
    function _determineModuloStart(uint256 oldEnd, uint256 duration)
        private
        view
        returns (uint256 start)
    {
        // Use the old end if the current time is still within the duration.
        if (oldEnd.add(duration) > now) return oldEnd;
        // Otherwise, use the closest multiple of the duration from the old end.
        uint256 distanceToStart = (now.sub(oldEnd)).mod(duration);
        return now.sub(distanceToStart);
    }

    function _state(uint256 moneyPoolId) private view returns (MoneyPoolState) {
        require(
            moneyPoolCount >= moneyPoolId && moneyPoolId > 0,
            "Fountain::state: Invalid moneyPoolId"
        );
        MoneyPool storage moneyPool = moneyPools[moneyPoolId];
        require(moneyPool.exists, "Fountain::state: Invalid MoneyPool");

        if (_isMoneyPoolExpired(moneyPool)) {
            return MoneyPoolState.Redistributing;
        }

        if (_isMoneyPoolStarted(moneyPool) && !_isMoneyPoolExpired(moneyPool)) {
            return MoneyPoolState.Active;
        }

        return MoneyPoolState.Pending;
    }

    function _getLatestMoneyPoolId(address moneyPoolAddress)
        private
        view
        returns (uint256 id)
    {
        return latestMoneyPoolIds[moneyPoolAddress];
    }

    function _getPendingMoneyPoolId(address moneyPoolAddress)
        private
        view
        returns (uint256 id)
    {
        uint256 moneyPoolId = latestMoneyPoolIds[moneyPoolAddress];
        if (moneyPoolId == 0) return 0;
        if (_state(moneyPoolId) != MoneyPoolState.Pending)
            // There is no pending moneyPool if the latest MoneyPool is not pending
            return 0;
        return moneyPoolId;
    }

    function _getActiveMoneyPoolId(address moneyPoolAddress)
        private
        view
        returns (uint256 id)
    {
        uint256 moneyPoolId = latestMoneyPoolIds[moneyPoolAddress];
        if (moneyPoolId == 0) return 0;

        // An Active moneyPool must be either the latest moneyPool or the
        // moneyPool immediately before it.
        if (_state(moneyPoolId) == MoneyPoolState.Active) return moneyPoolId;

        MoneyPool storage moneyPool = moneyPools[moneyPoolId];
        require(
            moneyPool.exists,
            "Fountain::getActiveMoneyPoolId: Invalid MoneyPool"
        );
        moneyPoolId = moneyPool.previousMoneyPoolId;
        if (moneyPoolId > 0 && _state(moneyPoolId) == MoneyPoolState.Active) {
            return moneyPoolId;
        }
        return 0;
    }
}
