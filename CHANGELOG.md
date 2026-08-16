# Changelog

## 1.1.0

First public release for PowerPC Macs running Mac OS X Tiger 10.4.11 (`8S165`).

- GCC 7.5.0 toolchain with GMP, MPFR, ISL, MPC, and runtime libraries.
- pkgconf, libffi, expat, xz/liblzma, SQLite, readline, and zlib.
- Perl 5.42.2 and GNU Make 4.4.1.
- OpenSSL 3.5.6 LTS, root CA certificates, curl 8.19.0, and wget 1.25.0.
- OpenSSH 10.3p1 client and server integration.
- Git 2.53.0 with Tiger compatibility patches.
- SecureTransport compatibility shim providing TLS 1.2/1.3 for supported
  system client applications.
- Native Tiger installer containing 11 component packages, plus rollback tools
  for OpenSSH and the Security shim.
- Checksum-locked source downloads, target checks, package validation, and
  installed-system tests.
