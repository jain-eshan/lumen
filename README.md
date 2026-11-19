# Narrator

A Mac menu bar app that reads a part of your screen aloud in a natural voice, follows new Claude replies as they arrive, and lets you ask questions about what's on screen.

Everything runs on your Mac. The voice is Kokoro, running locally. Reading uses no tokens and no API keys. Two optional features use your Claude plan through the `claude` command: richer reading direction (off by default) and Ask.

Needs an Apple silicon Mac on macOS 14 or later.

## Install

Download `Narrator.dmg` from the [latest release](https://github.com/jain-eshan/narrator/releases/latest), open it, and drag Narrator to Applications. The app is self-signed, so the first time, right-click it and choose Open. The file is about 900 MB because the voice engine and model are inside, so it works offline.

On first launch Lumen, a small moth librarian, flutters down onto your Dock, says hello, and walks you through the Screen Recording and Accessibility permissions. Narrator only looks at the area you select.

## What it does

- Select an area, say what it's for, and it reads it with a mood that fits (Calm, Warm, Serious, News, Story, or Auto).
- Pick a voice in the same box: a woman or a man, with an American or British accent, or Auto to match what you're reading. Click a voice to hear a sample first.
- Follow mode keeps reading new text as it appears, so a Claude chat is read as it streams in.
- Jump lets you click any sentence and continue from there.
- Ask answers questions about what's on screen. Type your question, or dictate it with any dictation app you already use, then press Return. Ask needs the `claude` command installed.
- Lumen lives on top of your Dock. It wanders and reads to itself, flies over to the icon of the app you're reading and sits there, and its mouth and lantern follow the voice. It cups its antennae while you ask a question, thinks while Claude works, and falls asleep after a few quiet minutes. Hover over it for a tip, and click it to start or pause reading. You can also pick it up and drop it, and it steps aside when your pointer is over the Dock below it. Turn it off from the menu bar. With Reduce Motion on, it stays put.

## Shortcuts

All shortcuts use Option + Shift.

| Keys | What it does |
|---|---|
| Option + Shift + 4 | Select an area to read |
| Option + Shift + Space | Play or pause |
| Option + Shift + , | Skip back |
| Option + Shift + . | Skip forward |
| Option + Shift + A | Ask a question. Press again to send it, or to close the box when it's empty |
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

## Lumen's art

Lumen's ten poses (reading, reading aloud, two walking steps, flying, waving, listening, thinking, celebrating, asleep) live in `app/lumen/` as transparent PNGs. They were made from one generated pose sheet, `art/lumen-sheet.png`, which was generated with an image model using `art/lumen-concept.jpg` as the character reference. `art/cutout.swift` uses Apple's Vision to cut each pose out, put them all on one canvas at one scale with the feet on the bottom edge, and clean the white edges:

```bash
swiftc -O art/cutout.swift -o /tmp/cutout
/tmp/cutout art/lumen-sheet.png app/lumen read talk walk1 walk2 fly wave listen think cheer sleep
```

The app finds the lantern in each pose by itself, so a new sheet needs no measuring. Keep the same ten poses in the same order.

## Layout

- `app/main.swift`: the whole app
- `app/build.sh`, `app/package.sh`: build and disk image
- `app/lumen/`: Lumen's poses, bundled into the app
- `art/`: Lumen's concept, pose sheet and the cut-out tool
- `scripts/kokoro_server.py`: the speech service the app starts
- `scripts/`: the other files are voice experiments from early development
- `requirements.txt`: the pinned Python packages
- `LICENSE`: GPL-3.0

## License

Narrator is licensed under the [GNU General Public License v3.0](LICENSE). The voice stack includes espeak-ng and phonemizer, which are GPL licensed, so the whole app is released under the GPL. This repository is the source for every release.

The app is signed with a self-signed identity. A paid Apple Developer ID would remove the "unidentified developer" prompt.
