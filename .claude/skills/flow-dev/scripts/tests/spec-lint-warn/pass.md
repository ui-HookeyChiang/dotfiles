---
title: "Test Pass Fixture"
kind: spec
slug: pass
date: 2026-05-15
status: proposed
---

# Test Pass Fixture

## Purpose

This is a valid spec fixture used to verify that spec-lint exits 0 (PASS).
All required frontmatter keys are present and all required sections exist.
No placeholder tokens appear anywhere in the document.

## Goals

- spec-lint exits 0 on this document.
- All required frontmatter keys: title, kind, slug, date, status are present.
- All required sections: Purpose, Goals, Design are present.

## Design

The design is straightforward: this document satisfies every FAIL and WARN
condition in spec-lint, so the linter should emit PASS and exit 0.
