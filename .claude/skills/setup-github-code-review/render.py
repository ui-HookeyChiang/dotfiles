#!/usr/bin/env python3
"""Render claude-pr-review.yml for each repo from template + repos.yaml.

Usage:
  python3 render.py                          # render all → /tmp/opencode/rendered/
  python3 render.py ustd lagd                # render specific repos
  python3 render.py --diff                   # diff against current remote
  python3 render.py --push [--branch NAME]   # render + clone + commit + push
  python3 render.py --ref abc123             # pin prompt-hub to specific SHA
  python3 render.py --ref HEAD               # resolve to current origin/main HEAD
"""
import argparse, os, subprocess, sys, shutil, tempfile
from pathlib import Path

import yaml

SCRIPT_DIR = Path(__file__).parent
TEMPLATE_PATH = SCRIPT_DIR / "template.yml"
REPOS_PATH = SCRIPT_DIR / "repos.yaml"
DEFAULT_OUTPUT = Path("/tmp/opencode/rendered")
DEFAULT_BRANCH = "chore/workflow-template-sync"


def resolve_prompt_hub_ref(ref: str | None) -> str:
    """Resolve the prompt-hub ref to a full SHA.

    - None or "HEAD": resolve origin/main HEAD via GitHub API
    - 40-char hex: use as-is
    - anything else: resolve via GitHub API
    """
    if ref and len(ref) == 40 and all(c in "0123456789abcdef" for c in ref):
        return ref

    # Resolve via GitHub API
    target = "heads/main" if (ref is None or ref == "HEAD") else ref
    r = subprocess.run(
        ["gh", "api", f"repos/ubiquiti/prompt-hub/git/ref/{target}",
         "--jq", ".object.sha"],
        capture_output=True, text=True
    )
    if r.returncode != 0:
        print(f"ERROR: cannot resolve prompt-hub ref '{target}': {r.stderr.strip()}", file=sys.stderr)
        sys.exit(1)
    sha = r.stdout.strip()
    if not sha:
        print(f"ERROR: empty SHA for prompt-hub ref '{target}'", file=sys.stderr)
        sys.exit(1)
    print(f"  prompt-hub ref: {sha[:12]} (resolved from {ref or 'origin/main'})")
    return sha


def load_config():
    with open(REPOS_PATH) as f:
        return yaml.safe_load(f)["repos"]


def render_one(repo_name: str, config: dict, template: str, prompt_hub_ref: str) -> str:
    """Render template for a single repo, return the rendered YAML string."""
    # 0. prompt-hub ref
    rendered = template.replace("@@PROMPT_HUB_REF@@", prompt_hub_ref)
    # 1. paths_ignore_extra
    extra_paths = config.get("paths_ignore_extra", [])
    if extra_paths:
        lines = "\n".join(f"      - '{p}'" for p in extra_paths)
        rendered = rendered.replace("      # @@PATHS_IGNORE_EXTRA@@", lines)
    else:
        rendered = rendered.replace("      # @@PATHS_IGNORE_EXTRA@@\n", "")

    # 2. directive_path (occurs 2x)
    rendered = rendered.replace("@@DIRECTIVE_PATH@@", config["directive_path"])

    # 3. domain_desc
    rendered = rendered.replace("@@DOMAIN_DESC@@", config["domain_desc"])

    # 4. extra_allowed_tools (conversation job)
    extra_tools = config.get("extra_allowed_tools", "")
    if extra_tools:
        rendered = rendered.replace("@@EXTRA_ALLOWED_TOOLS@@", f",{extra_tools}")
    else:
        rendered = rendered.replace("@@EXTRA_ALLOWED_TOOLS@@", "")

    # 5. conversation_submodules (only repos with third_party/ submodules)
    if config.get("conversation_submodules", False):
        rendered = rendered.replace(
            "          # @@CONVERSATION_SUBMODULES@@",
            "          submodules: recursive"
        )
    else:
        rendered = rendered.replace("          # @@CONVERSATION_SUBMODULES@@\n", "")

    # 6. review job trigger mode (auto vs label-only)
    trigger_mode = config.get("trigger_mode", "auto")
    if trigger_mode == "label-only":
        review_if = """    if: |
      !contains(github.event.pull_request.labels.*.name, 'claude-review-skip')
      && !contains(github.event.issue.labels.*.name, 'claude-review-skip')
      && (
        (github.event_name == 'pull_request'
          && github.event.pull_request.draft == false
          && !contains(github.event.pull_request.title, '[skip claude]')
          && github.event.action == 'labeled'
          && github.event.label.name == 'claude-pr-review')
        || (github.event_name == 'issue_comment'
            && github.event.issue.pull_request != null
            && !contains(github.event.issue.title, '[skip claude]')
            && contains(github.event.comment.body, '@claude /review-pr')
            && contains(fromJSON('["OWNER","MEMBER"]'),
                        github.event.comment.author_association))
      )"""
    else:
        review_if = """    if: |
      !contains(github.event.pull_request.labels.*.name, 'claude-review-skip')
      && !contains(github.event.issue.labels.*.name, 'claude-review-skip')
      && (
        (github.event_name == 'pull_request'
          && github.event.pull_request.draft == false
          && !contains(github.event.pull_request.title, '[skip claude]')
          && (
            !contains(fromJSON('["labeled","unlabeled"]'), github.event.action)
            || github.event.label.name == 'claude-review-skip'
          ))
        || (github.event_name == 'issue_comment'
            && github.event.issue.pull_request != null
            && !contains(github.event.issue.title, '[skip claude]')
            && contains(github.event.comment.body, '@claude /review-pr')
            && contains(fromJSON('["OWNER","MEMBER"]'),
                        github.event.comment.author_association))
      )"""
    rendered = rendered.replace("    # @@REVIEW_JOB_IF@@", review_if)

    return rendered


