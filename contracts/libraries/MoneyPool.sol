// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./Math.sol";

/// @notice Logic to manipulate MoneyPool data.
library MoneyPool {
    using SafeMath for uint256;

    /// @notice Possible states that a Money pool may be in
    /// @dev Money pool's are immutable once the Money pool is active.
    enum State {Upcoming, Active, Redistributing}

    /// @notice The Money pool structure represents a project stewarded by an address, and accounts for which addresses have helped sustain the project.
    struct Data {
        // A unique number that's incremented for each new Money pool, starting with 1.
        uint256 number;
        // The address who defined this Money pool and who has access to its sustainments.
        address owner;
        // The token that this Money pool can be funded with.
        IERC20 want;
        // The amount that represents sustainability for this Money pool.
        uint256 target;
        // The running amount that's been contributed to sustaining this Money pool.
        uint256 total;
        // The time when this Money pool will become active.
        uint256 start;
        // The number of seconds until this Money pool's surplus is redistributed.
        uint256 duration;
        // The amount of available funds that have been tapped by the owner.
        uint256 tapped;
        // Helper to verify this Money pool exists.
        bool exists;
        // Indicates if surplus funds have been redistributed for each sustainer address.
        mapping(address => bool) hasRedistributed;
        // The amount each address has contributed to sustaining this Money pool.
        mapping(address => uint256) sustainments;
        // The Money pool's version.
        uint8 version;
    }

    /// @dev Initializes a Money pool's parameters.
    /// @param self The Money pool to initialize.
    /// @param _owner The owner of the Money pool.
    /// @param _start The start time of the Money pool.
    /// @param _number The number of the Money pool.
    function _init(
        Data storage self,
        address _owner,
        uint256 _start,
        uint256 _number
    ) internal {
        self.number = _number;
        self.owner = _owner;
        self.start = _start;
        self.total = 0;
        self.tapped = 0;
        self.exists = true;
        self.version = 1;
    }

    /// @dev Configures the sustainability target and duration of the sender's current Money pool if it hasn't yet received sustainments, or
    /// @dev sets the properties of the Money pool that will take effect once the current Money pool expires.
    /// @param self The Money pool to configure.
    /// @param _target The sustainability target to set.
    /// @param _duration The duration to set, measured in seconds.
    /// @param _want The token that the Money pool wants.
    function _configure(
        Data storage self,
        uint256 _target,
        uint256 _duration,
        IERC20 _want
    ) internal {
        self.target = _target;
        self.duration = _duration;
        self.want = _want;
    }

    /// @dev Contribute a specified amount to the sustainability of the specified address's active Money pool.
    /// @dev If the amount results in surplus, redistribute the surplus proportionally to sustainers of the Money pool.
    /// @param self The Money pool to sustain.
    /// @param _amount Amount of sustainment.
    /// @param _beneficiary The address to associate with this sustainment. The mes.sender is making this sustainment on the beneficiary's behalf.
    function _sustain(
        Data storage self,
        uint256 _amount,
        address _beneficiary
    ) internal {
        // Increment the sustainments to the Money pool made by the message sender.
        self.sustainments[_beneficiary] = self.sustainments[_beneficiary].add(
            _amount
        );

        // Increment the total amount contributed to the sustainment of the Money pool.
        self.total = self.total.add(_amount);
    }

    /// @dev Increase the amount that has been tapped by the Money pool's owner.
    /// @param self The Money pool to tap.
    /// @param _amount The amount to tap.
    function _tap(Data storage self, uint256 _amount) internal {
        self.tapped = self.tapped.add(_amount);
    }

    /// @notice Clones the properties from the base.
    /// @param self The Money pool to clone onto.
    /// @param _baseMp The Money pool to clone from.
    function _clone(Data storage self, Data memory _baseMp) internal {
        self.target = _baseMp.target;
        self.duration = _baseMp.duration;
        self.want = _baseMp.want;
    }

    /// @dev The state the Money pool for the given number is in.
    /// @param self The Money pool to get the state of.
    /// @return state The state.
    function _state(Data memory self) internal view returns (State) {
        if (_hasExpired(self)) return State.Redistributing;
        if (_hasStarted(self)) return State.Active;
        return State.Upcoming;
    }

    /// @dev Returns the amount available for the given Money pool's owner to tap in to.
    /// @param self The Money pool to make the calculation for.
    /// @return The resulting amount.
    function _tappableAmount(Data storage self)
        internal
        view
        returns (uint256)
    {
        return Math.min(self.target, self.total).sub(self.tapped);
    }

    /// @dev Returns the date that is the nearest multiple of duration from oldEnd.
    /// @return start The date.
    function _determineNextStart(Data storage self)
        internal
        view
        returns (uint256)
    {
        uint256 _end = self.start.add(self.duration);
        // Use the old end if the current time is still within the duration.
        if (_end.add(self.duration) > now) return _end;
        // Otherwise, use the closest multiple of the duration from the old end.
        uint256 _distanceToStart = (now.sub(_end)).mod(self.duration);
        return now.sub(_distanceToStart);
    }

    /// @dev The properties of the given Money pool.
    /// @param self The Money pool to get the properties of.
    /// @return number The number of the Money pool.
    /// @return want The token the Money pool wants.
    /// @return target The amount of the want token this Money pool is targeting.
    /// @return start The time when this Money pool started.
    /// @return duration The duration of this Money pool, measured in seconds.
    /// @return total The total amount passed through the Money pool. Returns 0 if the Money pool isn't owned by the message sender.
    function _properties(Data memory self)
        internal
        pure
        returns (
            uint256,
            IERC20,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            self.number,
            self.want,
            self.target,
            self.start,
            self.duration,
            self.total
        );
    }

    /// @dev Check to see if the given Money pool has started.
    /// @param self The Money pool to check.
    /// @return hasStarted The boolean result.
    function _hasStarted(Data memory self) private view returns (bool) {
        return now >= self.start;
    }

    /// @dev Check to see if the given MoneyPool has expired.
    /// @param self The Money pool to check.
    /// @return hasExpired The boolean result.
    function _hasExpired(Data memory self) private view returns (bool) {
        return now > self.start.add(self.duration);
    }
}
