"""Regression test: session summaries are filtered by date-range session IDs.

Previously, collect_claude_sessions() included all sessions from
sessions-index.json regardless of date range, because sessions lack their
own timestamps.  The fix filters by checking session IDs collected from
date-filtered history.jsonl entries.
"""

import json
import sys
import textwrap
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

# Add parent directory (scripts/) to import path
SCRIPTS_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPTS_DIR))

# Import with hyphenated module name
import importlib

collector = importlib.import_module("collect-weekly-report")
collect_claude_sessions = collector.collect_claude_sessions


# ── Fixtures / helpers ────────────────────────────────────────────────────────

START = "2026-02-01"
END = "2026-02-28"

# Session IDs
SID_IN_RANGE = "aaaa-1111-in-range"
SID_OUT_OF_RANGE = "bbbb-2222-out-of-range"

# Timestamps (ms) — one inside range, one outside
TS_FEB_15 = 1771027200000  # 2026-02-15 approx
TS_JAN_01 = 1735689600000  # 2025-01-01 — well outside range


def _history_lines():
    """Return history.jsonl content with one in-range and one out-of-range entry."""
    in_range_entry = json.dumps({
        "timestamp": TS_FEB_15,
        "sessionId": SID_IN_RANGE,
        "project": "/home/testuser/my-project",
        "display": "fix storage raid issue",
    })
    out_of_range_entry = json.dumps({
        "timestamp": TS_JAN_01,
        "sessionId": SID_OUT_OF_RANGE,
        "project": "/home/testuser/other-project",
        "display": "old work",
    })
    return in_range_entry + "\n" + out_of_range_entry + "\n"


def _sessions_index(entries):
    """Build a sessions-index.json dict."""
    return {
        "originalPath": "/home/testuser/my-project",
        "entries": entries,
    }


# ── Tests ─────────────────────────────────────────────────────────────────────


@patch.object(collector, "PROJECTS_DIR")
@patch.object(collector, "STATS_CACHE")
@patch.object(collector, "HISTORY_JSONL")
def test_only_date_filtered_sessions_included(
    mock_history_path, mock_stats_path, mock_projects_path, tmp_path
):
    """Sessions whose IDs don't appear in date-filtered history are excluded.

    This is the core regression test: before the fix, SID_OUT_OF_RANGE and
    the no-ID session would have leaked into session_summaries.
    """
    # -- Set up history.jsonl --
    history_file = tmp_path / "history.jsonl"
    history_file.write_text(_history_lines())
    mock_history_path.exists.return_value = True
    mock_history_path.__fspath__ = lambda self: str(history_file)
    mock_history_path.__str__ = lambda self: str(history_file)
    # Make open() work with the mock path
    mock_history_path.__class__ = type(history_file)

    # -- Set up stats-cache.json (empty / no data) --
    mock_stats_path.exists.return_value = False

    # -- Set up projects dir with sessions-index.json --
    proj_dir = tmp_path / "projects" / "proj1"
    proj_dir.mkdir(parents=True)
    idx = _sessions_index([
        # Should be INCLUDED — its sessionId is in the date-filtered set
        {"sessionId": SID_IN_RANGE, "summary": "Fixed RAID rebuild"},
        # Should be EXCLUDED — sessionId is NOT in the date-filtered set
        {"sessionId": SID_OUT_OF_RANGE, "summary": "Old January work"},
        # Should be EXCLUDED — no sessionId field at all
        {"summary": "Mystery session with no ID"},
    ])
    (proj_dir / "sessions-index.json").write_text(json.dumps(idx))

    mock_projects_path.exists.return_value = True
    mock_projects_path.iterdir.return_value = iter([proj_dir])

    # We need to patch open() so the mock HISTORY_JSONL path works
    original_open = open

    def patched_open(path, *args, **kwargs):
        path_str = str(path)
        if "history.jsonl" in path_str or path_str == str(mock_history_path):
            return original_open(str(history_file), *args, **kwargs)
        return original_open(path, *args, **kwargs)

    with patch("builtins.open", side_effect=patched_open):
        result = collect_claude_sessions(START, END)

    # ── Assertions ──────────────────────────────────────────────────────
    summaries = result["session_summaries"]
    summary_ids = [s["session_id"] for s in summaries]

    # Only the in-range session should appear
    assert SID_IN_RANGE in summary_ids, (
        f"Expected {SID_IN_RANGE} in summaries, got {summary_ids}"
    )
    assert SID_OUT_OF_RANGE not in summary_ids, (
        f"Out-of-range session {SID_OUT_OF_RANGE} should have been filtered out"
    )
    assert len(summaries) == 1, (
        f"Expected exactly 1 session summary, got {len(summaries)}: {summaries}"
    )

    # Verify the included summary content
    assert summaries[0]["summary"] == "Fixed RAID rebuild"

    # Prompt count should reflect only the in-range entry
    assert result["total_prompts"] == 1

    # by_project should have exactly one project
    assert len(result["by_project"]) == 1
    assert result["by_project"][0]["prompts"] == 1


@patch.object(collector, "PROJECTS_DIR")
@patch.object(collector, "STATS_CACHE")
@patch.object(collector, "HISTORY_JSONL")
def test_no_sessions_when_history_empty(
    mock_history_path, mock_stats_path, mock_projects_path, tmp_path
):
    """When history.jsonl has no in-range entries, no sessions should appear."""
    # Empty history
    history_file = tmp_path / "history.jsonl"
    history_file.write_text("")
    mock_history_path.exists.return_value = True
    mock_history_path.__class__ = type(history_file)

    mock_stats_path.exists.return_value = False

    # Projects dir with sessions that would have leaked before the fix
    proj_dir = tmp_path / "projects" / "proj1"
    proj_dir.mkdir(parents=True)
    idx = _sessions_index([
        {"sessionId": "some-session", "summary": "Should not appear"},
    ])
    (proj_dir / "sessions-index.json").write_text(json.dumps(idx))

    mock_projects_path.exists.return_value = True
    mock_projects_path.iterdir.return_value = iter([proj_dir])

    original_open = open

    def patched_open(path, *args, **kwargs):
        path_str = str(path)
        if "history.jsonl" in path_str:
            return original_open(str(history_file), *args, **kwargs)
        return original_open(path, *args, **kwargs)

    with patch("builtins.open", side_effect=patched_open):
        result = collect_claude_sessions(START, END)

    assert result["session_summaries"] == []
    assert result["total_prompts"] == 0
