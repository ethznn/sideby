# Contributing to Sideby

Thanks for your interest in contributing to Sideby.

Sideby is pre-1.0 software, so product ideas, usability feedback, bug reports, and careful macOS testing are all useful.

## Setup

Requirements:

- macOS 14 or later.
- Xcode with a Swift 6 toolchain.

Run tests:

```bash
swift test
```

Build local app bundles:

```bash
scripts/build_app_bundle.sh
scripts/build_dev_app_bundle.sh
```

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the short development reference.

## Pull Requests

- Keep changes focused.
- Explain the problem and the approach.
- Add or update tests for logic changes.
- Run `swift test` before submitting.
- Include screenshots or recordings for visible UI changes when helpful.

For permission flow, global input, synthetic input, Space switching, app signing, sandboxing, or distribution changes, open an issue first. Those areas have user trust and release implications.

## Technical Boundaries

Sideby intentionally avoids private Mission Control and Spaces APIs. The current technical boundaries are listed in [docs/DECISIONS.md](docs/DECISIONS.md).

These boundaries are meant to protect users and keep the project maintainable. They are not intended to prevent new product ideas.

## License

By submitting a contribution, you agree that your contribution is licensed under the MIT License.
