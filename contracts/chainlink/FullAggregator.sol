// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Aggregator.sol";
import "../interfaces/IFullAggregator.sol";

contract FullAggregator is Aggregator, IFullAggregator {
    struct SubmissionInfo {
        bool confirmed; // whether is confirmed
        uint256 confirmations; // received confirmations count
        mapping(address => bool) hasVerified; // verifier => has already voted
    }

    mapping(bytes32 => SubmissionInfo) public getSubmissionInfo; // mint id => submission info

    event Confirmed(bytes32 submissionId, address operator); // emitted once the submission is confirmed by one oracle
    event SubmissionApproved(bytes32 submissionId); // emitted once the submission is confirmed by min required aount of oracles

    /// @dev Constructor that initializes the most important configurations.
    /// @param _minConfirmations Minimal required confirmations.
    /// @param _corePayment Oracle reward.
    /// @param _bonusPayment Oracle reward.
    /// @param _coreToken Link token to pay to oracles.
    /// @param _bonusToken DBR token to pay to oracles.
    constructor(
        uint256 _minConfirmations,
        uint256 _corePayment,
        uint256 _bonusPayment,
        IERC20 _coreToken,
        IERC20 _bonusToken
    )
        Aggregator(
            _minConfirmations,
            _corePayment,
            _bonusPayment,
            _coreToken,
            _bonusToken
        )
    {}

    /// @dev Confirms few transfer requests.
    /// @param _submissionIds Submission identifiers.
    function submitMany(bytes32[] memory _submissionIds)
        external
        override
        onlyOracle
    {
        for (uint256 i; i < _submissionIds.length; i++) {
            _submit(_submissionIds[i]);
        }
    }

    /// @dev Confirms the transfer request.
    /// @param _submissionId Submission identifier.
    function submit(bytes32 _submissionId) external override onlyOracle {
        _submit(_submissionId);
    }

    /// @dev Confirms single transfer request.
    /// @param _submissionId Submission identifier.
    function _submit(bytes32 _submissionId) internal {
        SubmissionInfo storage submissionInfo =
            getSubmissionInfo[_submissionId];
        require(
            !submissionInfo.hasVerified[msg.sender],
            "submit: submitted already"
        );
        submissionInfo.confirmations += 1;
        submissionInfo.hasVerified[msg.sender] = true;
        if (submissionInfo.confirmations >= minConfirmations) {
            submissionInfo.confirmed = true;
            emit SubmissionApproved(_submissionId);
        }
        _payOracle(msg.sender);
        emit Confirmed(_submissionId, msg.sender);
    }

    /// @dev Returns whether transfer request is confirmed.
    /// @param _submissionId Submission identifier.
    /// @return Whether transfer request is confirmed.
    function isSubmissionConfirmed(bytes32 _submissionId)
        external
        view
        override
        returns (bool)
    {
        return
            getSubmissionInfo[_submissionId].confirmed ||
            getSubmissionInfo[_submissionId].confirmations >= minConfirmations;
    }
}
