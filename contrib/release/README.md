# Fork releases

This pipeline lives on `ci/releases` so editor changes on `dev` stay independent
of release automation. `release.json` pins the source commit, Rust toolchain,
native runners, and output platforms.

Before pushing a manifest update, create its tag at `source_commit` and prepare
a draft GitHub release. For builds with `binary_asset`, upload the existing
binary under that name; its SHA256 must match `binary_sha256`. Builds without
that field publish the binary built by the native runner.

The preparation job reads draft assets with repository push access and passes
verified binaries to the native build jobs through Actions artifacts. The
native build jobs keep read-only repository access.

The workflow builds the pinned source with strict grammar fetching and
compilation, packages each binary with its matching runtime, and verifies the
archive checksums. It publishes the draft only after every platform succeeds.
Temporary input binaries are removed before publication.

Each archive includes `BUILD-INFO.json` with the source commit, binary hash,
platform, version, and grammar count. Keep `runtime` beside `hx` when installing,
or point `HELIX_RUNTIME` at that directory.
