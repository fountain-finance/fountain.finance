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
        // The addresses who have helped to sustain this purpose.
        address[] sustainers;
        // The amount each address has contributed to the sustaining of this purpose.
        mapping(address => uint256) sustainmentTracker;
        // The amount that will be redistributed to each address as a
        // consequence of abundant sustainment of this Purpose once it resolves.
        mapping(address => uint256) redistributionTracker;
    }

    enum Pool {REDISTRIBUTION, SUSTAINABILITY}

    // The current Purposes, which are immutable once the Purpose receives some sustainment.
    mapping(address => Purpose) currentPurposes;

    // The next Purposes, which are entirely mutable until they becomes the current Purpose.
    mapping(address => Purpose) nextPurposes;

    // The purposes which have not redistributed surplus funds yet.
    Purpose[] lockedPurposes;

    // The amount that has been redistributed to each address as a consequence of surplus.
    mapping(address => uint256) redistributionPool;

    // The funds that have accumulated to sustain each address's Purposes.
    mapping(address => uint256) sustainabilityPool;

    // The total number of Purposes created, which is used for issuing Purpose IDs.
    uint256 numPurposes;

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
        numPurposes = 0;
    }

    /// @dev Creates a Purpose to be sustained for the sending address.
    /// @param t The sustainability target for the Purpose, in DAI.
    /// @param d The duration of the Purpose, which starts once this is created.
    function createPurpose(uint256 t, uint256 d) external {
        require(
            !currentPurposes[msg.sender].exists,
            "This address already has a purpose. Try calling `update` instead."
        );
        require(d >= 1, "A Purpose must be at least one day long.");
        Purpose storage purpose = currentPurposes[msg.sender];
        purpose.id = numPurposes;
        purpose.sustainabilityTarget = t;
        purpose.currentSustainment = 0;
        purpose.start = now;
        purpose.duration = d;
        purpose.want = DAI;
        purpose.exists = true;
        // TODO
        // purpose.locked = true;

        emit PurposeCreated(numPurposes, msg.sender, t, d, DAI);

        numPurposes.add(1);
    }

    /// @dev Contribute a specified amount to the sustainability of the specified address's active Purpose.
    /// @dev If the amount results in surplus, redistribute the surplus proportionally to sustainers of the Purpose.
    /// @param w Address to sustain.
    /// @param a Amount of sustainment.
    function sustain(address w, uint256 a) external {
        require(a > 0, "The sustainment amount should be positive.");

        // The function operates on the state of the current Purpose belonging to the specified address.
        Purpose storage currentPurpose = currentPurposes[w];

        require(
            currentPurpose.exists,
            "This account doesn't yet have purpose."
        );

        // If the current Purpose is expired, make the next Purpose the
        // current Purpose if one exists.
        // If there is no next purpose, clone the current purpose.
        if (isPurposeExpired(currentPurpose)) {
            Purpose storage nextPurpose;
            if (nextPurposes[w].exists) nextPurpose = nextPurposes[w];
            else {
                nextPurpose = nextPurposeFromPurpose(currentPurpose);
            }
            currentPurpose = nextPurpose;

            /*

            Recurse since now there is a current Purpose.

            The worst case could be pretty brutal since the new Purpose
            may also be expired. If the Purpose duration is the minimimum of one day,
            this will recurse for each day since the last Purpose was interacted with,
            which theoretically could be millenia.

            I can't imagine a situation where this recursion would ever be
            expensive given the use cases of the contract.

            */
            // TODO: Recursion like this doesn't work. Compiler error:
            // Undeclared identifier. "sustain" is not (or not yet) visible at this point.
            // sustain(w, a);
            return;
        }

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

        // Redistribution amounts may have changed for the current Purpose.
        updateTrackedRedistribution(currentPurpose);

        // Emit events.
        emit PurposeSustained(currentPurpose.id, msg.sender, a);
    }

    /// @dev A message sender can withdraw what's been redistributed to it by a Purpose once it's expired.
    /// @param a The amount to withdraw.
    function withdrawFromRedistributionPool(uint256 a) public {
        // Before withdrawing, make sure any expired Purposes' trackedRedistribution
        // has been added to the redistribution pool.
        updateRedistributionPool();

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
    function withdrawFromSustainabilityPool(uint256 a) public {
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
        Purpose storage purpose = purposeToUpdate(msg.sender);
        if (t > 0) purpose.sustainabilityTarget = t;
        if (d > 0) purpose.duration = d;
        purpose.want = DAI; //IERC20(_want);
    }

    /// @dev The sustainability of a Purpose cannot be updated if there have been sustainments made to it.
    /// @param w The address to find a Purpose for.
    function purposeToUpdate(address w) private returns (Purpose storage) {
        require(currentPurposes[w].exists, "You don't yet have a purpose.");

        // If the address's current Purpose does not yet have sustainments, return it.
        if (currentPurposes[w].currentSustainment == 0) {
            return currentPurposes[w];
        }

        // If the address does not have a Purpose in the next Chapter, make one and return it.
        if (!nextPurposes[w].exists) {
            Purpose storage nextPurpose = nextPurposeFromPurpose(
                currentPurposes[w]
            );
            nextPurposes[w] = nextPurpose;
            return nextPurpose;
        }

        // Return the address's next Purpose.
        return nextPurposes[w];
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

    /// @dev Check to see if there are any locked purposes that have expired.
    /// @dev If so, unlock them by removing them from the lockedPurposes array.
    function updateRedistributionPool() private {
        // TODO: Need to use an array in storage because it is not possible to resize memory arrays
        // Otherwise need to define the size of the array during initialization
        // Compiler error: Unable to deduce common type for array elements.
        // See: https://ethereum.stackexchange.com/questions/11533/how-to-initialize-an-empty-array-and-push-items-into-it
        Purpose[] storage updatedLockedPurposes = []; // TODO error on this line
        for (uint256 i = 0; i < lockedPurposes.length; i++) {
            Purpose storage lockedPurpose = lockedPurposes[i];
            if (isPurposeExpired(lockedPurpose)) unlockPurpose(lockedPurpose);
            else updatedLockedPurposes.push(lockedPurposes);
        }
        //TODO verify this way to manipulate array storage works.
        lockedPurposes = updatedLockedPurposes;
    }

    /// @dev Check to see if the given Purpose has expired.
    /// @param p The Purpose to check.
    function isPurposeExpired(Purpose storage p) private returns (bool) {
        return now > p.start.add(p.duration.mul(1 days));
    }

    /// @dev Take any tracked redistribution in the given purpose and
    /// @dev add them to the redistribution pool.
    /// @param p The Purpose to unlock.
    function unlockPurpose(Purpose storage p) private {
        for (uint256 i = 0; i < p.sustainers.length; i++) {
            address sustainer = p.sustainers[i];
            redistributionPool[sustainer] = redistributionPool[sustainer].add(
                p.redistributionTracker[sustainer]
            );
        }
    }

    /// @dev Returns a copy of the given Purpose with reset sustainments, and
    /// @dev that starts when the given Purpose expired.
    function nextPurposeFromPurpose(Purpose storage p)
        private
        returns (Purpose storage)
    {
        // TODO: Compiler Error:
        // Type struct Fountain.Purpose memory is not implicitly convertible to expected type struct Fountain.Purpose storage pointer.
        Purpose storage purpose = Purpose(
            numPurposes,
            p.who,
            p.want,
            p.sustainabilityTarget,
            0,
            p.start.add(p.duration.mul(1 days)),
            p.duration,
            true
            // TODO not enough arguments
        );

        numPurposes.add(1);
        return purpose;
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
