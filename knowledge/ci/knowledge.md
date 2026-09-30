# CI & releases

## Practice

- **Semver** in [`VERSION`](../../VERSION) → `CFBundleShortVersionString`
- **Build number** = `git rev-list --count HEAD` → `CFBundleVersion`
- **Every push/PR** builds on `macos-14` via `.github/workflows/build.yml`
- **Every `main` push** updates GitHub Release tag `latest` with `LookAway.app.zip` (easy download URL)
- **Tag `vX.Y.Z`** publishes a versioned Release (keep tag in sync with `VERSION`)

## Install from CI

`https://github.com/zj05409/look-away/releases/latest/download/LookAway.app.zip` → unzip → Applications

## Local zip

`./build.sh --zip-only` writes `build/LookAway-<version>-<sha>.zip`
