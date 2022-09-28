#!/bin/bash
set -uxe
set -o pipefail

get_earthly_dir() {
  legacy_earthly_dir="$HOME/.earthly"
  new_earthly_dir="${XDG_STATE_HOME:-$HOME/.local/state}/earthly"

  if [[ ! -d "$legacy_earthly_dir" && ! -d "$new_earthly_dir" ]]; then
    echo ".earthly directory was missing after bootstrap"
    exit 1
  fi

  if [ -d "$legacy_earthly_dir" ]; then
    printf '%s\n' "$legacy_earthly_dir"
  else
    printf '%s\n' "$new_earthly_dir"
  fi
}

cd "$(dirname "$0")"
earthly=${earthly-"../../build/linux/amd64/earthly"}
earthly_dir=$(get_earthly_dir)

cp "$earthly_dir"/config.yml "$earthly_dir"/config.yml.bkup

function finish {
  mv "$earthly_dir"/config.yml.bkup "$earthly_dir"/config.yml
}
trap finish EXIT


"$earthly" config global.tls_enabled true

# FIXME bootstrap is failing with "open /home/runner/.local/state/earthly/certs/ca_cert.pem: permission denied", but generates them nonetheless.
"$earthly" --verbose --buildkit-host tcp://127.0.0.1:8372 bootstrap || (echo "ignoring bootstrap failure")

# bootstrapping should generate six pem files


test $(ls "$earthly_dir"/certs/*.pem | wc -l) = "6"

"$earthly" --verbose --buildkit-host tcp://127.0.0.1:8372 +target 2>&1 | perl -pe 'BEGIN {$status=1} END {exit $status} $status=0 if /running under remote-buildkit test/;'
