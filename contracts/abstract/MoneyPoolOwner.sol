// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../interfaces/IFountain.sol";

abstract contract MoneyPoolOwner is Ownable {
    using SafeERC20 for IERC20;

    /// @dev A reference to the Fountain contract.
    IFountain private _fountain;

    /// @notice Emitted when a new Fountain contract is set.
    event ResetFountain(
        IFountain indexed previousFountain,
        IFountain indexed newFountain
    );

    constructor(
        IFountain fountain,
        uint256 target,
        uint256 duration,
        IERC20 want
    ) internal {
        setFountain(fountain);
        configureMp(target, duration, want);
    }

    /** 
        @notice This allows the contract owner to collect funds from your Money pool.
        @param _mpNumber The number of the Money pool to collect funds from.
        @param _amount The amount to tap into.
    */
    function tapMp(uint256 _mpNumber, uint256 _amount)
        internal
        onlyOwner
        returns (bool)
    {
        _fountain.tap(_mpNumber, _amount, msg.sender);
    }

    /** 
        @notice This allows you to reset the Fountain contract that's running your Money pool.
        @dev Useful in case you need to switch to an updated Fountain contract
        without redeploying your contract.
        @dev You should also set the Fountain for the first time in your constructor.
        @param _newFountain The new Fountain contract.
    */
    function setFountain(IFountain _newFountain) public onlyOwner {
        require(
            _newFountain != IFountain(0),
            "MoneyPoolOwner: new Fountain is the zero address"
        );
        require(
            _newFountain != _fountain,
            "MoneyPoolOwner: new Fountain is the same as old Fountain"
        );
        _fountain = _newFountain;
        emit ResetFountain(_fountain, _newFountain);
    }

    /** 
        @notice This is how you reconfigure your Money pool.
        @dev The changes will take effect after your active Money pool expires.
        You may way to override this to create new permissions around who gets to decide
        the new Money pool parameters.
        @param _target The new Money pool target amount.
        @param _duration The new duration of your Money pool.
        @param _want The new token that your MoneyPool wants.
        @return mpNumber The number of the Money pool that was reconfigured.
    */
    function configureMp(
        uint256 _target,
        uint256 _duration,
        IERC20 _want
    ) public virtual onlyOwner returns (uint256) {
        // Increse the allowance so that Fountain can transfer want tokens from this contract's wallet into a MoneyPool.
        _want.safeIncreaseAllowance(address(_fountain), 10000000000000000000);
        // If there's an active Money pool, you'll want to decrease the allowance for the old want once it expires.

        return _fountain.configureMp(_target, _duration, _want);
    }

    /** 
        @notice This allows your contract to accept sustainments. 
        @dev You can charge your customers however you like, and they'll keep the surplus if there is any.
        @param _amount The amount you are taking. Your contract must give Fountain allowance.
        @param _sustainer Your contracts end user who is sustaining you.
        Any surplus from your Money pool will be redistributed to this address.
        @return mpNumber The number of the Money pool that was sustained.
    */
    function _sustainMp(uint256 _amount, address _sustainer)
        internal
        returns (uint256)
    {
        return _fountain.sustain(address(this), _amount, _sustainer);
    }
}
