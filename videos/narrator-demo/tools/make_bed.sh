#!/bin/zsh
# Builds the music bed: Holizna "Blue Skies" (CC0) trimmed so its beat drop (11.70s in the track) lands on
# Frame 2 (5.24s), faded, dipped for the calm Frame 6, and ducked under the narration with a sidechain.
# Also makes the quiet sound-effect copies. Safe to re-run. Run from the project folder after time_words.py.
set -euo pipefail
T=$(ffprobe -v error -show_entries format=duration -of csv=p=0 assets/music/vo-guide.wav)
# Quiet copies of the bundled Pixabay effects (HyperFrames media-use), 12 dB down.
SFX=~/.claude/video-kit/hyperframes/media-use/audio/assets/sfx; mkdir -p assets/sfx
for n in whoosh-short key-press click-soft sparkle chime; do ffmpeg -y -v error -i $SFX/$n.mp3 -af "volume=-12dB" -ar 48000 assets/sfx/$n.wav; done
ffmpeg -y -v error -i $SFX/typing.mp3 -t 0.75 -af "volume=-12dB,afade=t=out:st=0.55:d=0.2" -ar 48000 assets/sfx/typing-short.wav
ls assets/voice/0*.wav | sed "s|^|file '$PWD/|;s|$|'|" > /tmp/vo.txt
ffmpeg -y -v error -f concat -safe 0 -i /tmp/vo.txt -ar 48000 -ac 1 assets/music/vo-guide.wav && rm /tmp/vo.txt
FADE_OUT=$(echo "$T - 3.2" | bc -l)
ffmpeg -y -v error -ss 6.46 -t "$T" -i assets/music/blue-skies-holizna-cc0.mp3 -i assets/music/vo-guide.wav -filter_complex "
[0:a]aresample=48000,asetpts=PTS-STARTPTS,volume=-10dB,
volume='1-0.33*clip((t-27.4)/0.8,0,1)*clip((35.2-t)/0.8,0,1)':eval=frame,
afade=t=in:st=0:d=1.2,afade=t=out:st=$FADE_OUT:d=3.2[m];
[1:a]aresample=48000,pan=stereo|c0=c0|c1=c0[sc];
[m][sc]sidechaincompress=threshold=0.015:ratio=8:attack=15:release=420:makeup=1[bed]" \
  -map "[bed]" -ar 48000 -ac 2 assets/music/bed.wav
echo "bed: $(ffprobe -v error -show_entries format=duration -of csv=p=0 assets/music/bed.wav)s"
