"""Transcribe each sample locally and compare it with the passage it should say."""
import difflib
import json
import re
from pathlib import Path

import numpy as np
import soundfile as sf
from mlx_audio.stt.utils import load

LAB = Path(__file__).resolve().parent.parent
PASSAGES = json.loads((LAB / "scripts" / "passages.json").read_text())
model = load("mlx-community/parakeet-tdt-0.6b-v3")


def words(text):
    text = text.lower().replace(",", "").replace("-", " ")
    return re.findall(r"[a-z0-9']+", text)


rows = []
for path in sorted((LAB / "samples").glob("*.wav")):
    material, engine, voice = path.stem.split("-", 2)
    audio, rate = sf.read(path)
    heard = model.generate(str(path)).text
    expected, got = words(PASSAGES[material]["text"]), words(heard)
    matcher = difflib.SequenceMatcher(None, expected, got, autojunk=False)
    changes = [
        (" ".join(expected[a:b]), " ".join(got[c:d]))
        for tag, a, b, c, d in matcher.get_opcodes()
        if tag != "equal"
    ]
    rows.append(
        {
            "sample": path.stem,
            "word_match_pct": round(matcher.ratio() * 100, 1),
            "peak": round(float(np.abs(audio).max()), 3),
            "silent_pct": round(float((np.abs(audio) < 0.003).mean() * 100), 1),
            "changes": changes,
        }
    )
    print(json.dumps(rows[-1]), flush=True)
(LAB / "samples" / "verify.json").write_text(json.dumps(rows, indent=1))
