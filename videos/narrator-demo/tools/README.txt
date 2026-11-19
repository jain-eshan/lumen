Narrator demo video: how to rebuild it

The video is a HyperFrames project (hyperframes@0.8.164, run with npx). Everything runs locally: the voice is
Kokoro (af_heart, Narrator's own default voice), the music is a CC0 track, and there are no cloud services.
Set these before any HyperFrames command:

  export HYPERFRAMES_NO_TELEMETRY=1 DO_NOT_TRACK=1 HYPERFRAMES_SKIP_SKILLS=1
  export HYPERFRAMES_PYTHON=~/.claude/video-kit/hyperframes/.venv/bin/python
  SK=~/.claude/video-kit/hyperframes/product-launch-video/scripts

What lives where
  BRIEF.md          who the video is for and the brand ("your AI reading agent", "Read more. Without reading.")
  STORYBOARD.md     the 8 frames, shot by shot, with cue times
  SCRIPT.md         the narration, one line per frame
  frame.md          palette and type
  compositions/     one HTML file per frame, plus the captions
  capture/assets/   the real app stills (rendered by Narrator with --render-ui) and Lumen's poses
  assets/music/     Holizna "Blue Skies" (CC0); bed.wav and vo-guide.wav are made by make_bed.sh
  tools/            time_words.py, make_bed.sh, fix_fonts.py

Rebuild after changing SCRIPT.md (each step is safe to re-run)
  1. node $SK/audio.mjs --script ./SCRIPT.md --storyboard ./STORYBOARD.md --hyperframes . --out ./audio_meta.json --provider kokoro --voice af_heart
  2. rm -rf assets/voice-raw && cp -R assets/voice assets/voice-raw
  3. /usr/bin/python3 -I tools/time_words.py          pads each line, lifts it 6 dB, estimates word timings
  4. node $SK/audio.mjs sync-durations --audio-meta ./audio_meta.json --storyboard ./STORYBOARD.md
  5. zsh tools/make_bed.sh                            music bed ducked under the voice, plus quiet sound effects
     (if a frame's length changed, update the cue times in STORYBOARD.md and the frame HTML first)
  6. node $SK/captions.mjs build --storyboard ./STORYBOARD.md --audio-meta ./audio_meta.json --hyperframes . --out ./caption_groups.json
  7. /usr/bin/python3 -I tools/fix_fonts.py compositions/captions.html
  8. node $SK/assemble-index.mjs --storyboard ./STORYBOARD.md --hyperframes .
  9. node $SK/transitions.mjs inject --storyboard ./STORYBOARD.md --hyperframes .
 10. In index.html set the music (el-bgm) data-volume to 1 and each sound effect to 0.7. The bed is already mixed.
 11. npx --yes hyperframes@0.8.164 lint, then check, then snapshot --at <times>
 12. npx --yes hyperframes@0.8.164 render --skill=product-launch-video --quality high --output renders/narrator-demo.mp4

Credits
  Music: "Blue Skies" by Holizna (HoliznaCC0), CC0 1.0, from Free Music Archive. No credit required; given anyway.
  Sound effects: Pixabay Content License, bundled with HyperFrames media-use.
  Fonts: Instrument Serif and Archivo, SIL Open Font License 1.1 (assets/fonts/LICENSE.txt).
