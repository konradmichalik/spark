# Release Process

## Versioning

Spark follows [Semantic Versioning](https://semver.org/):
- **MAJOR** — breaking changes
- **MINOR** — new features, backward-compatible
- **PATCH** — bug fixes

## Creating a Release

1. **Update version numbers** in two files:

   - `project.yml` → `MARKETING_VERSION`
   - `Spark/Info.plist` → `CFBundleShortVersionString`

   Optionally bump `CURRENT_PROJECT_VERSION` (build number).

2. **Commit the version bump:**

   ```bash
   git add project.yml Spark/Info.plist
   git commit -m "release: v0.x.x"
   ```

3. **Tag and push:**

   ```bash
   git tag v0.x.x
   git push && git push --tags
   ```

4. **GitHub Actions takes over:**

   The `release.yml` workflow automatically:
   - Builds dual-architecture binaries (arm64 + x86_64)
   - Packages each into a DMG
   - Creates a GitHub Release with auto-generated notes
   - Generates SHA256 checksums
   - Dispatches an update to the [Homebrew tap](https://github.com/konradmichalik/homebrew-tap) to update the cask

5. **Verify:**

   - Check the [Releases page](https://github.com/konradmichalik/spark/releases) for the new release
   - Check the [Homebrew tap](https://github.com/konradmichalik/homebrew-tap/blob/main/Casks/spark.rb) for updated checksums
   - Test installation: `brew update && brew install konradmichalik/tap/spark`

## Changelog

Release notes are auto-generated from commit messages between tags. Use conventional commit prefixes (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`) to ensure clean release notes.
