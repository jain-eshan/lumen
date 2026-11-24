# Contributing to Lumen

Thank you for looking. Lumen is a small app, and a clear bug report helps as much as a pull request.

## Reporting a problem

[Open an issue](https://github.com/jain-eshan/lumen/issues/new/choose). The most useful reports include:

- your macOS version and the Lumen version (shown in Finder under Get Info),
- which app you were reading, and what you selected,
- what you expected and what happened,
- the end of the log, `~/Library/Logs/Narrator/narrator.log`. It records events, never the text on screen, but read it before you paste it.

For a security problem, see [SECURITY.md](SECURITY.md) and do not open a public issue.

## Changing the code

The app is a handful of Swift files in `app/`, described in the README under "Layout". The steps to build it are under "Build it" in the README.

Every pull request, and every push to `main`, runs the self-tests, a check that the app draws its screens, and the Follow eval on GitHub ([`.github/workflows/checks.yml`](.github/workflows/checks.yml)). A red check blocks nothing by itself, but please do not ask for a review until it is green. CI builds with plain `swiftc` on macOS 15 and cannot start the voice engine, so it does not replace trying the real app. Its comments list what else it cannot cover.

Run the same checks yourself before you open a pull request:

1. Run the self-tests: `Lumen.app/Contents/MacOS/Lumen --selftest`. Every line should say PASS.
2. If you touched how Lumen reads a chat, run the Follow eval: `evals/run.sh Lumen.app`. It shows nothing on screen and does not touch your cursor. It uses the on-device director unless "Richer voice with Claude" is on in your settings, which the scenarios do not cover yet ([#14](https://github.com/jain-eshan/lumen/issues/14)).
3. Keep the change small and in the style of the code around it. No new dependency for something a few lines can do.

### Adding a failure to the eval

Every scenario in `evals/run.sh` is a failure someone met. When you find a new one:

1. Add a case to `scenarios` in `app/Simulation.swift`: the user's message, the reply, and any odd line such as a status.
2. Add a line to `SCENARIOS` in `evals/run.sh` with the words that must be spoken and the words that must not.
3. Run it against the build **without** your fix and check that it fails. A scenario that cannot fail proves nothing. Then run it with the fix.

### Things to leave alone

- **Internal names.** The bundle ID `local.narrator.app`, the settings domain, `~/Library/Logs/Narrator` and `Application Support/Narrator` still say "narrator" on purpose, so people who update keep their settings and permissions. Do not rename them.
- **The brand.** Read [`brand/BRAND.md`](brand/BRAND.md) before making anything with the Lumen name or moth on it.

## License

By contributing you agree that your work is released under the [GNU General Public License v3.0](LICENSE), like the rest of Lumen.
