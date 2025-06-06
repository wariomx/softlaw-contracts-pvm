//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

contract GovernorHelpers {
    // ====== Membership Call Data Helpers ======

    function addMembershipCallData(
        address _member
    ) public pure returns (bytes memory) {
        return abi.encodeWithSignature("addMember(address)", _member);
    }

    function removeMembershipCallData(
        address _member
    ) public pure returns (bytes memory) {
        return abi.encodeWithSignature("removeMember(address)", _member);
    }

    function createChangeQuorumCallData(
        uint256 _newQuorum
    ) public pure returns (bytes memory) {
        return
            abi.encodeWithSignature("changeVotingQuorum(uint256)", _newQuorum);
    }

    function createChangeLockingPeriodCallData(
        uint256 _newPeriod
    ) public pure returns (bytes memory) {
        return
            abi.encodeWithSignature("changeLockingPeriod(uint256)", _newPeriod);
    }

    // ====== Treasury Call Data Helpers =======

    /**
     * @dev Create calldata for renouncing treasury ownership (emergency function)
     */
    function createRenounceTreasuryOwnershipCallData()
        public
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature("renounceOwnership()");
    }

    /**
     * @dev Create calldata for fund Treasury Print go BRR!!! (emergency function)
     */

    function callDataprintBrrrr(
        uint256 _amount
    ) public pure returns (bytes memory) {
        return abi.encodeWithSignature("printBrrrr(uint256)", _amount);
    }

    /**
     * @dev Create calldata for fund Treasury Print go BRR!!! (emergency function)
     */

    function callDataSpend(
        uint256 _amount,
        address _beneficiary
    ) public pure returns (bytes memory) {
        return
            abi.encodeWithSignature(
                "spend(uint256,address)",
                _amount,
                _beneficiary
            );
    }

    // ====== Copyright Registry Call Data Helpers =======

    /**
     * @dev Validate Copyright Registry
     */

    function callDataValidateCopyright(
        uint256 _id
    ) public pure returns (bytes memory) {
        return abi.encodeWithSignature("validate(uint256)", _id);
    }

    /**
     * @dev Pause Copyright Registry Contract
     */

    function callDataCopyrightPause() public pure returns (bytes memory) {
        return abi.encodeWithSignature("_pause())");
    }

    /**
     * @dev Unpause Copyright Registry contract operations
     */
    function callDataCopyrightUnpause() public pure returns (bytes memory) {
        return abi.encodeWithSignature("_unpause()");
    }

    /**
     * @dev Emergency withdrawal function in Copyright Registry
     */
    function callDataCopyrightEmergencyWithdraw()
        public
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSignature("_emergencyWithdraw");
    }

    /**
     * @dev Create calldata for setting an address as a recipient of the fees
     */
    function callDataSetFeeRecipient(
        address newRecipient
    ) public pure returns (bytes memory) {
        return
            abi.encodeWithSignature("setFeeRecipient(address)", newRecipient);
    }

    /**
     * @dev Create calldata for renouncing treasury ownership (emergency function)
     */

    function callDataUpdateRegistryFee(
        uint256 _newFee
    ) public pure returns (bytes memory) {
        return abi.encodeWithSignature("updateRegistryFee(uint256)", _newFee);
    }

    // ====== Copyright Licencing Call Data Helpers =======

    /**
     * @dev Create calldata for revoking a license
     */
    function createRevokeLicenseCallData(
        uint256 licenseId
    ) public pure returns (bytes memory) {
        return abi.encodeWithSignature("revokeLicense(uint256)", licenseId);
    }

    /**
     * @dev Create calldata for cancelling a license
     */
    function createCancelLicenseCallData(
        uint256 licenseId
    ) public pure returns (bytes memory) {
        return abi.encodeWithSignature("cancelLicense(uint256)", licenseId);
    }
}
