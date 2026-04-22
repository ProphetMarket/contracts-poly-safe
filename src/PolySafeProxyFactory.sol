// SPDX-License-Identifier: MIT
// Vendored from: https://github.com/Polymarket/proxy-factories
// Package: packages/safe-factory/contracts/SafeProxyFactory.sol
//
// Hardened for Prophet Market per audit Finding 3:
//   - CreateProxy signatures carry a per-signer nonce (non-replayable, revocable)
//   - CreateProxy signatures carry a deadline (expire automatically)
//   - Domain separator is recomputed at runtime when block.chainid changes,
//     so signatures cannot be replayed across chain forks.

pragma solidity >=0.7.0 <0.9.0;

import {GnosisSafeProxy} from "@gnosis.pm/safe-contracts/contracts/proxies/GnosisSafeProxy.sol";
import {GnosisSafe} from "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract SafeProxyFactory {
    event ProxyCreation(GnosisSafe proxy, address owner);

    address public masterCopy;

    address public fallbackHandler;

    /* EIP712 */

    // The EIP-712 typehash for the contract's domain.
    // Includes `version` per standard EIP-712 practice (OpenZeppelin EIP712 base).
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    // The EIP-712 typehash for the CreateProxy struct.
    // Includes `nonce` (per-signer counter) and `deadline` (expiry timestamp)
    // so signatures are non-replayable and bounded in time.
    bytes32 public constant CREATE_PROXY_TYPEHASH = keccak256(
        "CreateProxy(address paymentToken,uint256 payment,address paymentReceiver,uint256 nonce,uint256 deadline)"
    );

    string public constant NAME = "Prophet Market Proxy Factory";

    string public constant VERSION = "1";

    /// @notice Per-signer nonce for CreateProxy signatures. Increments on every
    /// successful `createProxy` call so a signature cannot be replayed.
    mapping(address => uint256) public nonces;

    // Cached domain separator computed at deploy time. Valid only while
    // block.chainid matches `_CACHED_CHAIN_ID`; otherwise recomputed on read.
    uint256 private immutable _CACHED_CHAIN_ID;
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;

    /* STRUCTS */

    struct Sig {
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /* CONSTRUCTOR */

    constructor(address _masterCopy, address _fallbackHandler) {
        masterCopy = _masterCopy;
        fallbackHandler = _fallbackHandler;

        _CACHED_CHAIN_ID = block.chainid;
        _CACHED_DOMAIN_SEPARATOR = _computeDomainSeparator();
    }

    /// @notice Returns the current EIP-712 domain separator.
    /// @dev Returns the cached value on the origin chain; recomputes if the
    /// chain has forked (block.chainid changed since deployment).
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparator();
    }

    function proxyCreationCode() public pure returns (bytes memory) {
        return type(GnosisSafeProxy).creationCode;
    }

    function getContractBytecode() public view returns (bytes memory) {
        return abi.encodePacked(proxyCreationCode(), abi.encode(masterCopy));
    }

    function getSalt(address user) public pure returns (bytes32) {
        return keccak256(abi.encode(user));
    }

    function computeProxyAddress(address user) external view returns (address) {
        bytes32 salt = getSalt(user);
        bytes32 bytecodeHash = keccak256(getContractBytecode());
        bytes32 _data = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, bytecodeHash));

        return address(uint160(uint256(_data)));
    }

    function createProxy(
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver,
        uint256 nonce,
        uint256 deadline,
        Sig calldata createSig
    ) external {
        require(block.timestamp <= deadline, "SafeProxyFactory: signature expired");

        // M-11: If payment is non-zero, require an explicit receiver.
        // Gnosis Safe's setup() routes payment to tx.origin when paymentReceiver == address(0),
        // which is front-runnable on public mempools.
        require(
            payment == 0 || paymentReceiver != address(0),
            "SafeProxyFactory: zero receiver with non-zero payment"
        );

        address owner = _getSigner(paymentToken, payment, paymentReceiver, nonce, deadline, createSig);

        // M-08: ECDSA.recover returns address(0) for malformed signatures.
        // Without this check, nonces[address(0)] (starting at 0) trivially passes
        // and a Safe is deployed with address(0) as owner, permanently occupying
        // the CREATE2 slot.
        require(owner != address(0), "SafeProxyFactory: invalid signature");

        require(nonces[owner]++ == nonce, "SafeProxyFactory: invalid nonce");

        _deploySafeFor(owner, paymentToken, payment, paymentReceiver);
    }

    /// @dev Deploys a 1-of-1 Safe for `owner` via CREATE2 and initializes it.
    /// Split out of `createProxy` to keep stack depth under the Solidity 0.8.4 limit.
    function _deploySafeFor(address owner, address paymentToken, uint256 payment, address payable paymentReceiver)
        private
    {
        GnosisSafe proxy;
        bytes memory deploymentData = getContractBytecode();
        bytes32 salt = getSalt(owner);
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            proxy := create2(0x0, add(0x20, deploymentData), mload(deploymentData), salt)
        }
        require(address(proxy) != address(0), "create2 call failed");

        address[] memory owners = new address[](1);
        owners[0] = owner;
        proxy.setup(owners, 1, address(0), "", fallbackHandler, paymentToken, payment, paymentReceiver);

        emit ProxyCreation(proxy, owner);
    }

    function _getSigner(
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver,
        uint256 nonce,
        uint256 deadline,
        Sig calldata sig
    ) internal virtual view returns (address) {
        bytes32 structHash = keccak256(
            abi.encode(CREATE_PROXY_TYPEHASH, paymentToken, payment, paymentReceiver, nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));

        return ECDSA.recover(digest, sig.v, sig.r, sig.s);
    }

    function _domainSeparator() internal view returns (bytes32) {
        if (block.chainid == _CACHED_CHAIN_ID) {
            return _CACHED_DOMAIN_SEPARATOR;
        }
        return _computeDomainSeparator();
    }

    function _computeDomainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(NAME)), keccak256(bytes(VERSION)), block.chainid, address(this))
        );
    }
}
