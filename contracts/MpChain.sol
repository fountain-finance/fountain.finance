// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IMpChain.sol";
import "./libraries/MoneyPool.sol";

contract MpChain is IMpChain, Ownable {
    using SafeMath for uint256;
    using MoneyPool for MoneyPool.Data;

    // --- private properties --- //

    // The official record of all Money pools ever created.
    mapping(uint256 => MoneyPool.Data) private get;

    // The previous chain, if there is one.
    MpChain private previous;

    // --- public properties --- //

    /// @notice A mapping from Money pool number's the the numbers of the previous Money pool for the same owner.
    mapping(uint256 => uint256) public override previousNumber;

    /// @notice The latest Money pool for each owner address.
    mapping(address => uint256) public override latestNumber;

    /// @notice The total number of Money pools created, which is used for issuing Money pool numbers.
    /// @dev Money pools should have a number > 0.
    uint256 public override length;

    // For each Money pool number, an indication if surplus funds have been redistributed for each sustainer address.
    mapping(uint256 => mapping(address => bool))
        public
        override hasRedistributed;

    // For each Money pool number, the amount each sustainer has contributed to sustaining the Money pool.
    mapping(uint256 => mapping(address => uint256))
        public
        override sustainments;

    // --- external views --- //

    /**  
        @notice The Money pool for the given number.
        @param _number The number of the Money pool to get.
        @return _mp The Money pool.
    */
    function mp(uint256 _number)
        external
        view
        override
        returns (MoneyPool.Data memory _mp)
    {
        _mp = get[_number];
        require(_mp.number > 0, "MpChain::mp: Money pool not found");
    }

    /**
        @notice The Money pool that's next up for an owner.
        @param _owner The owner of the Money pool being looked for.
        @return _mp The Money pool.
    */
    function upcomingMp(address _owner)
        external
        view
        override
        returns (MoneyPool.Data memory _mp)
    {
        _mp = _upcomingMp(_owner);
        require(_mp.number > 0, "MpChain::getUpcomingMp: Money pool not found");
        return _mp;
    }

    /**
        @notice The currently active Money pool for an owner.
        @param _owner The owner of the money pool being looked for.
        @return _mp The Money pool.
    */
    function activeMp(address _owner)
        external
        view
        override
        returns (MoneyPool.Data memory _mp)
    {
        _mp = _activeMp(_owner);
        require(_mp.number > 0, "MpChain::getActiveMp: Money pool not found");
        return _mp;
    }

    /**
        @notice The latest Money pool for an owner.
        @dev This Money pool might be in any state.
        @param _owner The owner of the money pool being looked for.
        @return _mp The Money pool.
    */
    function latestMp(address _owner)
        external
        view
        override
        returns (MoneyPool.Data memory _mp)
    {
        _mp = _latestMp(_owner);
        require(_mp.number > 0, "MpChain::getLatestMp: Money pool not found");
        return _mp;
    }

    /** 
        @notice The Money pool that came before the Money pool of the provided number for its owner.
        @param _number The number of the Money pool to find the previous for.
        @return _mp The previous Money pool.
    */
    function previousMp(uint256 _number)
        external
        view
        override
        returns (MoneyPool.Data memory)
    {
        return get[previousNumber[_number]];
    }

    /**
        @notice The amount left to be withdrawn by the Money pool's owner.
        @param _number The number of the Money pool to get the available sustainment from.
        @return amount The amount.
    */
    function tappableAmount(uint256 _number)
        external
        view
        override
        returns (uint256)
    {
        return get[_number]._tappableAmount();
    }

    /** 
        @notice The amount of redistribution in a Money pool that can be claimed by the given address.
        @param _number The number of the Money pool to get a redistribution amount for.
        @param _sustainer The address of the sustainer to get an amount for.
        @return amount The amount.
    */
    function trackedRedistribution(uint256 _number, address _sustainer)
        external
        view
        override
        returns (uint256)
    {
        return _trackedRedistribution(_number, _sustainer);
    }

    // --- external transactions --- //

    constructor() internal {
        length = 0;
    }

    function configure(
        address _owner,
        uint256 _target,
        uint256 _duration,
        IERC20 _want
    ) external override onlyOwner returns (MoneyPool.Data memory) {
        MoneyPool.Data storage _mp = _mpToConfigure(_owner);
        _mp._configure(_target, _duration, _want);
        return _mp;
    }

    function sustain(
        address _owner,
        uint256 _amount,
        address _beneficiary
    ) external override onlyOwner returns (MoneyPool.Data memory) {
        // Find the Money pool that this sustainment should go to.
        MoneyPool.Data storage _mp = _mpToSustain(_owner);

        // Increment the sustainments to the Money pool made by the message sender.
        sustainments[_mp.number][_beneficiary] = sustainments[_mp.number][
            _beneficiary
        ]
            .add(_amount);

        // Increment the total amount contributed to the sustainment of the Money pool.
        _mp.total = _mp.total.add(_amount);

        return _mp;
    }

    function tap(
        uint256 _number,
        address _owner,
        uint256 _amount
    ) external override onlyOwner returns (MoneyPool.Data memory) {
        MoneyPool.Data storage _mp = get[_number];
        require(
            _mp.owner == _owner,
            "MpChain::tap: A Money pool can only be tapped by its owner"
        );
        require(
            _mp._tappableAmount() >= _amount,
            "MpChain::tap: Not enough to collect"
        );

        _mp._tap(_amount);
    }

    function markAsRedistributed(uint256 _number, address _sustainer)
        external
        override
        onlyOwner
    {
        hasRedistributed[_number][_sustainer] = true;
    }

    // --- private transactions --- //

    /** 
        @notice The amount of redistribution in a Money pool that can be claimed by the given address.
        @param _mpNumber The number of the Money pool to get a redistribution amount for.
        @param _sustainer The address of the sustainer to get an amount for.
        @return amount The amount.
    */
    function _trackedRedistribution(uint256 _mpNumber, address _sustainer)
        private
        view
        returns (uint256)
    {
        MoneyPool.Data memory _mp = get[_mpNumber];
        // Return 0 if there's no surplus.
        if (_mp.duration == 0 || _mp.total <= _mp.target) return 0;

        uint256 _surplus = _mp.total.sub(_mp.target);

        // Calculate their share of the sustainment for the the given sustainer.
        // allocate a proportional share of the surplus, overwriting any previous value.
        uint256 _proportionOfTotal =
            sustainments[_mpNumber][_sustainer].div(_mp.total);

        return _surplus.mul(_proportionOfTotal);
    }

    // --- private transactions --- //

    /** 
        @notice The Money pool that is configurable for this owner.
        @dev The sustainability of a Money pool cannot be updated if there have been sustainments made to it.
        @param _owner The address who owns the Money pool to look for.
        @return _mp The resulting Money pool.
    */
    function _mpToConfigure(address _owner)
        private
        returns (MoneyPool.Data storage _mp)
    {
        // Allow active moneyPool to be updated if it has no sustainments
        _mp = _activeMp(_owner);
        if (_mp.duration > 0 && _mp.total == 0) return _mp;

        // Cannot update active moneyPool, check if there is a upcoming moneyPool
        _mp = _upcomingMp(_owner);
        if (_mp.duration > 0) return _mp;

        // No upcoming moneyPool found, clone the latest moneyPool
        _mp = _latestMp(_owner);

        MoneyPool.Data storage _newMp = _initMp(_owner, now);
        if (_mp.duration > 0) _newMp._clone(_mp);
        return _newMp;
    }

    /** 
        @notice The Money pool that is accepting sustainments for this owner.
        @dev Only active Money pools can be sustained.
        @param _owner The address who owns the Money pool to look for.
        @return _mp The resulting Money pool.
    */
    function _mpToSustain(address _owner)
        private
        returns (MoneyPool.Data storage _mp)
    {
        // Check if there is an active moneyPool
        _mp = _activeMp(_owner);
        if (_mp.duration > 0) return _mp;

        // No active moneyPool found, check if there is an upcoming moneyPool
        _mp = _upcomingMp(_owner);
        if (_mp.duration > 0) return _mp;

        // No upcoming moneyPool found, clone the latest moneyPool
        _mp = _latestMp(_owner);

        require(
            _mp.duration > 0,
            "Fountain::_mpToSustain: This owner has no Money pools"
        );

        // Use a start date that's a multiple of the duration.
        // This creates the effect that there have been scheduled Money pools ever since the `latest`, even if `latest` is a long time in the past.
        MoneyPool.Data storage _newMp =
            _initMp(_mp.owner, _mp._determineNextStart());
        _newMp._clone(_mp);
        return _newMp;
    }

    /** 
        @notice Initializes a Money pool to be sustained for the sending address.
        @param _owner The owner of the Money pool being initialized.
        @param _start The start time for the new Money pool.
        @return _newMp The initialized Money pool.
    */
    function _initMp(address _owner, uint256 _start)
        private
        returns (MoneyPool.Data storage _newMp)
    {
        length++;
        _newMp = get[length];
        _newMp._init(_owner, _start, length);
        previousNumber[length] = latestNumber[_owner];
        latestNumber[_owner] = length;
    }

    // --- private views --- //

    /** 
        @notice The currently active Money pool for an owner.
        @param _owner The owner of the money pool being looked for.
        @return _mp The active Money pool.
    */
    function _activeMp(address _owner)
        private
        view
        returns (MoneyPool.Data storage _mp)
    {
        _mp = _latestMp(_owner);
        if (_mp.duration == 0) return get[0];

        // An Active moneyPool must be either the latest moneyPool or the
        // moneyPool immediately before it.
        if (_mp._state() == MoneyPool.State.Active) return _mp;

        _mp = get[previousNumber[_mp.number]];
        if (_mp.duration > 0 && _mp._state() == MoneyPool.State.Active)
            return _mp;

        return get[0];
    }

    /** 
        @notice The Money pool that's next up for an owner.
        @param _owner The owner of the money pool being looked for.
        @return _mp The upcoming Money pool.
    */
    function _upcomingMp(address _owner)
        private
        view
        returns (MoneyPool.Data storage _mp)
    {
        _mp = _latestMp(_owner);
        if (_mp.duration == 0) return get[0];

        // There is no upcoming Money pool if the latest Money pool is not upcoming
        if (_mp._state() != MoneyPool.State.Upcoming) return get[0];
        return _mp;
    }

    /** 
        @notice The latest Money pool that was created by the owner.
        @dev This Money pool could be in any state.
        @param _owner The owner of the money pool being looked for.
        @return _mp The latest Money pool.
    */
    function _latestMp(address _owner)
        private
        view
        returns (MoneyPool.Data storage _mp)
    {
        return get[latestNumber[_owner]];
    }
}
