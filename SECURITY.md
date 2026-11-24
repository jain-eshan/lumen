# Security

## Reporting a vulnerability

Please do not open a public issue for a security problem. Use **Report a vulnerability** under the [Security tab](https://github.com/jain-eshan/lumen/security/advisories/new) of this repository, which sends the report privately to the maintainer.

Include what you found, how to reproduce it and the Lumen and macOS versions. You will get a reply as soon as the maintainer can, and credit in the release notes if you want it.

## What Lumen can see

- It looks only at the screen area you select, and only while it is reading. It needs Screen Recording and Accessibility permission for that.
- Reading runs on your Mac. Nothing is uploaded and there is no account or analytics.
- Two optional features, Ask and "Richer voice with Claude", send text through your own `claude` command and Claude plan. Lumen never holds an API key.
- Note for Claude puts what you mark on your clipboard and saves a file in Downloads. It sends nothing itself.
- The diagnostic log and History are stored on your Mac. The log records events, never the text on screen. See "Privacy" in the README for the full list.

## Supported versions

Only the [latest release](https://github.com/jain-eshan/lumen/releases/latest) is supported.

## Signing

Lumen is signed with a self-signed identity rather than an Apple Developer ID, so macOS shows an "unidentified developer" prompt the first time. Check the SHA-256 on the release page against the file you downloaded. A notarized build is tracked in [Issues](https://github.com/jain-eshan/lumen/issues/18).
