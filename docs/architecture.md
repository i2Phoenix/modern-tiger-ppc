# Architecture

The repository has one canonical build path. Historical packages and ad-hoc
host scripts are deliberately not part of it.

```text
config/sources.conf
        |
        v
host download -> ignored source cache -> deploy over SSH
                                      |
                                      v
                              Tiger source builds
                                      |
                         /usr/local + build output
                                      |
                                      v
                            component staging
                                      |
                         11 Tiger .pkg bundles
                                      |
                                      v
                              one .mpkg bundle
```

## Trust boundaries

- The public repository contains text source, patches, tests, and metadata.
- Downloaded upstream archives are checksum-verified and remain ignored.
- Build and package output lives under `~/modern-tiger-ppc-build` on Tiger.
- Target connection settings stay in ignored `config/target.env` on the host.
- Apple system binaries never cross into the repository or a package payload.

## Build layers

1. GCC 7 and its arithmetic libraries provide a compiler and runtime.
2. The Tiger linker translator adapts three modern Darwin option names and
   deliberately drops unsupported `-rpath` pairs.
3. Foundation libraries provide pkgconf, compression, XML, SQLite, readline,
   and FFI support.
4. Perl and GNU Make provide current build tools.
5. OpenSSL and the CA bundle provide command-line TLS.
6. curl, wget, OpenSSH, and Git are built against those layers.
7. The Security shim maps the Tiger SecureTransport surface to
   statically linked OpenSSL and forwards other Security APIs to a local copy of
   the target system library.

See [security-shim.md](security-shim.md) for the framework boundary and
[packaging.md](packaging.md) for activation behavior.
