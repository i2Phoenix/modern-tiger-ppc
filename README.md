# modern-tiger-ppc

`modern-tiger-ppc` brings a modern command-line toolchain and TLS 1.2/1.3 to
PowerPC Macs running Mac OS X Tiger 10.4.11 (`8S165`). It includes
OpenSSL-based tools and a SecureTransport compatibility shim for system
applications.

Version 1.1.0 is the project's first public release.

## Components

- GCC 7.5.0 plus GMP, MPFR, ISL, MPC, and runtime libraries
- pkgconf, libffi, expat, xz/liblzma, SQLite, readline, and zlib
- Perl 5.42.2 and GNU Make 4.4.1
- OpenSSL 3.5.6 with a Mozilla-derived CA bundle
- curl 8.19.0 and wget 1.25.0
- OpenSSH 10.3p1 with Tiger PAM/CoreFoundation compatibility
- Git 2.53.0 with Tiger-specific source patches
- SecureTransport-to-OpenSSL shim for TLS 1.2/1.3 system clients

## Repository contents

The repository contains source code, patches, metadata, and build scripts.
Downloaded sources, build output, local target settings, credentials, and Apple
or Xcode binaries are excluded. The Security shim creates its framework backup
locally on the target Mac during installation.

## Quick start

Ready-made installers support only PowerPC Macs running the exact Mac OS X
10.4.11 build `8S165`.

1. On a modern computer, open the
   [GitHub Releases](https://github.com/i2Phoenix/modern-tiger-ppc/releases)
   page.
2. Under **Assets**, download the `.mpkg.zip` release asset. Verify its SHA-256
   checksum against the release notes.
3. Transfer the downloaded ZIP to the Tiger Mac using USB storage, a local file
   share, or SCP, then extract it.
4. Open the extracted `.mpkg` in Finder and run Installer. If needed, choose
   **Customize** to view the components and deselect any you do not want to
   install.
5. Restart when requested, then perform the consumer checks documented in
   [docs/validation.md](docs/validation.md).

## Building from source

The build target must be a PowerPC Mac running 10.4.11 (`8S165`) with Xcode 2.5
Developer Tools. On a modern macOS or Linux staging host:

```sh
git clone https://github.com/i2Phoenix/modern-tiger-ppc.git
cd modern-tiger-ppc
cp config/target.env.example config/target.env
# edit target.env; use SSH keys or an interactive password prompt
make download
make lint
make deploy
make remote-check
make remote-verify-sources
```

On the Tiger host, build from the deployed source tree and generate native
Installer bundles:

```sh
cd ~/modern-tiger-ppc
bash scripts/tiger/check-host.sh
bash scripts/tiger/build-all.sh --yes
bash scripts/package/build-components.sh
bash scripts/package/build-metapackage.sh
bash scripts/package/verify-dist.sh
```

Source builds modify `/usr/local`. Installing the generated packages can also
replace selected `/usr/bin` entry points, switch the SSH service, import system
roots, and activate the Security shim. Read
[docs/build.md](docs/build.md), [docs/packaging.md](docs/packaging.md), and
[docs/security-shim.md](docs/security-shim.md) before running them.

## Validation

`make lint` is safe on the host. `make remote-check` performs read-only checks
on Tiger. Generated packages are verified with `make verify-dist`; hardware and
consumer-path checks are documented in [docs/validation.md](docs/validation.md).

## License

Project-authored material is available under the [MIT License](LICENSE):
`Copyright (c) 2026 Modern Tiger Project`. The accompanying [NOTICE](NOTICE)
identifies the original `modern-tiger-ppc` project. Third-party components and
derived patches retain their own licenses; see
[docs/licensing.md](docs/licensing.md).
