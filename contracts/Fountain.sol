pragma solidity >=0.4.25 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

/**

 @title Fountain

 Create a Purpose and say how much it'll cost to persue that purpose.
 Maybe your Purpose is providing a service or public good, maybe it's being a YouTuber, engineer, or artist -- or anything else.
 Anyone with your address can help sustain your Purpose, and
 once you're sustainable any additional contributions are redistributed back your sustainers and those you depend on.

 Each Purpose is like a tier of the fountain, and the predefined cost to pursue the purpose is like the bounds of that tier's pool.

 Your Purpose could be personal, or it could be managed by an address controlled by a community or business.
 Either way, an address can only be associated with one active Purpose at a time, and one queued up for when the active one expires.

 If a Purpose expires without one queued, the current one will be cloned and sustainments will be allocated to it.

 To avoid abuse, it's impossible for a Purpose's sustainability or duration to be changed once there has been a sustainment made to it.
 Any attempts to do so will just create/update the message sender's queued purpose.

 You can withdraw funds of yours from the sustainers pool (where surplus is distributed) or the sustainability pool (where sustainments are kept) at anytime.

*/
contract Fountain {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// @notice Possible states that a Purpose may be in
    // immutable once the Purpose receives some sustainment.
    // entirely mutable until they become active.
    enum PurposeState {Pending, Active, Redistributing}

    // The Purpose structure represents a purpose stewarded by an address, and accounts for which addresses have contributed to it.
    struct Purpose {
        // A unique ID for this purpose.
        uint256 id;
        // The address who defined this Purpose and who has access to its sustainments.
        address who;
        // The token that this Purpose can be funded with. Currently only DAI is supported.
        IERC20 want;
        // The amount that represents sustainability for this purpose.
        uint256 sustainabilityTarget;
        // The running amount that's been contributed to sustaining this purpose.
        uint256 currentSustainment;
        // The time when this Purpose will become active.
        uint256 start;
        // The number of days until this Purpose's redistribution is added to the redistributionPool.
        uint256 duration;
        // Helper to verify this Purpose exists.
        bool exists;
        // ID of the previous purpose
        uint256 previousPurposeId;
        // Indicates if surplus funds have been redistributed
        bool redistributed;
        // The addresses who have helped to sustain this purpose.
        // FIXME: Using arrays appears to be bad practice and can be expensive
        address[] sustainers;
        // The amount each address has contributed to the sustaining of this purpose.
        mapping(address => uint256) sustainmentTracker;
        // The amount that will be redistributed to each address as a
        // consequence of abundant sustainment of this Purpose once it resolves.
        mapping(address => uint256) redistributionTracker;
    }

    enum Pool {REDISTRIBUTION, SUSTAINABILITY}

    /// @notice The official record of all Purposes ever created
    mapping(uint256 => Purpose) public purposes;

    /// @notice The latest purpose for each owner
    mapping(address => uint256) public latestPurposeIds;

    /// @notice List of addresses sustained by each sustainer
    mapping(address => address[]) sustainedAddressesBySustainer;

    // TODO: Storing and iterating arrays in state is not going to work
    // see https://ethereum.stackexchange.com/a/27535
    // Instead redistribution status is checked and redistribution takes place
    // if needed each time a purpose is interacted with (sustain, updatePurpose,
    // withdrawFromSustainabilityPool)
    // // The purpose ids which have not redistributed surplus funds yet.
    // uint256[] lockedPurposeIds;

    // The amount that has been redistributed to each address as a consequence of surplus.
    mapping(address => uint256) redistributionPool;

    // The funds that have accumulated to sustain each address's Purposes.
    mapping(address => uint256) sustainabilityPool;

    // The total number of Purposes created, which is used for issuing Purpose IDs.
    // uint256 numPurposes;
    uint256 purposeCount;

    // The contract currently only supports sustainments in DAI.
    IERC20 public DAI;

    event PurposeCreated(
        uint256 indexed id,
        address indexed by,
        uint256 sustainabilityTarget,
        uint256 duration,
        IERC20 want
    );

    event PurposeSustained(
        uint256 indexed id,
        address indexed sustainer,
        uint256 amount
    );

    event Withdrawn(address indexed by, Pool indexed from, uint256 amount);

    constructor() public {
        DAI = IERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));
        purposeCount = 0;
    }

    /// @dev Creates a Purpose to be sustained for the sending address.
    /// @param t The sustainability target for the Purpose, in DAI.
    /// @param d The duration of the Purpose, which starts once this is created.
    function createPurpose(uint256 t, uint256 d) external {
        require(
            latestPurposeIds[msg.sender] == 0,
            "Fountain::createPurpose: Address already has a purpose, call `update` instead"
        );
        require(
            d >= 1,
            "Fountain::createPurpose: A purpose must be at least one day long"
        );

        purposeCount++;
        // Must create structs that have mappings using this approach to avoid
        // the RHS creating a memory-struct that contains a mapping.
        // See https://ethereum.stackexchange.com/a/72310
        Purpose storage newPurpose = purposes[purposeCount];
        newPurpose.id = purposeCount;
        newPurpose.who = msg.sender;
        newPurpose.sustainabilityTarget = t;
        newPurpose.currentSustainment = 0;
        newPurpose.start = now;
        newPurpose.duration = d;
        newPurpose.want = DAI;
        newPurpose.exists = true;
        newPurpose.previousPurposeId = 0;
        newPurpose.redistributed = false;

        latestPurposeIds[msg.sender] = newPurpose.id;

        emit PurposeCreated(newPurpose.id, msg.sender, t, d, DAI);
    }

    /// @dev Contribute a specified amount to the sustainability of the specified address's active Purpose.
    /// @dev If the amount results in surplus, redistribute the surplus proportionally to sustainers of the Purpose.
    /// @param w Address to sustain.
    /// @param a Amount of sustainment.
    function sustain(address w, uint256 a) external {
        require(
            a > 0,
            "Fountain::sustain: The sustainment amount should be positive"
        );

        uint256 purposeId = purposeIdToSustain(w);
        Purpose storage currentPurpose = purposes[purposeId];

        require(currentPurpose.exists, "Fountain::sustain: Purpose not found");

        // The amount that should be reserved for the sustainability of the Purpose.
        // If the Purpose is already sustainable, set to 0.
        // If the Purpose is not yet sustainable even with the amount, set to the amount.
        // Otherwise set to the portion of the amount it'll take for sustainability to be reached
        uint256 sustainabilityAmount = currentPurpose.currentSustainment.add(
            a
        ) <= currentPurpose.sustainabilityTarget
            ? a
            : currentPurpose.currentSustainment >=
                currentPurpose.sustainabilityTarget
            ? 0
            : currentPurpose.sustainabilityTarget.sub(
                currentPurpose.currentSustainment
            );

        // Save if the message sender is contributing to this Purpose for the first time.
        bool isNewSustainer = currentPurpose.sustainmentTracker[msg.sender] ==
            0;

        // Move the full sustainment amount to this address.
        DAI.transferFrom(msg.sender, address(this), a);

        // Increment the funds that can withdrawn for sustainability.
        sustainabilityPool[w] = sustainabilityPool[w].add(sustainabilityAmount);

        // Increment the sustainments to the Purpose made by the message sender.
        currentPurpose.sustainmentTracker[msg.sender] = currentPurpose
            .sustainmentTracker[msg.sender]
            .add(a);

        // Increment the total amount contributed to the sustainment of the Purpose.
        currentPurpose.currentSustainment = currentPurpose
            .currentSustainment
            .add(a);

        // Add the message sender as a sustainer of the Purpose if this is the first sustainment it's making to it.
        if (isNewSustainer) currentPurpose.sustainers.push(msg.sender);

        // Add this address to the sustainer's list of sustained addresses
        sustainedAddressesBySustainer[msg.sender].push(w);

        // Redistribution amounts may have changed for the current Purpose.
        updateTrackedRedistribution(currentPurpose);

        // Emit events.
        emit PurposeSustained(currentPurpose.id, msg.sender, a);
    }

    /// @dev A message sender can withdraw what's been redistributed to it by a Purpose once it's expired.
    /// @dev Note that funds may not have been fully redistributed and calling this does not redistribute. Calls to withdrawFromSustainabilityPool, sustain, and updatePurpose with trigger a redistribution only for the purpose they are called upon.
    /// @param a The amount to withdraw.
    function withdrawFromRedistributionPool(uint256 a) external {
        // Iterate over all of sender's sustained addresses to make sure
        // redistribution has completed for all redistributable purposes
        address[] storage sustainedAddresses = sustainedAddressesBySustainer[msg
            .sender];
        for (uint256 i = 0; i < sustainedAddresses.length; i++) {
            redistributePurpose(sustainedAddresses[i]);
        }

        require(
            redistributionPool[msg.sender] >= a,
            "This address doesn't have enough to withdraw this much."
        );

        DAI.safeTransferFrom(address(this), msg.sender, a);

        redistributionPool[msg.sender] = redistributionPool[msg.sender].sub(a);

        emit Withdrawn(msg.sender, Pool.SUSTAINABILITY, a);
    }

    /// @dev A message sender can withdrawl funds that have been used to sustain it's Purposes.
    /// @param a The amount to withdraw.
    function withdrawFromSustainabilityPool(uint256 a) external {
        require(
            sustainabilityPool[msg.sender] >= a,
            "This address doesn't have enough to withdraw this much."
        );

        DAI.safeTransferFrom(address(this), msg.sender, a);

        sustainabilityPool[msg.sender] = sustainabilityPool[msg.sender].sub(a);

        emit Withdrawn(msg.sender, Pool.SUSTAINABILITY, a);
    }

    /// @dev Updates the sustainability target and duration of the sender's current Purpose if it hasn't yet received sustainments, or
    /// @dev sets the properties of the Purpose that will take effect once the current Purpose expires.
    /// @param t The sustainability target to set.
    /// @param d The duration to set.
    function updatePurpose(
        uint256 t,
        uint256 d // address _want
    ) external {
        uint256 purposeId = purposeIdToUpdate(msg.sender);
        Purpose storage purpose = purposes[purposeId];
        if (t > 0) purpose.sustainabilityTarget = t;
        if (d > 0) purpose.duration = d;
        purpose.want = DAI; //IERC20(_want);
    }

    /// @dev The sustainability of a Purpose cannot be updated if there have been sustainments made to it.
    /// @param w The address to find a Purpose for.
    function purposeIdToUpdate(address w) private returns (uint256) {
        // Check if there is an active purpose
        uint256 purposeId = getActivePurposeId(w);
        if (purposeId != 0 && purposes[purposeId].currentSustainment == 0) {
            // Allow active purpose to be updated if it has no sustainments
            return purposeId;
        }

        // Cannot update active purpose, check if there is a pending purpose
        // TODO: Is it possible to have an active purpose that hasn't been
        // sustained as well as a pending purpose?
        purposeId = getPendingPurposeId(w);
        if (purposeId != 0) {
            return purposeId;
        }

        // No pending purpose found, clone the latest purpose
        purposeId = getLatestPurposeId(w);
        Purpose storage purpose = createPurposeFromId(purposeId);
        purposes[purpose.id] = purpose;
        latestPurposeIds[purpose.who] = purpose.id;
        return purpose.id;
    }

    /// @dev Only active or pending Purposes can be sustained. TODO Is this true?
    /// @param w The address to find a Purpose for.
    function purposeIdToSustain(address w) private returns (uint256) {
        // Check if there is an active purpose
        uint256 purposeId = getActivePurposeId(w);
        if (purposeId != 0) {
            return purposeId;
        }

        // No active purpose found, check if there is a pending purpose
        purposeId = getPendingPurposeId(w);
        if (purposeId != 0) {
            return purposeId;
        }

        // No pending purpose found, clone the latest purpose
        purposeId = getLatestPurposeId(w);
        Purpose storage purpose = createPurposeFromId(purposeId);
        purposes[purpose.id] = purpose;
        latestPurposeIds[purpose.who] = purpose.id;

        return purpose.id;
    }

    /// @dev Proportionally allocate the specified amount to the contributors of the specified Purpose,
    /// @dev meaning each sustainer will receive a portion of the specified amount equivalent to the portion of the total
    /// @dev amount contributed to the sustainment of the Purpose that they are responsible for.
    /// @param p The Purpose to update.
    function updateTrackedRedistribution(Purpose storage p) private {
        // Return if there's no surplus.
        if (p.sustainabilityTarget >= p.currentSustainment) return;

        uint256 surplus = p.sustainabilityTarget.sub(p.currentSustainment);

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

            //Store the updated redistribution in the Purpose.
            p.redistributionTracker[sustainer] = sustainerSurplusShare;
        }
    }

    // TODO Remove this, as it won't work.
    // /// @dev Check to see if there are any locked purposes that have expired.
    // /// @dev If so, unlock them by removing them from the lockedPurposes array.
    // function updateRedistributionPool() private {
    //     // TODO: Need to use an array in storage because it is not possible to resize memory arrays
    //     // Otherwise need to define the size of the array during initialization
    //     // Compiler error: Unable to deduce common type for array elements.
    //     // See: https://ethereum.stackexchange.com/questions/11533/how-to-initialize-an-empty-array-and-push-items-into-it
    //     Purpose[] memory updatedLockedPurposes = new Purpose[](
    //         lockedPurposes.length
    //     ); // TODO error on this line
    //     for (uint256 i = 0; i < lockedPurposes.length; i++) {
    //         Purpose storage lockedPurpose = lockedPurposes[i];
    //         if (isPurposeExpired(lockedPurpose)) unlockPurpose(lockedPurpose);
    //         else updatedLockedPurposes.push(lockedPurposes);
    //     }
    //     //TODO verify this way to manipulate array storage works.
    //     lockedPurposes = updatedLockedPurposes;
    // }

    /// @dev Check to see if the given Purpose has started.
    /// @param p The Purpose to check.
    function isPurposeStarted(Purpose storage p) private view returns (bool) {
        return now > p.start;
    }

    /// @dev Check to see if the given Purpose has expired.
    /// @param p The Purpose to check.
    function isPurposeExpired(Purpose storage p) private view returns (bool) {
        return now > p.start.add(p.duration.mul(1 days));
    }

    /// @dev Take any tracked redistribution in the given purpose and
    /// @dev add them to the redistribution pool.
    /// @param purposeAddress The Purpose address to redistribute.
    function redistributePurpose(address purposeAddress) private {
        uint256 purposeId = latestPurposeIds[purposeAddress];
        require(
            purposeId > 0,
            "Fountain::redistributePurpose: Purpose not found"
        );
        Purpose storage purpose = purposes[purposeId];

        // Iterate through all purposes for this address. For each iteration,
        // if the purpose has a state of redistributing and it has not yet
        // been redistributed, then process the redistribution. Iterate until
        // a purpose is found that has already been redistributed. This logic
        // should skip Active and Pending purposes.
        while (purposeId > 0 && !purpose.redistributed) {
            if (state(purpose.id) == PurposeState.Redistributing) {
                // This purpose still needs to be redistributed
                for (uint256 i = 0; i < purpose.sustainers.length; i++) {
                    address sustainer = purpose.sustainers[i];
                    redistributionPool[sustainer] = redistributionPool[sustainer]
                        .add(purpose.redistributionTracker[sustainer]);
                }
                // Mark purpose as having been redistributed
                purpose.redistributed = true;
            }
            purposeId = purpose.previousPurposeId;
            purpose = purposes[purposeId];
        }
    }

    /// @dev Returns a copy of the given Purpose with reset sustainments, and
    /// @dev that starts when the given Purpose expired.
    function createPurposeFromId(uint256 purposeId)
        private
        returns (Purpose storage)
    {
        Purpose storage currentPurpose = purposes[purposeId];
        require(
            currentPurpose.exists,
            "Fountain::createPurposeFromId: Invalid purpose"
        );

        purposeCount++;
        // Must create structs that have mappings using this approach to avoid
        // the RHS creating a memory-struct that contains a mapping.
        // See https://ethereum.stackexchange.com/a/72310
        Purpose storage purpose = purposes[purposeCount];
        purpose.id = purposeCount;
        purpose.who = currentPurpose.who;
        purpose.sustainabilityTarget = currentPurpose.sustainabilityTarget;
        purpose.currentSustainment = 0;
        purpose.start = currentPurpose.start.add(
            currentPurpose.duration.mul(1 days)
        );
        purpose.duration = currentPurpose.duration;
        purpose.want = currentPurpose.want;
        purpose.exists = true;
        purpose.previousPurposeId = currentPurpose.id;
        purpose.redistributed = false;

        // TODO: Should this emit PurposeCreated event? The callers of this will
        // emit PurposeUpdated and PurposeSustained events, but those events
        // don't indicate if a new Purpose was created.
        return purpose;
    }

    function state(uint256 purposeId) private view returns (PurposeState) {
        require(
            purposeCount >= purposeId && purposeId > 0,
            "Fountain::state: Invalid purpose id"
        );
        Purpose storage purpose = purposes[purposeId];
        require(purpose.exists, "Fountain::state: Invalid purpose");

        if (isPurposeExpired(purpose)) {
            return PurposeState.Redistributing;
        } else if (isPurposeStarted(purpose) && !isPurposeExpired(purpose)) {
            return PurposeState.Active;
        } else {
            return PurposeState.Pending;
        }
    }

    function getLatestPurposeId(address purposeAddress)
        private
        view
        returns (uint256)
    {
        uint256 purposeId = latestPurposeIds[purposeAddress];
        require(
            purposeId > 0,
            "Fountain::getLatestPurposeId: Purpose not found"
        );
        return purposeId;
    }

    function getPendingPurposeId(address purposeAddress)
        private
        view
        returns (uint256)
    {
        uint256 purposeId = latestPurposeIds[purposeAddress];
        require(
            purposeId > 0,
            "Fountain::getPendingPurposeId: Purpose not found"
        );
        if (state(purposeId) != PurposeState.Pending) {
            // There is no pending purpose if the latest Purpose is not pending
            return 0;
        }
        return purposeId;
    }

    function getActivePurposeId(address purposeAddress)
        private
        view
        returns (uint256)
    {
        uint256 purposeId = latestPurposeIds[purposeAddress];
        require(
            purposeId > 0,
            "Fountain::getActivePurposeId: Purpose not found"
        );
        // An Active purpose must be either the latest purpose or the
        // purpose immediately before it.
        if (state(purposeId) == PurposeState.Active) {
            return purposeId;
        }
        Purpose storage purpose = purposes[purposeId];
        require(
            purpose.exists,
            "Fountain::getActivePurposeId: Invalid purpose"
        );
        purposeId = purpose.previousPurposeId;
        if (state(purposeId) == PurposeState.Active) {
            return purposeId;
        }
        return 0;

        // TODO Remove this once above logic is tested and working properly
        // // uint256 count = 0;
        // while (purposeId != 0 && state(purposeId) != PurposeState.Active) {
        //     Purpose memory purpose = purposes(purposeId);
        //     if (purpose.start + purpose.duration > now) {
        //         // There is no active purpose when the current Purpose ends after
        //         // now and is not currently active
        //         return 0;
        //     }
        //     purposeId = purpose.previousPurposeId;
        //     if (state(purposeId) == PurposeState.Redistributing) {
        //         // There is no active purpose when the previous Purpose is in
        //         // the Redistributing state
        //         return 0;
        //     }
        //     // count.add(1);
        //     // TODO: Confirm loop should never execute more than 2 times??
        //     // assert(count < 2);
        // }
        // return purposeId;
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
