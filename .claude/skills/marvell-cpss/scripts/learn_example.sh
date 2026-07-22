#!/bin/bash
# Script to capture and learn new CPSS configuration examples

set -e

EXAMPLE_NAME="$1"
SKILL_DIR="/home/averyyang/.claude/skills/marvell-cpss"
EXAMPLES_FILE="$SKILL_DIR/references/examples.md"

if [ -z "$EXAMPLE_NAME" ]; then
    echo "Usage: $0 <example-name>"
    echo "Example: $0 'port-mirroring'"
    exit 1
fi

echo "=== Learning New Example: $EXAMPLE_NAME ==="
echo ""
echo "This script will help you document a new CPSS configuration example."
echo ""

# Create temporary file for the new example
TEMP_FILE=$(mktemp)

cat > "$TEMP_FILE" << 'EOF'
### Example: [NAME]

**Use Case:** [Brief description]

#### Configuration Commands
```
Console# configure
[Your commands here]
Console# end
```

#### What This Does
- [Explanation point 1]
- [Explanation point 2]

#### Underlying Lua Code
**File:** `[lua script path]`

```lua
-- [Key Lua implementation]
```

#### Validation
```
Console# [show command to verify]
```

**Or test with Lua:**
```lua
-- [Validation Lua code]
```

---
EOF

# Replace placeholders
sed -i "s/\[NAME\]/$EXAMPLE_NAME/g" "$TEMP_FILE"

echo "Template created at: $TEMP_FILE"
echo ""
echo "Next steps:"
echo "1. Edit the template file to add your example details"
echo "2. Test the configuration on your device"
echo "3. Run: cat $TEMP_FILE >> $EXAMPLES_FILE"
echo ""
echo "Or edit now with: vim $TEMP_FILE"
