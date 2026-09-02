"""Download YouTube audio with yt-dlp and transcribe it locally with Whisper.

Run through uv so no global install is needed:

    uv run --with static-ffmpeg --with openai-whisper python transcribe.py --url URL

Exit code is non-zero if any video failed, so a wrapper can detect partial runs.
"""

import argparse
import json
import os
import platform
import re
import subprocess
import sys
import tempfile
import time

VIDEO_ID_RE = re.compile(r"(?:v=|/)([a-zA-Z0-9_-]{11})")


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", help="Single YouTube video URL or 11-character video ID")
    parser.add_argument("--playlist", help="YouTube playlist URL")
    parser.add_argument("--output-dir", default="transcripts", help="Where the Markdown transcripts are written")
    parser.add_argument(
        "--model",
        default="turbo",
        choices=["tiny", "base", "small", "medium", "large", "turbo"],
        help="Whisper model size; smaller models mistranscribe technical vocabulary",
    )
    parser.add_argument("--category", default="General", help="Filename prefix and header field")
    parser.add_argument("--delay", type=int, default=5, help="Seconds to wait between videos in a playlist")
    parser.add_argument("--overwrite", action="store_true", help="Re-transcribe videos that already have a transcript")
    parser.add_argument("--prefer-native-subtitles", action="store_true", default=True, help="Prefer downloading YouTube native subtitles if available (default: True)")
    parser.add_argument("--force-whisper", action="store_true", help="Bypass native subtitles and force AI audio transcription")
    parser.add_argument("--engine", choices=["auto", "mlx", "cpu"], default="auto", help="Execution engine for transcription (default: auto)")
    return parser.parse_args()


def sanitize_filename(name):
    name = re.sub(r"[^\w\s-]", "", name).strip().replace(" ", "_")
    return name[:60] or "Untitled"


def format_timestamp(seconds):
    seconds = int(seconds)
    hours, rest = divmod(seconds, 3600)
    minutes, secs = divmod(rest, 60)
    if hours:
        return f"{hours}:{minutes:02d}:{secs:02d}"
    return f"{minutes:02d}:{secs:02d}"
def parse_vtt(vtt_text):
    segments = []
    blocks = re.split(r'\n{2,}', vtt_text.strip())
    for block in blocks:
        lines = [line for line in block.splitlines() if line.strip()]
        if not lines:
            continue
        
        time_line_idx = -1
        for i, line in enumerate(lines):
            if '-->' in line:
                time_line_idx = i
                break
                
        if time_line_idx != -1:
            time_str = lines[time_line_idx].split('-->')[0].strip()
            parts = time_str.split(':')
            try:
                seconds = float(parts[-1])
                if len(parts) >= 2:
                    seconds += int(parts[-2]) * 60
                if len(parts) >= 3:
                    seconds += int(parts[-3]) * 3600
                    
                text_lines = lines[time_line_idx+1:]
                text = " ".join(re.sub(r'<[^>]+>', '', l).strip() for l in text_lines)
                text = text.replace('\n', ' ')
                segments.append({"start": seconds, "text": text})
            except ValueError:
                pass
    return segments



def get_video_info(video_url_or_id):
    cmd = ["uvx", "yt-dlp", "--dump-json", "--no-warnings", video_url_or_id]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
        data = json.loads(res.stdout)
        return data.get("id"), data.get("title", "Untitled")
    except (subprocess.CalledProcessError, json.JSONDecodeError, OSError):
        # Metadata lookup can fail while the download still works; fall back to
        # the ID embedded in the URL so the video is not skipped outright.
        match = VIDEO_ID_RE.search(video_url_or_id)
        vid = match.group(1) if match else video_url_or_id
        return vid, f"YouTube_Video_{vid}"


def get_playlist_videos(playlist_url):
    cmd = ["uvx", "yt-dlp", "--flat-playlist", "--dump-json", "--no-warnings", playlist_url]
    videos = []
    try:
        res = subprocess.run(cmd, capture_output=True, text=True, check=True)
    except (subprocess.CalledProcessError, OSError) as exc:
        print(f"ERROR: could not read playlist: {exc}", flush=True)
        return videos

    for line in res.stdout.strip().split("\n"):
        if not line:
            continue
        try:
            item = json.loads(line)
        except json.JSONDecodeError as exc:
            print(f"WARN: skipping unparsable playlist line: {exc}", flush=True)
            continue
        videos.append((item.get("id"), item.get("title", "Untitled")))
    return videos


def transcript_path(output_dir, category, title):
    return os.path.join(output_dir, f"{category}_{sanitize_filename(title)}.md")


