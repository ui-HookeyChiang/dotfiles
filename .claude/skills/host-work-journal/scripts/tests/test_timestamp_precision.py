"""Tests for second-level timestamp precision in collect-weekly-report.py.

Covers:
  - ts_ms_to_datetime / iso_to_datetime precision and tz handling
  - parse_range_bounds expansion for date-only inputs
  - parse_range_bounds passthrough for ISO 8601 with time
  - in_range_dt boundary semantics (inclusive start + end)
  - datetime_to_iso truncates microseconds to second precision
  - Legacy compat: in_range still accepts YYYY-MM-DD strings
  - Output meta contains both date strings and ISO 8601 timestamps
"""

import importlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch

import pytest

SCRIPTS_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPTS_DIR))
collector = importlib.import_module("collect-weekly-report")


# ── ts_ms_to_datetime ──────────────────────────────────────────────────────


def test_ts_ms_to_datetime_returns_utc_aware():
    # 2026-02-15 12:34:56 UTC → ms
    ts_ms = int(datetime(2026, 2, 15, 12, 34, 56, tzinfo=timezone.utc).timestamp() * 1000)
    dt = collector.ts_ms_to_datetime(ts_ms)
    assert dt.tzinfo is not None
    assert dt.utcoffset().total_seconds() == 0
    assert dt.year == 2026 and dt.month == 2 and dt.day == 15
    assert dt.hour == 12 and dt.minute == 34 and dt.second == 56


def test_ts_ms_to_datetime_preserves_subsecond():
    # 845 ms → microsecond=845000
    ts_ms = int(datetime(2026, 2, 15, 12, 34, 56, tzinfo=timezone.utc).timestamp() * 1000) + 845
    dt = collector.ts_ms_to_datetime(ts_ms)
    assert dt.microsecond == 845_000


# ── iso_to_datetime ────────────────────────────────────────────────────────


def test_iso_to_datetime_with_z_suffix():
    dt = collector.iso_to_datetime("2026-02-26T05:54:18.845Z")
    assert dt is not None
    assert dt.tzinfo is not None
    assert dt.year == 2026 and dt.month == 2 and dt.day == 26
    assert dt.hour == 5 and dt.minute == 54 and dt.second == 18
    assert dt.microsecond == 845_000


def test_iso_to_datetime_with_offset():
    dt = collector.iso_to_datetime("2026-02-26T05:54:18+00:00")
    assert dt is not None
    assert dt.hour == 5 and dt.minute == 54 and dt.second == 18


def test_iso_to_datetime_converts_to_utc():
    # +08:00 input → UTC equivalent
    dt = collector.iso_to_datetime("2026-02-26T13:54:18+08:00")
    assert dt.hour == 5 and dt.minute == 54 and dt.second == 18
    assert dt.utcoffset().total_seconds() == 0


def test_iso_to_datetime_date_only_fallback():
    dt = collector.iso_to_datetime("2026-02-26")
    assert dt is not None
    assert dt.hour == 0 and dt.minute == 0 and dt.second == 0


def test_iso_to_datetime_handles_empty_and_invalid():
    assert collector.iso_to_datetime("") is None
    assert collector.iso_to_datetime(None) is None
    assert collector.iso_to_datetime("not-a-date") is None


# ── datetime_to_iso ────────────────────────────────────────────────────────


def test_datetime_to_iso_truncates_microseconds():
    dt = datetime(2026, 2, 15, 12, 34, 56, 845_123, tzinfo=timezone.utc)
    s = collector.datetime_to_iso(dt)
    assert s == "2026-02-15T12:34:56+00:00"
    # No microseconds component anywhere in the string
    assert ".845" not in s
    assert ".123" not in s


def test_datetime_to_iso_assumes_utc_for_naive():
    dt = datetime(2026, 2, 15, 12, 34, 56)
    s = collector.datetime_to_iso(dt)
    assert s == "2026-02-15T12:34:56+00:00"


def test_datetime_to_iso_handles_none():
    assert collector.datetime_to_iso(None) is None


# ── parse_range_bounds ─────────────────────────────────────────────────────


def test_parse_range_bounds_date_only_expansion():
    start_dt, end_dt = collector.parse_range_bounds("2026-02-01", "2026-02-28")
    assert start_dt.hour == 0 and start_dt.minute == 0 and start_dt.second == 0
    assert start_dt.microsecond == 0
    assert end_dt.hour == 23 and end_dt.minute == 59 and end_dt.second == 59
    assert end_dt.microsecond == 999_999
    assert start_dt.tzinfo is not None and end_dt.tzinfo is not None


