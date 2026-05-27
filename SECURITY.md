# Security Policy

## Supported Versions

Sideby is pre-1.0 software. Security fixes target the default branch until tagged releases are published.

## Reporting a Vulnerability

Please do not open a public issue for security vulnerabilities.

When the GitHub repository is public, use GitHub's private vulnerability reporting if it is enabled. If private vulnerability reporting is not available, contact the maintainer through the repository owner's public GitHub profile or another private channel published by the project.

Include:

- Affected commit, tag, or build.
- macOS version.
- Clear reproduction steps.
- Expected and actual behavior.
- Any logs, crash reports, or screenshots that do not expose private information.
- Whether the issue affects permissions, input capture, event posting, Apple Events, signing, or update distribution.

The maintainer will acknowledge valid reports, investigate, and coordinate disclosure based on severity and exploitability.

## Security-Relevant Areas

Please treat these areas as sensitive:

- Accessibility permission flow.
- Event tap input handling.
- Global shortcuts.
- Synthetic input and Space switching.
- Apple Events and System Events Automation.
- App bundle signing, entitlements, and direct distribution packaging.
- Local settings persistence.

Sideby must not store typed input, raw input events, screenshots, private Space IDs, app bundle IDs, window IDs, or hidden Mission Control state.
