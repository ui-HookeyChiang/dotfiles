---
title: "Test Warn Fixture"
kind: spec
slug: different-slug-than-filename
date: 2026-05-15
status: proposed
---

# Test Warn Fixture

## Purpose

This is a valid spec fixture used to verify that spec-lint exits 1 (WARN).
All required frontmatter keys are present and all required sections exist.
The frontmatter slug "different-slug-than-filename" does not match the
filename slug "warn", which triggers a slug-mismatch WARN.

## Goals

- spec-lint exits 1 on this document.
- The slug mismatch between frontmatter and filename is the sole WARN trigger.
- No FAIL conditions are present.

## Design

The slug in frontmatter is intentionally set to a value that differs from
the filename base (after stripping the date prefix). This exercises the
slug-mismatch WARN path added in O3.
