# Whisper Models and Execution Tiers

The YouTube Whisper Transcriber uses a tiered approach to process transcripts as quickly and accurately as possible. 

## Execution Tiers

1. **Tier 1: Native Subtitles (~2s)**
   - The fastest method. If the video has manually provided or clean subtitles (preferring English or Turkish), they are fetched directly via `yt-dlp`.
   - **Why it matters:** Skips downloading large audio files and bypassing ML inference completely, turning minutes of work into a ~2-second network request.
2. **Tier 2: Apple Silicon MLX Whisper (~2-3 min)**
   - When native subtitles are missing or bypassed (via `--force-whisper`), execution falls back to AI audio transcription.
   - On Apple Silicon (`Darwin` `arm64`), the `auto` engine uses GPU-accelerated `mlx_whisper` for massive speedups on Mac (e.g. M3).
3. **Tier 3: Standard CPU Whisper (Fallback)**
   - Standard `openai-whisper` executed on the CPU using `fp16=False`. Used only when MLX is unavailable or when forced via `--engine cpu`.

## Model Sizes & Accuracy Benchmarks

| Model | Parameters | Expected Accuracy | Performance Characteristics |
|---|---|---|---|
| **tiny** | 39 M | ~40% | Too inaccurate for general use. Severe hallucinations in technical vocabulary and languages like Turkish. |
| **base** | 74 M | ~65% | Unreliable for complex domains. Mistranscribes specialized jargon. |
| **small** | 244 M | ~85% | The minimum baseline for acceptable English technical talks, but struggles with thick accents. |
| **medium**| 769 M | ~93% | Very strong performance across most domains. |
| **turbo** | 809 M | ~99% | **(Default)** Optimized for speed and accuracy. Provides near-perfect transcripts, excellent multi-language support (like Turkish), and runs extremely fast on MLX. |
| **large** | 1550 M | ~99% | The most accurate model but slow on CPU. MLX-accelerated `large-v3` handles difficult edge cases optimally. |

### Why `turbo` is the Default
The `turbo` model offers the sweet spot: accuracy near `large` but inference speed near `small`, particularly when hardware-accelerated. Because technical talks turn entirely on acronyms, library names, and jargon, smaller models fail precisely where transcripts provide the most value. 

> **WARNING:** The `tiny` and `base` models are strongly discouraged for anything other than pipeline debugging. Their 40-65% accuracy benchmark means they will confidently invent words, resulting in unusable material for LLM contexts.
