# Packaging

Packages are built on the Tiger PowerPC target from its installed build tree.
The distributable layout is fixed at `PREFIX=/usr/local`; alternate prefixes
may be useful for experiments but cannot be packaged by the canonical scripts.
Output is written outside the repository:

```text
~/modern-tiger-ppc-build/output/components/*.pkg
~/modern-tiger-ppc-build/output/packages/*.mpkg
```

Build and verify them with:

```sh
/bin/bash scripts/package/build-components.sh
/bin/bash scripts/package/build-metapackage.sh
/bin/bash scripts/package/verify-dist.sh
```

The component format is the native Tiger bundle layout: `Archive.pax.gz`,
`Archive.bom`, `Info.plist`, `PkgInfo`, and Installer resources. Staged payload
files are recorded as `root:wheel`. Every component and the metapackage carry
the project MIT `LICENSE` and `NOTICE` in their Installer resources so binary
redistributions preserve the Modern Tiger Project copyright and original
project attribution.

## Components

| Component | Payload | Install-time system change |
|---|---|---|
| gcc7 | Compiler, runtime, GMP, MPFR, ISL, MPC | Adds required runtime and compiler links in `/usr/local` |
| syslibs | Foundation libraries and tools in `/usr/local` | Links pkgconf entry points in `/usr/bin` |
| perl | `/usr/local/perl-5.42` | None |
| make | `/usr/local/bin/make` and documentation | Redirects Tiger gnumake after preserving it |
| openssl | `/usr/local/ssl` excluding DER roots | Links OpenSSL tools and adds certificate environment variables |
| ca-roots | DER root set | Transactionally imports roots into `X509Anchors` |
| curl | curl and libcurl in `/usr/local` | Preserves and redirects `/usr/bin/curl` |
| wget | wget in `/usr/local` | Preserves and redirects `/usr/bin/wget` |
| openssh | OpenSSH tree plus public config templates | Validates, preserves, then switches launchd and client tools |
| git | `/usr/local/git` | Preserves and redirects `/usr/bin/git` |
| security-shim | Project-built wrapper only | Creates the local backup framework, activates the wrapper, requires restart |

Every component preflight independently enforces PowerPC and exact
10.4.11/8S165, including when a `.pkg` is installed outside the metapackage.
GCC, foundation libraries, Perl, OpenSSL, and curl are fixed runtime
dependencies: making them mandatory prevents a selectable Git installation
whose HTTP transport or embedded Perl scripts cannot start.

## Rollback

The two high-impact components install explicit commands:

```sh
sudo /usr/local/sbin/modern-tiger-ppc-rollback-openssh
sudo /usr/local/sbin/modern-tiger-ppc-rollback-security-shim
```

System command backups are kept under `/usr/bin/originals`. The initial
`X509Anchors` backup is stored next to the keychain as
`X509Anchors.pre-modern-tiger-ppc`; each CA import also creates a transaction
backup and restores it automatically on failure.

## Redistribution boundary

The Security shim package contains the project wrapper and third-party OpenSSL
code. It does not contain `Security`, `Security.pristine`, Xcode tools, SDK
files, or a prebuilt `SecurityBackup.framework`. The latter is assembled from
the destination Mac's own Security binary during postflight.
