"""Download YouTube audio with yt-dlp and transcribe it locally with Whisper.

Run through uv so no global install is needed:

    uv run --with static-ffmpeg --with openai-whisper python transcribe.py --url URL

Exit code is non-zero if any video failed, so a wrapper can detect partial runs.
"""

import argparse
import json
import os
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
        default="small",
        choices=["tiny", "base", "small", "medium", "large", "turbo"],
        help="Whisper model size; smaller models mistranscribe technical vocabulary",
    )
    parser.add_argument("--category", default="General", help="Filename prefix and header field")
    parser.add_argument("--delay", type=int, default=5, help="Seconds to wait between videos in a playlist")
    parser.add_argument("--overwrite", action="store_true", help="Re-transcribe videos that already have a transcript")
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


def transcribe_single_video(vid, title, args, whisper_model):
    file_path = transcript_path(args.output_dir, args.category, title)
    print(f"\n[Processing] {title} ({vid})", flush=True)

    with tempfile.TemporaryDirectory(prefix="yt-whisper-") as temp_dir:
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
            print(f"  transcribing with Whisper ({args.model})", flush=True)
            result = whisper_model.transcribe(audio_path, fp16=False)
        except Exception as exc:  # whisper raises a variety of runtime errors
            print(f"  FAILED transcription: {exc}", flush=True)
            return False

    segments = result.get("segments", [])
    lines = [
        f"# Transcript: {title}\n",
        f"**Category:** `{args.category}` | **Source:** `Whisper {args.model}` | "
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

    import static_ffmpeg

    static_ffmpeg.add_paths()
    import whisper

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

    print(f"Loading Whisper model ({args.model})...")
    whisper_model = whisper.load_model(args.model)

    failures = 0
    for index, (vid, title) in enumerate(pending, 1):
        print(f"[{index}/{len(pending)}]", end=" ")
        if not transcribe_single_video(vid, title, args, whisper_model):
            failures += 1
        if index < len(pending):
            time.sleep(args.delay)

    print(f"\nDone. {len(pending) - failures} succeeded, {failures} failed.")
    if failures:
        sys.exit(1)


if __name__ == "__main__":
    main()
