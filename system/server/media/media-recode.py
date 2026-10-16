"""Temporary space-reclaim re-encode for the over-encoded tail of the library.

The library is bimodal. Most of it (1093 HEVC 1080p files, median 2.17 Mbps,
0.045 bits per pixel per frame) is already at the efficiency a re-encode would
target, and re-encoding it is pure generation loss. A small tail is not encodes
at all but *remuxes*: 34-90 Mbps H.264, VC-1 and MPEG-2 at 0.2-0.87 bpp. Those
carry several hundred percent more bits than 1080p can show, so a re-encode
there is not a quality gamble - it is discarding redundancy.

This tool finds that tail by measurement, not by a hand-written list: it probes
every video file, computes bpp, and takes only what is above the threshold. That
also makes it self-resuming, because a file it has re-encoded drops below the
threshold and is never selected again.

It is deliberately a HOLDING MEASURE, not the destination:

  * It writes a *provisional* file. A native AV1/HEVC rip is still the better
    copy, and Houndarr's upgrade pass keeps hunting for one - it walks the whole
    library regardless of what is in it, so nothing here needs to change for
    that to continue.
  * The application's own record is refreshed afterwards (RescanMovie /
    RescanSeries / RescanArtist) so it sees the file that is really there. This
    is the part that matters and the part to check first: an application ranks
    releases by quality tier, NOT by size, so if it still believes the item is a
    remux it will reject a native WEB-DL as a downgrade and the temporary file
    becomes permanent. See the Audio and Safety notes at the top of this file,
    and run one file with --limit 1 --apply before committing the whole tail.

Safety, in order of importance:

  * RESOLUTION IS NEVER CHANGED. A 4K file is re-encoded at 4K. Downscaling is
    available only through the explicit --downscale-to flag, which is off by
    default, because choosing 4K for a film was a decision and this tool has no
    business quietly undoing it.
  * Dry run by default; it prints the plan and the profile each application
    currently records for the candidate, and changes nothing without --apply.
  * The original is untouched until the output has been probed and accepted
    (same duration within tolerance, a video stream present, and at least
    --min-saving smaller). Otherwise the output is deleted and the file skipped.
  * The swap is an atomic rename over the original path, so the filename the
    application tracks never changes.
  * Owner, group and mode are copied from the original onto the replacement, so
    the next service in the chain can still write it.
  * Video is the only stream that is re-encoded. Audio, subtitles,
    fonts/attachments, chapters and metadata are copied as they are unless
    --audio asks for lossless tracks to be re-encoded; see the audio note below.

Audio
-----

Measured on this library, audio is 5-12% of a remux - real, but nowhere near the
video's share, so `--audio copy` is the default. What the tracks in those files
usually look like is worth knowing before changing one, because they carry the
same content two or three times over: a TrueHD/DTS-HD MA track plus an AC-3 or
E-AC3 "compatibility" track for players that cannot decode the lossless one.

`--audio eac3` (or `opus`) re-encodes the lossless tracks to a lossy one at a
per-channel bitrate and copies the already-lossy tracks untouched. That discards
the lossless track *and any Atmos/object metadata in it*, which no ffmpeg
encoder can reproduce - so it is opt-in, never assumed.
"""

import argparse
import collections
import copy
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

import arr_client as arr

VIDEO_EXTENSIONS = {".mkv", ".mp4", ".avi", ".m4v", ".ts", ".webm", ".mov", ".wmv"}

# Which application owns which kind of library comes from ARR_APPS, a JSON the
# build writes from the shared application facts (lib/arr-apps.nix). It carries
# no API version on purpose: that literal goes stale on a major upgrade and a
# stale one reads as "the application is broken", so it is probed instead.


def load_apps():
    path = os.environ.get("ARR_APPS")
    if not path:
        sys.exit("media-recode: ARR_APPS is not set - run this through `nix run .#media-recode`")
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)["apps"]


def log(message):
    print(message, flush=True)


def warn(message):
    print(f"WARNING: {message}", file=sys.stderr, flush=True)


# The *arr plumbing lives in arr_client; this script's own convention is that a
# body means POST, and that a recode command needs a long timeout.
ApiError = arr.ApiError
api_key = arr.api_key


def call(port, version, key, path, body=None, timeout=120):
    return arr.call(port, version, key, path, body=body, timeout=timeout)


