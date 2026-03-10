# contracts-poly-safe

Standalone Foundry project for Polymarket's SafeProxyFactory. Deploys deterministic Gnosis Safe v1.3 proxy wallets using CREATE2, authorized via EIP-712 signatures.

Isolated from the main `contracts/` project to pin the compiler to **solc 0.8.4** with **Istanbul EVM** and **optimizer 200 runs** — matching Polymarket's on-chain deployment parameters. This ensures `proxyCreationCode()` produces bytecode identical to the constant in `PolySafeLib.sol`.

## Files

| File | Description |
|------|-------------|
| `src/PolySafeProxyFactory.sol` | Vendored SafeProxyFactory from [Polymarket/proxy-factories](https://github.com/Polymarket/proxy-factories) |
| `src/Deps.sol` | Force-compiles Safe v1.3 artifacts needed for deployment (GnosisSafeL2, CompatibilityFallbackHandler) |
| `script/DeployPolySafeFactory.s.sol` | Idempotent deploy script for GnosisSafeL2 singleton, CompatibilityFallbackHandler, and SafeProxyFactory |
| `test/PolySafeProxyFactory.t.sol` | Smoke tests for factory construction and deterministic address computation |
| `test/DeployPolySafeFactory.t.sol` | Deploy script tests: fresh deployment, idempotency, and mainnet guard |

## Dependencies

| Library | Version | Purpose |
|---------|---------|---------|
| `safe-contracts` | v1.3.0 | GnosisSafe, GnosisSafeL2, GnosisSafeProxy, CompatibilityFallbackHandler |
| `openzeppelin-contracts` | v4.9.6 | ECDSA signature recovery (used by factory's EIP-712 verification) |
| `forge-std` | v1.7.6 | Testing framework (pinned for solc 0.8.4 compatibility) |

## Build & Test

```shell
forge build    # Compile all contracts
forge test     # Run tests
forge fmt      # Format source files
```

## Deployment

Three contracts must be deployed in order. The SafeProxyFactory receives the singleton and fallback handler addresses in its constructor.

### Deployment order

1. **GnosisSafeL2** — the v1.3 singleton (logic contract for all Safe proxies)
2. **CompatibilityFallbackHandler** — fallback handler passed to Safe `setup()`
3. **SafeProxyFactory** — the factory, constructed with `SafeProxyFactory(singleton, handler)`

### Signing

**Never use private keys in environment variables.** All signing must use one of:

| Method | Flag | When to use |
|--------|------|-------------|
| Cast wallet (keystore) | `--account <name>` | Default for all environments |
| Hardware wallet (Ledger) | `--ledger` | Production deployments |
| Hardware wallet (Trezor) | `--trezor` | Production deployments |

Set up a cast wallet once:

```shell
cast wallet import prophet-deployer --interactive
# Enter private key when prompted (stored encrypted in ~/.foundry/keystores/)
```

### Deploy to Anvil (local testing)

```shell
# Start Anvil
anvil

# Deploy all three contracts (Anvil account 0)
forge script script/DeployPolySafeFactory.s.sol \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  --unlocked
```

### Deploy to testnet (Polygon Amoy)

```shell
forge script script/DeployPolySafeFactory.s.sol \
  --account prophet-deployer \
  --sender <DEPLOYER_ADDR> \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

### Deploy to production (hardware wallet)

```shell
forge script script/DeployPolySafeFactory.s.sol \
  --ledger \
  --sender <DEPLOYER_ADDR> \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

### Post-deployment

After deployment, record the three addresses in `.env.dev` and `.env.test`:

```shell
SAFE_FACTORY_ADDRESS=0x...    # SafeProxyFactory
SAFE_SINGLETON_ADDRESS=0x...  # GnosisSafeL2
```

Then update the CTF Exchange to use the new factory:

```shell
cast send <EXCHANGE_ADDR> "setSafeFactory(address)" <FACTORY_ADDR> \
  --account prophet-deployer \
  --rpc-url $RPC_URL
```

### Verification

After deployment, verify the bytecode matches `PolySafeLib.sol`:

```shell
# On-chain: factory.proxyCreationCode() should match the hex constant in PolySafeLib.sol
cast call <FACTORY_ADDR> "proxyCreationCode()(bytes)" --rpc-url $RPC_URL
```

## Notes

- **Compiler pinning**: solc 0.8.4 and Istanbul EVM are required to produce bytecode matching Polymarket's deployed factory. Do not upgrade without verifying bytecode compatibility.
- **Vendored source**: `PolySafeProxyFactory.sol` is vendored from [Polymarket/proxy-factories](https://github.com/Polymarket/proxy-factories) (`packages/safe-factory/contracts/SafeProxyFactory.sol`). Changes should be minimal and documented.
- **Safe v1.3**: This project uses Gnosis Safe v1.3 (not v1.4+). The `lib/safe-contracts` dependency must remain at the v1.3.0 tag.

## License

- `src/PolySafeProxyFactory.sol` — MIT (Polymarket)
- Safe v1.3 contracts — LGPL-3.0-only (Gnosis/Safe)
