#!/bin/bash
# Leave this running in your own Terminal. It makes a signed build each time
# a request file appears, so a tool that cannot use your signing key (an
# agent session) can ask for a build without you typing the command.
#
#   scripts/build-on-request.sh
#
# Request:  touch build/.request
# Result:   build/.result holds the exit code of scripts/release.sh --dry-run
#           --allow-dirty (the working tree as it is), build/.log holds its
#           output.
# Stop with Control-C.
set -u
cd "$(dirname "$0")/.."
mkdir -p build
rm -f build/.request build/.result
echo "waiting for build requests in $(pwd)/build/.request (Control-C stops)"
while true; do
  if [ -f build/.request ]; then
    rm -f build/.request build/.result
    echo "==> $(date '+%H:%M:%S') build requested"
    scripts/release.sh --dry-run --allow-dirty > build/.log 2>&1
    code=$?
    echo "$code" > build/.result
    if [ "$code" = 0 ]; then echo "    done, signed build is ready"; else echo "    FAILED with $code, see build/.log"; tail -5 build/.log; fi
  fi
  sleep 1
done
