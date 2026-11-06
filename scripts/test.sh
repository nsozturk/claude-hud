#!/usr/bin/env bash
# Transcript replay test. Pass the id of a running Claude Code session
# (any "sessionId" in ~/.claude/sessions/*.json), or --real to list what the HUD
# would show from your real transcripts.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
SOURCES=$(ls */*.swift | grep -v '^Tests/' | grep -v '^App/ClaudeHUDApp.swift' | grep -v '^build/')
swiftc -parse-as-library -o build/replay-test $SOURCES Tests/WatcherReplayTest.swift
build/replay-test "$@"
