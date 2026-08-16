# SecureTransport compatibility shim

Tiger's system applications call the SecureTransport API exported by
`Security.framework`. The shim preserves that ABI boundary while using OpenSSL
for modern TLS.

## Design

- `shim/securetransport_shim.c` implements the declared SSL entry points.
- `shim/security_non_ssl_symbols.txt` records the forwarding surface observed
  on the supported Tiger Security binary; it is reference metadata, not a
  copied implementation.
- OpenSSL is linked statically into the wrapper.
- TLS is restricted to current protocol versions supported by this project.
- Non-SSL Security exports are forwarded through Tiger's `LC_SUB_UMBRELLA`
  mechanism to `SecurityBackup.framework`.
- Export lists are compared exactly at build time. Unexpected OpenSSL symbols
  are hidden by `shim/shim_unexports.txt`.

`SecurityBackup.framework` is not a redistributed binary. During package
installation, the script:

1. preserves the target's original binary as `Security.pristine` once;
2. copies that local binary into a temporary private framework;
3. changes only its Mach-O install name with Xcode 2.5
   `install_name_tool`;
4. verifies both dependency paths;
5. atomically activates the wrapper;
6. exercises `/usr/bin/security` and rolls back immediately if loading fails.

The exact 10.4.11/8S165 requirement is not relaxed. A wrapper built for one
Tiger revision must not be installed on another revision.

## Risks

This is an unsupported replacement of a core system framework on an obsolete
operating system. A defect can prevent login, keychain, authorization, network,
or Installer operations. Keep local console access and the rollback command
available. Restart immediately after activation and verify the consumer paths
listed in [validation.md](validation.md).

The compatibility surface is deliberately incomplete outside ordinary client
HTTPS. Client-certificate loading, server-side TLS, EAP-TLS keying material,
session tickets, and several internal SecureTransport calls are stubbed or only
partially mapped. Do not use the shim for VPN/EAP authentication, TLS servers,
or workloads requiring those APIs until dedicated tests and implementations
exist.

The full Apple Security framework rebuild experiment was intentionally retired;
see [history/security-framework-rebuild.md](history/security-framework-rebuild.md).
