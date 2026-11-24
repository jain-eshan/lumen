#!/usr/bin/env python3
"""Builds the Lumen launch video's media: clips, soundtrack and the timeline injected into index.html.
Run from videos/lumen-launch: python3 tools/build.py [--no-clips]
Inputs: raw/session{1,3,4}.mov (screen takes), assets/vo/vo-take1.mp3 and vo-take2-mid.mp3 + vo-w1/vo-w2.json (narration + word times),
assets/music/cand/marimba.mp3 (Pixabay, "Corporate Marimba Startup Promo" by Alex Morgan)."""
import json, re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SFX = Path.home() / ".claude/video-kit/hyperframes/media-use/audio/assets/sfx"
TEMPO = 1.08          # narration sped up 8%
END = 68.0

def run(*a):
    subprocess.run(a, check=True, cwd=ROOT)

# Narration pieces: (file, source from, source to, place at). File 0 = vo-take1.mp3 (first take), 1 = vo-take2-mid.mp3 (rewritten lines)
VO_FILES = [("assets/vo/vo-take1.mp3", "assets/vo/vo-w1.json"), ("assets/vo/vo-take2-mid.mp3", "assets/vo/vo-w2.json")]
VO = [(0, 0.00, 10.32, 0.15), (1, 0.00, 2.75, 9.9), (1, 3.01, 9.20, 12.65), (1, 9.41, 14.55, 18.6), (1, 14.73, 20.20, 27.15),
      (1, 20.45, 28.72, 35.5), (1, 28.88, 36.40, 43.55), (0, 49.16, 53.99, 54.8), (1, 36.62, 40.64, 59.45), (0, 59.70, 61.76, 63.4)]
# Clips: name, take, in, out, speed, start in video
CLIPS = [("r1", 1, 46.8, 51.1, 2.0, 18.45), ("r2", 1, 66.0, 68.4, 1.0, 20.6), ("r3", 1, 104.4, 109.4, 4.167, 23.0),
         ("r4", 1, 112.2, 115.0, 1.0, 24.2), ("a1", 3, 188.0, 204.5, 4.583, 27.0), ("a2", 3, 210.75, 215.55, 1.0, 30.6),
         ("n1", 3, 115.0, 120.0, 1.786, 35.4), ("n2", 3, 127.0, 131.0, 2.0, 38.2), ("n4", 3, 277.4, 280.6, 2.0, 40.2),
         ("n3", 3, 295.4, 299.4, 2.5, 41.8), ("f1", 4, 166.6, 169.8, 1.0, 43.4), ("f2", 4, 193.5, 199.8, 3.5, 46.6),
         ("f3", 4, 310.1, 316.3, 1.0, 48.4)]
# Lumen's own voice at full volume: take, from, to, at, caption
SOLO = [(1, 112.80, 114.90, 24.8, "Quick commerce had changed how urban India shopped."),
        (3, 212.55, 215.21, 32.4, "My thesis is that it's mostly an industry-wide pattern…"),
        (4, 312.35, 316.25, 50.65, "Final answer: go with Option 2, own ten-minute delivery from Kettle's stores.")]
# Lumen quietly under the narration: take, from, to, at
BED = [(1, 66.0, 68.4, 20.6), (4, 166.6, 169.8, 43.4), (4, 310.1, 312.3, 48.4)]
SFXS = [("whoosh-short", 0.2, 18.4), ("chime", 0.2, 65.45)]

def clip_len(c): return (c[3] - c[2]) / c[4]

def cut_clips():
    out = ROOT / "assets/clips"; out.mkdir(parents=True, exist_ok=True)
    for n, take, a, b, s, _ in CLIPS:
        vf = f"setpts=PTS/{s},fps=30,scale=1600:-2"
        if n == "n3":  # blur Claude's sidebar (project names)
            vf = "split[a][b];[b]crop=530:1390:0:130,boxblur=24:2[bl];[a][bl]overlay=0:130," + vf
        run("ffmpeg", "-y", "-v", "error", "-ss", str(a), "-to", str(b), "-i", f"raw/session{take}.mov", "-an",
            "-filter_complex" if n == "n3" else "-vf", vf, "-c:v", "libx264", "-preset", "slow", "-crf", "18",
            "-pix_fmt", "yuv420p", "-movflags", "+faststart", f"assets/clips/{n}.mp4")
        print("clip", n, round(clip_len((n, take, a, b, s, 0)), 2))

