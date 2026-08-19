---
name: youtube-whisper-transcriber
description: Turns a YouTube video, talk, podcast or playlist into a timestamped Markdown transcript by downloading the audio with yt-dlp and running Whisper locally. Use this skill whenever the user wants a video transcribed, summarised, searched or quoted, even when they only paste a URL and say something like "what is in this talk" - and especially when YouTube subtitles are disabled, machine-generated, or blocked by HTTP 429 / IpBlocked.
compatibility: Requires `uv` on PATH and network access. Whisper runs on CPU; no API key is used.
---

# YouTube Whisper transcriber

Converts YouTube audio into a timestamped Markdown transcript using `yt-dlp` for
download and local Whisper for transcription.

## Why local Whisper rather than YouTube subtitles

YouTube's auto-captions are fragmented (no sentence boundaries, no punctuation),
silently unavailable on many videos, and rate-limited per IP. A transcript that
is sometimes missing and sometimes malformed cannot be the input to anything
durable. Running Whisper on the downloaded audio makes the output a function of
the audio alone: same video, same transcript, this year and in three years.

The cost is CPU time. That is the trade being made deliberately.

## Where transcripts belong

Write transcripts into the **data** workspace (`~/work/knowledge/transcripts/`),
never into `ai-hub`. Transcripts are raw input material, not doctrine and not
measurement; a few hundred of them would turn the hub's history into a document
store. Pass `--output-dir` explicitly rather than relying on the default.

## Running it

Single video:

```bash
uv run --with static-ffmpeg --with openai-whisper \
  python <path-to-skill>/scripts/transcribe.py \
  --url "https://www.youtube.com/watch?v=VIDEO_ID" \
  --output-dir transcripts \
  --category L1_ClaudeCode \
  --model small
```

Whole playlist:

```bash
uv run --with static-ffmpeg --with openai-whisper \
  python <path-to-skill>/scripts/transcribe.py \
  --playlist "https://www.youtube.com/playlist?list=PLAYLIST_ID" \
  --output-dir transcripts \
  --category Conference \
  --delay 5
```

The run is resumable: a video whose transcript file already exists is skipped
without downloading it again. Re-running an interrupted playlist is therefore
cheap and safe. Pass `--overwrite` only when the intent is to redo work, for
example after moving to a larger model.

## Parameters

| Flag | Meaning | Default |
|---|---|---|
| `--url` | Single video URL or 11-character video ID | - |
| `--playlist` | Playlist URL | - |
| `--output-dir` | Directory for the Markdown transcripts | `transcripts` |
| `--model` | Whisper size: `tiny`, `base`, `small`, `medium`, `large`, `turbo` | `small` |
| `--category` | Prefix for the filename and a field in the header | `General` |
| `--delay` | Seconds between videos in a playlist | `5` |
| `--overwrite` | Re-transcribe videos that already have a transcript file | off |

## Choosing a model size

`tiny` mistranscribes technical vocabulary badly - product names, library names
and acronyms are exactly the words a technical talk turns on, and exactly the
ones it gets wrong. Since the transcript is meant to be kept for years while the
transcription is done once, prefer `small` or larger and pay the CPU time once.
Use `tiny` only to check that the pipeline works end to end.

## Output format

```markdown
# Transcript: Inside Claude Code With Its Creator

**Category:** `Main` | **Source:** `Whisper small` | **YouTube ID:** [PQU9o_5rHC4](https://www.youtube.com/watch?v=PQU9o_5rHC4)

---

[00:00] At Anthropic the way that we thought about it is we don't build for the model of today.
[00:03] We build for the model six months from now.
```

Timestamps are `MM:SS` under an hour and `H:MM:SS` beyond it, so a two-hour
keynote stays quotable.

## Reading a transcript afterwards

A conference talk transcript runs to several thousand lines. Reading one whole
into the main session buys a summary at the cost of the rest of the session.
Delegate it: send an `Explore` or general-purpose subagent at the file with the
specific question, and keep the answer rather than the transcript.
