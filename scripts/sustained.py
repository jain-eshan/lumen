"""Time one engine alone over repeated rounds, to reveal slowdown on a fanless Mac.

Usage: sustained.py phonon|kokoro|kitten rounds
"""
import json
import resource
import sys
import tempfile
import time
from pathlib import Path

import soundfile as sf

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_samples import LAB, PASSAGES, VOICES, load  # noqa: E402


def main(engine, rounds):
    began = time.perf_counter()
    speak = load(engine)
    load_seconds = time.perf_counter() - began
    materials = ["case"] if engine == "kitten" else list(VOICES[engine])
    speeds = []
    total_audio = total_time = 0.0
    with tempfile.TemporaryDirectory() as folder:
        for round_number in range(rounds):
            audio = spent = 0.0
            for material in materials:
                out = Path(folder) / f"{round_number}-{material}.wav"
                start = time.perf_counter()
                speak(PASSAGES[material], VOICES[engine][material], out)
                spent += time.perf_counter() - start
                audio += sf.info(out).duration
            speeds.append(round(audio / spent, 2))
            total_audio += audio
            total_time += spent
    row = {
        "engine": engine,
        "load_s": round(load_seconds, 1),
        "audio_min": round(total_audio / 60, 1),
        "overall_speed_x": round(total_audio / total_time, 2),
        "speed_by_round": speeds,
        "peak_ram_gb": round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024**3, 2),
    }
    with (LAB / "samples" / "sustained.jsonl").open("a") as handle:
        handle.write(json.dumps(row) + "\n")
    print(json.dumps(row), flush=True)


if __name__ == "__main__":
    main(sys.argv[1], int(sys.argv[2]))