def mix():
    fast = []
    for k, (src, _) in enumerate(VO_FILES):
        fast.append(ROOT / f"assets/vo/vo-fast{k}.wav")
        run("ffmpeg", "-y", "-v", "error", "-i", src, "-af", f"atempo={TEMPO}", "-ar", "48000", "-ac", "1", str(fast[-1]))
    ins = ["-i", str(fast[0]), "-i", "raw/session1.mov", "-i", "raw/session3.mov", "-i", "raw/session4.mov",
           "-i", "assets/music/cand/marimba.mp3", "-i", str(fast[1])]
    f, v, l, x = [], [], [], []
    for i, (fi, a, b, at) in enumerate(VO):
        a, b = a / TEMPO, b / TEMPO; d = b - a; ms = int(at * 1000)
        f.append(f"[{0 if fi == 0 else 5}:a]atrim={a:.3f}:{b:.3f},asetpts=PTS-STARTPTS,afade=t=in:d=0.03,afade=t=out:st={d-0.06:.3f}:d=0.06,adelay={ms}|{ms}[v{i}]"); v.append(f"[v{i}]")
    k = 0
    for take, a, b, at, _ in SOLO:
        d = b - a; ms = int(at * 1000)
        f.append(f"[{ {1:1,3:2,4:3}[take] }:a]atrim={a}:{b},asetpts=PTS-STARTPTS,aresample=48000,afade=t=in:d=0.1,afade=t=out:st={d-0.2:.2f}:d=0.2,adelay={ms}|{ms}[l{k}]"); l.append(f"[l{k}]"); k += 1
    for take, a, b, at in BED:
        d = b - a; ms = int(at * 1000)
        f.append(f"[{ {1:1,3:2,4:3}[take] }:a]atrim={a}:{b},asetpts=PTS-STARTPTS,aresample=48000,volume=0.14,afade=t=in:d=0.3,afade=t=out:st={d-0.3:.2f}:d=0.3,adelay={ms}|{ms}[l{k}]"); l.append(f"[l{k}]"); k += 1
    for j, (name, vol, at) in enumerate(SFXS):
        ins += ["-i", str(SFX / f"{name}.mp3")]; ms = int(at * 1000)
        f.append(f"[{6+j}:a]aresample=48000,volume={vol},adelay={ms}|{ms}[x{j}]"); x.append(f"[x{j}]")
    # music: skip the quiet intro and repeat 8 bars (125 bpm) so the outro lands on the end card
    L = 15.36
    f.append(f"[4:a]aresample=48000,asplit=2[m1][m2];[m1]atrim=5.86:{25.0+L},asetpts=PTS-STARTPTS[ma];[m2]atrim=25.0,asetpts=PTS-STARTPTS[mb];"
             f"[ma][mb]acrossfade=d=0.03,atrim=0:{END},volume=0.2,afade=t=out:st={END-1.2}:d=1.2[mus]")
    f.append(f"{''.join(v)}amix=inputs={len(v)}:normalize=0[vo]")
    f.append(f"{''.join(l)}amix=inputs={len(l)}:normalize=0,volume=0.9[lum]")
    f.append(f"[vo][lum]amix=inputs=2:normalize=0,apad=whole_dur={END},asplit=2[sp][key]")
    f.append("[mus][key]sidechaincompress=threshold=0.02:ratio=8:attack=20:release=400[duck]")
    f.append(f"{''.join(x)}amix=inputs={len(x)}:normalize=0[fx]")
    f.append(f"[sp][duck][fx]amix=inputs=3:normalize=0,atrim=0:{END},loudnorm=I=-14:TP=-1.5:LRA=11[out]")
    (ROOT / "assets/audio").mkdir(parents=True, exist_ok=True)
    run("ffmpeg", "-y", "-v", "error", *ins, "-filter_complex", ";".join(f), "-map", "[out]", "-ar", "48000", "-ac", "2", "assets/audio/mix.wav")
    print("mix done")

def words():
    """Narration words with their times in the final video."""
    out = []
    for fi, (_, wj) in enumerate(VO_FILES):
        out += place(fi, json.loads((ROOT / wj).read_text())["transcription"])
    fix = {"Whisper": "Wispr", "WhisperFlow": "Wispr Flow"}
    return sorted([[fix.get(w, w), t] for w, t in out], key=lambda x: x[1])

def place(fi, raw):
    toks = [(s["text"], s["offsets"]["from"] / 1000) for s in raw if s["text"].strip()]
    ws = []
    for t, s in toks:
        if re.fullmatch(r"[,.?!]", t.strip()):
            if ws: ws[-1][0] += t.strip()
        elif not t.startswith(" ") and ws and not t.strip()[0].isupper() or t.strip() in ("'s", "'t", "'re"):
            ws[-1][0] += t.strip()
        else:
            ws.append([t.strip(), s])
    out = []
    for w, s in ws:
        for f2, a, b, at in VO:
            if f2 == fi and a - 0.05 <= s < b:
                out.append([w, round(at + (s - a) / TEMPO, 3)])
                break
    return out

def inject():
    tl = {"words": words(), "solos": [[at, at + (b - a), cap] for _, a, b, at, cap in SOLO],
          "clips": [[n, at, round(clip_len(c), 3)] for c in CLIPS for n, at in [(c[0], c[5])]], "end": END}
    html = (ROOT / "index.html").read_text()
    new = "const TL = " + json.dumps(tl, ensure_ascii=False) + "; // TL"
    html = re.sub(r"const TL = .*?; // TL", lambda _: new, html, flags=re.S)
    (ROOT / "index.html").write_text(html)
    print("timeline injected:", len(tl["words"]), "words")

def stills():
    (ROOT / "assets/stills").mkdir(parents=True, exist_ok=True)
    run("ffmpeg", "-y", "-v", "error", "-ss", "70", "-i", "raw/session1.mov", "-frames:v", "1", "-vf", "crop=1560:1300:400:120", "assets/stills/case.jpg")

if __name__ == "__main__":
    if "--no-clips" not in sys.argv: cut_clips(); stills()
    mix(); inject()
