---
name: tricky_quoting
description: Use when testing tricky quoting guards for Detector 6. Vars in comments, single-quotes, and quoted heredocs must not be flagged.
landing-group: workflow
---

# tricky_quoting

## Workflow

```bash
# $COMMENT_VAR should not be flagged (in a comment)
echo 'literal $SQUOTE_VAR not expanded'
cat <<'HEREDOC'
$HEREDOC_VAR also literal
HEREDOC
echo "this is fine"
```