def validate_yaml(content: str, repo: str):
    """Validate rendered content is valid YAML."""
    try:
        yaml.safe_load(content)
    except yaml.YAMLError as e:
        print(f"  ERROR: {repo} rendered invalid YAML: {e}", file=sys.stderr)
        return False
    return True


def render_repos(repos: list[str] | None = None, prompt_hub_ref: str = ""):
    """Render specified repos (or all) to output dir."""
    config = load_config()
    template = TEMPLATE_PATH.read_text()

    targets = repos if repos else list(config.keys())
    DEFAULT_OUTPUT.mkdir(parents=True, exist_ok=True)

    results = []
    for name in targets:
        if name not in config:
            print(f"  SKIP: {name} not in repos.yaml")
            continue
        rendered = render_one(name, config[name], template, prompt_hub_ref)
        if not validate_yaml(rendered, name):
            results.append((name, "INVALID YAML"))
            continue
        out_dir = DEFAULT_OUTPUT / name
        out_dir.mkdir(parents=True, exist_ok=True)
        out_file = out_dir / "claude-pr-review.yml"
        out_file.write_text(rendered)
        results.append((name, f"OK ({len(rendered.splitlines())} lines)"))

    for name, status in results:
        print(f"  {name}: {status}")
    return all("OK" in s for _, s in results)


def diff_repos(repos: list[str] | None = None, prompt_hub_ref: str = ""):
    """Diff rendered vs current remote."""
    config = load_config()
    template = TEMPLATE_PATH.read_text()
    targets = repos if repos else list(config.keys())

    for name in targets:
        if name not in config:
            continue
        rendered = render_one(name, config[name], template, prompt_hub_ref)
        # Fetch current from remote
        ref = config[name].get("default_branch", "master")
        r = subprocess.run(
            ["gh", "api", f"repos/ubiquiti/{name}/contents/.github/workflows/claude-pr-review.yml",
             "--jq", ".content"],
            capture_output=True, text=True
        )
        if r.returncode != 0:
            print(f"  {name}: FETCH FAILED")
            continue
        import base64
        current = base64.b64decode(r.stdout.strip().replace("\n", "")).decode()

        if current == rendered:
            print(f"  {name}: IDENTICAL")
        else:
            # Write to temp files and diff
            with tempfile.NamedTemporaryFile(mode='w', suffix='.yml', delete=False) as a:
                a.write(current)
                a_path = a.name
            with tempfile.NamedTemporaryFile(mode='w', suffix='.yml', delete=False) as b:
                b.write(rendered)
                b_path = b.name
            result = subprocess.run(
                ["diff", "--unified=3", a_path, b_path],
                capture_output=True, text=True
            )
            diff_lines = result.stdout.count("\n")
            print(f"  {name}: DIFFERS ({diff_lines} lines in diff)")
            os.unlink(a_path)
            os.unlink(b_path)


