"""Compare Narrator's current Kokoro delivery with a directed performance of the same words."""
import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import numpy as np
import soundfile as sf

LAB = Path(__file__).resolve().parent.parent
OUT = LAB / "samples" / "modulation"
OUT.mkdir(parents=True, exist_ok=True)
os.environ["ESPEAK_DATA_PATH"] = str(Path.home() / ".cache" / "voice-lab-espeak")
os.environ.setdefault("HF_HOME", str(LAB / "models"))
os.environ.setdefault("HF_HUB_OFFLINE", "1")

import misaki.espeak  # noqa: E402,F401
from mlx_audio.tts.utils import load_model  # noqa: E402
from phonemizer.backend.espeak.wrapper import EspeakWrapper  # noqa: E402

EspeakWrapper.set_data_path(os.environ["ESPEAK_DATA_PATH"] + "/espeak-ng-data")
model = load_model("mlx-community/Kokoro-82M-bf16")
RATE = 24000

# Each line: words, voice, speed, pitch in cents, loudness in dB, pause afterwards in seconds.
SCRIPTS = {
    "case": {
        "plain_voice": "bf_emma",
        "directed": [
            ("Meridian Foods had reached a [difficult](+1) point.", "bf_emma", 0.94, -40, 0, 0.5),
            ("Revenue grew from 120 million dollars in 2023 to 148 million in 2024,", "bf_emma", 1.05, 45, 1, 0.16),
            ("yet operating margin [fell](+2) from 14 percent to 9 percent.", "bf_emma", 0.9, -70, 0, 0.55),
            ("The chief executive, Anita Rao, believed the new cold chain network would pay for itself within three years.", "bf_emma", 1.03, 30, 0.5, 0.32),
            ("Her finance team was [less](+1) certain.", "bf_emma", 0.86, -100, -1.5, 0.65),
            ("Before the board meeting on Thursday, she had to decide whether to expand into two more regions,", "bf_emma", 1.04, 50, 1, 0.14),
            ("or to [pause](+2), and repair the margin first.", "bf_emma", 0.88, -60, 0, 0.3),
        ],
    },
    "novel": {
        "plain_voice": "bm_george",
        "directed": [
            ("The letter had waited in the drawer for [eleven](+1) years.", "bm_george", 0.9, -30, 0, 0.65),
            ("Mira turned it over in her hands, and the old paper whispered against her fingers.", "bm_george", 0.93, 20, -1, 0.45),
            ("Outside, the rain had finally stopped.", "bm_george", 0.85, -70, -2, 0.85),
            ("You [never](+2) told me,", "af_bella", 0.88, 50, -2, 0.22),
            ("she said quietly.", "bm_george", 0.92, -50, -3, 0.7),
            ("Her brother did not look up.", "bm_george", 0.9, -40, -1, 0.5),
            ("For a long moment, the only sound was the clock above the stove.", "bm_george", 0.84, -80, -3, 0.95),
            ("Then he sighed, and pushed the chair back from the table.", "bm_george", 0.96, -10, 0, 0.55),
            ("I never could,", "am_michael", 0.82, -90, -1, 0.2),
            ("he said.", "bm_george", 0.95, -40, -3, 0.45),
            ("Not to [you](+2).", "am_michael", 0.78, -130, -3, 0.3),
        ],
    },
}


def speak(text, voice, speed):
    parts = list(model.generate(text=text, voice=voice, speed=speed, lang_code=voice[0]))
    audio = np.concatenate([np.asarray(part.audio).squeeze() for part in parts])
    voiced = np.where(np.abs(audio) > 0.004)[0]
    return audio[max(0, voiced[0] - int(RATE * 0.03)) : voiced[-1] + int(RATE * 0.06)]


def shifted(audio, cents):
    if cents == 0:
        return audio
    with tempfile.TemporaryDirectory() as folder:
        source, target = Path(folder) / "in.wav", Path(folder) / "out.wav"
        sf.write(source, audio, RATE, subtype="FLOAT")
        subprocess.run([sys.argv[1], str(source), str(cents), str(target)], check=True, capture_output=True)
        result, _ = sf.read(target)
    result = result if result.ndim == 1 else result.mean(axis=1)
    voiced = np.where(np.abs(result) > 0.004)[0]
    return result[max(0, voiced[0] - int(RATE * 0.03)) : voiced[-1] + int(RATE * 0.06)]


def pitch_track(audio):
    frame, hop = int(RATE * 0.04), int(RATE * 0.01)
    low, high = int(RATE / 400), int(RATE / 70)
    values = []
    for start in range(0, len(audio) - frame, hop):
        window = audio[start : start + frame] * np.hanning(frame)
        if np.sqrt(np.mean(window**2)) < 0.012:
            continue
        correlation = np.fft.irfft(np.abs(np.fft.rfft(window, 2 * frame)) ** 2)[: high + 1]
        lag = low + int(np.argmax(correlation[low:]))
        if correlation[lag] > 0.55 * correlation[0]:
            values.append(RATE / lag)
    return np.array(values)


def describe(audio):
    pitch = pitch_track(audio)
    semitones = 12 * np.log2(pitch / np.median(pitch))
    return {
        "seconds": round(len(audio) / RATE, 1),
        "pitch_range_semitones": round(float(np.percentile(semitones, 90) - np.percentile(semitones, 10)), 1),
        "pitch_variation_semitones": round(float(np.std(semitones)), 2),
    }


results = {}
passages = json.loads((LAB / "scripts" / "passages.json").read_text())
for name, script in SCRIPTS.items():
    began = time.perf_counter()
    plain = []
    for sentence in re.split(r"(?<=[.!?\"])\s+", passages[name]["text"]):
        plain += [speak(sentence, script["plain_voice"], 1.0), np.zeros(int(RATE * 0.14))]
    plain_audio = np.concatenate(plain[:-1])
    sf.write(OUT / f"{name}-current.wav", plain_audio, RATE)

    directed = []
    for text, voice, speed, cents, gain, pause in script["directed"]:
        line = shifted(speak(text, voice, speed), cents) * 10 ** (gain / 20)
        directed += [line, np.zeros(int(RATE * pause))]
    directed_audio = np.clip(np.concatenate(directed[:-1]), -1, 1)
    sf.write(OUT / f"{name}-directed.wav", directed_audio, RATE)
    results[name] = {
        "current": describe(plain_audio),
        "directed": describe(directed_audio),
        "render_seconds": round(time.perf_counter() - began, 1),
    }
    print(name, json.dumps(results[name]), flush=True)
(OUT / "results.json").write_text(json.dumps(results, indent=1))
