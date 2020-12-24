// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Water is ERC20 {

    uint256 INITIAL_SUPPLY = 100000;

    constructor () public ERC20("Water Token", "WATER") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
