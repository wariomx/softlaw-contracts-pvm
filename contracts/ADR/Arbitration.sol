//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

contract Arbitration {
    struct Case {
        string mediatorA;
        string mediatorB;
        string object;
        bool vote;
    }

    Case[] public Cases;

    Case public currentCase;
}
