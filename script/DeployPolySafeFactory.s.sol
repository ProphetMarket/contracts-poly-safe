// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

import {Script, console} from "forge-std/Script.sol";

import {SafeProxyFactory} from "../src/PolySafeProxyFactory.sol";
import {GnosisSafeL2} from "@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol";
import {
    CompatibilityFallbackHandler
} from "@gnosis.pm/safe-contracts/contracts/handler/CompatibilityFallbackHandler.sol";
import {MultiSend} from "@gnosis.pm/safe-contracts/contracts/libraries/MultiSend.sol";

/// @param deployedSingleton        Pre-deployed GnosisSafeL2 (address(0) = deploy fresh)
/// @param deployedFallbackHandler  Pre-deployed CompatibilityFallbackHandler (address(0) = deploy fresh)
/// @param deployedFactory          Pre-deployed SafeProxyFactory (address(0) = deploy fresh)
/// @param deployedMultiSend        Pre-deployed MultiSend (address(0) = deploy fresh)
struct DeployConfig {
    address deployedSingleton;
    address deployedFallbackHandler;
    address deployedFactory;
    address deployedMultiSend;
}

/// @title DeployPolySafeFactory
/// @notice Deploys Polymarket Safe infrastructure: GnosisSafeL2 singleton, CompatibilityFallbackHandler,
///         and SafeProxyFactory.
/// @dev Idempotent: set DEPLOYED_SINGLETON, DEPLOYED_FALLBACK_HANDLER, or DEPLOYED_POLY_SAFE_FACTORY
///      environment variables to skip already-deployed contracts. Each is validated via code-size
///      check before being accepted.
///
///      Usage (keystore):
///        forge script script/DeployPolySafeFactory.s.sol --account deployer --sender <ADDR> --rpc-url $RPC_URL --broadcast
///
///      Usage (Anvil, no verification):
///        forge script script/DeployPolySafeFactory.s.sol --rpc-url http://localhost:8545 --broadcast --private-key <KEY>
contract DeployPolySafeFactory is Script {
    // ── Deployed addresses (populated during run()) ─────────────────
    address public deployedSingleton;
    address public deployedFallbackHandler;
    address public deployedFactory;
    address public deployedMultiSend;

    error MainnetNotSupported();

    /// @notice CLI entry point — signer resolved from CLI flags.
    function run() external {
        if (block.chainid == 137) revert MainnetNotSupported();

        vm.startBroadcast();
        _deploy(_configFromEnv());
        vm.stopBroadcast();
    }

    /// @notice Test entry point — broadcasts as the given address, reads config from env vars.
    function run(address deployer) external {
        if (block.chainid == 137) revert MainnetNotSupported();

        vm.startBroadcast(deployer);
        _deploy(_configFromEnv());
        vm.stopBroadcast();
    }

    /// @notice Test entry point — broadcasts as the given address, config passed directly.
    function run(address deployer, DeployConfig memory cfg) external {
        if (block.chainid == 137) revert MainnetNotSupported();

        vm.startBroadcast(deployer);
        _deploy(cfg);
        vm.stopBroadcast();
    }

    function _configFromEnv() internal view returns (DeployConfig memory) {
        return DeployConfig({
            deployedSingleton: _envAddress("DEPLOYED_SINGLETON"),
            deployedFallbackHandler: _envAddress("DEPLOYED_FALLBACK_HANDLER"),
            deployedFactory: _envAddress("DEPLOYED_POLY_SAFE_FACTORY"),
            deployedMultiSend: _envAddress("DEPLOYED_MULTI_SEND")
        });
    }

    function _deploy(DeployConfig memory cfg) internal {
        console.log("=== Poly Safe Factory Deployment ===");
        console.log("Chain ID:", block.chainid);
        console.log("");

        address singleton = _deploySingleton(cfg.deployedSingleton);
        address fallbackHandler = _deployFallbackHandler(cfg.deployedFallbackHandler);
        address factory = _deployFactory(singleton, fallbackHandler, cfg.deployedFactory);
        address multiSend = _deployMultiSend(cfg.deployedMultiSend);

        deployedSingleton = singleton;
        deployedFallbackHandler = fallbackHandler;
        deployedFactory = factory;
        deployedMultiSend = multiSend;

        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("");
        console.log("Copy-paste these into your shell:");
        console.log("");
        console.log(string(abi.encodePacked("export SAFE_SINGLETON_ADDRESS=", vm.toString(singleton))));
        console.log(string(abi.encodePacked("export FALLBACK_HANDLER_ADDRESS=", vm.toString(fallbackHandler))));
        console.log(string(abi.encodePacked("export SAFE_FACTORY_ADDRESS=", vm.toString(factory))));
        console.log(string(abi.encodePacked("export MULTI_SEND_ADDRESS=", vm.toString(multiSend))));
    }

    // ── Individual deployers ────────────────────────────────────────

    function _deploySingleton(address existing) internal returns (address) {
        if (_isDeployed(existing)) {
            console.log("[SKIP] GnosisSafeL2 already deployed at", existing);
            return existing;
        }

        GnosisSafeL2 singleton = new GnosisSafeL2();
        console.log("[DEPLOYED] GnosisSafeL2 at", address(singleton));
        return address(singleton);
    }

    function _deployFallbackHandler(address existing) internal returns (address) {
        if (_isDeployed(existing)) {
            console.log("[SKIP] CompatibilityFallbackHandler already deployed at", existing);
            return existing;
        }

        CompatibilityFallbackHandler handler = new CompatibilityFallbackHandler();
        console.log("[DEPLOYED] CompatibilityFallbackHandler at", address(handler));
        return address(handler);
    }

    function _deployFactory(address singleton, address fallbackHandler, address existing) internal returns (address) {
        if (_isDeployed(existing)) {
            console.log("[SKIP] SafeProxyFactory already deployed at", existing);
            return existing;
        }

        SafeProxyFactory factory = new SafeProxyFactory(singleton, fallbackHandler);
        console.log("[DEPLOYED] SafeProxyFactory at", address(factory));
        return address(factory);
    }

    function _deployMultiSend(address existing) internal returns (address) {
        if (_isDeployed(existing)) {
            console.log("[SKIP] MultiSend already deployed at", existing);
            return existing;
        }

        MultiSend ms = new MultiSend();
        console.log("[DEPLOYED] MultiSend at", address(ms));
        return address(ms);
    }

    // ── Helpers ─────────────────────────────────────────────────────

    function _envAddress(string memory name) internal view returns (address) {
        return vm.envOr(name, address(0));
    }

    function _isDeployed(address addr) internal view returns (bool) {
        return addr != address(0) && addr.code.length > 0;
    }
}
