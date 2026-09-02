---
name: youtube-whisper-transcriber
description: Turns a YouTube video, talk, podcast or playlist into a timestamped Markdown transcript. Use this skill WHENEVER the user mentions a YouTube URL, a video ID, or asks to transcribe, summarize, search or analyze a video. Automatically attempts to fetch native manual subtitles first, then falls back to hardware-accelerated AI audio transcription.
compatibility: Requires `uv` on PATH and network access. Uses MLX for Apple Silicon GPU acceleration or Whisper on CPU; no API key is used.
---

# YouTube Whisper Transcriber

Converts YouTube videos into a timestamped Markdown transcript using a tiered transcription process, ensuring the fastest and most accurate output.

## Execution Flow (3-Tiered)

To maximize performance, this tool defaults to the fastest available transcription tier:
1. **Tier 1: Native Subtitles (~2s)** - Automatically checks for manual/clean YouTube subtitles (e.g., English, Turkish) and parses them instantly.
2. **Tier 2: Apple Silicon MLX GPU (~2-3 min)** - If native subtitles are missing, falls back to `mlx_whisper` for massive hardware acceleration on compatible Macs.
3. **Tier 3: Standard CPU Whisper** - Falls back to standard CPU inference (`openai-whisper`) if MLX is unavailable.

For details on model parameter sizes, accuracy metrics, and why `turbo` is the preferred default, read `references/models.md` BEFORE changing the default model.

## Where transcripts belong

Write transcripts into the **data** workspace (`~/work/knowledge/transcripts/`), never into the vault's `50-knowledge/ai/`. Transcripts are raw input material, not doctrine and not measurement; a few hundred of them would turn the vault's history into a document store. Pass `--output-dir` explicitly rather than relying on the default.

## Running it

Single video (On Apple Silicon, add `--with mlx-whisper` for GPU acceleration):

```bash
uv run --with static-ffmpeg --with openai-whisper --with mlx-whisper \
  python <path-to-skill>/scripts/transcribe.py \
  --url "https://www.youtube.com/watch?v=VIDEO_ID" \
  --output-dir transcripts \
  --category L1_ClaudeCode \
  --model turbo
```

Whole playlist:

```bash
uv run --with static-ffmpeg --with openai-whisper --with mlx-whisper \
  python <path-to-skill>/scripts/transcribe.py \
  --playlist "https://www.youtube.com/playlist?list=PLAYLIST_ID" \
  --output-dir transcripts \
  --category Conference \
  --delay 5
```

The run is resumable: a video whose transcript file already exists is skipped. Re-running an interrupted playlist is safe.

## Parameters

| Flag | Meaning | Default |
|---|---|---|
| `--url` | Single video URL or 11-character video ID | - |
| `--playlist` | Playlist URL | - |
| `--output-dir` | Directory for the Markdown transcripts | `transcripts` |
| `--model` | Whisper size: `turbo`, `tiny`, `base`, `small`, `medium`, `large` | `turbo` |
| `--prefer-native-subtitles` | Try fetching manual YouTube subs first before downloading audio | `True` |
| `--force-whisper` | Bypass native subtitles; force AI transcription | `False` |
| `--engine` | Override execution tier (`auto`, `mlx`, `cpu`) | `auto` |
| `--category` | Prefix for the filename and a field in the header | `General` |
| `--delay` | Seconds between videos in a playlist | `5` |
| `--overwrite` | Re-transcribe videos that already have a transcript file | off |

## WARNING: `tiny` and `base` Models

If the user explicitly requests the `tiny` or `base` models, you MUST remind them of the benchmark results (found in `references/models.md`): **40%-65% accuracy** and severe hallucinations in Turkish and technical vocabulary. Recommend `turbo` instead, as it is heavily optimized and accurate (~99%).

## Output format

```markdown
# Transcript: Inside Claude Code With Its Creator

**Category:** `Main` | **Source:** `Whisper turbo (mlx)` | **YouTube ID:** [PQU9o_5rHC4](https://www.youtube.com/watch?v=PQU9o_5rHC4)

---

[00:00] At Anthropic the way that we thought about it is we don't build for the model of today.
[00:03] We build for the model six months from now.
```

## Reading a transcript afterwards

A conference talk transcript runs to several thousand lines. Reading one whole into the main session buys a summary at the cost of the rest of the session. Delegate it: send an `Explore` or general-purpose subagent at the file with the specific question, and keep the answer rather than the transcript.