def ffprobe(path):
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-print_format", "json",
             "-show_format", "-show_streams", path],
            capture_output=True, text=True, timeout=120,
        ).stdout
        data = json.loads(out)
    except Exception:
        return None
    streams = data.get("streams") or []
    stream = next((s for s in streams if s.get("codec_type") == "video"), None)
    if stream is None:
        return None
    fmt = data.get("format") or {}
    try:
        size = int(fmt.get("size") or 0)
        duration = float(fmt.get("duration") or 0)
        width = int(stream.get("width") or 0)
        height = int(stream.get("height") or 0)
    except (TypeError, ValueError):
        return None
    if not (size and duration > 0 and width and height):
        return None
    fps = 0.0
    for name in ("avg_frame_rate", "r_frame_rate"):
        raw = stream.get(name) or ""
        num, _, den = raw.partition("/")
        try:
            if float(num) > 0 and float(den) > 0:
                fps = float(num) / float(den)
                break
        except ValueError:
            continue
    kbps = 0.0
    try:
        kbps = float(stream.get("bit_rate") or 0) / 1000.0
    except (TypeError, ValueError):
        pass
    if not kbps:
        kbps = (size * 8 / duration) / 1000.0
    pix_fmt = (stream.get("pix_fmt") or "").lower()
    profile = stream.get("profile") or ""
    return {
        "codec": (stream.get("codec_name") or "?").lower(),
        "width": width, "height": height, "fps": fps or 24.0,
        "size": size, "duration": duration, "kbps": kbps,
        "bpp": (kbps * 1000.0) / (width * height * (fps or 24.0)),
        "audio": [s for s in streams if s.get("codec_type") == "audio"],
        # A 10-bit source must be uploaded as p010 and encoded as Main10.
        # Feeding it through nv12 does not fail - it silently converts the
        # picture to 8-bit and throws the HDR away, which is the worst kind of
        # bug because the output looks fine until it is compared.
        "ten_bit": "10" in pix_fmt or "p010" in pix_fmt or "10" in profile,
        "color_primaries": stream.get("color_primaries"),
        "color_transfer": stream.get("color_transfer"),
        "color_space": stream.get("color_space"),
        # Dolby Vision is a separate enhancement layer alongside the H.265 base.
        # No re-encode can carry it, so a DV file comes back as plain HDR10.
        "dovi": any(
            "DOVI" in (side.get("side_data_type") or "")
            for side in (stream.get("side_data_list") or [])
        ),
    }


# Codecs that are lossless on their own. DTS needs its profile checked, because
# ffprobe reports DTS-HD MA and plain lossy DTS Core both as codec_name "dts".
LOSSLESS_CODECS = frozenset({"truehd", "mlp", "flac", "alac"})
LOSSLESS_PCM_PREFIX = "pcm_"

# Fallback bitrates for lossless tracks ffprobe cannot report a bit_rate for,
# in kbps. Only ever used for the dry run's estimate, never for encoding.
LOSSLESS_GUESS_KBPS = {"truehd": 3500, "mlp": 3500, "dts": 3000}


def is_lossless(stream):
    codec = (stream.get("codec_name") or "").lower()
    if codec in LOSSLESS_CODECS or codec.startswith(LOSSLESS_PCM_PREFIX):
        return True
    if codec == "dts":
        return "MA" in (stream.get("profile") or "")
    return False


def audio_kbps(stream):
    """Best-effort bitrate for one audio stream, for the estimate only."""
    try:
        value = float(stream.get("bit_rate") or 0) / 1000.0
        if value:
            return value
    except (TypeError, ValueError):
        pass
    # mkvmerge writes the bitrate into the track title on these remuxes
    # ("... / 3130 kbps / 16-bit"), which is often the only place it exists.
    title = (stream.get("tags") or {}).get("title") or ""
    for part in title.replace("/", " ").split():
        if part.isdigit() and 60 <= int(part) <= 20000:
            return float(part)
    codec = (stream.get("codec_name") or "").lower()
    if codec.startswith(LOSSLESS_PCM_PREFIX):
        return 4608.0
    guess = LOSSLESS_GUESS_KBPS.get(codec)
    if guess:
        return guess
    if codec in ("flac", "alac"):
        return 900.0 * int(stream.get("channels") or 2) / 6
    return 0.0


def lossless_audio_bytes(info):
    """Estimated bytes held by the lossless tracks of one file."""
    total = 0.0
    for stream in info["audio"]:
        if is_lossless(stream):
            total += audio_kbps(stream) * 1000 / 8 * info["duration"]
    return total


def target_audio_bitrate(channels, override):
    """Lossy bitrate to aim for, in kbps, from the channel count."""
    if override:
        return override
    if channels >= 8:
        return 768
    if channels >= 6:
        return 640
    if channels >= 2:
        return 224
    return 128


def lossy_audio_bytes(info, override=0):
    """Bytes one file's lossless tracks would occupy once re-encoded to lossy."""
    channels = max(
        (int(s.get("channels") or 2) for s in info["audio"] if is_lossless(s)),
        default=2,
    )
    return target_audio_bitrate(channels, override) * 1000 / 8 * info["duration"]


def scan(library):
    paths = []
    for dirpath, _dirnames, filenames in os.walk(library):
        for name in filenames:
            if os.path.splitext(name)[1].lower() in VIDEO_EXTENSIONS:
                paths.append(os.path.join(dirpath, name))
    log(f"probing {len(paths)} video files under {library} ...")
    rows = []
    for index, path in enumerate(sorted(paths), 1):
        info = ffprobe(path)
        if info:
            rows.append((path, info))
        if index % 250 == 0:
            log(f"  {index}/{len(paths)}")
    return rows


