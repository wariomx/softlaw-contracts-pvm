// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {DaoMembership} from "../memberships/DAOMembership.sol";
import {DAOTreasury} from "../treasury/DAOTreasury.sol";
import {CopyrightsRegistry} from "../Registries/RCopyright.sol";
import {GovernorHelpers} from "./DAOGovernorHelpers.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SoftLawGovernance
 * @dev Core governance contract that handles proposals and voting
 */
contract SoftLawGovernance is GovernorHelpers, ReentrancyGuard {
    //instance contracts
    CopyrightsRegistry public registryContract;

    DAOTreasury public treasury;

    DaoMembership public membershipContract;

    // QUORUM & LOCKING PERIOD VARIABLES
    uint256 public votingQuorum;
    uint256 public lockingPeriod;

    enum VoteType {
        Nay,
        Aye,
        Abstain
    }
    enum ProposalType {
        Treasury,
        Membership,
        Registry
    }

    // Basic proposal info - common to all proposal types
    struct ProposalCore {
        string name;
        string description;
        address proponent;
        uint256 createdAt;
        bool executed;
        ProposalType proposalType;
    }

    // Voting data separated to avoid stack too deep errors
    struct ProposalVotes {
        uint256 ayeVotes;
        uint256 nayVotes;
        uint256 abstainVotes;
        mapping(address => bool) hasVoted;
    }

    // Membership-specific data
    struct MembData {
        bytes callData;
    }

    // Treasuary-specific data
    struct TreasuryData {
        bytes callData;
    }

    // Registry-specific data
    struct RegistryData {
        bytes callData;
    }

    // Mapping for proposal types
    mapping(uint256 => ProposalCore) private _proposalCore;
    mapping(uint256 => ProposalVotes) private _proposalVotes;

    // Mapping CallData
    mapping(uint256 => MembData) private _membData;
    mapping(uint256 => TreasuryData) private _treasuryData;
    mapping(uint256 => RegistryData) private _registryData;

    uint256 private proposalCount;

    // Events
    event ProposalCreated(
        uint256 indexed id,
        address indexed proposer,
        ProposalType proposalType
    );
    event VoteCast(uint256 indexed id, address indexed voter, VoteType vote);
    event ProposalExecuted(uint256 indexed id);
    event RegistryValidationProposalExecuted(
        uint256 indexed id,
        address beneficiary,
        uint256 registryId,
        uint256 amount
    );
    event ConsoleLog(TreasuryData td);

    event TreasuryProposalExecuted(
        uint256 indexed id,
        bool success,
        bytes returnData
    );
    event ExecutionFailed(uint256 indexed id, string reason);

    modifier onlyMember() {
        require(
            membershipContract.isMember(msg.sender),
            "Not a Softlaw DAO member"
        );
        _;
    }

    modifier onlySelf() {
        require(msg.sender == address(this), "Only DAO can call");
        _;
    }

    constructor(
        address _registryContract,
        address _membershipContract,
        address _treasuryContract
    ) {
        votingQuorum = 1;
        lockingPeriod = 30;
        treasury = DAOTreasury(_treasuryContract);
        registryContract = CopyrightsRegistry(_registryContract);
        membershipContract = DaoMembership(_membershipContract);
    }

    // Creates a core proposal record with common data
    function _createProposalCore(
        string memory _name,
        string memory _description,
        ProposalType _type
    ) internal returns (uint256) {
        uint256 id = proposalCount++;

        ProposalCore storage pc = _proposalCore[id];
        pc.name = _name;
        pc.description = _description;
        pc.proponent = msg.sender;
        pc.createdAt = block.timestamp;
        pc.executed = false;
        pc.proposalType = _type;

        return id;
    }

    function createTreasuryProposal(
        string memory _name,
        string memory _description,
        bytes memory _callData
    ) public onlyMember nonReentrant returns (uint256) {
        uint256 id = _createProposalCore(
            _name,
            _description,
            ProposalType.Treasury
        );

        TreasuryData storage td = _treasuryData[id];

        td.callData = _callData;

        emit ProposalCreated(id, msg.sender, ProposalType.Treasury);
        return id;
    }

    function createMembershipProposal(
        string memory _name,
        string memory _description,
        bytes memory _callData
    ) public onlyMember nonReentrant returns (uint256) {
        uint256 id = _createProposalCore(
            _name,
            _description,
            ProposalType.Membership
        );

        MembData storage ad = _membData[id];
        ad.callData = _callData;

        emit ProposalCreated(id, msg.sender, ProposalType.Membership);
        return id;
    }

    function vote(uint256 _id, VoteType _voteType) public onlyMember {
        require(_id < proposalCount, "Invalid proposal ID");
        require(!_proposalCore[_id].executed, "Already executed");

        ProposalVotes storage votes = _proposalVotes[_id];
        require(!votes.hasVoted[msg.sender], "Already voted");

        votes.hasVoted[msg.sender] = true;

        if (_voteType == VoteType.Aye) votes.ayeVotes++;
        else if (_voteType == VoteType.Nay) votes.nayVotes++;
        else votes.abstainVotes++;

        emit VoteCast(_id, msg.sender, _voteType);
    }

    function hasProposalPassed(uint256 _id) public view returns (bool) {
        require(_id < proposalCount, "Invalid proposal ID");

        ProposalVotes storage votes = _proposalVotes[_id];
        uint256 totalVotes = votes.ayeVotes +
            votes.nayVotes +
            votes.abstainVotes;
        return totalVotes >= votingQuorum && votes.ayeVotes > votes.nayVotes;
    }

    function executeProposal(uint256 _id) public onlyMember nonReentrant {
        require(_id < proposalCount, "Invalid proposal ID");

        ProposalCore storage pc = _proposalCore[_id];
        require(!pc.executed, "Already executed");
        require(hasProposalPassed(_id), "Not enough support");
        require(
            block.timestamp >= pc.createdAt + lockingPeriod,
            "Locking period active"
        );

        // Mark as executed first to prevent reentrancy
        pc.executed = true;

        bool success = false;
        bytes memory returnData;

        if (pc.proposalType == ProposalType.Treasury) {
            TreasuryData storage td = _treasuryData[_id];
            if (td.callData.length > 0) {
                // Execute the call on the treasury contract
                (success, returnData) = address(treasury).call(td.callData);

                if (!success) {
                    // Revert the executed status if failed
                    pc.executed = false;
                    // Extract revert reason if available
                    string memory reason = _getRevertMsg(returnData);
                    emit ExecutionFailed(_id, reason);
                    revert(
                        string(
                            abi.encodePacked(
                                "Treasury execution failed: ",
                                reason
                            )
                        )
                    );
                }

                emit TreasuryProposalExecuted(_id, success, returnData);
            }
        } else if (pc.proposalType == ProposalType.Membership) {
            MembData storage md = _membData[_id];
            if (md.callData.length > 0) {
                (success, returnData) = address(this).call(md.callData);

                if (!success) {
                    pc.executed = false;
                    string memory reason = _getRevertMsg(returnData);
                    emit ExecutionFailed(_id, reason);
                    revert(
                        string(
                            abi.encodePacked(
                                "Membership execution failed: ",
                                reason
                            )
                        )
                    );
                }
            }
        } else if (pc.proposalType == ProposalType.Registry) {
            //Todo
        }

        pc.executed = true;

        emit ProposalExecuted(_id);
    }

    function _getRevertMsg(
        bytes memory _returnData
    ) internal pure returns (string memory) {
        if (_returnData.length < 68) return "Transaction reverted silently";

        assembly {
            _returnData := add(_returnData, 0x04)
        }
        return abi.decode(_returnData, (string));
    }

    // Emergency Withdraw fund treasury function (requires special governance approval)
    function emergencyWithdrawFunds(uint256 _amount) public onlySelf {
        treasury.printBrrrr(_amount);
    }

    function changeVotingQuorum(uint256 _newQuorum) public onlySelf {
        votingQuorum = _newQuorum;
    }

    function changeLockingPeriod(uint256 _newPeriod) public onlySelf {
        lockingPeriod = _newPeriod;
    }

    // // ====== Membership Implementation Functions INTERFACE ======

    function addMember(address _newMember) public onlySelf {
        membershipContract._addMember(_newMember);
    }

    function removeMember(address _member) public onlySelf {
        membershipContract.removeMember(_member);
    }

    // ====== Registry Implementation Functions ======

    function createRegistryValidationProposal(
        uint256 _registryId,
        address _beneficiary,
        uint256 _amount
    ) public onlySelf returns (uint256) {
        uint256 id = _createProposalCore(
            "Registry Validation",
            "Validate the registry",
            ProposalType.Registry
        );

        RegistryData storage rd = _registryData[id];
    }

    // ====== View Functions ======

    function getProposalCore(
        uint256 _id
    )
        public
        view
        returns (
            string memory name,
            string memory description,
            address proponent,
            uint256 createdAt,
            bool executed,
            ProposalType proposalType
        )
    {
        require(_id < proposalCount, "Invalid proposal ID");
        ProposalCore storage pc = _proposalCore[_id];

        return (
            pc.name,
            pc.description,
            pc.proponent,
            pc.createdAt,
            pc.executed,
            pc.proposalType
        );
    }

    function getProposalVotes(
        uint256 _id
    )
        public
        view
        returns (uint256 ayeVotes, uint256 nayVotes, uint256 abstainVotes)
    {
        require(_id < proposalCount, "Invalid proposal ID");
        ProposalVotes storage votes = _proposalVotes[_id];

        return (votes.ayeVotes, votes.nayVotes, votes.abstainVotes);
    }

    function hasVoted(uint256 _id, address _voter) public view returns (bool) {
        require(_id < proposalCount, "Invalid proposal ID");
        return _proposalVotes[_id].hasVoted[_voter];
    }

    function getTotalProposals() public view returns (uint256) {
        return proposalCount;
    }

    // ====== Membership View Functions ======

    function getMemberCount() public view returns (uint256) {
        return membershipContract.getMemberCount();
    }

    // ====== Treasury View Functions ======

    function getTreasuryContract() public view returns (address) {
        return address(treasury);
    }

    function getTreasuryBalance() public view returns (uint256) {
        return treasury.getTreasuryBalance();
    }
}
