---
name: 7tv-emotes
description: >-
  Find and download emotes/stickers/GIFs from 7TV (7tv.app) by name. Use whenever the user wants
  to grab, fetch, download, or look up a 7TV emote — "get me the peepoHappy gif", "download the
  catJAM emote", "find a 7tv sticker of X", "grab that pog emote" — or wants a 7TV emote turned
  into a sticker for SeaTalk/WhatsApp/etc. Search and download need no auth. Even if the user
  doesn't say "7TV" by name, reach for this when they clearly want a Twitch/streamer-style emote
  or animated chat sticker by name. (Read/download only — this skill does not write to 7TV emote
  sets, which would require a logged-in JWT.)
---

# 7TV emotes — find & download

Search 7TV by emote name and download the image/GIF. No account or token needed — search and the
CDN are public. Everything runs through one bundled script; don't hand-roll curl/GraphQL.

## Tool

`scripts/7tv.sh` — two subcommands:

```bash
scripts/7tv.sh search "<query>" [limit]        # -> rows of:  <id> <TAB> <animated true|false> <TAB> <name> <TAB> <channels>
scripts/7tv.sh get <id> [name] [size] [outdir] # -> downloads, prints the saved file path
```

Search rows are **ranked by usage (most-used first)** — the 4th column is how many channels
have the emote, which is the popularity signal. 7TV's own default order is newest-first and its
`sort` arg is ignored, so this client-side ranking is what makes the *real* classic emote (the one
people mean) come out on top instead of some fresh 2-channel upload with the same name.

- **Size** is `1x|2x|3x|4x` (4x = largest, the default). For stickers, 4x is right — the pipeline size-caps anyway.
- **Format is auto-picked**: animated emotes download as `.gif`, static ones as `.png` (with `.webp` as a last-resort fallback). You don't choose — the script probes what exists.

## Workflow

1. **Search.** Run `scripts/7tv.sh search "<term>"`. Use the user's term as-is; 7TV matching is fuzzy and case-insensitive.

2. **Let the user pick — names collide heavily.** A single name like `peepoHappy` returns *hundreds* of near-identical variants (different artists, animated vs static, subtle spelling). Results are usage-ranked, so the **top row is the most-used variant** — usually the one the user means, and the right default to lean toward. But don't blind-grab it silently: show a short list — name, whether it's animated, and the channel count as the popularity cue — and let them choose, unless their request is specific enough that one row is the unambiguous match (e.g. they gave an exact + uncommon name). Animated-vs-static is the detail people care about most, so surface it too.

   When showing options, keep it scannable — you don't need to expose the raw IDs (they're internal), but **do** show the usage count, since that's how the user tells the famous emote from a clone. Something like: *"Found a few — 1) peepoHappy (animated, 8.2k channels), 2) peepoHappy (static, 410), 3) peepoHappyU (animated, 12). Top one's the most-used — go with that?"*

3. **Download.** `scripts/7tv.sh get <id> <name> 4x <outdir>`. Pass the emote name so the file lands as `<name>.<ext>` rather than a cryptic ID. The script prints the saved path — relay it.

   **Where to save (`outdir`):**
   - Default to `~/Desktop` unless the user says otherwise.
   - If the intent is to make a **sticker** (they mention SeaTalk, WhatsApp, "make it a sticker", or you're clearly feeding the sticker pipeline), save straight into the stickers repo's `input/` folder so it's ready to process. **Never hardcode an absolute path** — this skill ships inside the stickers repo and is also used via a user-level symlink, so resolve the repo at runtime: `REPO=$(scripts/7tv.sh repo-root)` and save into `$REPO/input`. That works for any clone location, any user, and through the symlink. Then offer to run the pipeline — see below.

4. **Optional — hand off to the sticker pipeline.** If the download was for a sticker, after saving into `$REPO/input` you can offer: *"Want me to run the sticker pipeline on it?"* and, on yes, run `(cd "$REPO" && ./main.sh)`. (That's a separate flow; this skill's job ends at the download.)

## Notes

- **No auth for any of this.** Adding an emote to *your own* 7TV set would need a logged-in JWT — out of scope here; tell the user to do that on 7tv.app directly if they ask.
- **If search returns nothing**, the name may be off — 7TV emotes are community-named and often have odd capitalization/suffixes. Suggest the user try a shorter or alternate spelling rather than guessing wildly.
- **Endpoints** (for reference; the script handles them): search = `https://7tv.io/v3/gql`, download = `https://cdn.7tv.app/emote/{id}/{size}.{fmt}`. The 7TV API is mid-rewrite, so if `search` ever starts returning errors/empty for everything, the GraphQL schema likely shifted — re-verify the query shape against `7tv.io` before assuming the emote doesn't exist.
