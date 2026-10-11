#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/compile.sh
swiftc -swift-version 5 -parse-as-library -I .build/release -L .build/release -lGuyiCore Tests/GuyiCoreTests/*.swift -o .build/release/core-tests -Xlinker -rpath -Xlinker @executable_path
.build/release/core-tests
clang -fobjc-arc -Wno-deprecated-declarations -framework Foundation -I Sources/CInputMethodBridge/include Sources/CInputMethodBridge/connection.m scripts/imk-connection-smoke.m -o .build/release/imk-connection-smoke
.build/release/imk-connection-smoke
