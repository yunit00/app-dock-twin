#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/checks
swiftc Sources/DockTwin/Model.swift Sources/DockTwin/DockView.swift Sources/DockTwin/SettingsView.swift Tests/DockTwinTests/DockModelTests.swift -o .build/checks/DockModelChecks
.build/checks/DockModelChecks