def transcribe_single_video(vid, title, args, model_container):
    file_path = transcript_path(args.output_dir, args.category, title)
    print(f"\n[Processing] {title} ({vid})", flush=True)

    with tempfile.TemporaryDirectory(prefix="yt-whisper-") as temp_dir:
        segments = []
        source_label = f"Whisper {args.model} ({args.engine_used})"
        
        if not args.force_whisper and args.prefer_native_subtitles:
            print("  checking for native subtitles...", flush=True)
            langs = "en.*,en,tr.*,tr"
            cmd = [
                "uvx", "yt-dlp",
                "--write-sub",
                "--sub-lang", langs,
                "--sub-format", "vtt",
                "--skip-download",
                "-o", os.path.join(temp_dir, "%(id)s.%(ext)s"),
                f"https://www.youtube.com/watch?v={vid}"
            ]
            try:
                subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
                vtt_file = next((f for f in os.listdir(temp_dir) if f.endswith(".vtt")), None)
                if vtt_file:
                    vtt_path = os.path.join(temp_dir, vtt_file)
                    with open(vtt_path, "r", encoding="utf-8") as f:
                        vtt_text = f.read()
                    parsed_segments = parse_vtt(vtt_text)
                    if parsed_segments:
                        segments = parsed_segments
                        source_label = "YouTube Native Subtitles"
                        print(f"  downloaded native subtitles: {vtt_file}", flush=True)
            except Exception:
                pass
        
        if not segments:
            audio_path = os.path.join(temp_dir, f"{vid}.m4a")
            print("  downloading audio via yt-dlp", flush=True)
            cmd = ["uvx", "yt-dlp", "-f", "ba", "-o", audio_path, f"https://www.youtube.com/watch?v={vid}"]
            try:
                subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
            except subprocess.CalledProcessError as exc:
                print(f"  FAILED download: {exc.stderr.strip().splitlines()[-1] if exc.stderr else exc}", flush=True)
                return False
            except OSError as exc:
                print(f"  FAILED download: {exc}", flush=True)
                return False

            try:
                print(f"  transcribing with Whisper ({args.model} on {args.engine_used})", flush=True)
                if args.engine_used == "mlx":
                    import mlx_whisper
                    mlx_model_name = args.mlx_model_mapping.get(args.model, f"mlx-community/whisper-{args.model}-mlx")
                    result = mlx_whisper.transcribe(audio_path, path_or_hf_repo=mlx_model_name)
                    segments = result.get("segments", [])
                else:
                    if model_container.get("whisper") is None:
                        import static_ffmpeg
                        static_ffmpeg.add_paths()
                        import whisper
                        print(f"  loading Whisper model ({args.model}) on CPU...", flush=True)
                        model_container["whisper"] = whisper.load_model(args.model)
                    result = model_container["whisper"].transcribe(audio_path, fp16=False)
                    segments = result.get("segments", [])
            except Exception as exc:  # whisper raises a variety of runtime errors
                print(f"  FAILED transcription: {exc}", flush=True)
                return False

    lines = [
        f"# Transcript: {title}\n",
        f"**Category:** `{args.category}` | **Source:** `{source_label}` | "
        f"**YouTube ID:** [{vid}](https://www.youtube.com/watch?v={vid})\n\n---\n",
    ]
    for segment in segments:
        lines.append(f"[{format_timestamp(segment.get('start', 0))}] {str(segment.get('text', '')).strip()}")

    # Write only after a successful transcription, so an interrupted run never
    # leaves a truncated file that the resume check would mistake for done.
    os.makedirs(args.output_dir, exist_ok=True)
    with open(file_path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))

    print(f"  wrote {len(segments)} lines to {file_path}", flush=True)
    return True


def main():
    args = parse_args()

    if bool(args.url) == bool(args.playlist):
        print("Error: pass exactly one of --url or --playlist.")
        sys.exit(2)

    if args.url:
        videos = [get_video_info(args.url)]
    else:
        videos = get_playlist_videos(args.playlist)

    pending = []
    skipped = 0
    for vid, title in videos:
        if not args.overwrite and os.path.exists(transcript_path(args.output_dir, args.category, title)):
            skipped += 1
            continue
        pending.append((vid, title))

    print(f"{len(videos)} video(s) found, {skipped} already transcribed, {len(pending)} to process.")
    if not pending:
        return

    if args.model in ("tiny", "base"):
        print("="*60)
        print(f"WARNING: You are using the '{args.model}' model.")
        print("Benchmarks show 40%-65% accuracy. Expect severe hallucinations in Turkish and technical vocabulary.")
        print("="*60)

    args.engine_used = "cpu"
    args.mlx_model_mapping = {}
    model_container = {}

    if args.engine == "auto":
        is_apple_silicon = platform.system() == "Darwin" and platform.machine() == "arm64"
        if is_apple_silicon:
            args.engine_used = "mlx"
    elif args.engine == "mlx":
        args.engine_used = "mlx"

    if args.engine_used == "mlx":
        try:
            import mlx_whisper
            args.mlx_model_mapping = {
                "turbo": "mlx-community/whisper-turbo",
                "tiny": "mlx-community/whisper-tiny-mlx",
                "base": "mlx-community/whisper-base-mlx",
                "small": "mlx-community/whisper-small-mlx",
                "medium": "mlx-community/whisper-medium-mlx",
                "large": "mlx-community/whisper-large-v3-mlx",
            }
        except ImportError:
            print("mlx_whisper not found, falling back to CPU whisper", flush=True)
            args.engine_used = "cpu"

    failures = 0
    for index, (vid, title) in enumerate(pending, 1):
        print(f"[{index}/{len(pending)}]", end=" ")
        if not transcribe_single_video(vid, title, args, model_container):
            failures += 1
        if index < len(pending):
            time.sleep(args.delay)

    print(f"\nDone. {len(pending) - failures} succeeded, {failures} failed.")
    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
