// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

abstract contract BaseBlobVault {
    event Settled(uint256 feeGwei);
    uint256 public settlePriceGwei;
    bool public settled;
    modifier onlyUnsettled() { require(!settled, "settled"); _; }

    /// @dev child calls when final fee known
    function _settle(uint256 feeGwei) internal onlyUnsettled {
        settled = true;
        settlePriceGwei = feeGwei;
        emit Settled(feeGwei);
    }
} 