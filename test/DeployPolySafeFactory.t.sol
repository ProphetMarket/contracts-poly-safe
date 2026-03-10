// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {DeployPolySafeFactory, DeployConfig} from "../script/DeployPolySafeFactory.s.sol";
import {SafeProxyFactory} from "../src/PolySafeProxyFactory.sol";
import {GnosisSafeL2} from "@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol";
import {
    CompatibilityFallbackHandler
} from "@gnosis.pm/safe-contracts/contracts/handler/CompatibilityFallbackHandler.sol";

contract DeployPolySafeFactoryTest is Test {
    DeployPolySafeFactory public deployScript;
    address public deployer;

    function setUp() public {
        deployer = makeAddr("deployer");
        deployScript = new DeployPolySafeFactory();
    }

    function _emptyConfig() internal pure returns (DeployConfig memory) {
        return
            DeployConfig({
                deployedSingleton: address(0), deployedFallbackHandler: address(0), deployedFactory: address(0)
            });
    }

    // ── Fresh deployment ────────────────────────────────────────────

    function test_DeploysAllThreeContracts() public {
        deployScript.run(deployer, _emptyConfig());

        assertTrue(deployScript.deployedSingleton() != address(0), "Singleton not deployed");
        assertTrue(deployScript.deployedFallbackHandler() != address(0), "FallbackHandler not deployed");
        assertTrue(deployScript.deployedFactory() != address(0), "Factory not deployed");
    }

    function test_FactoryPointsToSingleton() public {
        deployScript.run(deployer, _emptyConfig());

        SafeProxyFactory factory = SafeProxyFactory(deployScript.deployedFactory());
        assertEq(factory.masterCopy(), deployScript.deployedSingleton());
    }

    function test_FactoryPointsToFallbackHandler() public {
        deployScript.run(deployer, _emptyConfig());

        SafeProxyFactory factory = SafeProxyFactory(deployScript.deployedFactory());
        assertEq(factory.fallbackHandler(), deployScript.deployedFallbackHandler());
    }

    // ── Mainnet guard ───────────────────────────────────────────────

    function test_RevertsOnMainnet() public {
        vm.chainId(137);
        vm.expectRevert(DeployPolySafeFactory.MainnetNotSupported.selector);
        deployScript.run();
    }

    // ── Idempotency ─────────────────────────────────────────────────

    function test_SkipsPreDeployedSingleton() public {
        GnosisSafeL2 preSingleton = new GnosisSafeL2();

        DeployConfig memory cfg = _emptyConfig();
        cfg.deployedSingleton = address(preSingleton);

        deployScript.run(deployer, cfg);

        assertEq(deployScript.deployedSingleton(), address(preSingleton));
    }

    function test_SkipsPreDeployedFallbackHandler() public {
        CompatibilityFallbackHandler preHandler = new CompatibilityFallbackHandler();

        DeployConfig memory cfg = _emptyConfig();
        cfg.deployedFallbackHandler = address(preHandler);

        deployScript.run(deployer, cfg);

        assertEq(deployScript.deployedFallbackHandler(), address(preHandler));
    }

    function test_SkipsPreDeployedFactory() public {
        GnosisSafeL2 singleton = new GnosisSafeL2();
        CompatibilityFallbackHandler handler = new CompatibilityFallbackHandler();
        SafeProxyFactory preFactory = new SafeProxyFactory(address(singleton), address(handler));

        DeployConfig memory cfg = _emptyConfig();
        cfg.deployedSingleton = address(singleton);
        cfg.deployedFallbackHandler = address(handler);
        cfg.deployedFactory = address(preFactory);

        deployScript.run(deployer, cfg);

        assertEq(deployScript.deployedFactory(), address(preFactory));
    }

    function test_SkipsAllWhenFullyDeployed() public {
        GnosisSafeL2 singleton = new GnosisSafeL2();
        CompatibilityFallbackHandler handler = new CompatibilityFallbackHandler();
        SafeProxyFactory factory = new SafeProxyFactory(address(singleton), address(handler));

        DeployConfig memory cfg = DeployConfig({
            deployedSingleton: address(singleton),
            deployedFallbackHandler: address(handler),
            deployedFactory: address(factory)
        });

        deployScript.run(deployer, cfg);

        assertEq(deployScript.deployedSingleton(), address(singleton));
        assertEq(deployScript.deployedFallbackHandler(), address(handler));
        assertEq(deployScript.deployedFactory(), address(factory));
    }
}
