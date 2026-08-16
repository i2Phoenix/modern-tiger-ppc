# Build guide

## Supported target

The automated build intentionally accepts only:

- PowerPC;
- Mac OS X 10.4.11;
- build `8S165`;
- Xcode 2.5 Developer Tools.

The exact build check is required because the Security shim forwards private
implementation details to the target's original Security binary.

Allow substantial free disk space and build time. A Power Mac G5 defaults to
two parallel jobs; override `JOBS` only after validating thermal and memory
headroom.

## Prepare on a modern host

```sh
cp config/target.env.example config/target.env
# Set TIGER_HOST and TIGER_USER. Configure SSH keys or use an interactive prompt.
make download
make lint
make deploy
make remote-check
make remote-verify-sources
```

`config/target.env` and the downloaded archive cache are ignored. Passwords are
not accepted by project configuration or command-line arguments.

## Build on Tiger

The build writes only to `/usr/local` and
`~/modern-tiger-ppc-build` until packages are explicitly installed.

```sh
cd ~/modern-tiger-ppc
/bin/bash scripts/tiger/check-host.sh
/bin/bash scripts/tiger/build-all.sh --yes
```

Before changing `/usr/local`, `build-all.sh` compiles a tiny SHA-256 helper with
Xcode 2.5 and verifies every locked archive. The helper uses Tiger's
CommonCrypto because its original OpenSSL 0.9.7l has no SHA-256 digest command.
The source build then uses `sudo` interactively for installation under
`/usr/local`. It never embeds or pipes a password. Logs and intermediate files
remain under `~/modern-tiger-ppc-build` and must not be copied into Git.

`build-all.sh` does not replace the SSH daemon and does not activate the
Security shim. Those changes are Installer postflight operations described in
[packaging.md](packaging.md).

## Individual steps

Scripts under `scripts/tiger` are numbered in dependency order. They are safe
to rerun after reviewing the corresponding log, but each source directory is
re-extracted before rebuilding. The Security preparation step uses
`Security.pristine` when a prior installation has already activated the shim.

## Source integrity

Every row in `config/sources.conf` has a SHA-256 field. A dash is allowed during
development, but `scripts/host/release-check.sh` rejects all unlocked entries.
Update a version, URL, and checksum together.

The GCC 7 bootstrap archive is a third-party prebuilt PowerPC toolchain. Its
locked checksum proves that every build uses the reviewed byte-for-byte input;
it does not establish upstream provenance or reproducibility. Treat that
archive as an explicit bootstrap trust boundary and review it before release.
