---
title: "Test Fail Fixture"
slug: fail
date: 2026-05-15
status: proposed
---

# Test Fail Fixture

## Purpose

This is a broken spec fixture used to verify that spec-lint exits 2 (FAIL).
The frontmatter is missing the required "kind:" key, and the required
"## Goals" section is absent. Both are FAIL conditions per the O3 contract.

## Design

Two FAIL conditions are present:
- frontmatter missing key 'kind'
- section missing required heading 'Goals'

spec-lint must exit 2 and list both failures in its output.
