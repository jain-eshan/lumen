# Lumen launch video

A 68-second, 1920×1080 demo made for the LinkedIn and YouTube launch in November 2026. It is cut from real screen recordings of Lumen 1.4.1 and built with [HyperFrames](https://hyperframes.heygen.com).

## The story

AI made writing cheap, so there is more to read than anyone can get through, and most of it gets skimmed and forgotten. Lumen is the reading buddy that reads it to you, so more of it sticks. Each feature is shown as the problem it solves:

| Step | On screen | Problem it solves |
|---|---|---|
| 1 | Listen to any text on your screen | Long text is draining and little of it sticks |
| 2 | Want to check a fact? Ask Claude | Leaving the page to ask a question breaks the thread |
| 3 | Send Claude your thinking, not just the file | Claude gets the document, but not what you think about it |
| 4 | Hear Claude's replies instead of reading them | AI replies are walls of text, and typing slows you down |

The case on screen, Kettle and Co., is fictional (`props/`). The moth reacts to each moment in the side panel, and the gaps let you hear Lumen's own voice.

## Narration

Voice: ElevenLabs, "Emma", eleven_v4, sped up 8% in the edit.

> AI made writing almost free. So now there's ten times more to read. Replies, reports, cases, articles, every single day. Most of it gets skimmed, and forgotten. Meet Lumen, your reading buddy for Mac. It reads your screen out loud, so more of it sticks. Select any text. Lumen reads it to you, line by line, down the page. Stuck? Ask right where you are. Lumen answers out loud, from what's on your screen. Want Claude's help? Mark what matters, add your thoughts, and paste it all in one go. Claude gets your context, and your thinking. Then Lumen reads Claude's reply as it comes in. Answer back by voice, with Wispr Flow. No more walls of text. The voice runs on your Mac. No account, no API key. Free. Lumen is open source. Try it, and tell us what to build next. Lumen. It reads to you.

Two lines are vaguer than the on-screen text and are worth re-recording when there are credits: "Replies, reports, cases, articles" (say "Long Claude threads, market reports, case studies, newsletters") and "Stuck? Ask right where you are" (say "Want to check a fact? Ask Claude, with your document as context").

## Files

- `index.html`: the composition. `tools/build.py` writes the clip timings and narration word times into it.
- `tools/build.py`: cuts the clips from the screen recordings, mixes the narration, Lumen's voice and the music, and injects the timeline.
- `props/`: the fictional case (HTML source and PDF) read in the demo.
- `assets/brand/`, `assets/fonts/`: Lumen's poses and wordmarks, and the fonts.
- `assets/vo/vo-w1.json`, `vo-w2.json`: word timings of the two narration recordings.

Not in git: the screen recordings (`raw/`, about 1.3 GB), the narration audio, the music, the cut clips and the renders. The final render is kept in the main checkout at `videos/lumen-launch/renders/lumen-launch.mp4`.

## Rebuild

With `raw/session1.mov`, `session3.mov`, `session4.mov`, the narration files in `assets/vo/` and the music in `assets/music/cand/marimba.mp3`:

```bash
python3 tools/build.py
```

```bash
HYPERFRAMES_NO_TELEMETRY=1 DO_NOT_TRACK=1 HYPERFRAMES_SKIP_SKILLS=1 npx --yes hyperframes@0.8.164 render -f 30 -o renders/lumen-launch.mp4
```

## Credits

- Music: "Corporate Marimba Startup Promo" by Alex Morgan, Pixabay Content License.
- Sound effects: Pixabay Content License, bundled with HyperFrames.
- Fonts: Instrument Serif and Archivo, SIL Open Font License 1.1 (`assets/fonts/LICENSE.txt`).
