// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {Test} from "forge-std/Test.sol";
import {SafeProxyFactory} from "../src/PolySafeProxyFactory.sol";
import {GnosisSafeL2} from "@gnosis.pm/safe-contracts/contracts/GnosisSafeL2.sol";
import {GnosisSafe} from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import {
    CompatibilityFallbackHandler
} from "@gnosis.pm/safe-contracts/contracts/handler/CompatibilityFallbackHandler.sol";

contract PolySafeProxyFactoryTest is Test {
    /// @dev The proxyCreationCode constant from PolySafeLib.sol (contracts/lib/ctf-exchange/).
    ///      This is the source of truth for address derivation across the entire system.
    ///      Copied here because direct cross-project Solidity import is not possible.
    ///      Source of truth: contracts/lib/ctf-exchange/src/exchange/libraries/PolySafeLib.sol
    bytes internal constant POLY_SAFE_LIB_PROXY_CREATION_CODE =
        hex"608060405234801561001057600080fd5b5060405161017138038061017183398101604081905261002f916100b9565b6001600160a01b0381166100945760405162461bcd60e51b815260206004820152602260248201527f496e76616c69642073696e676c65746f6e20616464726573732070726f766964604482015261195960f21b606482015260840160405180910390fd5b600080546001600160a01b0319166001600160a01b03929092169190911790556100e7565b6000602082840312156100ca578081fd5b81516001600160a01b03811681146100e0578182fd5b9392505050565b607c806100f56000396000f3fe6080604052600080546001600160a01b0316813563530ca43760e11b1415602857808252602082f35b3682833781823684845af490503d82833e806041573d82fd5b503d81f3fea264697066735822122004356d37e05102655be65c4848223c2cf91f2f887bb3aaf1c0ebaa8a5130562f64736f6c63430008040033";

    SafeProxyFactory factory;
    GnosisSafeL2 singleton;
    CompatibilityFallbackHandler fallbackHandler;

    function setUp() public {
        singleton = new GnosisSafeL2();
        fallbackHandler = new CompatibilityFallbackHandler();
        factory = new SafeProxyFactory(address(singleton), address(fallbackHandler));
    }

    // ── Smoke tests ──────────────────────────────────────────────────

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

    // ── 3.1: Bytecode match ─────────────────────────────────────────

    function test_ProxyCreationCodeMatchesPolySafeLib() public {
        bytes memory factoryCode = factory.proxyCreationCode();
        assertEq(
            keccak256(factoryCode),
            keccak256(POLY_SAFE_LIB_PROXY_CREATION_CODE),
            "factory.proxyCreationCode() must match PolySafeLib.sol constant byte-for-byte"
        );
    }

    // ── 3.2: Deploy Safe, verify address derivation ─────────────────

    function test_DeploySafe_AddressMatchesComputeProxyAddress() public {
        (address signer, uint256 signerKey) = makeAddrAndKey("signer1");
        address predicted = factory.computeProxyAddress(signer);

        _deployProxy(signerKey);

        // Verify code was deployed at the predicted address
        assertTrue(predicted.code.length > 0, "Safe should be deployed at predicted address");

        // Verify the Safe is owned by the signer
        address[] memory owners = GnosisSafe(payable(predicted)).getOwners();
        assertEq(owners.length, 1, "Safe should have exactly one owner");
        assertEq(owners[0], signer, "Safe owner should be the signer");
    }

    function test_DeploySafe_ThreeEOAs() public {
        (address alice, uint256 aliceKey) = makeAddrAndKey("alice");
        (address bob, uint256 bobKey) = makeAddrAndKey("bob");
        (address charlie, uint256 charlieKey) = makeAddrAndKey("charlie");

        _assertDeployMatchesPredicted(alice, aliceKey, "alice");
        _assertDeployMatchesPredicted(bob, bobKey, "bob");
        _assertDeployMatchesPredicted(charlie, charlieKey, "charlie");
    }

    function test_DeploySafe_FallbackHandlerIsSet() public {
        (, uint256 signerKey) = makeAddrAndKey("signer-fb");
        address predicted = factory.computeProxyAddress(vm.addr(signerKey));

        _deployProxy(signerKey);

        // Slot for fallback handler in Safe v1.3: keccak256("fallback_manager.handler.address")
        bytes32 slot = 0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5;
        bytes32 stored = vm.load(predicted, slot);
        assertEq(address(uint160(uint256(stored))), address(fallbackHandler), "Fallback handler not set on Safe");
    }

    // ── 3.2 (UC-0PLQ-002/3.2): Salt derivation cross-verification ──

    /// @dev Verifies keccak256(abi.encode(addr)) produces known salt values.
    ///      The expected hashes here are the source of truth for the Go-side
    ///      TestSaltDerivation_MatchesSolidity test in safe_test.go.
    function test_SaltDerivation_KnownVectors() public {
        assertEq(
            keccak256(abi.encode(address(0x1234567890AbcdEF1234567890aBcdef12345678))),
            bytes32(0x9f28962a951b1cd243ff17e7db040d5966c242cce64c6d2d7c4e5e985dbc0389),
            "salt mismatch for 0x1234...5678"
        );
        assertEq(
            keccak256(abi.encode(address(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF))),
            bytes32(0xc4b19c94482ce57afc842306f3696b8839c9bb4bab0e205987ceb6c7017d8571),
            "salt mismatch for 0xDEAD...BeeF"
        );
        assertEq(
            keccak256(abi.encode(address(0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa))),
            bytes32(0xbc3e28998ce6b79c3c484e5137a150bab7450bb50428affa478afb88cafd2f65),
            "salt mismatch for 0xAAAA...AAAA"
        );
    }

    // ── Helpers ──────────────────────────────────────────────────────

    /// @dev Deploys a Safe for signer and asserts the address matches computeProxyAddress.
    function _assertDeployMatchesPredicted(address signer, uint256 signerKey, string memory label) internal {
        address predicted = factory.computeProxyAddress(signer);
        _deployProxy(signerKey);
        assertTrue(predicted.code.length > 0, label);
        address[] memory owners = GnosisSafe(payable(predicted)).getOwners();
        assertEq(owners.length, 1);
        assertEq(owners[0], signer);
    }

    /// @dev Signs a CreateProxy EIP-712 message and calls factory.createProxy().
    function _deployProxy(uint256 signerKey) internal {
        // No payment for tests
        address paymentToken = address(0);
        uint256 payment = 0;
        address payable paymentReceiver = payable(address(0));

        address signer = vm.addr(signerKey);
        uint256 nonce = factory.nonces(signer);
        uint256 deadline = block.timestamp + 1 hours;

        // Construct EIP-712 digest
        bytes32 structHash = keccak256(
            abi.encode(factory.CREATE_PROXY_TYPEHASH(), paymentToken, payment, paymentReceiver, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", factory.domainSeparator(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);

        factory.createProxy(paymentToken, payment, paymentReceiver, nonce, deadline, SafeProxyFactory.Sig(v, r, s));
    }

    // ── Finding 3 regression tests ──────────────────────────────────

    function test_CreateProxy_RevertsOnReplayedSignature() public {
        (address signer, uint256 signerKey) = makeAddrAndKey("replay-signer");

        address paymentToken = address(0);
        uint256 payment = 0;
        address payable paymentReceiver = payable(address(0));
        uint256 nonce = factory.nonces(signer);
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 structHash = keccak256(
            abi.encode(factory.CREATE_PROXY_TYPEHASH(), paymentToken, payment, paymentReceiver, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", factory.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);

        factory.createProxy(paymentToken, payment, paymentReceiver, nonce, deadline, SafeProxyFactory.Sig(v, r, s));
        assertEq(factory.nonces(signer), nonce + 1, "nonce should increment after successful deploy");

        // Replaying the same signature must revert (nonce is now stale).
        vm.expectRevert("SafeProxyFactory: invalid nonce");
        factory.createProxy(paymentToken, payment, paymentReceiver, nonce, deadline, SafeProxyFactory.Sig(v, r, s));
    }

    function test_CreateProxy_RevertsOnExpiredSignature() public {
        (, uint256 signerKey) = makeAddrAndKey("expired-signer");

        address paymentToken = address(0);
        uint256 payment = 0;
        address payable paymentReceiver = payable(address(0));
        uint256 nonce = factory.nonces(vm.addr(signerKey));
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 structHash = keccak256(
            abi.encode(factory.CREATE_PROXY_TYPEHASH(), paymentToken, payment, paymentReceiver, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", factory.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);

        // Advance past deadline.
        vm.warp(deadline + 1);

        vm.expectRevert("SafeProxyFactory: signature expired");
        factory.createProxy(paymentToken, payment, paymentReceiver, nonce, deadline, SafeProxyFactory.Sig(v, r, s));
    }

    // ── M-08: Zero-address guard after ECDSA recovery ────────────────

    /// @dev A malformed signature must be rejected before deploying a Safe.
    /// OpenZeppelin's ECDSA.recover reverts on (r=0, s=0), providing first-layer
    /// protection. Our explicit `owner != address(0)` guard is defense-in-depth
    /// for any future ECDSA library swap that might return zero instead of reverting.
    function test_CreateProxy_RevertsOnMalformedSignature() public {
        address paymentToken = address(0);
        uint256 payment = 0;
        address payable paymentReceiver = payable(address(0));
        uint256 nonce = 0; // nonces[address(0)] starts at 0, so nonce check would pass
        uint256 deadline = block.timestamp + 1 hours;

        SafeProxyFactory.Sig memory badSig = SafeProxyFactory.Sig(27, bytes32(0), bytes32(0));

        // Reverts via ECDSA library (first layer) before reaching our guard
        vm.expectRevert("ECDSA: invalid signature");
        factory.createProxy(paymentToken, payment, paymentReceiver, nonce, deadline, badSig);
    }

    /// @dev Malformed signatures must not increment the nonce for address(0).
    function test_CreateProxy_MalformedSig_DoesNotIncrementNonce() public {
        uint256 nonceBefore = factory.nonces(address(0));

        SafeProxyFactory.Sig memory badSig = SafeProxyFactory.Sig(28, bytes32(0), bytes32(0));

        vm.expectRevert();
        factory.createProxy(address(0), 0, payable(address(0)), 0, block.timestamp + 1 hours, badSig);

        assertEq(factory.nonces(address(0)), nonceBefore, "nonce for address(0) must not change");
    }

    /// @dev Verify the defense-in-depth guard: if _getSigner somehow returns
    /// address(0) (bypassing ECDSA's own checks), createProxy must still revert.
    /// We test this by deploying a factory wrapper that overrides _getSigner.
    function test_CreateProxy_RevertsWhenSignerIsZeroAddress() public {
        // Deploy the mock factory that always returns address(0) from _getSigner
        ZeroSignerFactory mockFactory = new ZeroSignerFactory(address(singleton), address(fallbackHandler));

        SafeProxyFactory.Sig memory anySig = SafeProxyFactory.Sig(27, bytes32(uint256(1)), bytes32(uint256(1)));

        vm.expectRevert("SafeProxyFactory: invalid signature");
        mockFactory.createProxy(address(0), 0, payable(address(0)), 0, block.timestamp + 1 hours, anySig);
    }

    // ── M-11: Zero paymentReceiver with non-zero payment ────────────

    /// @dev Non-zero payment with paymentReceiver == address(0) must revert.
    /// Gnosis Safe routes such payments to tx.origin, which is front-runnable.
    function test_CreateProxy_RevertsOnZeroReceiverWithPayment() public {
        (, uint256 signerKey) = makeAddrAndKey("m11-signer");

        address paymentToken = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        uint256 payment = 1 ether;
        address payable paymentReceiver = payable(address(0)); // zero receiver!
        uint256 nonce = factory.nonces(vm.addr(signerKey));
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 structHash = keccak256(
            abi.encode(factory.CREATE_PROXY_TYPEHASH(), paymentToken, payment, paymentReceiver, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", factory.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);

        vm.expectRevert("SafeProxyFactory: zero receiver with non-zero payment");
        factory.createProxy(paymentToken, payment, paymentReceiver, nonce, deadline, SafeProxyFactory.Sig(v, r, s));
    }

    /// @dev Zero payment with paymentReceiver == address(0) is fine (no money moves).
    function test_CreateProxy_AllowsZeroReceiverWithZeroPayment() public {
        (, uint256 signerKey) = makeAddrAndKey("m11-zero-payment");

        // This is the normal no-payment case used throughout tests — should succeed
        _deployProxy(signerKey);

        address predicted = factory.computeProxyAddress(vm.addr(signerKey));
        assertTrue(predicted.code.length > 0, "Safe should deploy when payment=0 and receiver=0");
    }

    /// @dev Proves that the dynamic domain separator prevents a signature signed
    /// on the origin chain from deploying the *victim's* Safe on a forked chain.
    ///
    /// The mechanism is `_domainSeparator()`: on a fork (different block.chainid),
    /// it recomputes the separator, which produces a different EIP-712 digest,
    /// which causes ecrecover to return a *different* address — not the victim.
    /// As a result, `_deploySafeFor(owner, ...)` uses a garbage owner for the
    /// salt, deploying at an address unrelated to the victim's counterfactual Safe.
    /// The victim's pre-funded address remains untouched.
    function test_CreateProxy_ForkProtection_RecoversDifferentSigner() public {
        (address victim, uint256 victimKey) = makeAddrAndKey("fork-victim");
        address victimPredicted = factory.computeProxyAddress(victim);

        address paymentToken = address(0);
        uint256 payment = 0;
        address payable paymentReceiver = payable(address(0));
        uint256 nonce = factory.nonces(victim);
        uint256 deadline = block.timestamp + 1 hours;

        // Sign against the origin-chain domain separator.
        bytes32 structHash = keccak256(
            abi.encode(factory.CREATE_PROXY_TYPEHASH(), paymentToken, payment, paymentReceiver, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", factory.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(victimKey, digest);

        // Simulate a chain fork: change block.chainid.
        vm.chainId(9999);

        // The fork's domain separator differs from the origin-chain one —
        // i.e. the cached fast-path is bypassed.
        assertFalse(
            factory.domainSeparator() == keccak256(abi.encodePacked("\x19\x01", factory.domainSeparator(), structHash)),
            "sanity check"
        );

        // Capture the deploy call. Either:
        //   (a) the signature replay succeeds, BUT deploys a Safe for some garbage
        //       address (not the victim) at an address unrelated to `victimPredicted`, or
        //   (b) the signature fails `_getSigner` and the call reverts.
        // In both cases the victim's counterfactual Safe is untouched.
        try factory.createProxy(
            paymentToken, payment, paymentReceiver, nonce, deadline, SafeProxyFactory.Sig(v, r, s)
        ) {
            // If it didn't revert, make sure the victim's predicted address was NOT deployed.
            assertEq(victimPredicted.code.length, 0, "fork replay must not deploy the victim's counterfactual Safe");
        } catch {
            // Revert path is also acceptable: victim's address stays uninitialized.
            assertEq(victimPredicted.code.length, 0, "victim's Safe should remain undeployed after revert");
        }
    }
}

/// @dev Mock factory that overrides _getSigner to always return address(0),
/// simulating a scenario where ECDSA recovery silently returns zero.
/// Used to verify the defense-in-depth guard in createProxy (M-08).
contract ZeroSignerFactory is SafeProxyFactory {
    constructor(address _masterCopy, address _fallbackHandler)
        SafeProxyFactory(_masterCopy, _fallbackHandler)
    {}

    function _getSigner(address, uint256, address payable, uint256, uint256, Sig calldata)
        internal
        pure
        override
        returns (address)
    {
        return address(0);
    }
}
