interface FountainV1MoneyPool {
    function nonce() external view returns (uint256);

    function owner() external view returns (address);

    // // The addresses who own MoneyPools that this MoneyPool depends on.
    // // Surplus from this MoneyPool will first go towards the sustainability of dependent's current MPs.
    // address[] dependents;
    // The token that this MoneyPool can be funded with.
    address public want;
    // The amount that represents sustainability for this MoneyPool.
    uint256 public sustainabilityTarget;
    // The time when this MoneyPool will become active.
    uint256 public start;
    // The number of days until this MoneyPool's redistribution is added to the redistributionPool.
    uint256 public duration;
    // The previous MoneyPool
    FountainV1MoneyPool public previous;
    // Indicates if surplus funds have been redistributed for each sustainer address
    mapping(address => bool) public redistributed;
    // The addresses who have helped to sustain this MoneyPool.
    // NOTE: Using arrays may be bad practice and/or expensive
    address[] public sustainers;

    // The Factory that created this MoneyPool.
    address private factory;
    // The amount each address has contributed to the sustaining of this MoneyPool.
    mapping(address => uint256) private sustainmentTracker;
    // The amount that will be redistributed to each address as a
    // consequence of abundant sustainment of this MoneyPool once it resolves.
    mapping(address => uint256) private redistributionTracker;
    // The running amount that's been contributed to sustaining this MoneyPool. Not visible to other contracts.
    uint256 private currentSustainment;

    /// @dev The number of sustainers of this MoneyPool.
    /// @return count The length of the sustainers array.
    function getSustainerCount() external view returns (uint256 count) {
        return sustainers.length;
    }

    /// @dev The state the MoneyPool is in.
    /// @return state The state.
    function state() external view returns (State) {
        if (this.hasExpired()) return State.Redistributing;
        if (this.hasStarted()) return State.Active;
        return State.Pending;
    }

    /// @dev Check to see if the given MoneyPool has started.
    /// @return hasStarted The boolean result.
    function hasStarted() external view returns (bool) {
        return now >= start;
    }

    /// @dev Check to see if the given MoneyPool has expired.
    /// @return hasExpired The boolean result.
    function hasExpired() external view returns (bool) {
        return now > start.add(duration.mul(1 days));
    }

    constructor(address _owner, FountainV1MoneyPool _previous) public {
        factory = msg.sender;
        currentSustainment = 0;
        owner = _owner;
        previous = _previous;
    }

    /// @dev Configure the MoneyPool's properties.
    function configure(
        uint256 _sustainabilityTarget,
        uint256 _duration,
        address _want,
        uint256 _start
    ) public onlyFactory {
        sustainabilityTarget = _sustainabilityTarget;
        duration = _duration;
        want = _want;
        start = _start;
    }

    /// @dev Adds an amount from the given sustainer address to this MoneyPool.
    /// @param sustainer The sustainer that is contributing the amount.
    /// @param amount The amount being contributed.
    function addSustainment(address sustainer, uint256 amount)
        public
        onlyFactory
    {
        // Save if the message sender is contributing to this MoneyPool for the first time.
        bool isNewSustainer = isSustainer(msg.sender);

        sustainmentTracker[sustainer] = sustainmentTracker[sustainer].add(
            amount
        );
        currentSustainment = currentSustainment.add(amount);

        // Add the message sender as a sustainer of the MoneyPool if this is the first sustainment it's making to it.
        if (isNewSustainer) sustainers.push(msg.sender);
    }

    /// @dev Sets the amount that should get redistributed to this user once this MoneyPool expires.
    /// @param sustainer The sustainer to set the amount for.
    /// @param amount The amount being set.
    function setRedistributionTracker(address sustainer, uint256 amount)
        public
        onlyFactory
    {
        redistributionTracker[sustainer] = amount;
    }

    /// @dev Marks the sustainer as having had allocated funds properly distributed.
    /// @param sustainer The sustainer to mark.
    function markAsRedistributed(address sustainer) public onlyFactory {
        redistributed[sustainer] = true;
    }

    /// @dev Determines if the given address has sustained this MoneyPool.
    /// @param candidate The sustainer to return a result for.
    /// @return flag Whether or not the condition is true.
    function isSustainer(address candidate)
        public
        view
        onlyFactory
        returns (bool flag)
    {
        return sustainmentTracker[candidate] > 0;
    }

    /// @dev Gets how much the given sustainer has contributed.
    /// @param sustainer The sustainer to return a result for.
    /// @return amount The sustainment amount.
    function getSustainmentTrackerAmount(address sustainer)
        public
        view
        onlyFactory
        returns (uint256 amount)
    {
        return sustainmentTracker[sustainer];
    }

    /// @dev Gets how much the given sustainer has been redistributed.
    /// @param sustainer The sustainer to return a result for.
    /// @return amount The redistribution amount.
    function getRedistributionTrackerAmount(address sustainer)
        public
        view
        onlyFactory
        returns (uint256 amount)
    {
        return redistributionTracker[sustainer];
    }

    /// @dev Gets the current sustainment amount this MoneyPool has received.
    /// @return amount the amount
    function getCurrentSustainment()
        public
        view
        onlyFactory
        returns (uint256 amount)
    {
        return currentSustainment;
    }
}
