// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import "../interfaces/IFountain.sol";

/// @dev This contract is an example of how you can use Fountain to fund your own project.
contract YourProject {
    IFountain fountain;

    /// @dev Create your Money pool in your constructor.
    constructor(address _fountain, IERC20 _dai) public {
        fountain = IFountain(_fountain);
        fountain.configureMp(10000 * (10 ^ 18), 30, _dai);
    }

    /// @dev Create a way for your contract to reconfigure your Money pool.
    /// @dev The changes will take effect after your active Money pool expires.
    /// @param _target The new Money pool target amount.
    /// @param _duration The new duration of your Money pool.
    /// @param _want The new token that your MoneyPool wants.
    /// @return mpId The ID of the Money pool that was reconfigured.
    function reconfigureMp(
        uint256 _target,
        uint256 _duration,
        IERC20 _want
    ) external returns (uint256 mpId) {
        /// TODO set your permissions for reconfiguring your Money pool.
        /// require(msg.sender === "some-specific-address");
        return fountain.configureMp(_target, _duration, _want);
    }

    /// @dev Create a way for your contract to take a fee. You can charge your customers however you like, and they'll keep the surplus if there is any.
    /// @param _amount The amount you are taking.
    /// @param _from Your contracts end user who you are taking a fee from. Any surplus from your Money pool will be redistributed to this address.
    /// @return mpId The ID of the Money pool that was sustained.
    function _takeFee(uint256 _amount, address _from)
        private
        returns (uint256 mpId)
    {
        /// The _amount will be pulled from the balance of this contract's address.
        return fountain.sustain(address(this), _amount, _from);
    }
}
