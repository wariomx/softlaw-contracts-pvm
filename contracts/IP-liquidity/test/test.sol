//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "../../treasury/DAOTreasury.sol";

contract Test is DAOTreasury {
    // constructor(uint256 _totalSupply) public {
    //     _mint(msg.sender, _totalSupply);
    // }

    constructor(address _owner) public DAOTreasury(_owner) {}
}
