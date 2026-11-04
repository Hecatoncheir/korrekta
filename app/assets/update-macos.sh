#!/bin/bash
set -euo pipefail
image="$1"
destination="$2"
parent_pid="$3"
log="$4"
exec >> "$log" 2>&1
[[ "$destination" == */Корректа.app && "$destination" != /Volumes/* ]]
test -w "$(dirname "$destination")"
for attempt in {1..60}; do
  if ! kill -0 "$parent_pid" 2>/dev/null; then break; fi
  sleep 1
done
if kill -0 "$parent_pid" 2>/dev/null; then exit 1; fi
mount_point=$(mktemp -d /tmp/korrekta-update.XXXXXX)
stage=$(mktemp -d "$(dirname "$destination")/.korrekta-update.XXXXXX")
hdiutil attach "$image" -readonly -nobrowse -mountpoint "$mount_point"
trap 'hdiutil detach "$mount_point"; rmdir "$mount_point"' EXIT
test -x "$mount_point/Корректа.app/Contents/MacOS/korrekta"
ditto "$mount_point/Корректа.app" "$stage/new.app"
mv "$destination" "$stage/previous.app"
if ! mv "$stage/new.app" "$destination"; then
  mv "$stage/previous.app" "$destination"
  exit 1
fi
open -n "$destination"
