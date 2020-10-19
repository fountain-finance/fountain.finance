pragma solidity >=0.4.25 <0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

/* 

 Create a Purpose and say how much it'll cost to persue that purpose. 
 Maybe your purpose is providing a service or public good, maybe it's being a YouTuber, engineer, or artist -- or anything else.
 Anyone with your address can help sustain your purpose, and once you're sustainable any additional contributions are redistributed back your sustainers and those you depend on.
 
 Each Purpose is like a tier of the fountain, and the predefined cost to pursue the purpose is like the volume of that tier's pool.

 Your Purpose could be personal, or it could be managed by an address controlled by a community or business. 
 Either way, an address can only be associated with one active Purpose at a time, and one queued up for when the active one expires.

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
        uint256 sustainment;
        // The time when this Purpose will become active.
        uint256 start;
        // The number of days this Purpose can be sustained for according to `sustainabilityTarget`.
        uint256 duration;
        // The addresses who have helped to sustain this purpose.
        address[] sustainers;
        // The amount each address has contributed to the sustaining of this purpose.
        mapping(address => uint256) sustainments;
        // The amount that has been redistributed to each address as a consequence of abundant sustainment of this Purpose.
        mapping(address => uint256) redistribution;
        // Helper to verify this Purpose exists.
        bool exists;
    }

    enum Pool {SUSTAINERS, SUSTAINABILITY}

    // The current Purposes, which are immutable once the Purpose receives some sustainment.
    mapping(address => Purpose) currentPurposes;

    // The next Purposes, which are entirely mutable until they becomes the current Purpose.
    mapping(address => Purpose) nextPurposes;

    // The amount that has been redistributed to each address as a consequence of overall abundance.
    mapping(address => uint256) sustainersPool;

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

    event Withdraw(address indexed by, Pool indexed from, uint256 amount);

    event PurposeBecameSustainable(uint256 indexed id, address indexed who);

    constructor() public {
        DAI = IERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));
        numPurposes = 0;
    }

    function getSustainment(address _who)
        public
        view
        returns (
            uint256 total,
            uint256 net,
            uint256 share,
            uint256 purposeId
        )
    {
        Purpose storage purpose = currentPurposes[_who];
        total = purpose.sustainments[msg.sender];
        net = purpose.sustainments[msg.sender].sub(
            purpose.redistribution[msg.sender]
        );
        share = purpose.sustainments[msg.sender].div(purpose.sustainment);
        purposeId = purpose.id;
    }

    function updateSustainability(uint256 _sustainabilityTarget)
        public
    // address _want
    {
        Purpose storage purpose = purposeToUpdate(msg.sender);
        purpose.sustainabilityTarget = _sustainabilityTarget;
        purpose.want = DAI; //IERC20(_want);
    }

    function updateDuration(uint256 _duration) public {
        Purpose storage purpose = purposeToUpdate(msg.sender);
        purpose.duration = _duration;
    }

    function updatePurpose(uint256 _sustainabilityTarget, uint256 _duration)
        public
    // address _want
    {
        Purpose storage purpose = purposeToUpdate(msg.sender);
        purpose.sustainabilityTarget = _sustainabilityTarget;
        purpose.duration = _duration;
        purpose.want = DAI; //IERC20(_want);
    }

    function createPurpose(
        uint256 _sustainabilityTarget,
        uint256 _duration,
        uint256 _start
    ) public {
        require(
            !currentPurposes[msg.sender].exists,
            "You already have a purpose."
        );
        Purpose storage purpose = currentPurposes[msg.sender];
        purpose.start = _start;
        purpose.id = numPurposes;
        purpose.sustainabilityTarget = _sustainabilityTarget;
        purpose.duration = _duration;
        purpose.want = DAI;

        emit PurposeCreated(
            numPurposes,
            msg.sender,
            _sustainabilityTarget,
            _duration,
            DAI
        );

        numPurposes.add(1);
    }

    // Contribute a specified amount to the sustainability of the specified address's active Purpose.
    // If the amount results in surplus, redistribute the surplus proportionally to sustainers of the Purpose.
    function sustain(address _who, uint256 _amount) public {
        require(_amount > 0, "The sustainment amount should be positive.");

        // The function operates on the state of the current Purpose belonging to the specified who.
        Purpose storage currentPurpose = currentPurposes[_who];

        require(
            currentPurpose.exists,
            "This account doesn't yet have purpose."
        );

        // If the current time is greater than the current Purpose's endTime, make the next Purpose the current Purpose if one exists.
        if (now > currentPurpose.start + (currentPurpose.duration * 1 days)) {
            Purpose storage nextPurpose = nextPurposes[_who];
            currentPurpose = nextPurpose;
            sustainActivePurpose(_who, _amount);
            return;
        }

        // The amount that should be reserved for the Purpose.
        uint256 amountToAllocateToPurpose = currentPurpose
            .sustainabilityTarget
            .sub(currentPurpose.sustainment) > _amount
            ? _amount
            : currentPurpose.sustainabilityTarget.sub(
                currentPurpose.sustainment
            );

        // Save if the message sender is contributing to this Purpose for the first time.
        bool isNewSustainer = currentPurpose.sustainments[msg.sender] == 0;
        // Save if the purpose is sustainable before operating on its state.
        bool wasSustainable = currentPurpose.sustainment >=
            currentPurpose.sustainabilityTarget;

        // Move the full sustainment amount to this address.
        DAI.transferFrom(msg.sender, address(this), _amount);

        // Increment the funds that can withdrawn for sustainability.
        sustainabilityPool[_who] = sustainabilityPool[_who].add(
            amountToAllocateToPurpose
        );

        // Increment the sustainments to the Purpose made by the message sender.
        currentPurpose.sustainments[msg.sender] = currentPurpose
            .sustainments[msg.sender]
            .add(_amount);
        // Increment the total amount contributed to the sustainment of the Purpose.
        currentPurpose.sustainment = currentPurpose.sustainment.add(_amount);
        // Add the message sender as a sustainer of the Purpose if this is the first sustainment it's making to it.
        if (isNewSustainer) {
            currentPurpose.sustainers.push(msg.sender);
        }

        // Save the amount to distribute before changing the state.
        uint256 surplus = currentPurpose.sustainment <=
            currentPurpose.sustainabilityTarget
            ? 0
            : currentPurpose.sustainment.sub(
                currentPurpose.sustainabilityTarget
            );

        // //TODO market buy native token.
        // uint amountToDistribute = _amount.sub(calculateFee(_amount, 1000);

        // Redistribute any leftover amount.
        if (surplus > 0) {
            redistribute(currentPurpose, surplus);
        }

        // Emit events.
        emit PurposeSustained(currentPurpose.id, msg.sender, _amount);
        if (
            !wasSustainable &&
            currentPurpose.sustainment >= currentPurpose.sustainabilityTarget
        ) {
            emit PurposeBecameSustainable(
                currentPurpose.id,
                currentPurpose.who
            );
        }
    }

    // A message sender can withdraw what's been redistributed to it.
    function withdrawFromSustainersPool(uint256 _amount) public {
        require(
            sustainersPool[msg.sender] >= _amount,
            "You don't have enough to withdraw this much."
        );

        DAI.safeTransferFrom(address(this), msg.sender, _amount);

        sustainersPool[msg.sender] = sustainersPool[msg.sender].sub(_amount);

        emit Withdraw(msg.sender, Pool.SUSTAINERS, _amount);
    }

    // A message sender can withdrawl funds that have been used to sustain it's Purposes.
    function withdrawFromSustainabilityPool(uint256 _amount) public {
        require(
            sustainabilityPool[msg.sender] >= _amount,
            "You don't have enough to withdraw this much."
        );

        DAI.safeTransferFrom(address(this), msg.sender, _amount);

        sustainabilityPool[msg.sender] = sustainabilityPool[msg.sender].sub(
            _amount
        );

        emit Withdraw(msg.sender, Pool.SUSTAINABILITY, _amount);
    }

    // Contribute a specified amount to the sustainability of the specified address's current Purpose.
    // If the amount results in surplus, redistribute the surplus proportionally to sustainers of the Purpose.
    function sustainActivePurpose(address _who, uint256 _amount) private {}

    // The sustainability of a Purpose cannot be updated if there have been sustainments made to it.
    function purposeToUpdate(address _who) private returns (Purpose storage) {
        require(currentPurposes[_who].exists, "You don't yet have a purpose.");

        // If the address's current Purpose does not yet have sustainments, return it.
        if (currentPurposes[_who].sustainment == 0) {
            return currentPurposes[_who];
        }

        // If the address does not have a Purpose in the next Chapter, make one and return it.
        if (!nextPurposes[_who].exists) {
            Purpose storage purpose = nextPurposes[_who];
            purpose.exists = true;
            return purpose;
        }

        // Return the address's next Purpose.
        return nextPurposes[_who];
    }

    function calculateFee(uint256 _amount, uint8 _basisPoints)
        private
        pure
        returns (uint256)
    {
        require((_amount.div(10000)).mul(10000) == _amount, "Amount too small");
        return (_amount.mul(_basisPoints)).div(1000);
    }

    // Proportionally allocate the specified amount to the contributors of the specified Purpose,
    // meaning each sustainer will receive a portion of the specified amount equivalent to the portion of the total
    // amount contributed to the sustainment of the Purpose that they are responsible for.
    function redistribute(Purpose storage _purpose, uint256 _amount) private {
        assert(_amount > 0);

        // For each sustainer, calculate their share of the sustainment and allocate a proportional share of the amount.
        for (uint256 i = 0; i < _purpose.sustainers.length; i++) {
            address sustainer = _purpose.sustainers[i];
            uint256 amountShare = (
                _purpose.sustainments[sustainer].mul(_amount)
            )
                .div(_purpose.sustainment);
            //Store the reditribution in the Purpose.
            _purpose.redistribution[sustainer] = _purpose
                .redistribution[sustainer]
                .add(amountShare);

            //Store the redistribution in the sustainers pool.
            sustainersPool[sustainer] = sustainersPool[sustainer].add(
                amountShare
            );
        }
    }
}
