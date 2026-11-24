# Changelog

Every release is on the [releases page](https://github.com/jain-eshan/lumen/releases), with the download and its SHA-256. Newest first.

## 1.4.1: Follow reads the whole reply

Fixes to Follow, the mode that reads Claude's replies as they arrive. It was missing text and reading things it should not, most of all when the selected area covered more than the chat column.

- **Long replies are read to the end.** When everything on screen has been read, Lumen scrolls down by itself and carries on. It scrolls over the text, tries other spots if the page does not move, and only then decides the page has ended.
- **Nothing is skipped after a scroll.** With a side panel inside the selection, text below the point already read could be ignored. It is now read.
- **Your own message is not read back to you.** That includes long messages and wide selections.
- **Short replies are read.** "Go ahead." was dropped as too short.
- **Claude's folded "thinking" line is skipped.**
- **A longer pause between paragraphs.**
- **A safety net.** Text that sits on screen unread for 6 seconds while nothing else is happening is read anyway, and the log says `guard:`.
- **A clearer log.** Pauses, resumes and every scroll (where it landed and whether the page moved) are recorded. The log never contains the text on screen.
- **Checks you can run.** `evals/run.sh` reads a drawn stand-in for the Claude chat with nothing showing on screen, one scenario per reported failure. There are 133 self-tests.

Also in this version, outside Follow:

- **Answers stay on screen.** Ask used to show one sentence at a time in a small strip that vanished a few seconds after the answer ended. The answer now appears in a card with the whole text at 17pt, the sentence being spoken highlighted, and buttons to open the source, copy the answer and stop the voice. It stays until you close it with Esc or ×, and a box underneath takes a follow-up.
- **Bigger text in the boxes.** The question field is 17pt (was 15) and the hint lines 12.5pt (was 11.5), in the Ask, purpose and note boxes.
- **Move any box.** Drag the playback bar, the Ask box, the answer card, the purpose box, the note box or the notes tray by their background if one covers something you need to see. Each opens in the new spot next time, on whichever display you put it. The tray no longer jumps back to the side when you add a part.
- **Lumen follows your Dock.** She now reads the Dock's real position on every step. If you resize the Dock, move it to another display, hide it or have none at the bottom, she walks or flutters onto the new floor instead of hovering where the Dock used to be. With no Dock at the bottom she stands on the screen's bottom edge, clear of a Dock at the side.

Known open items are tracked in [Issues](https://github.com/jain-eshan/lumen/issues).

## 1.4: Note for Claude

Mark parts of any document, write a thought on each, and paste them all into a Claude chat in one go. A PDF on your Mac comes back marked up, other documents as a notes PDF with the original attached, and anything else as a notes PDF with a picture of each part. History keeps your note sets and a list of what Lumen read aloud for 30 days.

## 1.3.2: Narrator is now Lumen

Same app, new name and icon. The playback bar and highlight use Lumen's colours. Reading, Ask, Follow and the voice are unchanged. Lumen keeps Narrator's settings.

## 1.3.1: Connect Claude

A guided way to connect Claude Code, with sign-in handled for you. Lumen finds Claude Code wherever it is installed, uses only a Claude plan and never an API account, and says why when Ask cannot answer.

## 1.3: Tables, and a lighter app

- A table is read row by row, with each value named by its column.
- Keep Lumen in one place.
- Smoother scrolling and highlighting.
- A smaller download (about 600 MB, down from 915 MB), a faster voice start and about 170 MB less memory.
- Follow stays quick in long sessions, and Lumen uses about 2% of one processor core while idle, down from about 15%.

## 1.2: Your AI reading agent

A 50-second demo video and a clearer introduction. Everything else is unchanged from 1.1.

## 1.1: Meet Lumen

The moth on your Dock, who reads along with the voice. A voice picker (a woman or a man, American or British, or Auto) with samples, and a plain Ask box.

## 1.0

The first build for Apple silicon Macs on macOS 14 or later: select an area, and a voice that runs on your Mac reads it aloud.
