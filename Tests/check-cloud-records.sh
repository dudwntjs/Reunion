#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
check_dir=$(mktemp -d)
trap 'rm -rf "$check_dir"' EXIT
xcrun swiftc -parse-as-library Shared/ReunionCore.swift Shared/Participants.swift Shared/CloudInvitation.swift \
    Reunion/SessionClient.swift Reunion/CloudRecordCodec.swift Tests/CloudKit/CloudRecordCheck.swift \
    -o "$check_dir/check"
"$check_dir/check"
