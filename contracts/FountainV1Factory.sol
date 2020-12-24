// SPDX-License-Identifier: MIT
// TODO: What license do we release under?
pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./FountainV1MoneyPool.sol";

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

contract FountainV1Factory {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// @dev The official record of all MoneyPools ever created
    mapping(uint256 => FountainV1MoneyPool) public moneyPools;

    /// @dev The latest MoneyPool for each MoneyPool owner
    mapping(address => FountainV1MoneyPool) latestMoneyPools;

    /// List of owners sustained by each sustainer
    mapping(address => address[]) public sustainedOwnersBySustainer;

    /// The amount that has been redistributed to each address as a consequence of surplus.
    mapping(address => uint256) public redistributionPool;

    /// The funds that have accumulated to sustain each address's MoneyPools.
    mapping(address => uint256) public sustainabilityPool;

    /// The total number of MoneyPools created, which is used for issuing MoneyPool IDs.
    /// MoneyPools should have an id > 0, 0 should not be a moneyPoolId.
    uint256 public moneyPoolCount;

    /// The contract currently only supports sustainments in DAI.
    address public DAI;

    // --- Events --- //

    /// This event should trigger when an MoneyPool is first initialized.
    event InitializeMoneyPool(
        FountainV1MoneyPool indexed mp,
        address indexed owner
    );

    /// This event should trigger when a MoneyPool's state changes to active.
    event ActivateMoneyPool(
        FountainV1MoneyPool indexed mp,
        address indexed owner,
        uint256 indexed target,
        uint256 duration,
        address want
    );

    /// This event should trigger when a MoneyPool is configured.
    event ConfigureMoneyPool(
        FountainV1MoneyPool indexed mp,
        address indexed owner,
        uint256 indexed target,
        uint256 duration,
        address want
    );

    /// This event should trigger when an MoneyPool is sustained.
    event SustainMoneyPool(
        FountainV1MoneyPool indexed mp,
        address indexed owner,
        address indexed sustainer,
        uint256 amount
    );

    /// This event should trigger when redistributions are collected.
    event CollectRedistributions(address indexed sustainer, uint256 amount);

    /// This event should trigger when sustainments are collected.
    event CollectSustainements(address indexed owner, uint256 amount);

    // --- External getters --- //

    // function getSustainmentTrackerAmount(address owner, address by)
    //     external
    //     view
    //     returns (uint256 amount)
    // {
    //     require(
    //         latestMoneyPools[owner] != MoneyPool(0),
    //         "No MoneyPool owned by this address"
    //     );
    //     return latestMoneyPools[owner].getSustainmentTracker(by);
    // }

    // function getRedistributionTrackerAmount(address owner, address sustainer)
    //     private
    //     view
    //     returns (uint256 amount)
    // {
    //     require(
    //         latestMoneyPools[owner] != MoneyPool(0),
    //         "No MoneyPool owned by this address"
    //     );
    //     return latestMoneyPools[owner].getRedistributionTracker(sustainer);
    // }

    /// @dev The MoneyPool that's next up for an owner.
    /// @param owner The owner of the money pool being looked for.
    /// @return mp The address of the pending MoneyPool.
    function getPendingMoneyPool(address owner)
        external
        view
        returns (FountainV1MoneyPool mp)
    {
        FountainV1MoneyPool _mp = latestMoneyPools[owner];
        if (_mp == FountainV1MoneyPool(0)) return FountainV1MoneyPool(0);
        // There is no pending moneyPool if the latest MoneyPool is not pending
        if (_mp.state() == FountainV1MoneyPool.State.Pending) return mp;
        return FountainV1MoneyPool(0);
    }

    /// @dev The currently active MoneyPool for an owner.
    /// @param owner The owner of the money pool being looked for.
    /// @return mp The active MoneyPool.
    function getActiveMoneyPool(address owner)
        external
        view
        returns (FountainV1MoneyPool mp)
    {
        FountainV1MoneyPool _mp = latestMoneyPools[owner];
        if (_mp == FountainV1MoneyPool(0)) return FountainV1MoneyPool(0);

        // An Active moneyPool must be either the latest moneyPool or the
        // moneyPool immediately before it.
        if (_mp.state() == FountainV1MoneyPool.State.Active) return _mp;

        // Reassign the MoneyPool to be the previous address.
        _mp = _mp.previous();

        //If neither the current or the previous MoneyPool is active, then MoneyPool is active.
        if (
            _mp != FountainV1MoneyPool(0) &&
            _mp.state() == FountainV1MoneyPool.State.Active
        ) return _mp;

        return FountainV1MoneyPool(0);
    }

    constructor(address dai) public {
        DAI = dai;
        moneyPoolCount = 0;
    }

    // --- external transactions --- //

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
        require(
            target > 0,
            "Fountain::configureMoneyPool: A MoneyPool target must be a positive number"
        );

        FountainV1MoneyPool _mp = _moneyPoolToConfigure(msg.sender);
        _mp.configure(target, duration, want, now);

        if (_mp.previous() == FountainV1MoneyPool(0))
            emit InitializeMoneyPool(_mp, msg.sender);

        emit ConfigureMoneyPool(_mp, msg.sender, target, duration, want);

        return true;
    }

    /// @notice Contribute a specified amount to the sustainability of the specified address's active MoneyPool.
    /// @notice If the amount results in surplus, redistribute the surplus proportionally to sustainers of the MoneyPool.
    /// @param owner The owner of the MoneyPool to sustain.
    /// @param amount Amount of sustainment.
    /// @return success If the sustainment was successful.
    function sustain(address owner, uint256 amount)
        external
        returns (bool success)
    {
        require(
            amount > 0,
            "Fountain::sustain: The sustainment amount should be positive"
        );

        FountainV1MoneyPool _mp = _moneyPoolToSustain(owner);

        require(
            _mp != FountainV1MoneyPool(0),
            "Fountain::sustain: MoneyPool owner not found"
        );

        bool wasInactive = _mp.state() != FountainV1MoneyPool.State.Active;

        // The amount that should be reserved for the sustainability of the MoneyPool.
        // If the MoneyPool is already sustainable, set to 0.
        // If the MoneyPool is not yet sustainable even with the amount, set to the amount.
        // Otherwise set to the portion of the amount it'll take for sustainability to be reached
        uint256 sustainabilityAmount;
        if (
            _mp.getCurrentSustainment().add(amount) <=
            _mp.sustainabilityTarget()
        ) {
            sustainabilityAmount = amount;
        } else if (_mp.getCurrentSustainment() >= _mp.sustainabilityTarget()) {
            sustainabilityAmount = 0;
        } else {
            sustainabilityAmount = _mp.sustainabilityTarget().sub(
                _mp.getCurrentSustainment()
            );
        }

        // Move the full sustainment amount to this address.
        require(
            IERC20(_mp.want()).transferFrom(msg.sender, address(this), amount),
            "ERC20 transfer failed"
        );

        // Increment the funds that can be collected from sustainability.
        sustainabilityPool[owner] = sustainabilityPool[owner].add(
            sustainabilityAmount
        );

        // Add the sustainments to the MoneyPool.
        _mp.addSustainment(msg.sender, amount);

        // Add this address to the sustainer's list of sustained addresses
        sustainedOwnersBySustainer[msg.sender].push(owner);

        // Redistribution amounts may have changed for the current MoneyPool.
        _updateTrackedRedistribution(_mp);

        // Emit events.
        emit SustainMoneyPool(_mp, _mp.owner(), msg.sender, amount);

        if (wasInactive)
            // Emit an event since since is the first sustainment being made towards this MoneyPool.
            // TODO: will emitting this event make the first sustainment of a MP significantly more costly in gas?
            emit ActivateMoneyPool(
                _mp,
                _mp.owner(),
                _mp.sustainabilityTarget(),
                _mp.duration(),
                _mp.want()
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
        address[] storage sustainedAddresses =
            sustainedOwnersBySustainer[msg.sender];
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

    // --- private --- //

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
    /// @return mp The resulting mp.
    function _moneyPoolToConfigure(address owner)
        private
        returns (FountainV1MoneyPool mp)
    {
        // Check if there is an active moneyPool
        FountainV1MoneyPool _mp = this.getActiveMoneyPool(owner);

        // Allow active moneyPool to be updated if it has no sustainments
        if (_mp != FountainV1MoneyPool(0) && _mp.getCurrentSustainment() == 0)
            return _mp;

        // Cannot update active moneyPool, check if there is a pending moneyPool
        _mp = this.getPendingMoneyPool(owner);
        if (_mp != FountainV1MoneyPool(0)) return _mp;

        // No pending moneyPool found, clone the latest moneyPool
        _mp = _getLatestMoneyPool(owner);

        if (_mp != FountainV1MoneyPool(0))
            return _createMoneyPoolFromMoneyPool(_mp, now);

        _mp = _initMoneyPool(owner);

        return _mp;
    }

    /// @dev Only active MoneyPools can be sustained.
    /// @param owner The address who owns the MoneyPool to look for.
    /// @return mp The resulting MoneyPool.
    function _moneyPoolToSustain(address owner)
        private
        returns (FountainV1MoneyPool mp)
    {
        // Check if there is an active moneyPool
        FountainV1MoneyPool _mp = this.getActiveMoneyPool(owner);
        if (_mp != FountainV1MoneyPool(0)) return _mp;

        // No active moneyPool found, check if there is a pending moneyPool
        _mp = this.getPendingMoneyPool(owner);
        if (_mp != FountainV1MoneyPool(0)) return _mp;

        // No pending moneyPool found, clone the latest moneyPool
        _mp = _getLatestMoneyPool(owner);

        require(
            _mp != FountainV1MoneyPool(0),
            "Fountain::moneyPoolIdToSustain: MoneyPool not found"
        );

        // Use a start date that's a multiple of the duration.
        // This creates the effect that there have been scheduled MoneyPools ever since the `latest`, even if `latest` is a long time in the past.
        uint256 start =
            _determineModuloStart(
                _mp.start().add(_mp.duration()),
                _mp.duration()
            );

        return _createMoneyPoolFromMoneyPool(_mp, start);
    }

    /// @dev Proportionally allocate the specified amount to the contributors of the specified MoneyPool,
    /// @dev meaning each sustainer will receive a portion of the specified amount equivalent to the portion of the total
    /// @dev amount contributed to the sustainment of the MoneyPool that they are responsible for.
    /// @param mp The MoneyPool to update.
    function _updateTrackedRedistribution(FountainV1MoneyPool mp) private {
        // Return if there's no surplus.
        if (mp.sustainabilityTarget() >= mp.getCurrentSustainment()) return;

        uint256 _surplus =
            mp.getCurrentSustainment().sub(mp.sustainabilityTarget());

        // For each sustainer, calculate their share of the sustainment and
        // allocate a proportional share of the surplus, overwriting any previous value.
        for (uint256 i = 0; i < mp.getSustainerCount(); i++) {
            address sustainer = mp.sustainers(i);

            uint256 _currentSustainmentProportion =
                mp.getSustainmentTrackerAmount(sustainer).div(
                    mp.getCurrentSustainment()
                );

            uint256 _sustainerSurplusShare =
                _surplus.mul(_currentSustainmentProportion);

            //Store the updated redistribution in the MoneyPool.
            mp.setRedistributionTracker(sustainer, _sustainerSurplusShare);
        }
    }

    /// @dev Take any tracked redistribution in the given moneyPool and
    /// @dev add them to the redistribution pool.
    /// @param owner The owner of the MoneyPool to redistribute.
    function _redistributeMoneyPool(address owner) private {
        FountainV1MoneyPool _mp = latestMoneyPools[owner];
        require(
            _mp != FountainV1MoneyPool(0),
            "Fountain::redistributeMoneyPool: MoneyPool not found"
        );

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
        while (_mp != FountainV1MoneyPool(0) && !_mp.redistributed(sustainer)) {
            if (_mp.state() == FountainV1MoneyPool.State.Redistributing) {
                redistributionPool[sustainer] = redistributionPool[sustainer]
                    .add(_mp.getRedistributionTrackerAmount(sustainer));
                _mp.markAsRedistributed(sustainer);
            }
            _mp = _mp.previous();
        }
    }

    /// @dev Returns a copy of the given MoneyPool with reset sustainments.
    /// @param baseMp The MoneyPool to base the new MoneyPool on.
    /// @param start The start date to use for the new MoneyPool.
    /// @return newMp The new MoneyPool.
    function _createMoneyPoolFromMoneyPool(
        FountainV1MoneyPool baseMp,
        uint256 start
    ) private returns (FountainV1MoneyPool newMp) {
        require(
            baseMp != FountainV1MoneyPool(0),
            "Fountain::createMoneyPoolFromId: Invalid moneyPool"
        );

        FountainV1MoneyPool _newMp = _initMoneyPool(baseMp.owner());

        _newMp.configure(
            baseMp.sustainabilityTarget(),
            baseMp.duration(),
            baseMp.want(),
            start
        );

        latestMoneyPools[baseMp.owner()] = _newMp;

        return _newMp;
    }

    /// @notice Initializes a MoneyPool to be sustained for the sending address.
    /// @param owner The owner of the money pool being initialized.
    /// @return mp The initialized MoneyPool.
    function _initMoneyPool(address owner)
        private
        returns (FountainV1MoneyPool mp)
    {
        moneyPoolCount++;
        FountainV1MoneyPool _mp =
            new FountainV1MoneyPool(owner, latestMoneyPools[owner]);
        moneyPools[moneyPoolCount] = _mp;
        latestMoneyPools[owner] = _mp;
        return _mp;
    }

    /// @dev The MoneyPool that is the latest configured MoneyPool for the owner.
    /// @param owner The owner of the money pool being looked for.
    /// @return mp The latest MoneyPool.
    function _getLatestMoneyPool(address owner)
        private
        view
        returns (FountainV1MoneyPool mp)
    {
        return latestMoneyPools[owner];
    }

    /// @dev Returns the date that is the nearest multiple of duration from oldEnd.
    /// @return start The date.
    function _determineModuloStart(uint256 oldEnd, uint256 duration)
        private
        view
        returns (uint256 start)
    {
        // Use the old end if the current time is still within the duration.
        if (oldEnd.add(duration) > now) return oldEnd;
        // Otherwise, use the closest multiple of the duration from the old end.
        uint256 _distanceToStart = (now.sub(oldEnd)).mod(duration);
        return now.sub(_distanceToStart);
    }
}
