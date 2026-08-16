# Validation

Validation is split by the claim it proves.

## Repository checks

`make lint` checks Bash syntax, executable modes, component metadata, secrets,
host-specific paths, AppleDouble files, package artifacts, static libraries,
dynamic libraries, and committed Mach-O files.

## Target preflight

`scripts/tiger/check-host.sh` is read-only. It reports the exact OS/build and
architecture, Xcode tools, source archive count, Security binary identity, free
space, installed tool paths, and whether pkgconf can actually start.

`scripts/tiger/verify-sources.sh` compiles the repository's small
CommonCrypto-based SHA-256 helper with Xcode 2.5, self-tests it with the empty
input digest, and verifies every deployed source archive against
`config/sources.conf`. `build-all.sh` runs this gate before its first install.

`scripts/tiger/test-installed.sh example.com` compiles the target probes with
Tiger's Xcode compiler, checks the shim and forwarding symbol surfaces, calls
Authorization and Keychain APIs, and performs live TLS handshakes through both
`dlopen` and the normally linked system framework.

## Package closure

`scripts/package/verify-dist.sh` checks all 11 component packages and validates
the metapackage when it is present. It walks every staged Mach-O file and
verifies that each dependency under `/usr/local` exists somewhere in the
aggregate payload. This guards against relying on an unpackaged library from
the build Mac.

The syslibs staging check explicitly requires `libpkgconf.5.dylib`, which is
needed by the packaged pkgconf executable.

## Hardware and consumer-path checks

After installation and restart, validate from the actual consumers:

```sh
openssl version -a
curl -Iv https://example.com/
wget --spider https://example.com/
ssh -V
git ls-remote https://github.com/git/git.git HEAD
/usr/bin/security list-keychains
```

Also verify:

- a new SSH connection without legacy client algorithm overrides;
- the negotiated SSH KEX, host key, and cipher with verbose client output;
- DNS, plain HTTP, HTTPS, and GitHub access from the Tiger host;
- Safari against modern TLS sites;
- Software Update discovery;
- Keychain and an authorization prompt;
- rollback commands from local console access.
