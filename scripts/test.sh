#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build
xcrun swiftc -swift-version 5 -module-cache-path /tmp/chui-swift-cache Sources/FileEngine.swift Tests/EngineTests.swift -o build/EngineTests
build/EngineTests
xcrun swiftc -swift-version 5 -module-cache-path /tmp/chui-swift-cache Sources/FileEngine.swift Sources/VolumeInfo.swift Tests/StorageTests.swift -o build/StorageTests
build/StorageTests
