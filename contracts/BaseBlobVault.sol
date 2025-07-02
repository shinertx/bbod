// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

abstract contract BaseBlobVault {
    /// @notice Emitted when a series or round is settled with the final fee.
    event Settled(uint256 feeGwei);

    /// @dev Child contracts call to emit the settlement event.  The previous
    ///      storage variables were removed to avoid duplicate state.
    function _settle(uint256 feeGwei) internal {
        emit Settled(feeGwei);
    }
}
