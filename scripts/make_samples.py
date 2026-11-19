"""Read the same three passages with one voice engine and log speed and memory.

Usage: make_samples.py phonon|kitten|kokoro
"""
import json
import resource
import sys
import time
from pathlib import Path

import numpy as np
import soundfile as sf

LAB = Path(__file__).resolve().parent.parent
PASSAGES = json.loads((LAB / "scripts" / "passages.json").read_text())
VOICES = {
    "phonon": {"case": "Imogen", "news": "Harper", "novel": "Maeve"},
    "kitten": {"case": "Victor", "news": "Luna", "novel": "Bella"},
    "kokoro": {"case": "bf_emma", "news": "af_heart", "novel": "bm_george"},
}


def load(engine):
    if engine == "phonon":
        import ptts

        tts = ptts.TTS("hf://gradium/phonon-31m-en", lang="en", quant="q8")

        def speak(passage, voice, out):
            tts.save(str(out), passage["text"], voice=voice)

        return speak

    if engine == "kitten":
        from kittenml import KittenTTS

        model = KittenTTS("KittenML/kitten-tts-2")

        def speak(passage, voice, out):
            parts = [
                np.asarray(model.generate(line, voice=voice, preset="expressive")).squeeze()
                for line in passage["kitten_lines"]
            ]
            gap = np.zeros(int(model.sample_rate * 0.28))
            joined = np.concatenate([x for part in parts for x in (part, gap)][:-1])
            sf.write(out, joined, model.sample_rate)

        return speak

    # espeak-ng cannot read data from very long folder paths, so use a short link.
    import os

    import misaki.espeak  # noqa: F401
    from phonemizer.backend.espeak.wrapper import EspeakWrapper

    EspeakWrapper.set_data_path(os.environ["ESPEAK_DATA_PATH"] + "/espeak-ng-data")

    from mlx_audio.tts.utils import load_model

    model = load_model("mlx-community/Kokoro-82M-bf16")

    def speak(passage, voice, out):
        results = list(
            model.generate(text=passage["text"], voice=voice, speed=1.0, lang_code=voice[0])
        )
        audio = np.concatenate([np.asarray(r.audio).squeeze() for r in results])
        sf.write(out, audio, results[0].sample_rate)

    return speak


def main(engine):
    started = time.perf_counter()
    speak = load(engine)
    load_seconds = time.perf_counter() - started
    log = LAB / "samples" / f"{engine}.results.jsonl"
    log.unlink(missing_ok=True)
    for material, voice in VOICES[engine].items():
        out = LAB / "samples" / f"{material}-{engine}-{voice}.wav"
        began = time.perf_counter()
        speak(PASSAGES[material], voice, out)
        seconds = time.perf_counter() - began
        info = sf.info(out)
        row = {
            "engine": engine,
            "material": material,
            "voice": voice,
            "load_s": round(load_seconds, 1),
            "generate_s": round(seconds, 2),
            "audio_s": round(info.duration, 2),
            "speed_x": round(info.duration / seconds, 2),
            "peak_ram_gb": round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024**3, 2),
        }
        with log.open("a") as handle:
            handle.write(json.dumps(row) + "\n")
        print(json.dumps(row), flush=True)


if __name__ == "__main__":
    main(sys.argv[1])
