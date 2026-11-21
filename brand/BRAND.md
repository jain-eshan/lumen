# Lumen brand guide

Lumen is a Mac app that reads anything on your screen aloud, and Lumen is also the small moth who lives on your Dock and does the reading. The product and the character share one name on purpose: "Lumen reads to you" is true both ways.

The app was called Narrator until version 1.3.2. Say "Lumen (formerly Narrator)" on public pages until the middle of 2027, so people who saw the first launch can find it.

## Name

- Write **Lumen**, with a capital L, in sentences. The wordmark is lowercase; text is not.
- Many products are called Lumen. Anywhere people search for it (store listings, the GitHub description, social bios, page titles), write **Lumen, the reading moth for Mac** the first time.
- Don't call it "Lumen app", "Lumen AI" or "LumenReader". Don't translate or abbreviate it.
- Lumen is "it", never "he" or "she".

## Words

| Use | Text |
|---|---|
| Tagline | Lumen reads to you. |
| One line (under 60 characters) | A small moth on your Dock that reads your screen aloud |
| Short description | Lumen is a Mac app that reads anything on your screen out loud, line by line, in a natural voice that runs entirely on your Mac. Point it at a Claude reply, an article or a long email thread, and a small moth on your Dock reads along with you. No account, no API key, works offline. |
| Proof points | Reads anything you can see. The voice runs on your Mac. Lumen keeps you company. |

## Voice

Lumen is bookish, calm and a little shy. It speaks in short, plain sentences.

- In the app (welcome, tips, errors), Lumen speaks for itself: "I'll read that for you." "Pick a spot and I'll start."
- In the README, release notes and docs, write in plain third person: "Lumen reads the area you select."
- Keep the charm in the art and the motion. No exclamation marks, no "Yay", no emoji in product text.
- Name the exact thing: "Allow Screen Recording for Lumen", not "Grant permissions".

## Logo

| File | Use it for |
|---|---|
| `lumen-icon.png` | App icon, avatars, favicons, Product Hunt thumbnail. 1024 × 1024, transparent outside the rounded square. |
| `lumen-wordmark-banner.png` | Page headers and social images where a dark band fits. Night-ink background included. |
| `lumen-wordmark-on-dark.png` | The word on any dark background. Transparent. |
| `lumen-wordmark-on-light.png` | The word on any light background. Transparent. |
| `lumen-social-1280x640.png` | GitHub social preview (Settings > Social preview). Icon, wordmark and tagline on night ink. |
| `lumen-og-1200x630.png` | Share image for web pages (Open Graph), used by eshanjain.com/lumen. |

The source images (raw generations) are `art/lumen-icon-final.png` and `art/lumen-wordmark-final.png`.

Rules:

- The icon tells you what Lumen does (a moth reading a glowing line). The wordmark tells you who it is (the m is the moth). Use them together on first contact, apart once people know the name.
- Below 24 px tall, use the icon, not the wordmark. The antennae turn to fuzz.
- Leave clear space around the wordmark equal to the height of the "u".
- Don't recolour, stretch, outline, add shadows to, or set the wordmark in a real font. The m is drawn, not typed.
- The wordmark is a picture. For large print or a vector need, redraw it as an SVG first.

## Colour

| Name | Hex | Role |
|---|---|---|
| Night ink | `#171527` | Backgrounds, text on light pages |
| Moth cream | `#F3EAD8` | Text on dark, paper, highlights' surroundings |
| Dusk lavender | `#8E7FA6` | Wings, secondary accents, quiet UI |
| Lantern amber | `#E8A33D` | The light. Use it for one thing per screen: the line being read, the main button, the glow |

The look is a warm light in a dark room. Mostly night ink and cream, a little lavender, one spot of amber. `tokens.css` has these as CSS variables.

## Type

- Headlines on the web: **Fraunces** (Google Fonts), weight 500 to 600, which is close to the wordmark's bookish serif.
- Body text on the web: the system font stack.
- In the app: the system font (SF Pro). The app's reading highlight uses Lantern amber.

## Where the brand lives

| Place | What carries the brand |
|---|---|
| The app | Name, icon, menu, Lumen's welcome lines |
| github.com/jain-eshan/lumen | README header, description, topics, social preview image |
| eshanjain.com/lumen | Landing page, case study, share image |
| Product Hunt | Name, tagline, thumbnail, gallery |
| Release notes and posts | Name, voice, the "formerly Narrator" line |