def test_parse_range_bounds_iso_8601_with_time():
    start_dt, end_dt = collector.parse_range_bounds(
        "2026-02-01T08:00:00", "2026-02-01T17:30:00"
    )
    assert start_dt.hour == 8 and start_dt.minute == 0 and start_dt.second == 0
    assert end_dt.hour == 17 and end_dt.minute == 30 and end_dt.second == 0


def test_parse_range_bounds_iso_with_offset():
    start_dt, _ = collector.parse_range_bounds(
        "2026-02-01T08:00:00+08:00", "2026-02-01T17:00:00+08:00"
    )
    # +08:00 → UTC midnight
    assert start_dt.hour == 0 and start_dt.minute == 0


def test_parse_range_bounds_mixed_date_and_iso():
    """End is date-only but start is ISO with time — both should work."""
    start_dt, end_dt = collector.parse_range_bounds(
        "2026-02-15T12:00:00", "2026-02-15"
    )
    assert start_dt.hour == 12
    assert end_dt.hour == 23 and end_dt.minute == 59


def test_parse_range_bounds_raises_on_garbage():
    with pytest.raises(ValueError):
        collector.parse_range_bounds("not-a-date", "2026-02-28")
    with pytest.raises(ValueError):
        collector.parse_range_bounds("2026-02-01", "")


# ── in_range_dt ────────────────────────────────────────────────────────────


def test_in_range_dt_inclusive_start():
    start = datetime(2026, 2, 1, 0, 0, 0, tzinfo=timezone.utc)
    end = datetime(2026, 2, 28, 23, 59, 59, tzinfo=timezone.utc)
    assert collector.in_range_dt(start, start, end) is True


def test_in_range_dt_inclusive_end():
    start = datetime(2026, 2, 1, 0, 0, 0, tzinfo=timezone.utc)
    end = datetime(2026, 2, 28, 23, 59, 59, tzinfo=timezone.utc)
    assert collector.in_range_dt(end, start, end) is True


def test_in_range_dt_just_before_start():
    start = datetime(2026, 2, 1, 0, 0, 0, tzinfo=timezone.utc)
    end = datetime(2026, 2, 28, 23, 59, 59, tzinfo=timezone.utc)
    just_before = datetime(2026, 1, 31, 23, 59, 59, tzinfo=timezone.utc)
    assert collector.in_range_dt(just_before, start, end) is False


def test_in_range_dt_just_after_end():
    start = datetime(2026, 2, 1, 0, 0, 0, tzinfo=timezone.utc)
    end = datetime(2026, 2, 28, 23, 59, 59, tzinfo=timezone.utc)
    just_after = datetime(2026, 3, 1, 0, 0, 0, tzinfo=timezone.utc)
    assert collector.in_range_dt(just_after, start, end) is False


def test_in_range_dt_cross_day_at_seconds():
    """A second-level range that straddles midnight."""
    start = datetime(2026, 2, 15, 23, 59, 50, tzinfo=timezone.utc)
    end = datetime(2026, 2, 16, 0, 0, 10, tzinfo=timezone.utc)
    inside_late = datetime(2026, 2, 15, 23, 59, 59, tzinfo=timezone.utc)
    inside_early = datetime(2026, 2, 16, 0, 0, 5, tzinfo=timezone.utc)
    outside = datetime(2026, 2, 16, 0, 0, 11, tzinfo=timezone.utc)
    assert collector.in_range_dt(inside_late, start, end) is True
    assert collector.in_range_dt(inside_early, start, end) is True
    assert collector.in_range_dt(outside, start, end) is False


def test_in_range_dt_handles_none():
    start = datetime(2026, 2, 1, tzinfo=timezone.utc)
    end = datetime(2026, 2, 28, tzinfo=timezone.utc)
    assert collector.in_range_dt(None, start, end) is False
    assert collector.in_range_dt(start, None, end) is False
    assert collector.in_range_dt(start, start, None) is False


# ── Legacy compat: in_range still works on date strings ────────────────────


def test_legacy_in_range_still_accepts_strings():
    assert collector.in_range("2026-02-15", "2026-02-01", "2026-02-28") is True
    assert collector.in_range("2026-01-15", "2026-02-01", "2026-02-28") is False


# ── cap_end_to_yesterday ───────────────────────────────────────────────────


def test_cap_end_to_yesterday_caps_today():
    """End covering today gets capped to yesterday 23:59:59.999999."""
    now = datetime(2026, 5, 11, 13, 0, 0, tzinfo=timezone.utc)
    # Caller asked for "today" — parse_range_bounds expanded it to end-of-day
    end_dt = datetime(2026, 5, 11, 23, 59, 59, 999_999, tzinfo=timezone.utc)
    capped = collector.cap_end_to_yesterday(end_dt, now=now)
    assert capped == datetime(2026, 5, 10, 23, 59, 59, 999_999, tzinfo=timezone.utc)


