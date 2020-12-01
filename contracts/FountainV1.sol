// SPDX-License-Identifier: MIT
// TODO: What license do we release under?
pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

/**

@title Fountain

Create a MoneyPool (MP) that'll be used to sustain your project, and specify what its sustainability target is.
Maybe your project is providing a service or public good, maybe it's being a YouTuber, engineer, or artist -- or anything else. Anyone with your address can help sustain your project, and once you're sustainable any additional contributions are redistributed back your sustainers.

Each MoneyPool is like a tier of the fountain, and the predefined cost to pursue the project is like the bounds of that tier's pool.

An address can only be associated with one active MoneyPool at a time, as well as a mutable one queued up for when the active MoneyPool expires. If a MoneyPool expires without one queued, the current one will be cloned and sustainments will be allocated to it. It's impossible for a MoneyPool's sustainability or duration to be changed once there has been a sustainment made to it. Any attempts to do so will just create/update the message sender's queued MP.

You can withdraw funds of yours from the sustainers pool (where MoneyPool surplus is distributed) or the sustainability pool (where MoneyPool sustainments are kept) at anytime.

Future versions will introduce MoneyPool dependencies so that your project's surplus can get redistributed to the MP of projects it is composed of before reaching sustainers. We also think it may be best to create a governance token WATER and route ~7% of ecosystem surplus to token holders, ~3% to contributors (which can be run through Fountain itself), and the rest to sustainers.

The basin of the Fountain is always the sustainers of projects.
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
        address who;
        // The token that this MoneyPool can be funded with. Currently only DAI is supported.
        IERC20 want;
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
    mapping(address => uint256) redistributionPool;

    // The funds that have accumulated to sustain each address's MoneyPools.
    mapping(address => uint256) sustainabilityPool;

    // The total number of MoneyPools created, which is used for issuing MoneyPool IDs.
    // MoneyPools should have an id > 0, 0 should not be a moneyPoolId.
    uint256 public moneyPoolCount;

    // The contract currently only supports sustainments in DAI.
    IERC20 public DAI;

    event MoneyPoolCreated(
        uint256 indexed id,
        address indexed by,
        uint256 sustainabilityTarget,
        uint256 duration,
        IERC20 want
    );

    event MoneyPoolUpdated(
        uint256 indexed id,
        address indexed by,
        uint256 sustainabilityTarget,
        uint256 duration,
        IERC20 want
    );

    event MoneyPoolSustained(
        uint256 indexed id,
        address indexed sustainer,
        uint256 amount
    );

    event Withdrawn(address indexed by, Pool indexed from, uint256 amount);

    constructor() public {
        DAI = IERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));
        moneyPoolCount = 0;
    }

    /// @notice Creates a MoneyPool to be sustained for the sending address.
    /// @param t The sustainability target for the MoneyPool, in DAI.
    /// @param d The duration of the MoneyPool, which starts once this is created.
    function createMoneyPool(uint256 t, uint256 d) external {
        require(
            latestMoneyPoolIds[msg.sender] == 0,
            "Fountain::createMoneyPool: Address already has a MoneyPool, call `update` instead"
        );
        require(
            d >= 1,
            "Fountain::createMoneyPool: A MoneyPool must be at least one day long"
        );

        moneyPoolCount++;
        // Must create structs that have mappings using this approach to avoid
        // the RHS creating a memory-struct that contains a mapping.
        // See https://ethereum.stackexchange.com/a/72310
        MoneyPool storage newMoneyPool = moneyPools[moneyPoolCount];
        newMoneyPool.who = msg.sender;
        newMoneyPool.sustainabilityTarget = t;
        newMoneyPool.currentSustainment = 0;
        newMoneyPool.start = now;
        newMoneyPool.duration = d;
        newMoneyPool.want = DAI;
        newMoneyPool.exists = true;
        newMoneyPool.previousMoneyPoolId = 0;

        latestMoneyPoolIds[msg.sender] = moneyPoolCount;

        emit MoneyPoolCreated(moneyPoolCount, msg.sender, t, d, DAI);
    }

    /// @notice Contribute a specified amount to the sustainability of the specified address's active MoneyPool.
    /// @notice If the amount results in surplus, redistribute the surplus proportionally to sustainers of the MoneyPool.
    /// @param w Address to sustain.
    /// @param a Amount of sustainment.
    function sustain(address w, uint256 a) external payable {
        require(
            a > 0,
            "Fountain::sustain: The sustainment amount should be positive"
        );

        // TODO: Should a MoneyPool creator be able to sustain their own MoneyPool?

        uint256 moneyPoolId = moneyPoolIdToSustain(w);
        MoneyPool storage currentMoneyPool = moneyPools[moneyPoolId];

        require(
            currentMoneyPool.exists,
            "Fountain::sustain: MoneyPool not found"
        );

        // The amount that should be reserved for the sustainability of the MoneyPool.
        // If the MoneyPool is already sustainable, set to 0.
        // If the MoneyPool is not yet sustainable even with the amount, set to the amount.
        // Otherwise set to the portion of the amount it'll take for sustainability to be reached
        uint256 sustainabilityAmount = currentMoneyPool.currentSustainment.add(
            a
        ) <= currentMoneyPool.sustainabilityTarget
            ? a
            : currentMoneyPool.currentSustainment >=
                currentMoneyPool.sustainabilityTarget
            ? 0
            : currentMoneyPool.sustainabilityTarget.sub(
                currentMoneyPool.currentSustainment
            );

        // // TODO: Is this logic any clearer than above?
        // uint256 sustainabilityAmount;
        // if (
        //     currentMoneyPool.currentSustainment.add(a) <=
        //     currentMoneyPool.sustainabilityTarget
        // ) {
        //     sustainabilityAmount = a;
        // } else if (
        //     currentMoneyPool.currentSustainment >=
        //     currentMoneyPool.sustainabilityTarget
        // ) {
        //     sustainabilityAmount = 0;
        // } else {
        //     sustainabilityAmount = currentMoneyPool.sustainabilityTarget.sub(
        //         currentMoneyPool.currentSustainment
        //     );
        // }

        // Save if the message sender is contributing to this MoneyPool for the first time.
        bool isNewSustainer = currentMoneyPool.sustainmentTracker[msg.sender] ==
            0;

        // TODO: Not working.`Returned error: VM Exception while processing transaction: revert`
        //https://ethereum.stackexchange.com/questions/60028/testing-transfer-of-tokens-with-truffle
        // Move the full sustainment amount to this address.
        // DAI.transferFrom(msg.sender, address(this), a);

        // Increment the funds that can withdrawn for sustainability.
        sustainabilityPool[w] = sustainabilityPool[w].add(sustainabilityAmount);

        // Increment the sustainments to the MoneyPool made by the message sender.
        currentMoneyPool.sustainmentTracker[msg.sender] = currentMoneyPool
            .sustainmentTracker[msg.sender]
            .add(a);

        // Increment the total amount contributed to the sustainment of the MoneyPool.
        currentMoneyPool.currentSustainment = currentMoneyPool
            .currentSustainment
            .add(a);

        // Add the message sender as a sustainer of the MoneyPool if this is the first sustainment it's making to it.
        if (isNewSustainer) currentMoneyPool.sustainers.push(msg.sender);

        // Add this address to the sustainer's list of sustained addresses
        sustainedAddressesBySustainer[msg.sender].push(w);

        // Redistribution amounts may have changed for the current MoneyPool.
        updateTrackedRedistribution(currentMoneyPool);

        // Emit events.
        emit MoneyPoolSustained(moneyPoolId, msg.sender, a);
    }

    /// @notice A message sender can withdraw what's been redistributed to it by a MoneyPool once it's expired.
    /// @param a The amount to withdraw.
    function withdrawRedistributions(uint256 a) external payable {
        // Iterate over all of sender's sustained addresses to make sure
        // redistribution has completed for all redistributable MoneyPools
        address[] storage sustainedAddresses = sustainedAddressesBySustainer[msg
            .sender];
        for (uint256 i = 0; i < sustainedAddresses.length; i++) {
            redistributeMoneyPool(sustainedAddresses[i]);
        }
        performWithdrawRedistributions(a);
    }

    function withdrawRedistributions(uint256 a, address sustained)
        external
        payable
    {
        redistributeMoneyPool(sustained);
        performWithdrawRedistributions(a);
    }

    function withdrawRedistributions(uint256 a, address[] calldata sustained)
        external
        payable
    {
        for (uint256 i = 0; i < sustained.length; i++) {
            redistributeMoneyPool(sustained[i]);
        }
        performWithdrawRedistributions(a);
    }

    function performWithdrawRedistributions(uint256 a) private {
        require(
            redistributionPool[msg.sender] >= a,
            "This address doesn't have enough to withdraw this much."
        );

        DAI.safeTransferFrom(address(this), msg.sender, a);

        redistributionPool[msg.sender] = redistributionPool[msg.sender].sub(a);

        emit Withdrawn(msg.sender, Pool.SUSTAINABILITY, a);
    }

    /// @notice A message sender can withdrawl funds that have been used to sustain it's MoneyPools.
    /// @param a The amount to withdraw.
    function withdrawSustainments(uint256 a) external {
        require(
            sustainabilityPool[msg.sender] >= a,
            "This address doesn't have enough to withdraw this much."
        );

        DAI.safeTransferFrom(address(this), msg.sender, a);

        sustainabilityPool[msg.sender] = sustainabilityPool[msg.sender].sub(a);

        emit Withdrawn(msg.sender, Pool.SUSTAINABILITY, a);
    }

    /// @notice Updates the sustainability target and duration of the sender's current MoneyPool if it hasn't yet received sustainments, or
    /// @notice sets the properties of the MoneyPool that will take effect once the current MoneyPool expires.
    /// @param t The sustainability target to set.
    /// @param d The duration to set.
    function updateMoneyPool(
        uint256 t,
        uint256 d // address _want
    ) external {
        require(
            latestMoneyPoolIds[msg.sender] > 0,
            "You don't yet have a MoneyPool."
        );
        uint256 moneyPoolId = moneyPoolIdToUpdate(msg.sender);
        MoneyPool storage moneyPool = moneyPools[moneyPoolId];
        if (t > 0) moneyPool.sustainabilityTarget = t;
        if (d > 0) moneyPool.duration = d;
        moneyPool.want = DAI; //IERC20(_want);

        emit MoneyPoolUpdated(
            moneyPoolId,
            moneyPool.who,
            moneyPool.sustainabilityTarget,
            moneyPool.duration,
            DAI
        );
    }

    // --- External getters for testing --- //
    // TODO: Is there a better approach than exposing getters

    function getSustainabilityPool(address w) external view returns (uint256) {
        return sustainabilityPool[w];
    }

    function getRedistributionPool(address w) external view returns (uint256) {
        return redistributionPool[w];
    }

    function getSustainedAddressCount(address w)
        external
        view
        returns (uint256)
    {
        return sustainedAddressesBySustainer[w].length;
    }

    function getSustainabilityTarget(address w)
        external
        view
        returns (uint256)
    {
        require(
            latestMoneyPoolIds[w] > 0,
            "No MoneyPool found at this address"
        );
        require(
            moneyPools[latestMoneyPoolIds[w]].exists,
            "No MoneyPool found at this address"
        );
        return moneyPools[latestMoneyPoolIds[w]].sustainabilityTarget;
    }

    function getDuration(address w) external view returns (uint256) {
        require(
            latestMoneyPoolIds[w] > 0,
            "No MoneyPool found at this address"
        );
        require(
            moneyPools[latestMoneyPoolIds[w]].exists,
            "No MoneyPool found at this address"
        );
        return moneyPools[latestMoneyPoolIds[w]].duration;
    }

    function getCurrentSustainment(address w) external view returns (uint256) {
        require(
            latestMoneyPoolIds[w] > 0,
            "No MoneyPool found at this address"
        );
        require(
            moneyPools[latestMoneyPoolIds[w]].exists,
            "No MoneyPool found at this address"
        );
        return moneyPools[latestMoneyPoolIds[w]].currentSustainment;
    }

    function getSustainerCount(address w) external view returns (uint256) {
        require(
            latestMoneyPoolIds[w] > 0,
            "No MoneyPool found at this address"
        );
        require(
            moneyPools[latestMoneyPoolIds[w]].exists,
            "No MoneyPool found at this address"
        );
        return moneyPools[latestMoneyPoolIds[w]].sustainers.length;
    }

    function getSustainmentTrackerAmount(address who, address by)
        external
        view
        returns (uint256)
    {
        require(
            latestMoneyPoolIds[who] > 0,
            "No MoneyPool found at this address"
        );
        require(
            moneyPools[latestMoneyPoolIds[who]].exists,
            "No MoneyPool found at this address"
        );
        return moneyPools[latestMoneyPoolIds[who]].sustainmentTracker[by];
    }

    function getRedistributionTrackerAmount(address who, address by)
        external
        view
        returns (uint256)
    {
        require(
            latestMoneyPoolIds[who] > 0,
            "No MoneyPool found at this address"
        );
        require(
            moneyPools[latestMoneyPoolIds[who]].exists,
            "No MoneyPool found at this address"
        );
        return moneyPools[latestMoneyPoolIds[who]].redistributionTracker[by];
    }

    // --- private --- //

    /// @dev The sustainability of a MoneyPool cannot be updated if there have been sustainments made to it.
    /// @param w The address to find a MoneyPool for.
    function moneyPoolIdToUpdate(address w) private returns (uint256) {
        // Check if there is an active moneyPool
        uint256 moneyPoolId = getActiveMoneyPoolId(w);
        if (
            moneyPoolId != 0 && moneyPools[moneyPoolId].currentSustainment == 0
        ) {
            // Allow active moneyPool to be updated if it has no sustainments
            return moneyPoolId;
        }

        // Cannot update active moneyPool, check if there is a pending moneyPool
        moneyPoolId = getPendingMoneyPoolId(w);
        if (moneyPoolId != 0) {
            return moneyPoolId;
        }

        // No pending moneyPool found, clone the latest moneyPool
        moneyPoolId = getLatestMoneyPoolId(w);
        MoneyPool storage moneyPool = createMoneyPoolFromId(moneyPoolId);
        moneyPools[moneyPoolId] = moneyPool;
        latestMoneyPoolIds[w] = moneyPoolId;
        return moneyPoolId;
    }

    /// @dev Only active MoneyPools can be sustained.
    /// @param w The address to find a MoneyPool for.
    function moneyPoolIdToSustain(address w) private returns (uint256) {
        // Check if there is an active moneyPool
        uint256 moneyPoolId = getActiveMoneyPoolId(w);
        if (moneyPoolId != 0) {
            return moneyPoolId;
        }

        // No active moneyPool found, check if there is a pending moneyPool
        moneyPoolId = getPendingMoneyPoolId(w);
        if (moneyPoolId != 0) {
            return moneyPoolId;
        }

        // No pending moneyPool found, clone the latest moneyPool
        moneyPoolId = getLatestMoneyPoolId(w);
        MoneyPool storage moneyPool = createMoneyPoolFromId(moneyPoolId);
        moneyPools[moneyPoolId] = moneyPool;
        latestMoneyPoolIds[w] = moneyPoolId;

        return moneyPoolId;
    }

    /// @dev Proportionally allocate the specified amount to the contributors of the specified MoneyPool,
    /// @dev meaning each sustainer will receive a portion of the specified amount equivalent to the portion of the total
    /// @dev amount contributed to the sustainment of the MoneyPool that they are responsible for.
    /// @param p The MoneyPool to update.
    function updateTrackedRedistribution(MoneyPool storage p) private {
        // Return if there's no surplus.
        if (p.sustainabilityTarget >= p.currentSustainment) return;

        uint256 surplus = p.currentSustainment.sub(p.sustainabilityTarget);

        // For each sustainer, calculate their share of the sustainment and
        // allocate a proportional share of the surplus, overwriting any previous value.
        for (uint256 i = 0; i < p.sustainers.length; i++) {
            address sustainer = p.sustainers[i];

            uint256 currentSustainmentProportion = p
                .sustainmentTracker[sustainer]
                .div(p.currentSustainment);

            uint256 sustainerSurplusShare = surplus.mul(
                currentSustainmentProportion
            );

            //Store the updated redistribution in the MoneyPool.
            p.redistributionTracker[sustainer] = sustainerSurplusShare;
        }
    }

    /// @dev Check to see if the given MoneyPool has started.
    /// @param p The MoneyPool to check.
    function isMoneyPoolStarted(MoneyPool storage p)
        private
        view
        returns (bool)
    {
        return now >= p.start;
    }

    /// @dev Check to see if the given MoneyPool has expired.
    /// @param p The MoneyPool to check.
    function isMoneyPoolExpired(MoneyPool storage p)
        private
        view
        returns (bool)
    {
        return now > p.start.add(p.duration.mul(1 days));
    }

    /// @dev Take any tracked redistribution in the given moneyPool and
    /// @dev add them to the redistribution pool.
    /// @param moneyPoolAddress The MoneyPool address to redistribute.
    function redistributeMoneyPool(address moneyPoolAddress) private {
        uint256 moneyPoolId = latestMoneyPoolIds[moneyPoolAddress];
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
            if (state(moneyPoolId) == MoneyPoolState.Redistributing) {
                redistributionPool[sustainer] = redistributionPool[sustainer]
                    .add(moneyPool.redistributionTracker[sustainer]);
                moneyPool.redistributed[sustainer] = true;
            }
            moneyPoolId = moneyPool.previousMoneyPoolId;
            moneyPool = moneyPools[moneyPoolId];
        }
    }

    /// @dev Returns a copy of the given MoneyPool with reset sustainments, and
    /// @dev that starts when the given MoneyPool expired.
    function createMoneyPoolFromId(uint256 moneyPoolId)
        private
        returns (MoneyPool storage)
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
        moneyPool.who = currentMoneyPool.who;
        moneyPool.sustainabilityTarget = currentMoneyPool.sustainabilityTarget;
        moneyPool.currentSustainment = 0;
        moneyPool.start = currentMoneyPool.start.add(
            currentMoneyPool.duration.mul(1 days)
        );
        moneyPool.duration = currentMoneyPool.duration;
        moneyPool.want = currentMoneyPool.want;
        moneyPool.exists = true;
        moneyPool.previousMoneyPoolId = moneyPoolCount;

        emit MoneyPoolUpdated(
            moneyPoolCount,
            moneyPool.who,
            moneyPool.sustainabilityTarget,
            moneyPool.duration,
            DAI
        );

        return moneyPool;
    }

    function state(uint256 moneyPoolId) private view returns (MoneyPoolState) {
        require(
            moneyPoolCount >= moneyPoolId && moneyPoolId > 0,
            "Fountain::state: Invalid moneyPoolId"
        );
        MoneyPool storage moneyPool = moneyPools[moneyPoolId];
        require(moneyPool.exists, "Fountain::state: Invalid MoneyPool");

        if (isMoneyPoolExpired(moneyPool)) {
            return MoneyPoolState.Redistributing;
        }

        if (isMoneyPoolStarted(moneyPool) && !isMoneyPoolExpired(moneyPool)) {
            return MoneyPoolState.Active;
        }

        return MoneyPoolState.Pending;
    }

    function getLatestMoneyPoolId(address moneyPoolAddress)
        private
        view
        returns (uint256)
    {
        uint256 moneyPoolId = latestMoneyPoolIds[moneyPoolAddress];
        require(
            moneyPoolId > 0,
            "Fountain::getLatestMoneyPoolId: MoneyPool not found"
        );
        return moneyPoolId;
    }

    function getPendingMoneyPoolId(address moneyPoolAddress)
        private
        view
        returns (uint256)
    {
        uint256 moneyPoolId = latestMoneyPoolIds[moneyPoolAddress];
        require(
            moneyPoolId > 0,
            "Fountain::getPendingMoneyPoolId: MoneyPool not found"
        );
        if (state(moneyPoolId) != MoneyPoolState.Pending) {
            // There is no pending moneyPool if the latest MoneyPool is not pending
            return 0;
        }
        return moneyPoolId;
    }

    function getActiveMoneyPoolId(address moneyPoolAddress)
        private
        view
        returns (uint256)
    {
        uint256 moneyPoolId = latestMoneyPoolIds[moneyPoolAddress];
        require(
            moneyPoolId > 0,
            "Fountain::getActiveMoneyPoolId: MoneyPool not found"
        );
        // An Active moneyPool must be either the latest moneyPool or the
        // moneyPool immediately before it.
        if (state(moneyPoolId) == MoneyPoolState.Active) {
            return moneyPoolId;
        }
        MoneyPool storage moneyPool = moneyPools[moneyPoolId];
        require(
            moneyPool.exists,
            "Fountain::getActiveMoneyPoolId: Invalid MoneyPool"
        );
        moneyPoolId = moneyPool.previousMoneyPoolId;
        if (moneyPoolId > 0 && state(moneyPoolId) == MoneyPoolState.Active) {
            return moneyPoolId;
        }
        return 0;
    }

    // // Not yet used
    // function calculateFee(uint256 _amount, uint8 _basisPoints)
    //     private
    //     pure
    //     returns (uint256)
    // {
    //     require((_amount.div(10000)).mul(10000) == _amount, "Amount too small");
    //     return (_amount.mul(_basisPoints)).div(1000);
    // }
}
