// SPDX-License-Identifier: MIT
// Force-compile Safe v1.3 contracts needed for deployment.
// Vendored pattern from Polymarket/proxy-factories (packages/safe-factory/contracts/Deps.sol).

pragma solidity >=0.7.0 <0.9.0;

import {
    CompatibilityFallbackHandler
} from "@gnosis.pm/safe-contracts/contracts/handler/CompatibilityFallbackHandler.sol";
import {GnosisSafeL2} from "@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol";

/// @dev Empty contract to force Foundry to compile Safe v1.3 artifacts.
abstract contract Deps {}
