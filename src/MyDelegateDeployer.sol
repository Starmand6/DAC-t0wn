// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IJBController3_1} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBController3_1.sol";
import {IJBDelegatesRegistry} from "@jbx-protocol/juice-delegates-registry/src/interfaces/IJBDelegatesRegistry.sol";
import {IJBDirectory} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import {IJBSingleTokenPaymentTerminalStore3_1_1} from
    "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBSingleTokenPaymentTerminalStore3_1_1.sol";
import {DominantJuice} from "./DominantJuice.sol";

/// @notice A contract that deploys a delegate contract.
contract MyDelegateDeployer {
    event DelegateDeployed(uint256 projectId, DominantJuice delegate, IJBDirectory directory, address caller);

    /// @notice This contract's current nonce, used for the Juicebox delegates registry.
    uint256 internal _nonce;

    /// @notice An implementation of the Delegate being deployed.
    DominantJuice public delegate;

    /// @notice A contract that stores references to deployer contracts of delegates.
    IJBDelegatesRegistry public immutable delegatesRegistry;

    /// @notice Mapping to easily find the delegate/clone address for each projectID.
    mapping(uint256 => address) public delegateOfProject;

    /// @param _delegatesRegistry A contract that stores references to delegate deployer contracts.
    constructor(IJBDelegatesRegistry _delegatesRegistry) {
        //delegateImplementation = _delegateImplementation;
        delegatesRegistry = _delegatesRegistry;
    }

    /// @notice Deploys a DominantJuice delegate for the provided project ID.
    /// @param _projectID The ID of the project for which the delegate will be deployed.
    /// @param _cycleTarget Funding target for the dominant assurance cycle/campaign.
    /// @param _minimumPledgeAmount Minimum amount that payers can pledge.
    /// @param _maxEarlyPledgers Maximum allowed early plegers for funding cycle.
    /// @return delegate The address of the newly deployed DominantJuice delegate.
    function deployDelegateFor(
        address _owner,
        uint256 _projectID,
        uint256 _cycleTarget,
        uint256 _minimumPledgeAmount,
        uint32 _maxEarlyPledgers,
        IJBController3_1 _controller,
        IJBDirectory _directory,
        IJBSingleTokenPaymentTerminalStore3_1_1 _paymentTerminalStore
    ) external returns (DominantJuice) {
        //address delegateAddress = address(delegate);
        //address payable payableDelegateAddress = payable(delegateAddress);

        // Deploy the delegate clone from the implementation and map to projectID.
        // delegate = DominantJuice(Clones.clone(delegateAddress));
        delegate = new DominantJuice();
        delegateOfProject[_projectID] = address(delegate);

        // Initialize the DominantJuice delegate.
        delegate.initialize(
            _projectID, _cycleTarget, _minimumPledgeAmount, _maxEarlyPledgers, _controller, _paymentTerminalStore
        );

        // Transfer delegate ownership to owner address input. launchProjectFor() owner address
        // is now the owner of the dominant assurance delegate contract clone.
        delegate.transferOwnership(_owner);

        // Add the delegate to the registry. Contract nonce starts at 1.
        // delegatesRegistry.addDelegate(address(this), ++_nonce);

        emit DelegateDeployed(_projectID, delegate, _directory, msg.sender);

        return delegate;
    }

    function getDelegateOfProject(uint256 _projectID) external view returns (address) {
        return delegateOfProject[_projectID];
    }
}