def load_app_state():
    """Read each application's item list once, to map a file to its owner."""
    state = {}
    for name, spec in load_apps().items():
        key = api_key(spec["dir"])
        if key is None:
            continue
        version, app_state = arr.probe_version(spec["port"], key)
        if version is None:
            warn(f"{name}: not answering on port {spec['port']} ({app_state})")
            continue
        try:
            items = call(spec["port"], version, key, spec["items"]) or []
        except ApiError as error:
            warn(f"{name}: {error}")
            continue
        state[name] = {"spec": dict(spec, version=version), "key": key, "items": items}
    return state


def owner_of(state, path):
    for name, app in state.items():
        key = app["spec"]["path_key"]
        for item in app["items"]:
            folder = (item.get(key) or "").rstrip("/")
            if folder and (path == folder or path.startswith(folder + "/")):
                return name, app, item
    return None, None, None


def recorded_quality(app, item):
    """What the application currently believes about this item's file."""
    spec = app["spec"]
    key = app["key"]
    try:
        if spec["items"] == "/movie":
            fresh = call(spec["port"], spec["version"], key, f"/movie/{item['id']}")
            file_info = fresh.get("movieFile") or {}
        elif spec["items"] == "/artist":
            fresh = call(spec["port"], spec["version"], key, f"/artist/{item['id']}")
            file_info = {"quality": (fresh.get("statistics") or {})}
        else:
            fresh = call(spec["port"], spec["version"], key, f"/series/{item['id']}")
            stats = fresh.get("statistics") or {}
            file_info = {"quality": stats}
        quality = ((file_info.get("quality") or {}).get("quality") or {}).get("name")
        score = file_info.get("customFormatScore")
        return quality, score
    except (ApiError, KeyError, TypeError):
        return None, None


# Quality is not comparable across these encoders: hevc_vaapi and libsvtav1
# count to ~52-63, while the AV1 encoders count to 255. Using one default for
# all of them would make an AV1 encode either near-lossless (huge) or visibly
# broken, so the default follows the chosen encoder.
DEFAULT_QP = {
    "hevc_vaapi": 24,
    "libsvtav1": 30,
    "av1_vaapi": 110,
    "av1_amf": 110,
}


def quality_args(encoder, args):
    """The rate-control arguments each encoder ACTUALLY accepts.

    These are not interchangeable, and getting it wrong is not cosmetic.
    Measured against this ffmpeg (jellyfin-ffmpeg 8.1.2):

      * hevc_vaapi has -qp (0-52) and no global_quality of its own;
      * av1_vaapi has NO -qp option at all - its whole quality control surface
        is -rc_mode plus the generic -global_quality, so an ICQ/CQP request with
        -qp fails outright;
      * av1_amf takes -qp_i/-qp_p on the AV1 0-255 scale, a different scale from
        hevc_vaapi's 0-52, and needs the AMF runtime loaded.
    """
    if encoder == "libsvtav1":
        return ["-preset", str(args.preset), "-crf", str(args.qp)]
    if encoder == "hevc_vaapi":
        return ["-rc_mode", "CQP", "-qp", str(args.qp)]
    if encoder == "av1_vaapi":
        return ["-rc_mode", "ICQ", "-global_quality", str(args.qp)]
    if encoder == "av1_amf":
        quality = str(args.qp)
        return [
            "-usage", "high_quality", "-quality", "high_quality",
            "-rc", "cqp", "-qp_i", quality, "-qp_p", quality,
        ]
    return []


# Codecs the GPU's video engine can decode as well as encode. VC-1 is
# deliberately absent: no RDNA VCN decodes it, so those files keep software
# decode (and there are four VC-1 1080p remuxes in this library).
HW_DECODE_CODECS = frozenset({"h264", "hevc", "av1", "vp9", "mpeg2video"})