def test_cap_end_to_yesterday_caps_future():
    """Future end-date also gets capped to yesterday."""
    now = datetime(2026, 5, 11, 9, 0, 0, tzinfo=timezone.utc)
    end_dt = datetime(2026, 6, 1, 23, 59, 59, 999_999, tzinfo=timezone.utc)
    capped = collector.cap_end_to_yesterday(end_dt, now=now)
    assert capped == datetime(2026, 5, 10, 23, 59, 59, 999_999, tzinfo=timezone.utc)


def test_cap_end_to_yesterday_passthrough_past():
    """Past end-date is returned unchanged."""
    now = datetime(2026, 5, 11, 13, 0, 0, tzinfo=timezone.utc)
    end_dt = datetime(2026, 4, 30, 23, 59, 59, 999_999, tzinfo=timezone.utc)
    capped = collector.cap_end_to_yesterday(end_dt, now=now)
    assert capped == end_dt


def test_cap_end_to_yesterday_boundary_yesterday_end():
    """End at yesterday 23:59:59.999999 is exactly the boundary — keep as-is."""
    now = datetime(2026, 5, 11, 0, 0, 5, tzinfo=timezone.utc)
    end_dt = datetime(2026, 5, 10, 23, 59, 59, 999_999, tzinfo=timezone.utc)
    capped = collector.cap_end_to_yesterday(end_dt, now=now)
    assert capped == end_dt


def test_cap_end_to_yesterday_run_just_after_midnight():
    """Running at 00:00:05 UTC on day D: end=D 23:59:59 caps to D-1 23:59:59."""
    now = datetime(2026, 5, 11, 0, 0, 5, tzinfo=timezone.utc)
    end_dt = datetime(2026, 5, 11, 23, 59, 59, 999_999, tzinfo=timezone.utc)
    capped = collector.cap_end_to_yesterday(end_dt, now=now)
    assert capped == datetime(2026, 5, 10, 23, 59, 59, 999_999, tzinfo=timezone.utc)


# ── Output structure: meta retains date strings + adds timestamps ──────────


def test_collect_claude_sessions_emits_first_last_timestamps(tmp_path):
    """history.jsonl entries within range should set first/last timestamps."""
    history_file = tmp_path / "history.jsonl"
    ts_early = int(datetime(2026, 2, 15, 8, 0, 0, tzinfo=timezone.utc).timestamp() * 1000)
    ts_late = int(datetime(2026, 2, 20, 22, 30, 0, tzinfo=timezone.utc).timestamp() * 1000)
    ts_out = int(datetime(2025, 12, 1, 0, 0, 0, tzinfo=timezone.utc).timestamp() * 1000)
    history_file.write_text(
        json.dumps({"timestamp": ts_early, "sessionId": "s1", "project": "/p", "display": "hi"})
        + "\n"
        + json.dumps({"timestamp": ts_late, "sessionId": "s2", "project": "/p", "display": "bye"})
        + "\n"
        + json.dumps({"timestamp": ts_out, "sessionId": "s3", "project": "/p", "display": "old"})
        + "\n"
    )

    with patch.object(collector, "STATS_CACHE") as mock_stats, \
         patch.object(collector, "HISTORY_JSONL") as mock_hist, \
         patch.object(collector, "PROJECTS_DIR") as mock_proj:
        mock_stats.exists.return_value = False
        mock_hist.exists.return_value = True
        # Match the trick used in test_collect_session_filter.py so the
        # `with open(HISTORY_JSONL, ...)` call hits a real file under the hood.
        mock_hist.__class__ = type(history_file)
        mock_proj.exists.return_value = False

        original_open = open

        def patched_open(path, *a, **kw):
            path_str = str(path)
            if "history.jsonl" in path_str or path_str == str(mock_hist):
                return original_open(str(history_file), *a, **kw)
            return original_open(path, *a, **kw)

        with patch("builtins.open", side_effect=patched_open):
            result = collector.collect_claude_sessions("2026-02-01", "2026-02-28")

    assert result["first_prompt_timestamp"] is not None
    assert result["last_prompt_timestamp"] is not None
    first = collector.iso_to_datetime(result["first_prompt_timestamp"])
    last = collector.iso_to_datetime(result["last_prompt_timestamp"])
    assert first == datetime(2026, 2, 15, 8, 0, 0, tzinfo=timezone.utc)
    assert last == datetime(2026, 2, 20, 22, 30, 0, tzinfo=timezone.utc)
    # Out-of-range entry must not have bled in
    assert result["total_prompts"] == 2
