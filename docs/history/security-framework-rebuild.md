# Retired full-framework rebuild path

An earlier experiment attempted to rebuild a larger Apple Security framework
surface. It introduced SDK/source provenance problems and coupled the output to
Apple implementation material that cannot belong in a clean public repository.

The canonical design now implements only the declared SecureTransport wrapper
surface and forwards the remaining calls to a backup created from the target
Mac's own framework. Historical build trees, copied framework binaries, package
artifacts, and exploratory scripts were deliberately excluded from this
repository.

This document records the decision only. It is not a supported alternative
build path.
