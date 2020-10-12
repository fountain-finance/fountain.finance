pragma solidity >=0.4.25 <0.7.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

/* 

 The Organism contract specifies the metaphysical workings of a system made up of Purposes and their stewards, constrained only by time.
 Each Purpose is premeditated with sustainability number that can be contributed towards by any sustainer. Any surplus get's redistributed proportionally back to sustainers.
  
 No seriously, don't over think it. Create a Purpose and say how much it'll cost you to persue that purpose. 
 Maybe your purpose is providing a service or public good, maybe it's being a YouTuber, engineer, or artist -- or anything else.
 Anyone with your address can help sustain your purpose, and once you're sustainable any additional contributions are redistributed back your sustainers.

 Your purpose could be personal, or it could be managed by an address controlled by a community or business. 
 Either way, an address can only have one active Purpose at a time, and one queued up for when the active one expires.

 To avoid abuse, it's impossible for a steward to update a Purpose's sustainability or duration once there has been a sustainment made to it. 
 Any attempts to do so will just create/update the steward's queued purpose.

 You can withdrawl funds of yours from the sustainers pool (where surplus is distributed) or the sustainability pool (where sustainments are kept) at anytime.

*/
contract Organism {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // The Purpose structure represents a purpose envisioned by a steward, and accounts for who has contributed to the vision.
    struct Purpose {
        // A unique ID for this purpose.
        uint256 id;
        // The address which is stewarding this purpose and which has access to its funds.
        address steward;
        // The token that this Purpose can be funded with.
        address want;
        // The amount that represents sustainability for this purpose.
        uint256 sustainability;
        // The running amount that's been contributed to sustaining this purpose.
        uint256 sustainment;
        // The time when this Purpose will become active.
        uint256 start;
        // The number of days this Purpose can be sustained for according to `sustainability`.
        uint256 duration;
        // The addresses who have helped to sustain this purpose.
        address[] sustainers;
        // The amount each address has contributed to the sustaining of this purpose.
        mapping(address => uint256) sustainments;
        // The net amount each address has contributed to the sustaining of this purpose after redistribution.
        mapping(address => uint256) netSustainments;
        // The amount that has been redistributed to each address as a consequence of abundant sustainment of this Purpose.
        mapping(address => uint256) redistribution;
        // Helper to verify this Purpose exists.
        bool exists;
    }

    enum Pools {SUSTAINERS, SUSTAINABILITY}

    // The current Purposes, which are immutable once the Purpose receives some sustainment.
    mapping(address => Purpose) currentPurposes;

    // The next Purposes, which are entirely mutable until they becomes the current Purpose.
    mapping(address => Purpose) nextPurposes;

    // The amount that has been redistributed to each address as a consequence of overall abundance.
    mapping(address => uint256) sustainersPool;

    // The funds that have accumulated to sustain each steward's Purposes.
    mapping(address => uint256) sustainabilityPool;

    unit256 numPurposes;

    IERC20 public DAI;

    event PurposeCreated(
        uint256 indexed id,
        address indexed by,
        uint256 sustainability,
        uint256 duration,
        address want
    );

    event PurposeSustained(
        uint256 indexed id,
        address indexed sustainer,
        uint256 amount
    );

    event Withdrawl(address indexed by, Pool indexed from, uint256 amount);

    event PurposeBecameSustainable(uint256 indexed id, uint256 indexed steward);

    constructor() public {
        DAI = IERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));
        numPurposes = 0;
    }

    function updateSustainability(uint256 _sustainability, address _want)
        public
    {
        Purpose storage purpose = purposeToUpdate(msg.sender);
        purpose.sustainability = _sustainability;
        purpose.want = _want;
    }

    function updateDuration(uint256 _duration) public {
        Purpose storage purpose = purposeToUpdate(msg.sender);
        purpose.duration = _duration;
    }

    function updatePurpose(
        uint256 _sustainability,
        uint256 _duration,
        address _want
    ) public {
        Purpose storage purpose = purposeToUpdate(msg.sender);
        purpose.sustainability = _sustainability;
        purpose.duration = _duration;
        purpose.want = _want;
    }

    function createPurpose(
        uint256 _sustainability,
        address _want,
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
        purpose.sustainability = _sustainability;
        purpose.duration = _duration;
        purpose.want = _want;

        emit PurposeCreated(
            numPurposes,
            msg.sender,
            _sustainability,
            _duration,
            _want
        );

        numPurposes.add(1);
    }

    // Contribute a specified amount to the sustainability of the specified Steward's active Purpose.
    // If the amount results in surplus, redistribute the surplus proportionally to sustainers of the Purpose.
    function sustain(address _steward, uint256 _amount) public {
        // The function first tries to operate on the state of the current Purpose belonging to the specified steward.
        Purpose storage currentPurpose = currentPurposes[_steward];

        require(
            currentPurpose.exists,
            "This account isn't currently stewarding a purpose."
        );
        require(_amount > 0, "The sustainment amount should be positive.");

        sustainPurpose(currentPurpose, _steward, _amount);
    }

    // A message sender can withdrawl what's been redistributed to it.
    function withdrawlSustainers(uint256 _amount) public {
        require(
            sustainersPool[msg.sender] >= _amount,
            "You don't have enough to withdrawl this much."
        );

        require(
            DAI.transferFrom(address(this), msg.sender, _amount),
            "Transfer failed."
        );
        sustainersPool[msg.sender] = sustainersPool[msg.sender].sub(_amount);

        emit Withdrawl(msg.sender, Pool.SUSTAINERS, _amount);
    }

    // A message sender can withdrawl funds that have been used to sustain it's Purposes.
    function withdrawlSustainability(uint256 _amount) public {
        require(
            sustainabilityPool[msg.sender] >= _amount,
            "You don't have enough to withdrawl this much."
        );

        require(
            DAI.transferFrom(address(this), msg.sender, _amount),
            "Transfer failed."
        );
        sustainabilityPool[msg.sender] = sustainabilityPool[msg.sender].sub(
            _amount
        );

        emit Withdrawl(msg.sender, Pool.SUSTAINABILITY, _amount);
    }

    // Contribute a specified amount to the sustainability of a Purpose stewarded by the specified address.
    // If the amount results in surplus, redistribute the surplus proportionally to sustainers of the Purpose.
    function sustainPurpose(
        Purpose storage _purpose,
        address _steward,
        uint256 _amount
    ) private {
        // If the current time is greater than the current Purpose's endTime, progress to the next Purpose.
        if (now > _purpose.start + (_purpose.duration * 1 days)) {
            Purpose storage nextPurpose = nextPurposes[_steward];
            require(
                nextPurpose.exists,
                "This account isn't currently stewarding a purpose."
            );
            currentPurposes[_steward] = nextPurposes[_steward];
            sustainPurpose(_purpose, _steward, _amount);
            return;
        }

        // The amount that should be reserved for the steward to withdrawl.
        unit amountToSendToSteward = _purpose.sustainability.sub(
            _purpose.sustainment
        ) > _amount
            ? _amount
            : _purpose.sustainability.sub(_purpose.sustainment);

        // Save if the message sender is contributing to this Purpose for the first time.
        bool isNewSustainer = _purpose.sustainments[msg.sender] == 0;
        // Save if the purpose is sustainable before operating on its state.
        bool isSustainable = _purpose.sustainments >= _purpose.sustanainability;

        require(
            daiInstance.transferFrom(
                msg.sender,
                address(this),
                amountToSendToSteward
            ),
            "Transfer failed."
        );

        // Increment the funds that the steward has access to withdrawl.
        funds[_steward] = funds[_steward].add(amountToSendToSteward);

        // Increment the sustainments to the Purpose made by the message sender.
        _purpose.sustainments[msg.sender] = _purpose.sustainments[msg.sender]
            .add(_amount);
        // Increment the total amount contributed to the sustainment of the Purpose.
        _purpose.sustainment = _purpose.sustainment.add(_amount);
        // Add the message sender as a sustainer of the Purpose if this is the first sustainment it's making to it.
        if (isNewSustainer) {
            _purpose.sustainers.push(msg.sender);
        }

        // Save the amount to distribute before changing the state.
        uint256 surplus = _purpose.sustainment <= _purpose.sustainability
            ? 0
            : _purpose.sustainment.sub(_purpose.sustainability);

        // //TODO market buy native token.
        // uint amountToDistribute = _amount.sub(calculateFee(_amount, 1000);

        // Redistribute any leftover amount.
        if (amountToDistribute > 0) {
            redistribute(_purpose, amountToDistribute);
        }

        // Emit events.
        emit PurposeSustained(_purpose.id, msg.sender, _amount);
        if (
            !isSustainable && _purpose.sustainments >= _purpose.sustanainability
        ) {
            emit PurposeBecameSustainable(_purpose.id, _purpose.steward);
        }
    }

    // The sustainability of a Purpose cannot be updated if there have been sustainments made to it.
    function purposeToUpdate(address _steward)
        private
        returns (Purpose storage)
    {
        require(
            currentPurposes[_address].exists,
            "You don't yet have a purpose."
        );

        // If the steward's current Purpose does not yet have sustainments, return it.
        if (currentPurposes[_steward].sustainment == 0) {
            return currentPurposes[_steward];
        }

        // If the steward does not have a Purpose in the next Chapter, make one and return it.
        if (!nextPurposes[_steward].exists) {
            Purpose storage purpose = nextPurposes[_steward];
            purpose.exists = true;
            return purpose;
        }

        // Return the steward's next Purpose.
        return nextPurposes[_steward];
    }

    function calculateFee(uint256 _amount, uint8 basisPoints)
        private
        returns (uint256)
    {
        require((amount / 10000) * 10000 == _amount, "Amount too small");
        return (amount * basisPoints) / 1000;
    }

    // Proportionally allocate the specified amount to the contributors of the specified Purpose,
    // meaning each sustainer will receive a portion of the specified amount equivalent to the portion of the total
    // amount contributed to the sustainment of the Purpose that they are responsible for.
    function redistribute(Purpose storage purpose, uint256 amount) private {
        assert(amount > 0);

        // For each sustainer, calculate their share of the sustainment and allocate a proportional share of the amount.
        for (uint256 i = 0; i < purpose.sustainers.length; i++) {
            address sustainer = purpose.sustainers[i];
            uint256 amountShare = (purpose.sustainments[sustainer].mul(amount))
                .div(purpose.sustainment);
            sustainersPool[sustainer] = sustainersPool[sustainer].add(
                amountShare
            );
        }
    }
}
