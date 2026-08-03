#!/usr/bin/env python3
"""Unit tests for trigger-eval detection logic."""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))
from trigger_eval.run_eval import _json_has_skill, normalize_eval_set  # noqa: E402

pass_count = 0
fail_count = 0


def assert_true(label, value):
    global pass_count, fail_count
    if value:
        print(f"  PASS: {label}")
        pass_count += 1
    else:
        print(f"  FAIL: {label}")
        fail_count += 1


def test_real_skill_name_detection():
    """Verify that matching on the real skill name works."""
    skill_name = "flow"
    clean_name = "flow-skill-abc12345"

    assert_true(
        "real skill name detected in accumulated_json",
        _json_has_skill('{"skill": "flow"}', skill_name),
    )
    assert_true(
        "synthetic name detected in accumulated_json",
        clean_name in f'{{"skill": "{clean_name}"}}',
    )
    assert_true(
        "unrelated skill does not match",
        not _json_has_skill('{"skill": "tdd"}', skill_name),
    )
    assert_true(
        "flow does not match flow-dev",
        not _json_has_skill('{"skill": "flow-dev"}', skill_name),
    )


def test_query_prompt_normalization():
    """Verify that eval sets with 'prompt' field are normalized."""
    eval_set = [
        {"prompt": "How do I start a feature?", "should_trigger": True},
        {"prompt": "What time is it?", "should_trigger": False},
    ]

    normalize_eval_set(eval_set)

    assert_true("prompt normalized to query", "query" in eval_set[0])
    assert_true("prompt key removed", "prompt" not in eval_set[0])
    assert_true(
        "value preserved",
        eval_set[0]["query"] == "How do I start a feature?",
    )


def test_substring_false_positive_guard():
    """Ensure skill_name match is exact for Skill tool (not substring)."""
    skill_name = "flow"
    assert_true(
        "flow does not match flow-dev",
        not _json_has_skill('{"skill": "flow-dev"}', skill_name),
    )
    assert_true(
        "flow does not match flow-merge",
        not _json_has_skill('{"skill": "flow-merge"}', skill_name),
    )


if __name__ == "__main__":
    print("=== test_trigger_detection.py ===")
    test_real_skill_name_detection()
    test_query_prompt_normalization()
    test_substring_false_positive_guard()
    print(f"\nResults: {pass_count} passed, {fail_count} failed")
    sys.exit(0 if fail_count == 0 else 1)
