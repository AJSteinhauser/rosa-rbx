#!/usr/bin/env bash
set -euo pipefail

VERSION=$(grep '^version' wally.toml | sed 's/version = "\(.*\)"/\1/')

cat > src/models/version.luau << EOF
-- Auto-generated from wally.toml — do not edit manually.
return "$VERSION"
EOF
