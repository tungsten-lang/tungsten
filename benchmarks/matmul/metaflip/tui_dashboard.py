"""Pure presentation helpers for the FlipFleet single-screen dashboard.

The coordinator writes a plain, versioned ``status.json``.  These helpers
therefore accept both the current schema and partial/older
snapshots.  They never read files, inspect processes, or depend on curses;
callers can render their output in a terminal, a log, or a test fixture.

The small formatters use compact SI-like suffixes for counters (``K``, ``M``,
``B``) while durations use wall-clock units.  In particular, a small move
count is never rounded into the misleading ``0.0B`` used by the original TUI.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from datetime import datetime, timezone
import math
import time
from typing import Any, Optional


__all__ = [
    "build_time_timeline",
    "compact_number",
    "derive_health_state",
    "duration",
    "format_cpu_island_row",
    "format_objective",
    "rate",
    "summarize_diversity",
    "summarize_effectiveness",
    "summarize_gpu_roles",
]


_MISSING = "—"
_NUMBER_SUFFIXES = ("", "K", "M", "B", "T", "P", "E")


def _mapping(value: Any) -> Mapping:
    return value if isinstance(value, Mapping) else {}


def _number(value: Any) -> Optional[float]:
    """Coerce a JSON scalar to a finite float, excluding booleans."""
    if value is None or isinstance(value, bool):
        return None
    try:
        result = float(value)
    except (TypeError, ValueError, OverflowError):
        return None
    return result if math.isfinite(result) else None


def _integer(value: Any) -> Optional[int]:
    number = _number(value)
    if number is None or not number.is_integer():
        return None
    return int(number)


def _clip(text: str, width: int) -> str:
    if width <= 0:
        return ""
    if len(text) <= width:
        return text
    if width == 1:
        return "…"
    return text[: width - 1].rstrip() + "…"


def compact_number(value: Any, precision: int = 1) -> str:
    """Format a counter using the smallest honest compact suffix.

    >>> compact_number(999)
    '999'
    >>> compact_number(12_500)
    '12.5K'
    >>> compact_number(2_500_000_000)
    '2.5B'
    >>> compact_number(None)
    '—'
    """
    number = _number(value)
    if number is None:
        return _MISSING
    try:
        precision = max(0, min(3, int(precision)))
    except (TypeError, ValueError, OverflowError):
        precision = 1
    sign = "-" if number < 0 else ""
    scaled = abs(number)
    suffix_index = 0
    while scaled >= 1000 and suffix_index < len(_NUMBER_SUFFIXES) - 1:
        scaled /= 1000.0
        suffix_index += 1

    # Rounding 999.96K to 1000.0K is less useful than promoting it to 1.0M.
    if (suffix_index < len(_NUMBER_SUFFIXES) - 1 and
            round(scaled, precision) >= 1000):
        scaled /= 1000.0
        suffix_index += 1

    suffix = _NUMBER_SUFFIXES[suffix_index]
    if suffix_index == 0 and scaled.is_integer():
        body = str(int(scaled))
    else:
        body = f"{scaled:.{precision}f}".rstrip("0").rstrip(".")
    return f"{sign}{body}{suffix}"


def rate(value: Any, seconds: Any = None, precision: int = 1) -> str:
    """Format a per-second rate.

    With one argument, ``value`` is already a rate.  With two, it is a count
    divided by ``seconds``.  Invalid and zero-duration samples return an em
    dash instead of manufacturing infinity.

    >>> rate(12_500_000)
    '12.5M/s'
    >>> rate(25_000, 2)
    '12.5K/s'
    """
    number = _number(value)
    if number is None:
        return _MISSING
    if seconds is not None:
        span = _number(seconds)
        if span is None or span <= 0:
            return _MISSING
        number /= span
    return f"{compact_number(number, precision)}/s"


def duration(seconds: Any) -> str:
    """Format a wall-clock interval without implying false precision.

    >>> duration(0.42)
    '420ms'
    >>> duration(134 * 60)
    '2h14m'
    >>> duration(3 * 86400 + 7200)
    '3d02h'
    """
    value = _number(seconds)
    if value is None:
        return _MISSING
    sign = "-" if value < 0 else ""
    value = abs(value)
    if value < 1:
        return f"{sign}{int(round(value * 1000))}ms"
    if value < 10:
        rendered = f"{value:.1f}".rstrip("0").rstrip(".")
        return f"{sign}{rendered}s"
    whole = int(round(value))
    if whole < 60:
        return f"{sign}{whole}s"
    minutes, sec = divmod(whole, 60)
    if minutes < 60:
        return f"{sign}{minutes}m{sec:02d}s"
    hours, minute = divmod(minutes, 60)
    if hours < 24:
        return f"{sign}{hours}h{minute:02d}m"
    days, hour = divmod(hours, 24)
    return f"{sign}{days}d{hour:02d}h"


def _timestamp(value: Any) -> Optional[float]:
    number = _number(value)
    if number is not None:
        return number
    if not isinstance(value, str) or not value.strip():
        return None
    text = value.strip()
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.timestamp()


def _status_updated_at(status: Mapping) -> Optional[float]:
    health = _mapping(status.get("health"))
    for source in (status, health):
        for key in ("updated_at", "generated_at", "timestamp", "updated"):
            parsed = _timestamp(source.get(key))
            if parsed is not None:
                return parsed
    # Current FlipFleet snapshots expose enough information to reconstruct
    # their generation time even before an explicit heartbeat field exists.
    started = _timestamp(status.get("started"))
    elapsed = _number(status.get("elapsed"))
    if started is not None and elapsed is not None and elapsed >= 0:
        return started + elapsed
    return None


def derive_health_state(
    status: Any, now: Any = None, stale_after: float = 5.0
) -> dict[str, Any]:
    """Classify a status snapshot as one of six dashboard health states.

    Precedence is ``FAILED``, ``DONE``, ``COMPILING``, ``STALE``,
    ``DEGRADED``, then ``LIVE``.  The returned mapping also contains ``age``,
    ``updated_at``, ``stale``, ``severity``, ``phase``, and human-readable
    ``reasons``.  Missing fields are tolerated for compatibility with old
    status files.
    """
    snapshot = _mapping(status)
    current = _number(now)
    if current is None:
        current = time.time()
    threshold = _number(stale_after)
    if threshold is None or threshold <= 0:
        threshold = 5.0
    updated_at = _status_updated_at(snapshot)
    age = max(0.0, current - updated_at) if updated_at is not None else None
    stale = age is not None and age > threshold

    reasons: list[str] = []
    producer_state = str(snapshot.get("producer_state") or "").casefold()
    error = snapshot.get("error")
    if error:
        reasons.append(str(error))
    elif producer_state == "failed":
        reasons.append("coordinator reported failure")

    explicit_health = _mapping(snapshot.get("health"))
    explicit_reasons = explicit_health.get("reasons", snapshot.get("warnings", ()))
    if isinstance(explicit_reasons, str):
        explicit_reasons = (explicit_reasons,)
    if isinstance(explicit_reasons, Sequence):
        reasons.extend(str(reason) for reason in explicit_reasons if reason)

    compiling = bool(snapshot.get("compiling")) or producer_state == "compiling"
    done = bool(snapshot.get("done")) or producer_state == "done"
    if not error and not done and not compiling:
        gpu = _mapping(snapshot.get("gpu"))
        if gpu.get("enabled") is True and gpu.get("running") is False:
            reasons.append("GPU enabled but not running")
        roles = _mapping(gpu.get("roles"))
        retrying = [
            str(name) for name, value in roles.items()
            if _mapping(value).get("retry_at") is not None and
            (_number(_mapping(value).get("lanes")) or 0) > 0
        ]
        if retrying:
            reasons.append("GPU retry: " + ", ".join(sorted(retrying)))

        walkers = snapshot.get("walkers")
        elapsed = _number(snapshot.get("elapsed")) or 0.0
        if isinstance(walkers, Sequence) and not isinstance(walkers, (str, bytes)):
            stopped = [
                walker for walker in walkers
                if (_mapping(walker).get("running") is False or
                    str(_mapping(walker).get("process_state") or "").casefold()
                    in ("exited", "stopped", "failed"))
            ]
            if stopped:
                reasons.append(f"{len(stopped)}/{len(walkers)} CPU walkers not running")
            unknown = sum(
                _integer(_mapping(walker).get("rank")) is None
                for walker in walkers
            )
            if walkers and unknown and elapsed >= max(5.0, threshold):
                reasons.append(f"{unknown}/{len(walkers)} CPU walkers lack telemetry")

        if snapshot.get("degraded") is True or explicit_health.get("degraded") is True:
            reasons.append("coordinator reported degraded operation")

    # Preserve order while preventing duplicate explicit/derived warnings.
    reasons = list(dict.fromkeys(reasons))
    failed = bool(error) or producer_state == "failed"
    if failed:
        state = "FAILED"
    elif done:
        state = "DONE"
    elif compiling:
        state = "COMPILING"
    elif stale:
        state = "STALE"
        reasons.insert(0, f"status {duration(age)} old")
    elif reasons:
        state = "DEGRADED"
    else:
        state = "LIVE"

    severity = {
        "FAILED": "error",
        "STALE": "error",
        "DEGRADED": "warning",
        "COMPILING": "info",
        "DONE": "success",
        "LIVE": "success",
    }[state]
    return {
        "state": state,
        "label": state,
        "severity": severity,
        "phase": ("failed" if failed else "compile" if compiling else
                  "done" if done else "search"),
        "age": age,
        "updated_at": updated_at,
        "stale": stale,
        "reasons": reasons,
    }


def _objective_phrase(best: int, target: int, noun: str, improvement: str) -> str:
    gap = best - target
    if gap > 0:
        return f"{gap} above {noun} {target}"
    if gap == 0:
        return f"matches {noun} {target}"
    return f"{improvement} {noun} {target} by {-gap}"


def format_objective(status: Any) -> str:
    """Describe the best rank against an honest record or baseline target.

    ``configured_record`` remains the historical comparison when recovery has
    tightened the active ``record``.  A distinct recovered frontier is shown
    as a second comparison, so restarting from an unpublished improvement can
    never make that improvement look like an established world record.
    """
    snapshot = _mapping(status)
    best = _integer(_mapping(snapshot.get("best")).get("rank"))
    configured = _integer(snapshot.get("configured_record"))
    active = _integer(snapshot.get("record"))
    target = configured if configured is not None else active
    known = bool(snapshot.get("record_known", True))
    recovered = _integer(snapshot.get("recovered_rank"))

    noun = "known record" if known else "baseline"
    if best is None:
        return f"best unknown · {noun} {target}" if target is not None else "best unknown"
    if target is None:
        return f"best rank {best}"

    primary = _objective_phrase(best, target, noun, "beats")
    if recovered is not None and recovered != target:
        recovered_phrase = _objective_phrase(
            best, recovered, "recovered frontier", "beats")
        return f"{primary} · {recovered_phrase}"
    return primary


def format_cpu_island_row(
    walker: Any, best_rank: Any = None, width: int = 58
) -> str:
    """Render one compact CPU-island row with door, zone, rank and exposure."""
    item = _mapping(walker)
    walker_id = _integer(item.get("id"))
    ident = f"w{walker_id:02d}" if walker_id is not None else "w??"
    door = str(item.get("door") or item.get("role") or "unknown")
    zone = str(item.get("zone") or item.get("profile") or "unknown")

    rank_value = _integer(item.get("rank"))
    frontier = _integer(best_rank)
    rank_text = f"r{rank_value}" if rank_value is not None else "r?"
    if rank_value is not None and frontier is not None:
        delta = rank_value - frontier
        delta_text = "=best" if delta == 0 else f"{delta:+d}"
    else:
        delta_text = "?"

    work = compact_number(item.get("work_moves"), 1)
    wander = compact_number(item.get("wander_moves"), 1)
    quota = (f"W{work}/{wander}"
             if work != _MISSING or wander != _MISSING else "")

    phase_value = (item.get("current_zone") or item.get("phase") or
                   item.get("current_phase"))
    band = item.get("band")
    phase = ""
    if band is not None:
        phase = f"b{band}"
    elif phase_value not in (None, ""):
        phase = str(phase_value)

    speed = None
    for key in ("rate_mps", "moves_per_second", "moves_per_sec", "mps", "rate"):
        speed = _number(item.get(key))
        if speed is not None:
            break
    exposure = rate(speed) if speed is not None else "mv" + compact_number(item.get("mv"), 1)

    current_rank = _integer(item.get("current_rank"))
    if current_rank is not None and current_rank != rank_value:
        rank_text += f"→{current_rank}"

    progress_age = _number(item.get("progress_age"))
    progress = f"idle{duration(progress_age)}" if progress_age is not None else ""
    source = item.get("source")
    source_text = ""
    if source not in (None, ""):
        source_text = str(source)
        prefix = door + "/"
        if source_text.startswith(prefix):
            source_text = source_text[len(prefix):]
        if source_text != door:
            source_text = "src:" + source_text
        else:
            source_text = ""
    process_state = str(item.get("process_state") or "").casefold()
    running = item.get("running")
    process_text = ""
    if process_state == "stopped":
        process_text = "stopped"
    elif running is False or process_state in ("exited", "failed"):
        process_text = "!" + (process_state or "down")
        exit_code = _integer(item.get("exit_code"))
        if exit_code is not None:
            process_text += f"({exit_code})"

    seed_rank = _integer(item.get("seed_rank"))
    seed_text = (f"seed{seed_rank}"
                 if seed_rank is not None and seed_rank != rank_value else "")
    fields = [ident, door, zone, rank_text, delta_text]
    if seed_text:
        fields.append(seed_text)
    if phase:
        fields.append(phase)
    fields.append(exposure)
    fields.extend(field for field in (progress, quota, source_text, process_text)
                  if field)
    try:
        limit = max(0, int(width))
    except (TypeError, ValueError, OverflowError):
        limit = 58
    return _clip(" ".join(fields), limit)


def _count(mapping: Mapping, key: str) -> int:
    value = _integer(mapping.get(key))
    return max(0, value) if value is not None else 0


def summarize_diversity(status: Any) -> list[str]:
    """Summarize frontier, shoulder, symmetry, and GPU archive diversity."""
    snapshot = _mapping(status)
    counters = _mapping(snapshot.get("counters"))
    lines: list[str] = []

    archive = _integer(counters.get("archive"))
    capacity = _integer(counters.get("archive_capacity"))
    minimum = _integer(counters.get("archive_min_distance"))
    if archive is not None or capacity is not None:
        fill = (f"{archive if archive is not None else '?'}"
                f"/{capacity if capacity is not None else '?'}")
        distance_text = str(minimum) if minimum is not None else _MISSING
        lines.append(
            f"Frontier {fill} · Δmin {distance_text} · "
            f"evict {_count(counters, 'archive_evictions')} / "
            f"reject {_count(counters, 'archive_rejections')}")

    cpu = _mapping(snapshot.get("cpu"))
    near = _mapping(cpu.get("near"))
    tiers = _mapping(near.get("tiers"))
    tier_fragments = []
    for delta in (1, 2):
        tier = _mapping(tiers.get(f"+{delta}", tiers.get(delta)))
        if not tier:
            continue
        size = _integer(tier.get("size"))
        cap = _integer(tier.get("capacity"))
        distance_value = _integer(tier.get("minimum_distance"))
        distance_text = str(distance_value) if distance_value is not None else _MISSING
        tier_fragments.append(
            f"+{delta} {size if size is not None else '?'}/"
            f"{cap if cap is not None else '?'} Δ{distance_text}")
    if tier_fragments:
        lines.append("Shoulders " + " · ".join(tier_fragments))

    near_counters = _mapping(near.get("counters"))
    if near or near_counters:
        selections = _count(near_counters, "selections")
        successes = _count(near_counters, "successes")
        signature_rejections = _count(near_counters, "signature_quota")
        novelty_rejections = _count(near_counters, "novelty")
        lines.append(
            f"Near return {successes}/{selections} · "
            f"struct reject {signature_rejections} · "
            f"novelty reject {novelty_rejections}")

    symmetry = _mapping(cpu.get("symmetry"))
    if symmetry:
        size = _integer(symmetry.get("size"))
        least = _integer(symmetry.get("least_uses"))
        most = _integer(symmetry.get("most_uses"))
        ranks = symmetry.get("ranks")
        rank_text = ""
        if isinstance(ranks, Sequence) and not isinstance(ranks, (str, bytes)):
            rendered = [str(rank) for rank in ranks if _integer(rank) is not None]
            if rendered:
                rank_text = " · ranks " + ",".join(rendered)
        lines.append(
            f"Symmetry {size if size is not None else '?'} seeds · "
            f"uses {least if least is not None else '?'}–"
            f"{most if most is not None else '?'}{rank_text}")

    gpu = _mapping(snapshot.get("gpu"))
    pareto = _mapping(gpu.get("pareto"))
    if pareto and gpu.get("enabled") is not False:
        size = _integer(pareto.get("size"))
        cap = _integer(pareto.get("capacity"))
        lines.append(
            f"GPU Pareto {size if size is not None else '?'}/"
            f"{cap if cap is not None else '?'} · "
            f"admit {_count(pareto, 'admissions')} / "
            f"reject {_count(pareto, 'rejections')} / "
            f"evict {_count(pareto, 'evictions')}")
    return lines or ["Diversity telemetry unavailable"]


def summarize_effectiveness(status: Any) -> list[str]:
    """Return exposure-normalized CPU/GPU effectiveness summaries when possible."""
    snapshot = _mapping(status)
    cpu = _mapping(snapshot.get("cpu"))
    counters = _mapping(snapshot.get("counters"))
    lines: list[str] = []

    # Current producers key cohorts by sticky ``door/zone`` identity.  Rank
    # drops, density ties, and useful shoulder admissions are all productive;
    # launches or cycle-outs alone are deliberately not rewards.
    cpu_roles = _mapping(cpu.get(
        "cohorts", cpu.get("roles", cpu.get("door_stats"))))
    role_yields = []
    minimum_yield_moves = 100_000_000
    for name, raw_stats in cpu_roles.items():
        stats = _mapping(raw_stats)
        moves = _number(stats.get("moves", stats.get("exposure")))
        productive = sum(_count(stats, key) for key in (
            "rank_drops", "tie_improvements", "near_admissions"))
        reported_yield = _number(stats.get("productive_per_billion"))
        if reported_yield is None and moves is not None and moves > 0:
            reported_yield = productive * 1e9 / moves
        stable_yield = (reported_yield if moves is not None and
                        moves >= minimum_yield_moves else None)
        launches = _count(stats, "launches")
        if reported_yield is not None or moves or productive or launches:
            role_yields.append((
                stable_yield, str(name), stats, productive, moves or 0.0))
    if role_yields:
        role_yields.sort(key=lambda item: (
            -(item[0] if item[0] is not None else -1.0), -item[4], item[1]))
        for productive_per_billion, name, stats, _, moves in role_yields[:5]:
            yield_text = (f"{productive_per_billion:.2f} prod/B"
                          if productive_per_billion is not None else "warming")
            lines.append(
                f"CPU {name} {yield_text} · "
                f"↓{_count(stats, 'rank_drops')} "
                f"tie{_count(stats, 'tie_improvements')} "
                f"near{_count(stats, 'near_admissions')} · "
                f"{compact_number(moves)} mv")
        if len(role_yields) > 5:
            lines.append(f"… {len(role_yields) - 5} more CPU cohorts")
    else:
        total_moves = _number(cpu.get("moves", counters.get("cpu_moves")))
        exposure_label = "moves"
        if total_moves is None:
            walkers = snapshot.get("walkers")
            if isinstance(walkers, Sequence) and not isinstance(walkers, (str, bytes)):
                samples = [_number(_mapping(walker).get("mv")) for walker in walkers]
                finite_samples = [sample for sample in samples if sample is not None]
                if finite_samples:
                    total_moves = sum(finite_samples)
                    exposure_label = "current-process moves"
        rank_results = _count(counters, "new_bests")
        density_results = _count(counters, "tie_improvements")
        if total_moves is not None and total_moves > 0:
            useful_per_billion = (rank_results + density_results) * 1e9 / total_moves
            lines.append(
                f"CPU fleet {rank_results} rank + {density_results} density · "
                f"{useful_per_billion:.2f} useful/B {exposure_label}")
        elif counters:
            lines.append(f"CPU fleet {rank_results} rank + {density_results} density results")

    near_counters = _mapping(_mapping(cpu.get("near")).get("counters"))
    selections = _count(near_counters, "selections")
    if selections:
        successes = _count(near_counters, "successes")
        lines.append(
            f"Shoulder return {successes}/{selections} "
            f"({100.0 * successes / selections:.1f}%)")

    launches = _mapping(cpu.get("door_launches"))
    if launches:
        ordered = sorted(
            ((max(0, _integer(count) or 0), str(name))
             for name, count in launches.items()),
            key=lambda item: (-item[0], item[1]))
        shown = ordered[:5]
        suffix = f" +{len(ordered) - len(shown)}" if len(ordered) > len(shown) else ""
        lines.append("Door launches: " + ", ".join(
            f"{name} {compact_number(count, 1)}" for count, name in shown) + suffix)

    gpu_status = _mapping(snapshot.get("gpu"))
    gpu_roles = (_mapping(gpu_status.get("roles"))
                 if gpu_status.get("enabled") is not False else {})
    gpu_yields = []
    for name, raw_stats in gpu_roles.items():
        stats = _mapping(raw_stats)
        lane_epochs = _number(stats.get("lane_epochs"))
        reward_value = _number(stats.get("reward"))
        reward_per_lane_epoch = _number(stats.get("reward_per_lane_epoch"))
        if (reward_per_lane_epoch is None and lane_epochs is not None and
                lane_epochs > 0 and reward_value is not None):
            reward_per_lane_epoch = reward_value / lane_epochs
        if reward_per_lane_epoch is not None:
            gpu_yields.append((reward_per_lane_epoch, str(name)))
    if gpu_yields:
        gpu_yields.sort(key=lambda item: (-item[0], item[1]))
        lines.append("GPU reward/lane-epoch: " + ", ".join(
            f"{name} {value:.2f}" for value, name in gpu_yields[:5]))

    return lines or ["Effectiveness telemetry unavailable"]


def summarize_gpu_roles(status: Any, limit: Optional[int] = 8) -> list[str]:
    """Render the most exposed adaptive GPU roles and their useful outcomes."""
    gpu = _mapping(_mapping(status).get("gpu"))
    if gpu.get("enabled") is False:
        return ["GPU off"]
    roles = _mapping(gpu.get("roles"))
    if not roles:
        return ["GPU off" if gpu.get("enabled") is False else "GPU role telemetry unavailable"]

    rows = []
    for name, raw_stats in roles.items():
        stats = _mapping(raw_stats)
        lanes = max(0, _integer(stats.get("lanes")) or 0)
        lane_epochs = _number(stats.get("lane_epochs")) or 0.0
        reward_value = _number(stats.get("reward")) or 0.0
        reported_efficiency = _number(stats.get("reward_per_lane_epoch"))
        efficiency = (reported_efficiency if reported_efficiency is not None else
                      reward_value / lane_epochs if lane_epochs > 0 else 0.0)
        rows.append((lanes, efficiency, str(name), stats))
    rows.sort(key=lambda row: (-row[0], -row[1], row[2]))

    if limit is None:
        row_limit = len(rows)
    else:
        try:
            row_limit = max(0, int(limit))
        except (TypeError, ValueError, OverflowError):
            row_limit = 8

    rendered = []
    for lanes, efficiency, name, stats in rows[:row_limit]:
        seed = _mapping(stats.get("seed"))
        seed_rank = _integer(seed.get("rank"))
        recipe_value = seed.get("recipe")
        if isinstance(recipe_value, Sequence) and not isinstance(recipe_value, (str, bytes)):
            recipe = "+".join(str(item) for item in recipe_value)
        else:
            recipe = str(recipe_value or "?")
        seed_text = f"r{seed_rank if seed_rank is not None else '?'}/{recipe}"
        candidates = _count(stats, "candidates")
        pareto = _count(stats, "pareto")
        drops = _count(stats, "rank_drops")
        density = _count(stats, "density_improvements")
        failures = _count(stats, "failures")
        suffix = f" · fail {failures}" if failures else ""
        if stats.get("retry_at") is not None:
            suffix += " retrying"
        rendered.append(
            f"{name} {lanes}l {seed_text} · cand {compact_number(candidates)} "
            f"P{pareto} ↓{drops} d{density} · R/le {efficiency:.2f}{suffix}")
    omitted = len(rows) - min(len(rows), row_limit)
    if omitted:
        rendered.append(f"… {omitted} more GPU role{'s' if omitted != 1 else ''}")
    return rendered or ["GPU roles hidden"]


def build_time_timeline(
    perf_curve: Any, elapsed: Any, width: int
) -> list[str]:
    """Build a time-proportional rank timeline with lower rank visually up.

    The horizontal coordinate is wall time rather than event number, so long
    plateaus remain visible.  Rank drops climb to higher rows; same-rank
    density events use diamonds.  At most eight rank rows are emitted, making
    this suitable for a single-screen dashboard even after many improvements.
    Every returned line is at most ``width`` characters.
    """
    try:
        output_width = max(0, int(width))
    except (TypeError, ValueError, OverflowError):
        output_width = 0
    if output_width < 12:
        return [_clip("timeline unavailable", output_width)] if output_width else []
    if not isinstance(perf_curve, Sequence) or isinstance(perf_curve, (str, bytes)):
        return [_clip("No performance events yet", output_width)]

    points = []
    for order, raw_point in enumerate(perf_curve):
        point = _mapping(raw_point)
        event_time = _number(point.get("t", point.get("time")))
        rank_value = _integer(point.get("rank"))
        if event_time is None or rank_value is None:
            continue
        points.append((max(0.0, event_time), order, rank_value))
    if not points:
        return [_clip("No performance events yet", output_width)]
    points.sort(key=lambda point: (point[0], point[1]))

    horizon = _number(elapsed)
    horizon = max(point[0] for point in points) if horizon is None else max(0.0, horizon)
    horizon = max(horizon, max(point[0] for point in points), 1e-9)
    low_rank = min(point[2] for point in points)
    high_rank = max(point[2] for point in points)
    height = min(8, max(1, high_rank - low_rank + 1))
    labels = [
        low_rank if height == 1 else
        int(round(low_rank + row * (high_rank - low_rank) / (height - 1)))
        for row in range(height)
    ]
    label_width = max(3, max(len(f"r{label}") for label in labels))
    plot_width = max(4, output_width - label_width - 2)

    def row_for(rank_value: int) -> int:
        if high_rank == low_rank:
            return 0
        return min(height - 1, max(0, int(round(
            (rank_value - low_rank) * (height - 1) / (high_rank - low_rank)))))

    def column_for(event_time: float) -> int:
        return min(plot_width - 1, max(0, int(round(
            min(event_time, horizon) * (plot_width - 1) / horizon))))

    grid = [[" " for _ in range(plot_width)] for _ in range(height)]
    plotted = [(column_for(t), row_for(rank_value), rank_value)
               for t, _, rank_value in points]

    # Carry the incumbent horizontally between events and from the final event
    # to "now".  Vertical strokes at improvements make their upward direction
    # immediately visible without pretending unobserved intermediate ranks
    # were actual records.
    for index, (column, row, _) in enumerate(plotted):
        next_column = (plotted[index + 1][0]
                       if index + 1 < len(plotted) else plot_width - 1)
        for x in range(column + 1, next_column):
            if grid[row][x] == " ":
                grid[row][x] = "─"
        if index + 1 < len(plotted):
            target_column, target_row, _ = plotted[index + 1]
            if target_row != row:
                for y in range(min(row, target_row) + 1, max(row, target_row)):
                    grid[y][target_column] = "│"
                # The corner lives on the incumbent row; the target marker
                # itself terminates the other end of the vertical stroke.
                grid[row][target_column] = "┘" if target_row < row else "┐"

    for index, (column, row, rank_value) in enumerate(plotted):
        same_rank = index > 0 and rank_value == plotted[index - 1][2]
        grid[row][column] = "◆" if same_rank else "●"
    # A light endpoint exposes time since the final improvement even when it
    # occupies almost the entire available horizon.
    final_column, final_row, _ = plotted[-1]
    if final_column < plot_width - 1:
        grid[final_row][plot_width - 1] = "▷"

    lines = [
        _clip(f"r{label:<{label_width - 1}} │{''.join(grid[row])}", output_width)
        for row, label in enumerate(labels)
    ]

    left = "0s"
    right = duration(horizon)
    axis_width = plot_width
    if len(left) + len(right) + 1 <= axis_width:
        axis = left + " " * (axis_width - len(left) - len(right)) + right
    else:
        axis = _clip(right, axis_width).rjust(axis_width)
    lines.append(_clip(" " * (label_width + 2) + axis, output_width))
    return lines
