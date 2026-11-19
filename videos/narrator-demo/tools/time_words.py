"""Adds breathing room around each narration clip and estimates word timings for captions.

Kokoro gives no word timestamps, so speech stretches are found with ffmpeg's silence detection,
matched to the script's phrases (split at punctuation), and each phrase's words are spread across
its stretch by length. Reads assets/voice-raw/NN.wav, writes padded assets/voice/NN.wav and
updates audio_meta.json (duration_s and words, frame-relative seconds).
Each clip is also lifted 6 dB with a limiter, so the narration sits near -16 LUFS.
"""
import json, re, subprocess, sys

LEAD = {1: 0.45}            # seconds of silence before a line (default below)
TAIL = {1: 0.8, 8: 3.6}     # seconds after a line; frame 8 holds the URL card
DEFAULT_LEAD, DEFAULT_TAIL = 0.3, 0.75

def speech_spans(path):
    out = subprocess.run(["ffmpeg", "-hide_banner", "-i", path, "-af", "silencedetect=noise=-38dB:d=0.11", "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    total = float(re.search(r"Duration: (\d+):(\d+):([\d.]+)", out).groups()[2]) + 60 * float(re.search(r"Duration: (\d+):(\d+)", out).group(2))
    starts = [float(x) for x in re.findall(r"silence_start: ([\d.]+)", out)]
    ends = [float(x) for x in re.findall(r"silence_end: ([\d.]+)", out)]
    spans, cursor = [], 0.0
    for s, e in zip(starts, ends + [total] * (len(starts) - len(ends))):
        if s - cursor > 0.05: spans.append([cursor, s])
        cursor = e
    if total - cursor > 0.05: spans.append([cursor, total])
    return spans, total

def phrases(text):
    parts = [p.strip() for p in re.split(r"(?<=[,.?:!])\s+", text) if p.strip()]
    return [p.split() for p in parts]

def spread(words, start, end):
    weights = [len(w) + 1 for w in words]
    total, t, out = sum(weights), start, []
    for w, k in zip(words, weights):
        d = (end - start) * k / total
        out.append({"text": w, "start": round(t, 3), "end": round(t + d, 3)})
        t += d
    return out

script = open("SCRIPT.md").read()
lines = {int(m.group(1)): " ".join(m.group(2).split()) for m in re.finditer(r"\(Frame (\d+)\)[\s\S]*?\n\n    (.+)\n", script)}
meta = json.load(open("audio_meta.json"))
for voice in meta["voices"]:
    n = voice["frame"]
    raw = f"assets/voice-raw/{n:02d}.wav"
    spans, total = speech_spans(raw)
    groups = phrases(lines[n])
    lengths = [sum(len(w) + 1 for w in g) for g in groups]
    speech = sum(e - s for s, e in spans)
    fits = len(spans) == len(groups) and all(
        0.45 <= (e - s) / (speech * n / sum(lengths)) <= 2.2 for (s, e), n in zip(spans, lengths))
    if fits:
        timed = [w for g, (s, e) in zip(groups, spans) for w in spread(g, s, e)]
        how = "phrase-matched"
    else:
        timed = spread([w for g in groups for w in g], spans[0][0], spans[-1][1])
        how = f"spread ({len(spans)} spans, {len(groups)} phrases)"
    lead, tail = LEAD.get(n, DEFAULT_LEAD), TAIL.get(n, DEFAULT_TAIL)
    subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", raw, "-af",
                    f"adelay={int(lead*1000)}:all=1,apad=pad_dur={tail},volume=6dB,alimiter=limit=0.89:level=false", f"assets/voice/{n:02d}.wav"], check=True)
    for w in timed: w["start"] = round(w["start"] + lead, 3); w["end"] = round(w["end"] + lead, 3)
    voice["words"] = timed
    voice["duration_s"] = round(lead + total + tail, 3)
    print(f"frame {n}: {voice['duration_s']}s, {len(timed)} words, {how}")
json.dump(meta, open("audio_meta.json", "w"), indent=2)
print("total", round(sum(v["duration_s"] for v in meta["voices"]), 2), "s")
