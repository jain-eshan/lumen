---
format: 1920x1080
duration: 50s
message: "Narrator is your AI reading agent: read more, without reading."
arc: Hook (permission to stop reading), Meet the agent, Meet its face, Point, Tune, Sit back, Keeps up and answers, Brand close
audience: Mac users who would rather listen than read long text, including people chatting with Claude
mode: collaborative
music: none
---

## Video direction

- brand: Narrator is "your AI reading agent". Brand line: "Read more. Without reading." The lockup is the app icon + the wordmark "Narrator" (Instrument Serif) + the descriptor "AI reading agent" (Archivo micro-label, uppercase, tracked). The lockup opens the product (Frame 2) and closes the film (Frame 8). Frames 3 to 7 carry a small brand bug in the top-left corner: icon 44px, "Narrator" in Instrument Serif about 30px, "AI reading agent" micro-label under it, at left 64px, top 52px, ink at 85%. The bug sits in exactly the same place in every frame (handoff_in = handoff_out: same x, y, scale 1, opacity 1, static), fades in over the first 0.3s of Frame 3 only and is simply present from t=0 in Frames 4 to 7.
- palette system: paper (#F7F3EA) ground, one sun-bloom (sun / sun-soft / haze) behind the focal element, a faint ember (lavender, #B9A8D6) bloom in the opposite corner. Ink (#121214) for all type. Sun (#FFC729) is the brand accent: the reading highlight, the selection, chip glows, the lantern glow, the brand-line underline. The app's own panels (purpose box, Ask box, playback bar) are dark surfaces shown exactly as rendered. Lumen always stands on a dark ink Dock strip (rounded bar, ink at about 92%, five muted rounded-square tiles) just above the caption band.
- type: Instrument Serif for headlines, the wordmark and the brand line; Archivo for labels, chips and body; JetBrains Mono for keycaps and the URL. Sentence case except the descriptor micro-label.
- Lumen: always the real PNG poses. Lip-sync is a hard swap between lumen-read and lumen-talk at word starts (deterministic). Lumen never scales up and down to breathe.
- motion grammar: smooth long-tail settles (power3); no bounce except the single playful hop in Frame 8. Every frame reveals each piece on its spoken cue. The music lifts at the start of Frame 2, so Frame 2's first reveal should land crisply on its first frame.
- rhythm: Frame 1 is tension, Frame 2 the lift, Frames 3 to 5 brisk, Frame 6 the calm "sit back" breather, Frame 7 brisk again, Frame 8 lands the brand line and holds.
- caption band: the bottom 17% (y 896 to 1080) stays clear.
- negative list: no browser chrome, no real macOS menu bar, no purple-blue AI gradients, no robot or sparkle-AI cliches, no bokeh, no stock photos, no lazy breathing, no slow back-half pan or push, no front-loading, no screensaver floating.

## Frame 1: Too much to read

- scene: Text piles up and blurs; "Too much to read," then "and zero energy to read it?" set; on "Don't." the lines hard-cut to "Don't. Just listen."
- voiceover: "Too much to read, and zero energy to read it? Don't. Just listen."
- duration: 5.24s
- transition_in: cut
- status: animated
- src: compositions/frames/01-too-much.html
- type: hook
- persuasion: Pain validation, then permission
- beat: overwhelm, then relief
- blueprint: compose
- asset_candidates:
- focal: the headline lines
- roles: none, typography only

Compose: the hard-cut swap is the spine.
Scene 1 (0.0 to 1.5s): paper ground, sun-bloom behind center, faint grey text columns rise and stack behind, softly blurred. "Too much to read," assembles word by word on the VO (Too 0.45, much 0.69, to 0.99, read 1.18), display ramp, centered.
Scene 2 (1.5 to 3.2s): a second line sets under it word by word: "and zero energy to read it?" (and 1.54, zero 1.78, energy 2.08, to 2.50, read 2.69, it 2.99).
Scene 3 (3.2 to 5.24s): on "Don't." (3.23) both lines hard-cut in place to one line "Don't. Just listen." with "listen." in the italic display; the text columns clear; a sun highlight sweeps under "listen." on the VO (3.96); hold.

## Frame 2: Meet Narrator

- scene: The brand lockup builds: icon, wordmark, descriptor "AI reading agent"; then "Reads anything on your Mac out loud."; then three chips: Reads anything, Sounds human, Runs on your Mac.
- voiceover: "Meet Narrator, your AI reading agent. It reads anything on your Mac out loud, in a voice that sounds human."
- duration: 7.71s
- transition_in: zoom-through
- status: animated
- src: compositions/frames/02-meet-narrator.html
- type: product_intro
- persuasion: Category creation
- beat: curiosity, then confidence
- blueprint: titlecard-reveal
- asset_candidates: assets/app-icon.png - app icon, Lumen standing on a yellow reading line on a dark rounded square
- focal: assets/app-icon.png
- roles: app-icon = cutout

Adapt: the title-card build (mark, name, descriptor) is the signature; it stays on paper.
Scene 1 (0.0 to 1.3s): on the music lift at t=0 the icon lands (smooth settle) and on "Narrator" (0.59) the wordmark rises beside it; sun-bloom swells behind the icon.
Scene 2 (1.3 to 3.3s): on "your AI reading agent" (1.31) the descriptor "AI READING AGENT" sets under the wordmark as a tracked Archivo micro-label with a short sun underline that draws on "agent" (2.34).
Scene 3 (3.3 to 5.5s): on "It reads anything on your Mac out loud" (3.33) a body-lede line sets word by word: "Reads anything on your Mac out loud."
Scene 4 (5.5 to 7.71s): three square hairline chips land in sequence from "in a voice" (5.5): "Reads anything", "Sounds human", "Runs on your Mac"; "Sounds human" glows sun on "sounds human" (6.28); hold.

## Frame 3: Meet Lumen

- scene: The brand bug fades in top-left. "And it has a face." then "Meet Lumen"; Lumen flutters in, lands on the Dock, reads, then waves.
- voiceover: "And it has a face. Meet Lumen, the little moth who reads with you from your Dock."
- duration: 5.53s
- transition_in: crossfade
- status: animated
- src: compositions/frames/03-meet-lumen.html
- type: product_intro
- persuasion: Character attachment
- beat: delight
- asset_candidates: assets/lumen-fly.png - Lumen hovering, wings spread; assets/lumen-read.png - Lumen reading; assets/lumen-wave.png - Lumen waving; assets/app-icon.png - app icon for the brand bug
- focal: assets/lumen-fly.png then assets/lumen-read.png then assets/lumen-wave.png
- roles: lumen poses = cutout; app-icon = brand bug

Compose: an arrival shot. The headline block sits upper-left but below the brand bug (top at least 190px).
Scene 1 (0.0 to 1.7s): brand bug fades in. Lumen (fly pose) glides in from upper right toward the Dock. "And it has a face." sets word by word (0.30 to 0.98) in the headline-sm ramp.
Scene 2 (1.7 to 2.7s): on "Meet Lumen" (1.76, Lumen 2.08) the big headline "Meet Lumen" sets ("Lumen" italic) and Lumen lands on the Dock right of center, swapping to lumen-read with a small settle.
Scene 3 (2.7 to 5.53s): subline sets word by word from 2.73: "The moth who reads with you, right from your Dock." On "Dock" (4.54) Lumen swaps to lumen-wave and a faint sun glow blooms behind it; hold.

## Frame 4: Point at anything

- scene: Brand bug top-left. A page of text; keycaps Option, Shift, 4 press in; a cursor drags a yellow selection over the page; a small tag reads "anything you'd rather not read".
- voiceover: "Press Option, Shift, 4, and drag over anything you'd rather not read."
- duration: 5.27s
- transition_in: push-slide LEFT
- status: animated
- src: compositions/frames/04-select.html
- type: key_feature
- persuasion: Show, don't tell
- beat: clarity and control
- blueprint: cursor-ui-demo
- asset_candidates: assets/app-icon.png - app icon for the brand bug
- focal: a page card of text (built in HTML)
- roles: app-icon = brand bug

Adapt: one drag, no clicks.
Scene 1 (0.0 to 2.4s): page card in place (same tides text). Keycaps press on the VO: Option 0.62, Shift 1.17, 4 at 1.82.
Scene 2 (2.4 to 4.0s): on "drag" (2.58) the cursor drags and the sun selection grows over both paragraphs.
Scene 3 (4.0 to 5.27s): a small JetBrains Mono sun tag pins to the selection's top-right corner on "rather not read" (3.67): "anything you'd rather not read"; hold.

## Frame 5: Tune it

- scene: Brand bug top-left. The real purpose box slides up; a label "Tell it what to focus on"; the cursor picks Warm, then Man (UK); "Plays a sample" appears.
- voiceover: "Tell it what to focus on. Pick a mood, and a voice you like."
- duration: 4.23s
- transition_in: crossfade
- status: animated
- src: compositions/frames/05-purpose.html
- type: key_feature
- persuasion: Choice and control
- beat: control
- blueprint: panel-edit-live-sync
- asset_candidates: assets/purpose-start.png - real purpose box, nothing picked; assets/purpose-mood.png - after picking Warm; assets/purpose-voice.png - after picking Warm and Man (UK); assets/app-icon.png - app icon for the brand bug
- focal: assets/purpose-start.png then assets/purpose-mood.png then assets/purpose-voice.png
- roles: purpose images = cutout; app-icon = brand bug

Adapt: each click flips the real panel to its next real state.
Scene 1 (0.0 to 1.6s): purpose-start slides up (power3); the label above it reads "Tell it what to focus on" (sets on 0.30).
Scene 2 (1.6 to 2.6s): on "mood" (2.02) the cursor clicks Warm; cut to purpose-mood.
Scene 3 (2.6 to 4.23s): on "voice you like" (2.65 to 3.17) the cursor clicks Man (UK) at 2.96; cut to purpose-voice; the "Plays a sample" tag pops in at 3.05; hold. No sweep over the Woman and Man chips this time.

## Frame 6: Sit back

- scene: Brand bug top-left. The real playback bar slides down; sentences highlight one by one; Lumen reads along on the Dock with mouth and lantern following the voice.
- voiceover: "Then sit back. It reads line by line, highlighting as it goes, while Lumen reads along."
- duration: 6.4s
- transition_in: crossfade
- status: animated
- src: compositions/frames/06-reading.html
- type: key_feature
- persuasion: Show, don't tell
- beat: ease
- asset_candidates: assets/bar-reading.png - real playback bar; assets/lumen-read.png - Lumen reading; assets/lumen-talk.png - Lumen reading aloud; assets/app-icon.png - app icon for the brand bug
- focal: the page card with the highlight
- roles: bar-reading = supporting; lumen-read = cutout; lumen-talk = cutout; app-icon = brand bug
- blueprint: compose

Compose: the calm breather.
Lip-sync word starts for this frame: 0.30, 0.60, 0.84, 1.19, 1.37, 1.73, 2.03, 2.21, 2.56, 3.34, 3.52, 3.69, 4.05, 4.41, 4.77, 5.12. The lantern glow pulses at the same times.
Scene 1 (0.0 to 1.2s): on "Then sit back" the playback bar slides down from the top.
Scene 2 (1.2 to 2.5s): on "It reads line by line" (1.19) sentence one highlights.
Scene 3 (2.5 to 3.7s): on "highlighting as it goes" (2.56) sentence two highlights.
Scene 4 (3.7 to 6.4s): sentence three highlights at 3.69; on "while Lumen reads along" (4.05) the label "Lumen reads along" sets beside Lumen; hold.

## Frame 7: Keeps up, and answers

- scene: Brand bug top-left. A chat card; the Following bar slides down; the reply streams in; then the real Ask box drops in, keycaps press, the question types and Lumen thinks.
- voiceover: "Chatting with Claude? It reads every new reply out loud. Stuck on something? Press Option, Shift, A, and just ask."
- duration: 8.05s
- transition_in: push-slide LEFT
- status: animated
- src: compositions/frames/07-follow-ask.html
- type: key_feature
- persuasion: Value stacking
- beat: confidence
- blueprint: prompt-type-submit-generate
- asset_candidates: assets/bar-following.png - real playback bar in Following state; assets/ask-box.png - real Ask box; assets/lumen-listen.png - Lumen listening; assets/lumen-think.png - Lumen thinking; assets/lumen-read.png - Lumen reading; assets/lumen-talk.png - Lumen reading aloud; assets/app-icon.png - app icon for the brand bug
- focal: the chat card, then assets/ask-box.png
- roles: bar-following = supporting; ask-box = cutout; lumen poses = cutout; app-icon = brand bug

Adapt: type, then submit, then thinking.
Scene 1 (0.0 to 1.6s): on "Chatting with Claude?" the chat card enters with the user bubble.
Scene 2 (1.6 to 3.7s): on "It reads every new reply out loud" (1.64) the Following bar slides down and the reply streams in word by word (1.82 to 3.4); Lumen lip-syncs at 1.64, 1.82, 2.19, 2.55, 2.80, 3.16, 3.40.
Scene 3 (3.7 to 4.9s): on "Stuck on something?" (3.77) the chat dims and steps back; the real Ask box drops in; Lumen swaps to lumen-listen.
Scene 4 (4.9 to 8.05s): keycaps Option 5.35, Shift 5.84, A 6.26; the question types from 6.3 to 7.2: "Why does the Moon cause tides?"; on "ask" (7.0) a submit press and Lumen swaps to lumen-think with thinking dots; hold.

## Frame 8: Read more. Without reading.

- scene: The lockup returns; the brand line "Read more. Without reading." lands big; the GitHub address types in; Lumen cheers.
- voiceover: "Narrator. Read more, without reading. Free on GitHub."
- duration: 7.14s
- transition_in: zoom-through
- status: animated
- src: compositions/frames/08-get-it.html
- type: cta
- persuasion: Brand promise
- beat: motivation
- blueprint: kinetic-type-beats
- asset_candidates: assets/app-icon.png - app icon; assets/lumen-cheer.png - Lumen celebrating
- focal: the brand line
- roles: app-icon = cutout; lumen-cheer = cutout

Adapt: the beat-by-beat snap onto the brand line, then the URL.
Scene 1 (0.0 to 0.9s): on "Narrator." (0.30) the lockup (icon, wordmark, "AI READING AGENT" micro-label) arrives in the upper third, smaller than in Frame 2.
Scene 2 (0.9 to 2.5s): the brand line lands in two beats in the large display ramp: "Read more." on 0.90, then "Without reading." on 1.56 in italic; a sun underline sweeps under "Without reading." on "reading" (2.04).
Scene 3 (2.5 to 4.2s): on "Free on GitHub" (2.58) a JetBrains Mono URL pill types "github.com/jain-eshan/narrator" (2.6 to 3.5) with a small tag beside it: "Free and open source". Lumen (lumen-cheer) on the Dock at bottom right hops once as the URL completes (3.6).
Scene 4 (4.2 to 7.14s): hold on the end card; caret blinks a few times then stops; gentle fade to paper in the last 0.5s.
