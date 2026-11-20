# Narrator

**Your AI reading agent. Read more. Without reading.**

[![Watch the 50-second demo](docs/demo-poster.jpg)](https://github.com/jain-eshan/narrator/releases/download/v1.2/narrator-demo.mp4)

[Watch the 50-second demo](https://github.com/jain-eshan/narrator/releases/download/v1.2/narrator-demo.mp4) · [Download for Mac](https://github.com/jain-eshan/narrator/releases/latest)

Narrator is a Mac menu bar app for the long stuff you were going to skip: Claude replies, articles, docs, email threads. Point it at any part of your screen and it reads it to you in a natural voice, highlighting each line as it goes. It keeps up with Claude as new replies stream in, and it answers questions about what's on screen. Its face is Lumen, a small moth who lives on your Dock and reads along with you.

Reading runs entirely on your Mac. The voice is Kokoro, running locally: no tokens, no API keys, no account, and it works offline. Two optional features use your Claude plan through the `claude` command: richer reading direction (off by default) and Ask.

Needs an Apple silicon Mac on macOS 14 or later.

## Install

Download `Narrator.dmg` from the [latest release](https://github.com/jain-eshan/narrator/releases/latest), open it, and drag Narrator to Applications. The app is self-signed rather than signed with an Apple Developer ID, so macOS stops it the first time. On macOS 15 or later, open it once, then go to System Settings > Privacy & Security, scroll down and click Open Anyway. On macOS 14, right-click it and choose Open. The file is about 900 MB because the voice engine and model are inside, so it works offline.

On first launch Lumen flutters down onto your Dock, says hello, and walks you through the Screen Recording and Accessibility permissions. Narrator only looks at the area you select.

## What it does

- **Point at anything.** Press Option + Shift + 4 and drag over any text on screen.
- **Tune it.** Say what it's for, pick a mood (Calm, Warm, Serious, News, Story, or Auto) and a voice: a woman or a man, with an American or British accent, or Auto to match what you're reading. Click a voice to hear a sample first.
- **Sit back.** It reads line by line and highlights each one as it goes, then scrolls on by itself.
- **Tables make sense.** A table is read row by row, with each value named by its column, instead of column by column.
- **Keep up with Claude.** Follow mode reads new replies as they stream in.
- **Jump.** Click any sentence and it carries on from there.
- **Ask.** Press Option + Shift + A to ask about what's on screen. Type, or dictate with any dictation app you already use, then press Return. Ask needs the `claude` command installed.
- **Lumen.** The moth lives on top of your Dock. It wanders and reads to itself, flies over to the icon of the app you're reading, and its mouth and lantern follow the voice. It listens while you ask, thinks while Claude works, and falls asleep after a few quiet minutes. Hover over it for a tip, click it to start or pause, or pick it up and drop it. It steps aside when your pointer is over the Dock below it. Turn it off from the menu bar, or choose Keep Lumen in one place and it stays wherever you drop it, with no wandering or following. With Reduce Motion on, it stays put.

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

## Privacy

- **Reading stays on your Mac.** Narrator looks only at the area you select, reads its text with macOS's own text recognition, and speaks it with the voice model inside the app. Nothing is uploaded. There is no account, no analytics and no tracking.
- **Claude features send text only when you use them.** With "Richer voice with Claude" on, the text in your reading area goes to Claude to plan the reading. Ask sends your question, the sentence being read, and the text in the reading area (or in the window under your pointer when nothing is being read), and Claude may search the web to answer. Both run through your own `claude` command and your Claude plan. Narrator never uses an API key.
- **What stays on disk.** Your settings (voice, mood, speed, and what you asked it to read in each app) are kept in macOS preferences. A diagnostic log at `~/Library/Logs/Narrator/narrator.log` records events such as which app was read and how long things took, never the text itself.

## Uninstall

Quit Narrator from the menu bar, then:

```bash
rm -rf /Applications/Narrator.app ~/Library/Logs/Narrator ~/.cache/narrator-espeak
```

```bash
defaults delete local.narrator.app
```

You can also remove Narrator from Screen Recording and Accessibility in System Settings, under Privacy & Security.

## Build it

You need Xcode command line tools and [uv](https://docs.astral.sh/uv/). The app is a handful of Swift files in `app/`, plus a Python voice service, `scripts/kokoro_server.py`.

```bash
uv venv envs/kokoro --python 3.12
uv pip install --python envs/kokoro/bin/python -r requirements.txt
HF_HOME=models envs/kokoro/bin/python -c "from huggingface_hub import snapshot_download; snapshot_download('mlx-community/Kokoro-82M-bf16')"
```

The text tools in `requirements.txt` pull in PyTorch, but the voice runs on MLX and never uses it, so `build.sh` leaves PyTorch and its companions out of the app.

Create a self-signed code signing identity and put its files in `.signing/` (`identity`, `keychain-password`, `narrator.keychain-db`). `build.sh` reads them. Then:

```bash
zsh app/build.sh --full    # builds Narrator.app with the voice engine and model inside (about 1 GB)
zsh app/package.sh         # optional: makes dist/Narrator.dmg to share
```

These steps have not been tried on a clean machine yet. If one fails, please open an issue.

### Check a change

The reading logic has its own checks, and the app can draw its playback bar, boxes and Lumen's poses to images, so you can see a visual change without clicking through it:

```bash
Narrator.app/Contents/MacOS/Narrator --selftest
```

```bash
mkdir -p /tmp/previews && Narrator.app/Contents/MacOS/Narrator --render-ui=/tmp/previews
```

## Lumen's art

Lumen's ten poses (reading, reading aloud, two walking steps, flying, waving, listening, thinking, celebrating, asleep) live in `app/lumen/` as transparent PNGs. They were made from one generated pose sheet, `art/lumen-sheet.png`, which was generated with an image model using `art/lumen-concept.jpg` as the character reference. `art/cutout.swift` uses Apple's Vision to cut each pose out, put them all on one canvas at one scale with the feet on the bottom edge, and clean the white edges:

```bash
swiftc -O art/cutout.swift -o /tmp/cutout
/tmp/cutout art/lumen-sheet.png app/lumen read talk walk1 walk2 fly wave listen think cheer sleep
```

The app finds the lantern in each pose by itself, so a new sheet needs no measuring. Keep the same ten poses in the same order.

## Demo video

The demo is a [HyperFrames](https://hyperframes.heygen.com) project in `videos/narrator-demo/`, built from the app's real parts: Lumen's poses and the purpose box, Ask box and playback bar as rendered by the app itself (`--render-ui`). It is narrated in Narrator's own default voice (Kokoro, Heart) and made entirely on this Mac. `BRIEF.md` holds the brand and audience, `STORYBOARD.md` the eight frames shot by shot, and `SCRIPT.md` the narration. `videos/narrator-demo/tools/README.txt` lists the rebuild steps. The narration, mixed music bed and renders are generated, so they are not in git.

## Layout

- `app/*.swift`: the app, one file per part:
  - `Reading.swift`: turns recognized screen text into spoken phrases
  - `Claude.swift`: the optional Claude reading direction, Ask, and the on-device director
  - `Speech.swift`: talks to the voice service, plus the diagnostic log
  - `Screen.swift`: screen capture, scrolling and window lookup
  - `Views.swift`: the selector, highlight, jump picker and shared visual style
  - `Lumen.swift`: Lumen on the Dock and its speech bubble
  - `App.swift`: the menu bar app that ties it all together
  - `SelfTest.swift`: checks run with `--selftest`
  - `main.swift`: starts the app
- `app/build.sh`, `app/package.sh`: build and disk image
- `app/lumen/`: Lumen's poses, bundled into the app
- `art/`: Lumen's concept, pose sheet and the cut-out tool
- `videos/narrator-demo/`: the demo video's sources and tools
- `docs/`: images used in this README
- `scripts/kokoro_server.py`: the speech service the app starts
- `scripts/`: the other files are voice experiments from early development
- `requirements.txt`: the pinned Python packages
- `LICENSE`: GPL-3.0

## Credits

- Voice: [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) (Apache-2.0), run with [mlx-audio](https://github.com/Blaizzy/mlx-audio).
- Lumen: an original character, generated with an image model and cut out with Apple's Vision.
- Demo music: "Blue Skies" by [Holizna](https://freemusicarchive.org/music/holiznacc0/), CC0 1.0, from Free Music Archive.
- Demo sound effects: Pixabay Content License, bundled with HyperFrames.
- Demo fonts: Instrument Serif and Archivo, SIL Open Font License 1.1 (`videos/narrator-demo/assets/fonts/LICENSE.txt`).

## License

Narrator is licensed under the [GNU General Public License v3.0](LICENSE). The voice stack includes espeak-ng and phonemizer, which are GPL licensed, so the whole app is released under the GPL. This repository is the source for every release.

The app is signed with a self-signed identity. A paid Apple Developer ID would remove the "unidentified developer" prompt.