def encode_command(path, output, args, info, hardware_decode=True):
    """Build the ffmpeg call: video re-encoded, everything else copied.

    The video is re-encoded at its OWN resolution. A scale filter is added only
    when --downscale-to asks for one and the source is genuinely taller than it,
    which is the only way this function can change what the viewer sees.

    DECODE MATTERS AS MUCH AS ENCODE. Without -hwaccel the source is decoded on
    the CPU and only the encode happens on the GPU - and for a 4K remux that
    decode is by far the larger cost, which is why a hardware transcode looks
    like a CPU job. With it, the decoder produces VAAPI surfaces that the
    encoder consumes directly: no hwupload, no CPU pixel conversion, and the
    scaling (if any) happens in the video engine too.

    Bit depth follows the source: a 10-bit file is p010 and Main10, with the
    colour properties copied across, so HDR survives. On hevc_vaapi the HDR
    mastering metadata rides along in the SEI, which that encoder includes by
    default.

    AMF IS NOT VAAPI. An AMF encoder takes frames from system memory rather than
    from VAAPI surfaces, so the two paths cannot share a filter chain: with GPU
    decode the frames have to be downloaded back before AMF can see them, and
    the pix_fmt is set on the encoder rather than by an hwupload. Everything
    else about the job is the same.

    Audio follows --audio: by default every stream is copied. Otherwise each
    LOSSLESS stream is re-encoded and every already-lossy one is still copied,
    so a commentary or foreign track that is already AC-3 costs nothing to keep.
    """
    vaapi = args.encoder.endswith("_vaapi")
    amf = args.encoder.endswith("_amf")
    decode_on_gpu = hardware_decode and (vaapi or amf) and info["codec"] in HW_DECODE_CODECS
    sw_format = "p010le" if info["ten_bit"] else "nv12"

    target = args.downscale_to if args.downscale_to < info["height"] else 0
    filters = []
    if decode_on_gpu and amf:
        # GPU-decoded frames come back to system memory for AMF, then the pixel
        # format is fixed up. Decoding still happened on the video engine, which
        # is the expensive half.
        filters.append("hwdownload")
        filters.append(f"format={sw_format}")
        if target:
            filters.append(f"scale=-2:{target}")
    elif decode_on_gpu:
        # VAAPI surfaces go straight into the VAAPI encoder; the only thing left
        # is to scale them, and that happens in the video engine too.
        if target:
            width = int(round(info["width"] * target / info["height"] / 2)) * 2
            filters.append(f"scale_vaapi=w={width}:h={target}")
    else:
        if target:
            filters.append(f"scale=-2:{target}")
        if vaapi:
            # p010 for 10-bit sources, nv12 otherwise. Getting this wrong is
            # silent: nv12 would convert HDR to 8-bit and throw it away.
            filters.append("format=p010" if info["ten_bit"] else "format=nv12")
            filters.append("hwupload")

    command = ["ffmpeg", "-hide_banner", "-nostdin", "-y", "-nostats", "-progress", "pipe:1"]
    if decode_on_gpu:
        command += ["-hwaccel", "vaapi", "-hwaccel_output_format", "vaapi"]
    if vaapi or decode_on_gpu:
        command += ["-vaapi_device", args.device]
    command += ["-i", path, "-map", "0", "-map_metadata", "0", "-map_chapters", "0"]
    if filters:
        command += ["-vf", ",".join(filters)]
    command += ["-c", "copy", "-c:v:0", args.encoder]
    if amf:
        # AMF declares its own bit depth instead of reading it from an upload.
        command += ["-pix_fmt", sw_format]
        if info["ten_bit"]:
            command += ["-bitdepth", "10"]
    command += quality_args(args.encoder, args)

    if args.encoder == "hevc_vaapi" and info["ten_bit"]:
        command += ["-profile:v:0", "main10"]
    for flag, key in (
        ("-color_primaries", "color_primaries"),
        ("-color_trc", "color_transfer"),
        ("-colorspace", "color_space"),
    ):
        if info.get(key):
            command += [flag, info[key]]

    if args.audio != "copy":
        codec = "libopus" if args.audio == "opus" else "eac3"
        for index, stream in enumerate(info["audio"]):
            if not is_lossless(stream):
                continue
            channels = int(stream.get("channels") or 2)
            rate = target_audio_bitrate(channels, args.audio_bitrate)
            command += [f"-c:a:{index}", codec, f"-b:a:{index}", f"{rate}k"]

    command += ["-max_muxing_queue_size", "4096", output]
    return command


# ffmpeg's -progress stream is a flat list of key=value lines, one block per
# update, terminated by progress=continue or progress=end. Anything else on the
# merged stream is a log line, kept only to explain a failure.
PROGRESS_KEYS = frozenset({
    "frame", "fps", "bitrate", "total_size", "out_time_us", "out_time",
    "dup_frames", "drop_frames", "speed", "progress",
})

# Where a run records what it is doing, so progress can be watched from another
# shell as well as from the terminal it was started in.
STATUS_FILE = "/run/media-recode/status"

# How often a non-interactive run is allowed to print a progress line.
PROGRESS_EVERY_SECONDS = 5.0


def human_time(seconds):
    seconds = max(0, int(seconds))
    return f"{seconds // 3600:02d}:{(seconds % 3600) // 60:02d}:{seconds % 60:02d}"


def progress_line(state, duration):
    """Summarise ffmpeg's latest progress block as one line."""
    try:
        done = int(state.get("out_time_us") or 0) / 1_000_000
    except ValueError:
        done = 0.0
    percent = (100.0 * done / duration) if duration else 0.0
    try:
        speed = float(str(state.get("speed") or "0").rstrip("x"))
    except ValueError:
        speed = 0.0
    eta = human_time((duration - done) / speed) if speed > 0 else "--:--:--"
    try:
        size = int(state.get("total_size") or 0) / 1024 ** 3
    except ValueError:
        size = 0.0
    return (
        f"{percent:5.1f}%  {state.get('frame') or '0':>7} frames  "
        f"{state.get('fps') or '0':>6} fps  {speed:4.2f}x  "
        f"{human_time(done)}/{human_time(duration)}  "
        f"{size:5.2f} GiB  eta {eta}"
    )


def write_status(text):
    """Best-effort progress file for another terminal. Never fatal."""
    try:
        os.makedirs(os.path.dirname(STATUS_FILE), mode=0o755, exist_ok=True)
        with open(STATUS_FILE, "w", encoding="utf-8") as handle:
            handle.write(text + "\n")
    except OSError:
        pass


