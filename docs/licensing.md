# Licensing and third-party material

Project-authored material is licensed under the MIT License with the following
copyright notice:

```text
Copyright (c) 2026 Modern Tiger Project
```

The top-level `LICENSE` contains the complete terms. `NOTICE` identifies
`modern-tiger-ppc` as the original project. Both files are copied into every
generated component package and the final metapackage.

Downloaded dependencies are not stored in Git. Their upstream archives retain
their own notices and license files. A release review must inspect and preserve
the terms for GCC and its arithmetic libraries, pkgconf, libffi, expat, xz,
SQLite, readline, zlib, Perl, GNU Make, OpenSSL, curl, wget, OpenSSH, Git, and the
Mozilla-derived CA bundle.

The locked GCC 7 bootstrap is a third-party prebuilt archive rather than an
upstream source release. Its origin, bundled notices, and redistribution terms
require a separate review before publishing binary packages.

Apple Security, Xcode, SDK, and operating-system binaries are not part of this
repository or its distributable payloads. Scripts may operate on the user's
locally installed copy to provide compatibility, but that copy remains on the
target Mac.

Before a binary release:

1. inventory third-party licenses from the exact locked source archives;
2. review static-link obligations for the Security shim;
3. include all required upstream license texts and notices;
4. publish source and binary notices together with the release.
