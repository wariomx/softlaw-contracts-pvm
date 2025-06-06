// SPDX-License-Identifier: Unlicensed

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

pragma solidity ^0.8.19;

contract DisputeResolution is Ownable {
    struct Judge {
        string name;
        bool isLawyer;
    }

    constructor() Ownable(0x121BB4c10017F74F29443FD3bD6F4192d4d2b34B) {}

    function EmmitVote() public {}

    function disputeResolution() public onlyOwner {}

    function Appeal() public {}

    function submitEvidence() public {}
}
