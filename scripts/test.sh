#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build
xcrun swiftc -swift-version 5 -module-cache-path /tmp/chui-swift-cache Sources/FileEngine.swift Tests/EngineTests.swift -o build/EngineTests
build/EngineTests
xcrun swiftc -swift-version 5 -module-cache-path /tmp/chui-swift-cache Sources/FileEngine.swift Sources/VolumeInfo.swift Tests/StorageTests.swift -o build/StorageTests
build/StorageTests

xcrun swiftc -module-cache-path /tmp/chui-swift-cache Sources/FileEngine.swift Tests/FolderBytesTests.swift -o build/FolderBytesTests
build/FolderBytesTests

xcrun swiftc -module-cache-path /tmp/chui-swift-cache Sources/FileEngine.swift Tests/SortingTests.swift -o build/SortingTests
build/SortingTests

xcrun swiftc -module-cache-path /tmp/chui-swift-cache Sources/FileEngine.swift Sources/TransferProgress.swift Tests/TransferProgressTests.swift -o build/TransferProgressTests
build/TransferProgressTests