def run_ffmpeg(command, duration, label):
    """Run ffmpeg, rendering its progress while it works.

    Progress updates a single line when stdout is a terminal, and is reduced to
    occasional whole lines when it is not - a log file full of carriage returns
    is unreadable. Either way the same text goes to STATUS_FILE, so a long run
    can be checked from another shell.

    Returns (returncode, log_tail, state), where log_tail is the last few log
    lines and is what explains a failure, and state is the last progress block -
    which is how the benchmark reads the achieved fps and speed.
    """
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
        bufsize=1,
    )
    state = {}
    log_tail = collections.deque(maxlen=25)
    interactive = sys.stdout.isatty()
    last_paint = 0.0
    last_percent = -1

    for raw in process.stdout:
        line = raw.rstrip("\n")
        key, _, value = line.partition("=")
        if key in PROGRESS_KEYS:
            state[key] = value
            # Only a finished block is worth drawing.
            if key != "progress":
                continue
        elif line:
            log_tail.append(line)
            continue
        else:
            continue

        now = time.monotonic()
        summary = progress_line(state, duration)
        if interactive:
            if now - last_paint >= 0.2:
                sys.stdout.write("\r    " + summary.ljust(100))
                sys.stdout.flush()
                last_paint = now
                write_status(label + "\n" + summary)
            continue

        try:
            percent = int(float(summary.split("%")[0]))
        except ValueError:
            percent = -1
        if percent != last_percent and now - last_paint >= PROGRESS_EVERY_SECONDS:
            log(f"    {summary}")
            last_paint = now
            last_percent = percent
            write_status(label + "\n" + summary)

    if interactive:
        sys.stdout.write("\r" + " " * 100 + "\r")
        sys.stdout.flush()
    process.wait()
    return process.returncode, list(log_tail), state


# Where the benchmark writes its sample encodes. Deliberately NOT /tmp, which is
# a tmpfs here, and not the library, where a stray file is something the *arr
# applications would notice on their next scan.
BENCHMARK_DIR = "/home/.recode-bench"

BENCHMARKABLE = ("hevc_vaapi", "av1_amf", "av1_vaapi", "libsvtav1")


def benchmark_command(args, path, output, encoder, info, seconds, offset):
    """The real encode command, limited to a sample and aimed at a scratch file.

    Built from the same function the real run uses, so what is measured is what
    would actually happen - including the AMF download hop and the copied audio.
    """
    sample = copy.copy(args)
    sample.encoder = encoder
    sample.qp = args.qp if args.qp is not None else DEFAULT_QP.get(encoder, 24)

    command = encode_command(path, output, sample, info, True)
    command[-1] = output
    index = command.index("-i")
    command[index:index] = ["-ss", f"{offset:.3f}", "-t", str(seconds)]
    return command


def benchmark_scratch_dir():
    """A scratch directory for the sample encodes, degrading gracefully.

    /home is preferred because it is a real disk with room to spare, while /tmp
    is a tmpfs in this configuration. If that is not writable - someone running
    without sudo - a temporary directory is used and the run says so, rather
    than writing a 4K sample into RAM without mentioning it.
    """
    try:
        os.makedirs(BENCHMARK_DIR, exist_ok=True)
        return BENCHMARK_DIR
    except OSError:
        fallback = tempfile.mkdtemp(prefix="recode-bench-")
        warn(f"{BENCHMARK_DIR} is not writable; writing samples to {fallback} instead")
        return fallback


def run_benchmark(args, path, info):
    """Encode the same sample through several encoders and report the trade."""
    encoders = [name.strip() for name in args.benchmark_encoders.split(",") if name.strip()]
    unknown = [name for name in encoders if name not in BENCHMARKABLE]
    if unknown:
        sys.exit(f"cannot benchmark {', '.join(unknown)}; known: {', '.join(BENCHMARKABLE)}")

    seconds = args.benchmark
    # From the middle of the film: the opening is usually titles, which are
    # cheap to encode and would flatter every encoder equally.
    offset = max(0.0, info["duration"] * 0.4)
    scratch = benchmark_scratch_dir()

    log(f"benchmark: {seconds}s from {human_time(offset)} into {os.path.basename(path)}")
    log(
        f"source: {info['codec']} {info['width']}x{info['height']} "
        f"{'10-bit' if info['ten_bit'] else '8-bit'} at {info['kbps'] / 1000:.1f} Mbps"
    )
    log("")

    source_bytes = info["kbps"] * 1000 / 8 * seconds
    rows = []
    for encoder in encoders:
        output = os.path.join(scratch, f"sample.{encoder}.mkv")
        qp = args.qp if args.qp is not None else DEFAULT_QP.get(encoder, 24)
        log(f"  {encoder} (qp {qp})")
        command = benchmark_command(args, path, output, encoder, info, seconds, offset)
        started = time.monotonic()
        returncode, log_tail, state = run_ffmpeg(command, seconds, f"benchmark {encoder}")
        elapsed = time.monotonic() - started
        if returncode != 0:
            warn(f"{encoder}: failed: {log_tail[-1] if log_tail else 'no output'}")
            continue
        size = os.path.getsize(output) if os.path.exists(output) else 0
        try:
            os.remove(output)
        except OSError:
            pass
        try:
            speed = float(str(state.get("speed") or "0").rstrip("x"))
        except ValueError:
            speed = 0.0
        try:
            fps = float(state.get("fps") or 0)
        except ValueError:
            fps = 0.0
        rows.append((encoder, qp, elapsed, fps, speed, size))

    if scratch != BENCHMARK_DIR:
        shutil.rmtree(scratch, ignore_errors=True)
    else:
        try:
            os.rmdir(scratch)
        except OSError:
            pass

    if not rows:
        warn("no encoder produced a sample")
        return 1

    log("")
    log(f"{'encoder':12} {'qp':>4} {'wall':>9} {'fps':>7} {'speed':>7} "
        f"{'output':>10} {'of source':>10}")
    for encoder, qp, elapsed, fps, speed, size in rows:
        ratio = (size / source_bytes * 100) if source_bytes else 0.0
        log(
            f"{encoder:12} {qp:>4} {human_time(elapsed):>9} {fps:>7.1f} {speed:>6.2f}x "
            f"{size / 1024 ** 2:>8.1f}M {ratio:>9.0f}%"
        )

    if len(rows) > 1:
        fastest = min(rows, key=lambda row: row[2])
        slowest = max(rows, key=lambda row: row[2])
        smallest = min(rows, key=lambda row: row[5])
        if fastest[2] > 0:
            log("")
            log(f"{slowest[0]} takes {slowest[2] / fastest[2]:.2f}x the wall time of {fastest[0]}")
        log(f"smallest sample: {smallest[0]} at {smallest[5] / 1024 ** 2:.1f} MiB")
        log("")
        log("'speed' is against real time: 1.00x means the encode takes as long as the")
        log("film runs. Scale 'wall' by the film's length to get the real job time.")
    return 0


