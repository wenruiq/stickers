#!/usr/bin/env bash
# Minimal 7TV emote search + download. No auth needed (read/download only).
#
#   7tv.sh search "<query>" [limit]        -> rows: id <TAB> animated <TAB> name <TAB> channels
#                                              (ranked by channel usage, most-used first)
#   7tv.sh get <id> [name] [size] [outdir] -> downloads best format, prints saved path
#
# Download format is auto-picked: gif (animated) > png (static) > webp (fallback).
# Sizes: 1x 2x 3x 4x (4x = largest, default).
set -euo pipefail

GQL="https://7tv.io/v3/gql"
CDN="https://cdn.7tv.app/emote"
UA="7tv-emotes-skill/1.0"

cmd="${1:-}"; shift || true

case "$cmd" in
  repo-root)
    # Print the stickers repo root (the dir containing main.sh). Resolves through
    # symlinks via `cd -P`, so this is correct whether the skill is invoked from a
    # cloned repo copy or a user-level symlink that points back into the repo.
    here="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    d="$here"
    while [ "$d" != "/" ]; do
      if [ -f "$d/main.sh" ]; then echo "$d"; exit 0; fi
      d="$(dirname "$d")"
    done
    echo "repo root (dir containing main.sh) not found above $here" >&2
    exit 1
    ;;
  search)
    q="${1:?usage: search \"<query>\" [limit]}"; limit="${2:-15}"
    # 7TV's API floors search results at ~30 regardless of the `limit` arg, and its
    # `sort` argument is currently ignored (API mid-rewrite) — the default order is
    # newest-first, which buries classic emotes (e.g. the real `4Head`) under fresh
    # uploads that nobody uses. So we pull each emote's usage count (`channels.total`)
    # and rank client-side by it, most-used first, then cap with `head`. Output gains
    # a 4th column: the channel count, so the picker can show popularity.
    body=$(jq -nc --arg q "$q" \
      '{query:"query($q:String!){emotes(query:$q,limit:30){count items{id name animated channels{total}}}}",variables:{q:$q}}')
    curl -s -m 25 -A "$UA" -X POST "$GQL" -H 'Content-Type: application/json' --data "$body" \
      | jq -r '.data.emotes.items | sort_by(-(.channels.total // 0))[] | [.id, (.animated|tostring), .name, ((.channels.total // 0)|tostring)] | @tsv' \
      | head -n "$limit"
    ;;
  get)
    id="${1:?usage: get <id> [name] [size] [outdir]}"
    name="${2:-$id}"; size="${3:-4x}"; dir="${4:-.}"
    mkdir -p "$dir"
    safe=$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_')
    for fmt in gif png webp; do
      out="$dir/$safe.$fmt"
      if curl -s -m 60 -A "$UA" -f -o "$out" "$CDN/$id/$size.$fmt"; then
        echo "$out"; exit 0
      fi
      rm -f "$out"
    done
    echo "no downloadable file for $id at $size (tried gif/png/webp)" >&2
    exit 1
    ;;
  *)
    echo "usage: 7tv.sh search \"<query>\" [limit] | get <id> [name] [size] [outdir]" >&2
    exit 2
    ;;
esac
