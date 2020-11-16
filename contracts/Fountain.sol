// SPDX-License-Identifier: MIT
// TODO: What license do we release under?
pragma solidity >=0.6.0 <0.8.0;

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
    /// @dev immutable once the Purpose receives some sustainment.
    /// @dev entirely mutable until they become active.
    enum PurposeState {Pending, Active, Redistributing}

    /// @notice The Purpose structure represents a purpose stewarded by an address, and accounts for which addresses have contributed to it.
    struct Purpose {
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
        // NOTE: Using arrays may be bad practice and/or expensive
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

    /// @notice The latest purpose for each creator address
    mapping(address => uint256) public latestPurposeIds;

    /// @notice List of addresses sustained by each sustainer
    mapping(address => address[]) public sustainedAddressesBySustainer;

    // The amount that has been redistributed to each address as a consequence of surplus.
    mapping(address => uint256) redistributionPool;

    // The funds that have accumulated to sustain each address's Purposes.
    mapping(address => uint256) sustainabilityPool;

    // The total number of Purposes created, which is used for issuing Purpose IDs.
    // Purposes should have an id > 0, 0 should not be a purpose id.
    uint256 public purposeCount;

    // The contract currently only supports sustainments in DAI.
    IERC20 public DAI;

    event PurposeCreated(
        uint256 indexed id,
        address indexed by,
        uint256 sustainabilityTarget,
        uint256 duration,
        IERC20 want
    );

    event PurposeUpdated(
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

    /// @notice Creates a Purpose to be sustained for the sending address.
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
        newPurpose.who = msg.sender;
        newPurpose.sustainabilityTarget = t;
        newPurpose.currentSustainment = 0;
        newPurpose.start = now;
        newPurpose.duration = d;
        newPurpose.want = DAI;
        newPurpose.exists = true;
        newPurpose.previousPurposeId = 0;
        newPurpose.redistributed = false;

        latestPurposeIds[msg.sender] = purposeCount;

        emit PurposeCreated(purposeCount, msg.sender, t, d, DAI);
    }

    /// @notice Contribute a specified amount to the sustainability of the specified address's active Purpose.
    /// @notice If the amount results in surplus, redistribute the surplus proportionally to sustainers of the Purpose.
    /// @param w Address to sustain.
    /// @param a Amount of sustainment.
    function sustain(address w, uint256 a) external payable {
        require(
            a > 0,
            "Fountain::sustain: The sustainment amount should be positive"
        );

        // TODO: Should a purpose creator be able to sustain their own Purpose?

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

        // // TODO: Is this logic any clearer than above?
        // uint256 sustainabilityAmount;
        // if (
        //     currentPurpose.currentSustainment.add(a) <=
        //     currentPurpose.sustainabilityTarget
        // ) {
        //     sustainabilityAmount = a;
        // } else if (
        //     currentPurpose.currentSustainment >=
        //     currentPurpose.sustainabilityTarget
        // ) {
        //     sustainabilityAmount = 0;
        // } else {
        //     sustainabilityAmount = currentPurpose.sustainabilityTarget.sub(
        //         currentPurpose.currentSustainment
        //     );
        // }

        // Save if the message sender is contributing to this Purpose for the first time.
        bool isNewSustainer = currentPurpose.sustainmentTracker[msg.sender] ==
            0;

        // TODO: Not working.`Returned error: VM Exception while processing transaction: revert`
        //https://ethereum.stackexchange.com/questions/60028/testing-transfer-of-tokens-with-truffle
        // Move the full sustainment amount to this address.
        // DAI.transferFrom(msg.sender, address(this), a);

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
        emit PurposeSustained(purposeId, msg.sender, a);
    }

    /// @notice A message sender can withdraw what's been redistributed to it by a Purpose once it's expired.
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

    /// @notice A message sender can withdrawl funds that have been used to sustain it's Purposes.
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

    /// @notice Updates the sustainability target and duration of the sender's current Purpose if it hasn't yet received sustainments, or
    /// @notice sets the properties of the Purpose that will take effect once the current Purpose expires.
    /// @param t The sustainability target to set.
    /// @param d The duration to set.
    function updatePurpose(
        uint256 t,
        uint256 d // address _want
    ) external {
        require(
            latestPurposeIds[msg.sender] > 0,
            "You don't yet have a purpose."
        );
        uint256 purposeId = purposeIdToUpdate(msg.sender);
        Purpose storage purpose = purposes[purposeId];
        if (t > 0) purpose.sustainabilityTarget = t;
        if (d > 0) purpose.duration = d;
        purpose.want = DAI; //IERC20(_want);

        emit PurposeUpdated(
            purposeId,
            purpose.who,
            purpose.sustainabilityTarget,
            purpose.duration,
            DAI
        );
    }

    // --- External getters for testing --- //

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
        require(latestPurposeIds[w] > 0, "No purpose found at this address");
        require(
            purposes[latestPurposeIds[w]].exists,
            "No purpose found at this address"
        );
        return purposes[latestPurposeIds[w]].sustainabilityTarget;
    }

    function getDuration(address w) external view returns (uint256) {
        require(latestPurposeIds[w] > 0, "No purpose found at this address");
        require(
            purposes[latestPurposeIds[w]].exists,
            "No purpose found at this address"
        );
        return purposes[latestPurposeIds[w]].duration;
    }

    function getCurrentSustainment(address w) external view returns (uint256) {
        require(latestPurposeIds[w] > 0, "No purpose found at this address");
        require(
            purposes[latestPurposeIds[w]].exists,
            "No purpose found at this address"
        );
        return purposes[latestPurposeIds[w]].currentSustainment;
    }

    function getSustainerCount(address w) external view returns (uint256) {
        require(latestPurposeIds[w] > 0, "No purpose found at this address");
        require(
            purposes[latestPurposeIds[w]].exists,
            "No purpose found at this address"
        );
        return purposes[latestPurposeIds[w]].sustainers.length;
    }

    function getSustainmentTrackerAmount(address who, address by)
        external
        view
        returns (uint256)
    {
        require(latestPurposeIds[who] > 0, "No purpose found at this address");
        require(
            purposes[latestPurposeIds[who]].exists,
            "No purpose found at this address"
        );
        return purposes[latestPurposeIds[who]].sustainmentTracker[by];
    }

    function getRedistributionTrackerAmount(address who, address by)
        external
        view
        returns (uint256)
    {
        require(latestPurposeIds[who] > 0, "No purpose found at this address");
        require(
            purposes[latestPurposeIds[who]].exists,
            "No purpose found at this address"
        );
        return purposes[latestPurposeIds[who]].redistributionTracker[by];
    }

    // --- private --- //

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
        purposeId = getPendingPurposeId(w);
        if (purposeId != 0) {
            return purposeId;
        }

        // No pending purpose found, clone the latest purpose
        purposeId = getLatestPurposeId(w);
        Purpose storage purpose = createPurposeFromId(purposeId);
        purposes[purposeId] = purpose;
        latestPurposeIds[w] = purposeId;
        return purposeId;
    }

    /// @dev Only active Purposes can be sustained.
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
        purposes[purposeId] = purpose;
        latestPurposeIds[w] = purposeId;

        return purposeId;
    }

    /// @dev Proportionally allocate the specified amount to the contributors of the specified Purpose,
    /// @dev meaning each sustainer will receive a portion of the specified amount equivalent to the portion of the total
    /// @dev amount contributed to the sustainment of the Purpose that they are responsible for.
    /// @param p The Purpose to update.
    function updateTrackedRedistribution(Purpose storage p) private {
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

            //Store the updated redistribution in the Purpose.
            p.redistributionTracker[sustainer] = sustainerSurplusShare;
        }
    }

    /// @dev Check to see if the given Purpose has started.
    /// @param p The Purpose to check.
    function isPurposeStarted(Purpose storage p) private view returns (bool) {
        return now >= p.start;
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
        // Short circuits by testing `purpose.redistributed` to limit number
        // of iterations since all previous purposes must have already been
        // redistributed.
        while (purposeId > 0 && !purpose.redistributed) {
            if (state(purposeId) == PurposeState.Redistributing) {
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
        purpose.who = currentPurpose.who;
        purpose.sustainabilityTarget = currentPurpose.sustainabilityTarget;
        purpose.currentSustainment = 0;
        purpose.start = currentPurpose.start.add(
            currentPurpose.duration.mul(1 days)
        );
        purpose.duration = currentPurpose.duration;
        purpose.want = currentPurpose.want;
        purpose.exists = true;
        purpose.previousPurposeId = purposeCount;
        purpose.redistributed = false;

        emit PurposeUpdated(
            purposeCount,
            purpose.who,
            purpose.sustainabilityTarget,
            purpose.duration,
            DAI
        );

        return purpose;
    }

    function state(uint256 purposeId) private view returns (PurposeState) {
        require(
            purposeCount >= purposeId && purposeId > 0,
            "Fountain::state: Invalid purposeId"
        );
        Purpose storage purpose = purposes[purposeId];
        require(purpose.exists, "Fountain::state: Invalid purpose");

        if (isPurposeExpired(purpose)) {
            return PurposeState.Redistributing;
        }

        if (isPurposeStarted(purpose) && !isPurposeExpired(purpose)) {
            return PurposeState.Active;
        }

        return PurposeState.Pending;
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
        if (purposeId > 0 && state(purposeId) == PurposeState.Active) {
            return purposeId;
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
