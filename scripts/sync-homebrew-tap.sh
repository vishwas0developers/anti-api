#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_DIR="${1:-}"

if [ -z "$TARGET_DIR" ]; then
    echo "Usage: scripts/sync-homebrew-tap.sh /path/to/homebrew-anti-api"
    exit 1
fi

mkdir -p "$TARGET_DIR/Formula"
cp "$REPO_ROOT/Formula/anti-api.rb" "$TARGET_DIR/Formula/anti-api.rb"

cat > "$TARGET_DIR/README.md" <<'EOF'
# homebrew-anti-api

Homebrew tap for [Anti-API](https://github.com/ink1ing/anti-api).

## Install

```bash
brew tap ink1ing/anti-api
brew install anti-api
```

## Upgrade

```bash
brew upgrade anti-api
```

## Run

```bash
anti-api
```

## Notes

- The formula installs a prebuilt macOS Apple Silicon bundle. It does not download Rust, LLVM, or Bun at install time.
- In-app self-update is disabled for Homebrew-managed installs. Use `brew upgrade anti-api` instead.
- Formula source of truth: `Formula/anti-api.rb` from the main Anti-API repository.
EOF

echo "Synced Homebrew tap files to $TARGET_DIR"
