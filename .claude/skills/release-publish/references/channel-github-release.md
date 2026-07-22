# Channel: github-release

Create a GitHub Release — this is the **authoritative store** for release notes (tag-bound, `Latest` flag, edit history, API-accessible). No repo-side copy is kept: `scripts/sync-skills-landing.sh` reads release metadata directly from the GitHub Release API, so `releases/` files are not needed and are in `.gitignore`.

Auth: uses the same `gh auth` token as the main repo. Verify with `gh auth status`.

```bash
VERSION="v0.3.0"  # from Step 0

# Write release note to a tempfile, then create the GitHub Release from it.
RELEASE_FILE=$(mktemp --suffix=.md)
cat > "$RELEASE_FILE" << 'RELEASE_EOF'
# content from release-note output
RELEASE_EOF

gh release create "$VERSION" \
  --title "$VERSION" \
  --notes-file "$RELEASE_FILE"

rm -f "$RELEASE_FILE"
```

`repo` is a deprecated alias for `github-release` — it still works for one release cycle but emits a `[DEPRECATED]` warning. Use `github-release` going forward.
