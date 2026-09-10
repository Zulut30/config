#!/bin/bash
set -euo pipefail
KOPILKA_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$KOPILKA_ROOT"
/usr/bin/xcrun swift build
KOPILKA_BUILD="$(/usr/bin/xcrun swift build --show-bin-path)"
/usr/bin/xcrun swiftc -parse-as-library \
    -I "$KOPILKA_BUILD/Modules" -I Sources/CSQLite \
    "$KOPILKA_BUILD/KopilkaCore.build/Note.swift.o" \
    "$KOPILKA_BUILD/KopilkaCore.build/Database.swift.o" \
    Sources/Kopilka/Capture.swift Tests/KopilkaTests/CoreTests.swift \
    -framework Carbon -lsqlite3 -o "$KOPILKA_BUILD/KopilkaChecks"
"$KOPILKA_BUILD/KopilkaChecks"
