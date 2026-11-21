"""Kokoro speech service for Lumen.

Reads one JSON request per line on stdin: {"id": 1, "text": "...", "voice": "af_heart"}
Writes one JSON reply per line on stdout: {"id": 1, "path": "/tmp/...wav"} or {"id": 1, "error": "..."}
"""
import atexit
import json
import os
import shutil
import signal
import sys
import tempfile
import uuid
from pathlib import Path

LAB = Path(__file__).resolve().parent.parent
replies = sys.stdout
sys.stdout = sys.stderr  # Model libraries print progress; keep the reply channel clean.

os.environ.setdefault("HF_HOME", str(LAB / "models"))
os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")

import espeakng_loader  # noqa: E402

# espeak-ng cannot read data from very long folder paths, so use a short link.
link = Path.home() / ".cache" / "narrator-espeak"
link.parent.mkdir(parents=True, exist_ok=True)
if link.is_symlink():
    link.unlink()
link.symlink_to(Path(espeakng_loader.__file__).parent)
os.environ["ESPEAK_DATA_PATH"] = str(link)

import misaki.espeak  # noqa: E402,F401
import numpy as np  # noqa: E402
import soundfile as sf  # noqa: E402
from mlx_audio.tts.utils import load_model  # noqa: E402
from phonemizer.backend.espeak.wrapper import EspeakWrapper  # noqa: E402

EspeakWrapper.set_data_path(str(link / "espeak-ng-data"))
# The app passes the model folder it ships with; development runs use the downloaded copy.
model = load_model(os.environ.get("NARRATOR_MODEL", "mlx-community/Kokoro-82M-bf16"))
folder = Path(tempfile.mkdtemp(prefix="narrator-"))
# Clips the app never played are deleted when the service ends. The app ends it with SIGTERM.
atexit.register(shutil.rmtree, folder, True)
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))


def reply(message):
    replies.write(json.dumps(message) + "\n")
    replies.flush()


def synthesize(text, voice, speed=1.0):
    results = list(model.generate(text=text, voice=voice, speed=speed, lang_code=voice[0]))
    audio = np.concatenate([np.asarray(result.audio).squeeze() for result in results])
    rate = results[0].sample_rate
    # Kokoro pads each clip with about 0.4 seconds of silence, which makes reading sound choppy.
    voiced = np.where(np.abs(audio) > 0.004)[0]
    if voiced.size:
        audio = audio[max(0, voiced[0] - int(rate * 0.03)) : voiced[-1] + int(rate * 0.06)]
        # Voices differ in loudness, so level them before each mood adds its own change.
        loudness = float(np.sqrt(np.mean(audio**2)))
        audio = audio * min(0.1 / max(loudness, 1e-4), 0.95 / float(np.abs(audio).max()))
    path = folder / f"{uuid.uuid4().hex}.wav"
    sf.write(path, audio, rate)
    return path


synthesize("Ready.", "af_heart").unlink()
reply({"ready": True})

for line in sys.stdin:
    request = json.loads(line)
    try:
        path = synthesize(request["text"], request["voice"], request.get("speed", 1.0))
        reply({"id": request["id"], "path": str(path)})
    except Exception as error:  # Report the failure so the app can skip this sentence.
        reply({"id": request["id"], "error": str(error)})
