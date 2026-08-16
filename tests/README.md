# Tiger runtime tests

The C programs in this directory are small target-side probes, not portable
unit tests. Compile and run the supported set on the G5 with:

```sh
/bin/bash scripts/tiger/test-installed.sh example.com
```

The runner does not modify Security.framework. It checks the active framework's
declared shim and forwarding symbols, exercises Authorization and Keychain
calls, creates SecureTransport contexts through both `dlopen` and normal
framework linking, and performs two real HTTPS handshakes.

Run it after a restart following Security shim installation. A successful run
does not cover the explicitly unsupported EAP-TLS, server TLS, or client
certificate paths documented in `docs/security-shim.md`.
