#!/bin/sh
# Runs the Swift Testing suite.
#
# Command Line Tools does not add its developer Testing framework or private
# interop library to package builds, so those search paths are supplied here as
# one source of truth. A machine with full Xcode — a CI runner, or a developer
# who installed it — needs none of that, and passing paths that do not exist
# there fails the build. So the flags are added only when the CLT directory is
# actually present.
#
#   Scripts/test.sh                      everything
#   Scripts/test.sh --skip liveModel     everything that does not need a model
set -eu

FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
TESTING_INTEROP="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
TESTING_PLUGINS="/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"

# The CLT runner can fill its event pipe before executing a large suite when
# every Swift Testing case is scheduled at once.
export SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH="${SWT_EXPERIMENTAL_MAXIMUM_PARALLELIZATION_WIDTH:-1}"

# Sparkle is an XCFramework, and the app target links it. A test bundle that
# imports the app therefore has to be able to find it at load time, which
# nothing arranges outside an .app bundle. Resolved rather than hardcoded: the
# slice directory is named after the architectures it holds.
SPARKLE_SLICE=""
for candidate in .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/*/; do
  if [ -d "$candidate" ]; then
    SPARKLE_SLICE="$(cd "$candidate" && pwd)"
    break
  fi
done

set -- "$@"
if [ -n "$SPARKLE_SLICE" ]; then
  set -- "$@" -Xlinker -rpath -Xlinker "$SPARKLE_SLICE"
fi

if [ -d "$FRAMEWORKS" ]; then
  exec swift test \
    -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
    -Xswiftc -plugin-path -Xswiftc "$TESTING_PLUGINS" \
    -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$TESTING_INTEROP" \
    "$@"
fi

exec swift test "$@"
