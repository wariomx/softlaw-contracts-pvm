// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.19;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721Pausable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ERC721Votes} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Votes.sol";

/// @custom:security-contact gm@soft.law
contract DaoMembership is
    ERC721,
    ERC721Enumerable,
    ERC721URIStorage,
    ERC721Pausable,
    AccessControl,
    ERC721Burnable,
    EIP712,
    ERC721Votes
{
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");
    bytes32 public constant LAWYER_ROLE = keccak256("LAWYER_ROLE");
    bytes32 public constant ARBITRATOR_ROLE = keccak256("ARBITRATOR_ROLE");

    uint256 private _nextTokenId;

    struct Member {
        address memberAddress;
        string name;
        string description;
        bool isLawyer;
        bool isCreator;
        bool isArbitrator;
    }

    address[] private memberList;
    mapping(address => bool) public isMember;
    mapping(address => Member) public members;

    event MemberAdded(address indexed member, bool isLawyer, bool isCreator);
    event MemberRemoved(address indexed member);
    event MemberRoleUpdated(
        address indexed member,
        bool isLawyer,
        bool isCreator,
        bool isArbitrator
    );

    constructor(
        address _defaultAdmin,
        address _slawyer,
        address _creator,
        address _arbitrator
    ) ERC721("SoftLaw", "SLaw") EIP712("SoftLaw", "1") {
        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _grantRole(GOVERNOR_ROLE, _defaultAdmin);
        _grantRole(CREATOR_ROLE, _creator);
        _grantRole(LAWYER_ROLE, _slawyer);

        // Agregar automáticamente a los miembros cuando se asignan roles
        _addMemberWithRoles(_creator, false, true, false);
        _addMemberWithRoles(_slawyer, true, false, false);
        _addMemberWithRoles(_arbitrator, false, false, true);
        _addMemberWithRoles(_defaultAdmin, false, false, false);
    }

    function _baseURI() internal pure override returns (string memory) {
        return "www.soft.law";
    }

    function pause() public onlyRole(GOVERNOR_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(GOVERNOR_ROLE) {
        _unpause();
    }

    function safeMint(
        address to,
        string memory uri
    ) public onlyRole(GOVERNOR_ROLE) returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        return tokenId;
    }

    // Override grantRole para agregar automáticamente como miembro
    function grantRole(
        bytes32 role,
        address account
    ) public virtual override onlyRole(getRoleAdmin(role)) {
        super.grantRole(role, account);

        if (
            role == LAWYER_ROLE ||
            role == CREATOR_ROLE ||
            role == ARBITRATOR_ROLE
        ) {
            _autoAddMember(account);
        }
    }

    // Override revokeRole para actualizar el estado del miembro
    function revokeRole(
        bytes32 role,
        address account
    ) public virtual override onlyRole(getRoleAdmin(role)) {
        super.revokeRole(role, account);

        if (
            role == LAWYER_ROLE ||
            role == CREATOR_ROLE ||
            role == ARBITRATOR_ROLE
        ) {
            _updateMemberRoles(account);
        }
    }

    // Intern function to add member when a  rol is assigned
    function _autoAddMember(address _member) internal {
        bool isLawyer = hasRole(LAWYER_ROLE, _member);
        bool isCreator = hasRole(CREATOR_ROLE, _member);
        bool isArbitrator = hasRole(ARBITRATOR_ROLE, _member);

        if (!isMember[_member]) {
            _addMemberWithRoles(_member, isLawyer, isCreator, isArbitrator);
        } else {
            // Actualizar roles existentes
            members[_member].isLawyer = isLawyer;
            members[_member].isCreator = isCreator;
            members[_member].isArbitrator = isArbitrator;
            emit MemberRoleUpdated(_member, isLawyer, isCreator, isArbitrator);
        }
    }

    // Función interna para actualizar roles del miembro cuando se revoca un rol
    function _updateMemberRoles(address _member) internal {
        if (isMember[_member]) {
            bool isLawyer = hasRole(LAWYER_ROLE, _member);
            bool isCreator = hasRole(CREATOR_ROLE, _member);
            bool isArbitrator = hasRole(ARBITRATOR_ROLE, _member);

            members[_member].isLawyer = isLawyer;
            members[_member].isCreator = isCreator;
            members[_member].isArbitrator = isArbitrator;

            // Si no tiene ningún rol, remover de miembros (opcional)
            if (!isLawyer && !isCreator && !hasRole(GOVERNOR_ROLE, _member)) {
                removeMember(_member);
            } else {
                emit MemberRoleUpdated(
                    _member,
                    isLawyer,
                    isCreator,
                    isArbitrator
                );
            }
        }
    }

    // Función mejorada para agregar miembros con roles específicos
    function _addMemberWithRoles(
        address _member,
        bool _isLawyer,
        bool _isCreator,
        bool _isArbitrator
    ) internal {
        require(!isMember[_member], "Already a member");

        isMember[_member] = true;
        memberList.push(_member);

        members[_member] = Member({
            memberAddress: _member,
            name: "",
            description: "",
            isLawyer: _isLawyer,
            isCreator: _isCreator,
            isArbitrator: _isArbitrator
        });

        emit MemberAdded(_member, _isLawyer, _isCreator);
    }

    // Public function to add a member (ONLY GOVERNOR)
    function _addMember(address _member) public onlyRole(GOVERNOR_ROLE) {
        bool isLawyer = hasRole(LAWYER_ROLE, _member);
        bool isCreator = hasRole(CREATOR_ROLE, _member);
        bool isArbitrator = hasRole(ARBITRATOR_ROLE, _member);
        _addMemberWithRoles(_member, isLawyer, isCreator, isArbitrator);
    }

    // Función para remover miembro
    function removeMember(address _member) public onlyRole(GOVERNOR_ROLE) {
        require(isMember[_member], "Not a member");
        isMember[_member] = false;

        // Remover de la lista de miembros
        for (uint256 i = 0; i < memberList.length; i++) {
            if (memberList[i] == _member) {
                memberList[i] = memberList[memberList.length - 1];
                memberList.pop();
                break;
            }
        }

        delete members[_member];
        emit MemberRemoved(_member);
    }

    // Función para actualizar información del miembro
    function updateMemberInfo(
        address _member,
        string memory _name,
        string memory _description
    ) public {
        require(
            isMember[_member] &&
                (_member == msg.sender || hasRole(GOVERNOR_ROLE, msg.sender)),
            "Not authorized to update member info"
        );

        members[_member].name = _name;
        members[_member].description = _description;
    }

    // Funciones de consulta
    function getMemberCount() external view returns (uint256) {
        return memberList.length;
    }

    function getMemberList() external view returns (address[] memory) {
        return memberList;
    }

    function getMemberInfo(
        address _member
    ) external view returns (Member memory) {
        require(isMember[_member], "Not a member");
        return members[_member];
    }

    function getLawyerCount() external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < memberList.length; i++) {
            if (members[memberList[i]].isLawyer) {
                count++;
            }
        }
        return count;
    }

    function getCreatorCount() external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < memberList.length; i++) {
            if (members[memberList[i]].isCreator) {
                count++;
            }
        }
        return count;
    }

    // The following functions are overrides required by Solidity.
    function _update(
        address to,
        uint256 tokenId,
        address auth
    )
        internal
        override(ERC721, ERC721Enumerable, ERC721Pausable, ERC721Votes)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(
        address account,
        uint128 value
    ) internal override(ERC721, ERC721Enumerable, ERC721Votes) {
        super._increaseBalance(account, value);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
