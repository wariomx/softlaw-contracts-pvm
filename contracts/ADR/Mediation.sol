// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Arbitration.sol";

contract Mediation is Arbitration {
    function createCase(
        string memory _mediatorA,
        string memory _mediatorB,
        string memory _object
    ) public returns (uint256 index) {
        Cases.push(
            Case({
                mediatorA: _mediatorA,
                mediatorB: _mediatorB,
                object: _object,
                vote: false
            })
        );

        return Cases.length - 1;
    }

    function getCase(
        uint256 index
    ) public view returns (string memory, string memory, string memory, bool) {
        require(index < Cases.length, "Case does not exist");

        Case storage selectedCase = Cases[index];
        return (
            selectedCase.mediatorA,
            selectedCase.mediatorB,
            selectedCase.object,
            selectedCase.vote
        );
    }

    function decideCase(bool _vote, uint256 index) public returns (bool) {
        require(index < Cases.length, "Case does not exist");

        Cases[index].vote = _vote;
        return Cases[index].vote;
    }
}
