# Contributing

Keep changes source-only and reproducible. Never commit downloaded archives,
build output, host configuration, credentials, keys, Apple binaries, Xcode/SDK
files, package bundles, or logs.

Before proposing a change:

```sh
make lint
```

For build or package changes, also test on exact Mac OS X 10.4.11 (`8S165`)
PowerPC, rebuild the affected component, run
`scripts/package/verify-dist.sh`, and report which hardware consumer paths were
actually exercised. Do not describe a successful compile as hardware or
end-to-end validation.

Update `config/versions.conf`, `config/sources.conf`, patches, documentation,
and checksums together when changing a dependency. Keep scripts compatible with
Tiger's Bash 2.05 and base command-line tools.

Project-authored contributions accepted into this repository are distributed
under its MIT License. Contributors must have the right to submit their work
and must preserve the licenses and notices of any derived third-party material.
