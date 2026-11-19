# Narrator

A Mac menu bar app that reads a part of your screen aloud in a natural voice, follows new Claude replies as they arrive, and lets you ask questions about what's on screen.

Everything runs on your Mac. The voice is Kokoro, running locally. Reading uses no tokens and no API keys. Two optional features use your Claude plan through the `claude` command: richer reading direction (off by default) and Ask.

Needs an Apple silicon Mac on macOS 14 or later.

## Install

Download `Narrator.dmg` from the [latest release](https://github.com/jain-eshan/narrator/releases/latest), open it, and drag Narrator to Applications. The app is self-signed, so the first time, right-click it and choose Open. The file is about 900 MB because the voice engine and model are inside, so it works offline.

On first launch Nox, the owl, asks for Screen Recording and Accessibility permission and walks you through it. Narrator only looks at the area you select.

## What it does

- Select an area, say what it's for, and it reads it with a mood that fits (Calm, Warm, Serious, News, Story, or Auto).
- Follow mode keeps reading new text as it appears, so a Claude chat is read as it streams in.
- Jump lets you click any sentence and continue from there.
- Ask answers spoken or typed questions about what's on screen. Spoken questions work through Wispr Flow if you have it, or you can type. Ask needs the `claude` command installed.
- Nox lives by the notch, walks to the line being read, and reacts to what Narrator is doing. Turn it off from the menu bar.

## Shortcuts

All shortcuts use Option + Shift.

| Keys | What it does |
|---|---|
| Option + Shift + 4 | Select an area to read |
| Option + Shift + Space | Play or pause |
| Option + Shift + , | Skip back |
| Option + Shift + . | Skip forward |
| Option + Shift + A | Ask a question |
| Option + Shift + J | Jump to a sentence |
| Esc | Cancel a selection or jump |

## Build it

You need Xcode command line tools and [uv](https://docs.astral.sh/uv/). The app is one Swift file, `app/main.swift`, plus a Python voice service, `scripts/kokoro_server.py`.

```bash
uv venv envs/kokoro --python 3.12
uv pip install --python envs/kokoro/bin/python -r requirements.txt
HF_HOME=models envs/kokoro/bin/python -c "from huggingface_hub import snapshot_download; snapshot_download('mlx-community/Kokoro-82M-bf16')"
```

Create a self-signed code signing identity and put its files in `.signing/` (`identity`, `keychain-password`, `narrator.keychain-db`). `build.sh` reads them. Then:

```bash
zsh app/build.sh --full    # builds Narrator.app with the voice engine and model inside (about 1.9 GB)
zsh app/package.sh         # optional: makes dist/Narrator.dmg to share
```

These steps have not been tried on a clean machine yet. If one fails, please open an issue.

## Layout

- `app/main.swift`: the whole app
- `app/build.sh`, `app/package.sh`: build and disk image
- `scripts/kokoro_server.py`: the speech service the app starts
- `scripts/`: the other files are voice experiments from early development
- `requirements.txt`: the pinned Python packages
- `LICENSE`: GPL-3.0

## License

Narrator is licensed under the [GNU General Public License v3.0](LICENSE). The voice stack includes espeak-ng and phonemizer, which are GPL licensed, so the whole app is released under the GPL. This repository is the source for every release.

The app is signed with a self-signed identity. A paid Apple Developer ID would remove the "unidentified developer" prompt.
