#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build="$PWD/.build/release"
mkdir -p "$build"
swiftc -swift-version 5 -O -parse-as-library -emit-module -emit-library -module-name GuyiCore Sources/GuyiCore/*.swift -emit-module-path "$build/GuyiCore.swiftmodule" -o "$build/libGuyiCore.dylib" -Xlinker -install_name -Xlinker @rpath/libGuyiCore.dylib
clang -O2 -c Sources/CRimeBridge/bridge.c -I Sources/CRimeBridge/include -I /opt/homebrew/include -o "$build/rime-bridge.o"
clang -O2 -fobjc-arc -Wno-deprecated-declarations -c Sources/CInputMethodBridge/connection.m -I Sources/CInputMethodBridge/include -o "$build/imk-connection.o"
swiftc -swift-version 5 -O -I "$build" -I Sources/CRimeBridge/include -I Sources/CInputMethodBridge/include -L "$build" -L /opt/homebrew/lib -lGuyiCore -lrime Sources/GuyiApp/*.swift "$build/rime-bridge.o" "$build/imk-connection.o" -o "$build/guyi" -Xlinker -rpath -Xlinker @executable_path/../Frameworks -Xlinker -rpath -Xlinker @executable_path
swiftc -swift-version 5 -O -parse-as-library -I "$build" -L "$build" -lGuyiCore Sources/GuyiEval/main.swift -o "$build/guyi-eval" -Xlinker -rpath -Xlinker @executable_path
