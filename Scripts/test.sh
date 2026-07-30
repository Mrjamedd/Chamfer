#!/bin/sh
# Runs the full Swift Testing suite. Command Line Tools does not add its
# developer Testing framework or private interop library to package builds, so
# keep both compile-time and runtime search paths here as one source of truth.
set -eu
FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
TESTING_INTEROP="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
TESTING_PLUGINS="/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"

exec swift test \
  -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
  -Xswiftc -plugin-path -Xswiftc "$TESTING_PLUGINS" \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$TESTING_INTEROP" \
  "$@"
