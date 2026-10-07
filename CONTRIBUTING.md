# Contributing

## Prerequisites

- macOS 14.0 (Sonoma) or later
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- [SwiftLint](https://github.com/realm/SwiftLint) (`brew install swiftlint`)

## Setup

```bash
git clone https://github.com/konradmichalik/spark.git
cd spark
make setup    # installs XcodeGen and SwiftLint, points core.hooksPath at .githooks
make xcode    # generates Spark.xcodeproj
open Spark.xcodeproj
```

> [!IMPORTANT]
> `project.yml` is the source of truth for project configuration. The generated `Spark.xcodeproj` is git-ignored, so run `make xcode` again after adding or removing files. Never edit it by hand.

## Build, lint, and test

```bash
make build    # release build
make lint     # SwiftLint, strict mode
```

Or in Xcode: select your development team under **Signing & Capabilities**, then **Cmd+R**.

```bash
xcodebuild -scheme Spark -configuration Debug test
```

`make setup` installs a pre-commit hook (`.githooks/pre-commit`) that runs SwiftLint on staged Swift files and blocks the commit on any violation.

## Commit messages

Conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`, `perf:`. Release notes are generated from these between tags, so a clear prefix matters.

## Submitting a change

Open an issue first for anything beyond a small fix, to agree on the approach before writing code. Every push runs SwiftLint and an Xcode build + test in CI ([`.github/workflows/lint.yml`](.github/workflows/lint.yml), [`.github/workflows/build.yml`](.github/workflows/build.yml)); a pull request merges once both are green.

UI changes follow the [design rules](docs/design/rules.md) and carry a light and a dark screenshot in the pull request.

See [`docs/how-it-works.md`](docs/how-it-works.md) for the architecture and project structure, and [`docs/release.md`](docs/release.md) for how releases are cut.