def benchmark_main(args):
    """Resolve what to benchmark, then benchmark it."""
    if args.benchmark_file:
        path = args.benchmark_file
        info = ffprobe(path)
        if info is None:
            sys.exit(f"cannot probe {path}")
        return run_benchmark(args, path, info)

    rows = scan(args.library)
    candidates = [(path, info) for path, info in rows if info["bpp"] >= args.min_bpp]
    if not candidates:
        sys.exit("nothing above the bpp threshold to benchmark; pass --benchmark-file")
    path, info = max(candidates, key=lambda pair: pair[1]["size"])
    return run_benchmark(args, path, info)


def replace_with_original_attributes(original, output):
    """Swap the file in, keeping the owner/group/mode the original had."""
    stat = os.stat(original)
    os.chmod(output, stat.st_mode & 0o7777)
    try:
        os.chown(output, stat.st_uid, stat.st_gid)
    except PermissionError:
        warn(f"could not copy ownership onto {output} (not root?)")
    os.replace(output, original)


def rescan(state, path):
    name, app, item = owner_of(state, path)
    if app is None:
        warn(f"no application claims {path}; the swap is done but not rescanned")
        return
    spec = app["spec"]
    body = {"name": spec["rescan"], spec["ids_key"]: [item["id"]]}
    try:
        call(spec["port"], spec["version"], app["key"], "/command", body=body)
        title = item.get("title") or item.get("artistName") or item["id"]
        log(f"    told {name} to rescan {title}")
    except ApiError as error:
        warn(f"{name}: could not rescan {path}: {error}")


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Re-encode only the library's over-encoded tail (remuxes), as a "
            "temporary space measure, and refresh each application's record so "
            "its native-upgrade hunt still works. Dry run unless --apply."
        )
    )
    parser.add_argument("--library", default="/Vault/Media")
    parser.add_argument("--min-bpp", type=float, default=0.12,
                        help="only files above this bits-per-pixel are candidates (default 0.12)")
    parser.add_argument("--downscale-to", type=int, default=0, metavar="HEIGHT",
                        help="never change resolution unless this is set to a height smaller "
                             "than the source (default 0 = keep every file at its own "
                             "resolution)")
    parser.add_argument("--encoder", default="hevc_vaapi",
                        help="hevc_vaapi (default), av1_amf, av1_vaapi or libsvtav1. "
                             "av1_amf is AMD's own AV1 encoder and the only AV1 path with "
                             "real quality controls; its runtime is put on the loader path "
                             "by the wrapper. Note its --qp is on the AV1 0-255 scale, NOT "
                             "hevc_vaapi's 0-52 - see the README note on choosing one. "
                             "av1_vaapi has no -qp in this ffmpeg and is reported to produce "
                             "grainy output on RDNA4")
    parser.add_argument("--qp", type=int, default=None,
                        help="quality, on the selected encoder's own scale - these are NOT "
                             "comparable, so the default follows the encoder: hevc_vaapi 24 "
                             "(0-52, lower is better), libsvtav1 CRF 30 (0-63), av1_vaapi and "
                             "av1_amf 110 (0-255). Leaving it unset picks that default")
    parser.add_argument("--preset", type=int, default=6, help="libsvtav1 preset (default 6)")
    parser.add_argument("--device", default="/dev/dri/renderD128")
    parser.add_argument("--benchmark", type=int, nargs="?", const=60, default=0, metavar="SECONDS",
                        help="encode the same sample through several encoders and report "
                             "speed and size for each, then exit (default 60 seconds)")
    parser.add_argument("--benchmark-file", metavar="PATH",
                        help="source for --benchmark (default: the largest candidate, which "
                             "needs the library scan)")
    parser.add_argument("--benchmark-encoders", default="hevc_vaapi,av1_amf,av1_vaapi",
                        help="comma list to compare (default hevc_vaapi,av1_amf,av1_vaapi)")
    parser.add_argument("--min-saving", type=float, default=0.25,
                        help="discard the output unless it is this much smaller (default 0.25)")
    parser.add_argument("--audio", choices=("copy", "eac3", "opus"), default="copy",
                        help="'copy' keeps every audio stream (default). 'eac3'/'opus' "
                             "re-encode only the LOSSLESS tracks, discarding the TrueHD/"
                             "DTS-HD MA copy and any Atmos metadata in it; already-lossy "
                             "tracks are still copied")
    parser.add_argument("--audio-bitrate", type=int, default=0, metavar="KBPS",
                        help="override the lossy audio bitrate (default 0 = by channel count)")
    parser.add_argument("--include-dolby-vision", action="store_true",
                        help="also re-encode Dolby Vision files. Skipped by default: DV is a "
                             "second video layer that no re-encode can carry, so the result "
                             "loses Dolby Vision and keeps only the HDR10 base")
    parser.add_argument("--limit", type=int, default=0, help="stop after this many files")
    parser.add_argument("--apply", action="store_true", help="actually re-encode")
    args = parser.parse_args()
    if args.qp is None and not args.benchmark:
        args.qp = DEFAULT_QP.get(args.encoder, 24)
        log(f"quality: {args.encoder} at --qp {args.qp} (the default for that encoder)")

    if args.benchmark:
        return benchmark_main(args)

    rows = scan(args.library)
    candidates = [
        (path, info) for path, info in rows
        if info["bpp"] >= args.min_bpp
    ]
    candidates.sort(key=lambda pair: -pair[1]["size"])

    # Dolby Vision is a second video layer beside the H.265 base, and no
    # re-encode can carry it: the result plays as HDR10 and the DV layer is
    # gone for good. That is a feature being deleted, so it is opt-in - which
    # is the same rule the resolution rule follows.
    dovi = [(path, info) for path, info in candidates if info["dovi"]]
    if dovi and not args.include_dolby_vision:
        candidates = [(path, info) for path, info in candidates if not info["dovi"]]

    total = sum(info["size"] for _path, info in candidates)
    log("")
    log(f"{len(candidates)} candidate(s) above {args.min_bpp} bpp, {total / 1024 ** 3:.1f} GiB")
    if dovi:
        dovi_gib = sum(info["size"] for _p, info in dovi) / 1024 ** 3
        if args.include_dolby_vision:
            log(f"  including {len(dovi)} Dolby Vision file(s), {dovi_gib:.1f} GiB "
                "(--include-dolby-vision); they will come back as HDR10 only")
        else:
            log(f"  {len(dovi)} Dolby Vision file(s), {dovi_gib:.1f} GiB, are SKIPPED: a "
                "re-encode cannot carry the DV layer")
            log("  add --include-dolby-vision to accept HDR10-only output for those")
    if not candidates:
        return 0

    ten_bit = sum(1 for _p, i in candidates if i["ten_bit"])
    if ten_bit:
        log(f"  {ten_bit} of them are 10-bit/HDR and will be encoded as Main10 with their "
            "colour properties copied across")

    state = load_app_state() if args.apply else {}

    if not args.apply:
        log("")
        log(f"{'size':>9}  {'bpp':>6}  {'codec':>10}  {'res':>10}  {'Mbps':>7}  file")
        for path, info in candidates[:40]:
            log(
                f"{info['size'] / 1024 ** 3:8.1f}G  {info['bpp']:6.3f}  {info['codec']:>10}  "
                f"{info['width']}x{info['height']:<5}  {info['kbps'] / 1000:7.2f}  "
                f"{path.replace(args.library + '/', '')[:60]}"
            )
        if len(candidates) > 40:
            log(f"  ... and {len(candidates) - 40} more")
        log("")
        if args.downscale_to:
            log(f"resolution: downscaling anything taller than {args.downscale_to}p "
                "(--downscale-to was given)")
        else:
            log("resolution: PRESERVED for every file (no downscaling)")
        if args.audio == "copy":
            log("audio: copied as-is (--audio copy)")
        else:
            log(f"audio: lossless tracks -> {args.audio}; already-lossy tracks copied")
        if args.encoder.endswith("_vaapi"):
            log("decode: on the GPU too (-hwaccel vaapi), falling back to software decode "
                "if the engine refuses a source")
        elif args.encoder.endswith("_amf"):
            log("decode: on the GPU too (hwdownload for AMF), falling back to software "
                "decode if the engine refuses a source")
        else:
            log("decode: software (this encoder is software only)")
        # A same-resolution re-encode of a remux lands around a quarter to a
        # fifth of the source. Kept deliberately rough: the trial gives the
        # real ratio for this content and this encoder.
        estimated = total * 0.25
        log(f"rough estimate at --qp {args.qp}: ~{estimated / 1024 ** 3:.0f} GiB kept, "
            f"~{(total - estimated) / 1024 ** 3:.0f} GiB reclaimed")

        with_lossless = [info for _p, info in candidates if any(is_lossless(s) for s in info["audio"])]
        lossless_bytes = sum(lossless_audio_bytes(info) for _p, info in candidates)
        if with_lossless:
            kept = sum(lossy_audio_bytes(info, args.audio_bitrate) for info in with_lossless)
            log("")
            log(f"audio detail: {len(with_lossless)} of {len(candidates)} candidates carry "
                f"lossless tracks, holding ~{lossless_bytes / 1024 ** 3:.0f} GiB")
            log(f"  re-encoding just those would reclaim a further "
                f"~{(lossless_bytes - kept) / 1024 ** 3:.0f} GiB "
                f"(that is what --audio eac3 does)")
            log("  what it costs: the TrueHD/DTS-HD MA track goes, and with it any Atmos")
            log("  object audio, which no ffmpeg encoder can reproduce. The already-lossy")
            log("  AC-3/E-AC3 tracks in these files are duplicates of it and are kept as-is,")
            log("  so a client that cannot decode TrueHD still has something to play.")
        log("DRY RUN - nothing was re-encoded. Add --apply, and read the trial")
        log("procedure in the module comments before doing the whole tail.")
        log("")
        log("What each application currently records for the biggest candidates")
        log("(re-run after a trial re-encode to see what the rescan changed):")
        dry_state = load_app_state()
        for path, info in candidates[:8]:
            name, app, item = owner_of(dry_state, path)
            if app is None:
                log(f"  {os.path.basename(path)[:44]:46} no owning application")
                continue
            quality, score = recorded_quality(app, item)
            log(f"  {os.path.basename(path)[:44]:46} {name}: quality={quality} "
                f"customFormatScore={score}")
        return 0

    done = 0
    reclaimed = 0
    log(f"progress also goes to {STATUS_FILE} - `cat` it from another shell")
    # Cleared for good if the first hardware-decode attempt fails; see the
    # fallback in the loop below.
    hw_decode = True
    for path, info in candidates:
        if args.limit and done >= args.limit:
            break

        output = path + ".recode.mkv"
        target = args.downscale_to if args.downscale_to < info["height"] else 0
        shape = f"{target}p" if target else f"{info['height']}p (unchanged)"
        log(f"[{done + 1}] {path.replace(args.library + '/', '')}")
        log(
            f"    {info['size'] / 1024 ** 3:.1f} GiB, {info['bpp']:.3f} bpp, "
            f"{info['codec']} {info['width']}x{info['height']} -> {args.encoder} at {shape}"
        )

        # Try decoding on the GPU first. One failure is enough to conclude the
        # engine will not take this source - whether that is a codec it cannot
        # decode or an option the driver refuses, the answer is the same for
        # every later file - so it falls back to software decode once and stays
        # there, rather than paying a failed attempt per file.
        attempts = [True, False] if hw_decode else [False]
        returncode = 1
        log_tail = []
        elapsed = 0.0
        for hardware_decode in attempts:
            command = encode_command(path, output, args, info, hardware_decode)
            started = time.monotonic()
            returncode, log_tail, _state = run_ffmpeg(command, info["duration"], path)
            elapsed = time.monotonic() - started
            if returncode == 0:
                if not hardware_decode and hw_decode:
                    warn("software decode used for this file")
                break
            if os.path.exists(output):
                os.remove(output)
            if hardware_decode:
                hw_decode = False
                warn("hardware decode failed; falling back to software decode from here on")
            else:
                detail = log_tail[-1] if log_tail else "no output"
                warn(f"ffmpeg failed, keeping the original: {detail}")
        if returncode != 0:
            write_status(f"last run failed: {path}")
            continue
        write_status(f"last completed: {path}")

        new_info = ffprobe(output)
        if new_info is None:
            warn("output did not probe; keeping the original")
            os.remove(output)
            continue
        if abs(new_info["duration"] - info["duration"]) > max(2.0, info["duration"] * 0.01):
            warn(f"duration changed ({info['duration']:.0f}s -> {new_info['duration']:.0f}s); "
                 "keeping the original")
            os.remove(output)
            continue
        saving = 1 - (new_info["size"] / info["size"])
        if saving < args.min_saving:
            warn(f"only {saving * 100:.0f}% smaller; keeping the original")
            os.remove(output)
            continue

        replace_with_original_attributes(path, output)
        reclaimed += info["size"] - new_info["size"]
        done += 1
        log(f"    replaced: {info['size'] / 1024 ** 3:.1f} -> {new_info['size'] / 1024 ** 3:.1f} GiB "
            f"({saving * 100:.0f}% smaller, {elapsed / 60:.1f} min)")
        rescan(state, path)

    log("")
    log(f"re-encoded {done} file(s), reclaimed {reclaimed / 1024 ** 3:.1f} GiB")
    if done:
        log("Houndarr's upgrade pass still walks these items, so a native rip can "
            "still replace the provisional copy - check one in the application's UI")
    return 0


if __name__ == "__main__":
    sys.exit(main())