def push_repos(repos: list[str] | None = None, branch: str = DEFAULT_BRANCH, prompt_hub_ref: str = ""):
    """Render, clone, commit, push for each repo."""
    config = load_config()
    template = TEMPLATE_PATH.read_text()
    targets = repos if repos else list(config.keys())
    workdir = Path("/tmp/opencode/push-workdir")
    workdir.mkdir(parents=True, exist_ok=True)

    for name in targets:
        if name not in config:
            continue
        rendered = render_one(name, config[name], template, prompt_hub_ref)
        if not validate_yaml(rendered, name):
            print(f"  {name}: SKIP (invalid YAML)")
            continue

        repo_dir = workdir / name
        if repo_dir.exists():
            shutil.rmtree(repo_dir)

        default_br = config[name].get("default_branch", "master")
        # Try cloning the target branch; fall back to default branch
        r = subprocess.run(
            ["git", "clone", "--depth=1", "--branch", branch,
             f"git@github.com:ubiquiti/{name}.git", str(repo_dir)],
            capture_output=True, text=True
        )
        if r.returncode != 0:
            # Branch doesn't exist yet; clone default and create branch
            subprocess.run(
                ["git", "clone", "--depth=1", "--branch", default_br,
                 f"git@github.com:ubiquiti/{name}.git", str(repo_dir)],
                capture_output=True, text=True, check=True
            )
            subprocess.run(
                ["git", "checkout", "-b", branch],
                cwd=repo_dir, capture_output=True, text=True, check=True
            )

        wf_path = repo_dir / ".github" / "workflows" / "claude-pr-review.yml"
        wf_path.parent.mkdir(parents=True, exist_ok=True)
        wf_path.write_text(rendered)

        # Commit
        subprocess.run(["git", "add", str(wf_path)], cwd=repo_dir, check=True,
                       capture_output=True)
        r = subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=repo_dir,
                           capture_output=True)
        if r.returncode == 0:
            print(f"  {name}: SKIP (no diff)")
            continue

        subprocess.run(
            ["git", "commit", "-m",
             "fix(ci): sync workflow from prompt-hub template\n\n"
             "Rendered from code-review/workflow-template/ — includes all\n"
             "shared improvements from udc canary (Phase 4, stale-rerun\n"
             "guards, dismiss logic, cancel-in-progress:false).",
             "--no-verify"],
            cwd=repo_dir, capture_output=True, text=True, check=True
        )

        r = subprocess.run(
            ["git", "push", "origin", branch],
            cwd=repo_dir, capture_output=True, text=True
        )
        if r.returncode == 0:
            print(f"  {name}: PUSHED")
        else:
            print(f"  {name}: PUSH FAILED ({r.stderr.strip()[:80]})")

        # Handle extra_branches — same rendered workflow pushed to each branch
        for extra_br in config[name].get("extra_branches", []):
            sync_branch = f"chore/workflow-template-sync-{extra_br}"
            eb_dir = workdir / f"{name}-{extra_br}"
            if eb_dir.exists():
                shutil.rmtree(eb_dir)
            try:
                subprocess.run(
                    ["git", "clone", "--depth=1", "--branch", extra_br,
                     f"git@github.com:ubiquiti/{name}.git", str(eb_dir)],
                    capture_output=True, text=True, check=True
                )
            except subprocess.CalledProcessError as e:
                print(f"  {name} [{extra_br}]: FAILED (clone: {e.stderr.strip()[:80]})")
                continue

            subprocess.run(
                ["git", "checkout", "-b", sync_branch],
                cwd=eb_dir, capture_output=True, text=True, check=True
            )

            eb_wf = eb_dir / ".github" / "workflows" / "claude-pr-review.yml"
            eb_wf.parent.mkdir(parents=True, exist_ok=True)
            eb_wf.write_text(rendered)

            # -f because some branches have .gitignore blocking .github
            subprocess.run(["git", "add", "-f", str(eb_wf)], cwd=eb_dir,
                           check=True, capture_output=True)
            r = subprocess.run(["git", "diff", "--cached", "--quiet"],
                               cwd=eb_dir, capture_output=True)
            if r.returncode == 0:
                print(f"  {name} [{extra_br}]: SKIP (no diff)")
                continue

            subprocess.run(
                ["git", "commit", "-m",
                 "fix(ci): sync workflow from prompt-hub template\n\n"
                 "Rendered from code-review/workflow-template/ — includes all\n"
                 "shared improvements from udc canary (Phase 4, stale-rerun\n"
                 "guards, dismiss logic, cancel-in-progress:false).",
                 "--no-verify"],
                cwd=eb_dir, capture_output=True, text=True, check=True
            )

            r = subprocess.run(
                ["git", "push", "origin", sync_branch],
                cwd=eb_dir, capture_output=True, text=True
            )
            if r.returncode == 0:
                print(f"  {name} [{extra_br}]: PUSHED")
            else:
                print(f"  {name} [{extra_br}]: FAILED ({r.stderr.strip()[:80]})")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repos", nargs="*", help="Specific repos to process")
    parser.add_argument("--diff", action="store_true", help="Diff against remote")
    parser.add_argument("--push", action="store_true", help="Push to repos")
    parser.add_argument("--branch", default=DEFAULT_BRANCH, help="Branch for push")
    parser.add_argument("--ref", default=None,
                        help="prompt-hub SHA (40-char hex, 'HEAD' for origin/main, or omit to auto-resolve)")
    args = parser.parse_args()

    prompt_hub_ref = resolve_prompt_hub_ref(args.ref)
    repos = args.repos or None
    if args.diff:
        diff_repos(repos, prompt_hub_ref)
    elif args.push:
        push_repos(repos, args.branch, prompt_hub_ref)
    else:
        ok = render_repos(repos, prompt_hub_ref)
        sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
