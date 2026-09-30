# CI & releases

## Practice

- **Semver** in [`VERSION`](../../VERSION) → `CFBundleShortVersionString`
- **Build number** = `git rev-list --count HEAD` → `CFBundleVersion`
- **Every push/PR** builds on `macos-14` via `.github/workflows/build.yml`
- **Every `main` push** updates GitHub Release tag `latest` with `LookAway.app.zip` (easy download URL)
- **Tag `vX.Y.Z`** publishes a versioned Release (keep tag in sync with `VERSION`)
- **Manual dispatch with `release: true`** creates tag `v<VERSION>` at the built commit and publishes the same Release (useful when tags cannot be pushed directly)
- Release notes come from the `## <VERSION>` section of `CHANGELOG.md`
- `build.sh` produces a universal (arm64 + x86_64) binary

## Install from CI

`https://github.com/zj05409/look-away/releases/latest/download/LookAway.app.zip` → unzip → Applications

## Local zip

`./build.sh --zip-only` writes `build/LookAway-<version>-<sha>.zip`
