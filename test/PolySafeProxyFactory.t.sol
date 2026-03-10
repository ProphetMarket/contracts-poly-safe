// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

import {Test} from "forge-std/Test.sol";
import {SafeProxyFactory} from "../src/PolySafeProxyFactory.sol";
import {GnosisSafeL2} from "@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol";
import {
    CompatibilityFallbackHandler
} from "@gnosis.pm/safe-contracts/contracts/handler/CompatibilityFallbackHandler.sol";

contract PolySafeProxyFactoryTest is Test {
    SafeProxyFactory factory;
    GnosisSafeL2 singleton;
    CompatibilityFallbackHandler fallbackHandler;

    function setUp() public {
        singleton = new GnosisSafeL2();
        fallbackHandler = new CompatibilityFallbackHandler();
        factory = new SafeProxyFactory(address(singleton), address(fallbackHandler));
    }

    function test_MasterCopyIsSet() public {
        assertEq(factory.masterCopy(), address(singleton));
    }

    function test_FallbackHandlerIsSet() public {
        assertEq(factory.fallbackHandler(), address(fallbackHandler));
    }

    function test_ProxyCreationCodeIsNonEmpty() public {
        bytes memory code = factory.proxyCreationCode();
        assertTrue(code.length > 0, "proxyCreationCode should be non-empty");
    }

    function test_ComputeProxyAddressIsDeterministic() public {
        address user = address(0xBEEF);
        address addr1 = factory.computeProxyAddress(user);
        address addr2 = factory.computeProxyAddress(user);
        assertEq(addr1, addr2, "computeProxyAddress should be deterministic");
        assertFalse(addr1 == address(0), "computed address should not be zero");
    }

    function test_DifferentUsersGetDifferentAddresses() public {
        address user1 = address(0xBEEF);
        address user2 = address(0xCAFE);
        address addr1 = factory.computeProxyAddress(user1);
        address addr2 = factory.computeProxyAddress(user2);
        assertFalse(addr1 == addr2, "different users should get different Safe addresses");
    }
}
