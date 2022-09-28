#!/usr/bin/env bash

set -ue
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
earthly=$(realpath "$earthly")
earthly_dir=$(get_earthly_dir)

echo "=== Test 1: Hand Bootstrapped ==="

"$earthly" bootstrap


echo "----"
"$earthly" +test | tee hand_boot_output # Hand boots are gloves ;)

if  cat hand_boot_output | grep -q "bootstrap |"; then
    echo "build did extra bootstrap"
    exit 1
fi

rm -rf "${earthly_dir:?}/"

echo "=== Test 2: Implied Bootstrap ==="

"$earthly" +test

if [[ ! -d "$earthly_dir" ]]; then
  echo "$earthly_dir directory was missing after bootstrap"
  exit 1
fi

echo "----"
"$earthly" +test | tee imp_boot_output

if  cat imp_boot_output | grep -q "bootstrap |"; then
    echo "build did extra bootstrap"
    exit 1
fi

rm -rf "${earthly_dir:?}/"

echo "=== Test 3: CI ==="

"$earthly" --ci +test

if [[ ! -d "$earthly_dir" ]]; then
  echo "$earthly_dir directory was missing after bootstrap"
  exit 1
fi

echo "----"
"$earthly" --ci +test | tee ci_boot_output

if  cat ci_boot_output | grep -q "bootstrap |"; then
    echo "build did extra bootstrap"
    exit 1
fi

rm -rf "${earthly_dir:?}/"

echo "=== Test 4: With Autocomplete ==="

"$earthly" bootstrap

if [[ -f "/usr/share/bash-completion/completions/earthly" ]]; then
  echo "autocompletions were present when they should not have been"
  exit 1
fi

echo "----"
sudo "$earthly" bootstrap --with-autocomplete

if [[ ! -f "/usr/share/bash-completion/completions/earthly" ]]; then
  echo "autocompletions were missing when they should have been present"
  exit 1
fi

rm -rf "${earthly_dir:?}/"
sudo rm -rf "/usr/share/bash-completion/completions/earthly"

echo "=== Test 5: Permissions ==="

touch testfile
USR=$(stat --format '%U' testfile)
GRP=$(stat --format '%G' testfile)

echo "Current defaults:"
echo "User : $USR"
echo "Group: $GRP"

"$earthly" bootstrap

if [[ $(stat --format '%U' "$earthly_dir") != "$USR" ]]; then
  echo "earthly directory is not owned by the user"
  stat "$earthly_dir"
  exit 1
fi

if [[ $(stat --format '%G' "$earthly_dir") != "$GRP" ]]; then
  echo "earthly directory is not owned by the users group"
  stat "$earthly_dir"
  exit 1
fi

echo "----"
touch "$earthly_dir/config.yml"
sudo chown -R 12345:12345 "$earthly_dir"

sudo "$earthly" bootstrap

if [[ $(stat --format '%U' "$earthly_dir") != "$USR" ]]; then
  echo "earthly directory is not owned by the user"
  stat "$earthly_dir"
  exit 1
fi

if [[ $(stat --format '%G' "$earthly_dir") != "$GRP" ]]; then
  echo "earthly directory is not owned by the users group"
  stat "$earthly_dir"
  exit 1
fi

if [[ $(stat --format '%U' "$earthly_dir/config.yml") != "$USR" ]]; then
  echo "earthly config is not owned by the user"
  stat "$earthly_dir/config.yml"
  exit 1
fi

if [[ $(stat --format '%G' "$earthly_dir/config.yml") != "$GRP" ]]; then
  echo "earthly config is not owned by the users group"
  stat "$earthly_dir/config.yml"
  exit 1
fi

echo "=== Test 6: works in read-only directory ==="

sudo mkdir /tmp/earthly-read-only-test
sudo cp Earthfile /tmp/earthly-read-only-test/.
sudo chmod 0755 /tmp/earthly-read-only-test/.

prevdir=$(pwd)
cd /tmp/earthly-read-only-test/.

if touch this-should-fail 2>/dev/null; then
  echo "this directory should have been read-only; something is wrong with this test"
  exit 1
fi

"$earthly" +test

cd "$prevdir"

echo "=== Test 7: Homebrew Source ==="

if which docker > /dev/null; then
  docker rm -f earthly-buildkitd
fi

bash=$("$earthly" bootstrap --source bash)
if [[ "$bash" != *"complete -o nospace"* ]]; then
  echo "bash autocompletion appeared to be incorrect"
  echo "$bash"
  exit 1
fi

zsh=$("$earthly" bootstrap --source zsh)
if [[ "$zsh" != *"complete -o nospace"* ]]; then
  echo "zsh autocompletion appeared to be incorrect"
  echo "$zsh"
  exit 1
fi

if docker container ls | grep earthly-buildkitd; then
  echo "--source created a docker container"
  exit 1
fi

if [[ -f ../../build/linux/amd64/earth ]]; then
  echo "--source symlinked earthly to earth"
fi

if ! DOCKER_HOST="docker is missing" "$earthly" bootstrap --source zsh > /dev/null 2>&1; then
  echo "--source failed when docker was missing"
  exit 1
fi

rm -rf "${earthly_dir:?}/"

echo "=== Test 8: No Buildkit ==="

"$earthly" bootstrap --no-buildkit
if docker container ls | grep earthly-buildkitd; then
  echo "--no-buildkit created a docker container"
  exit 1
fi

if ! DOCKER_HOST="docker is missing" "$earthly" bootstrap --no-buildkit; then
  echo "--no-buildkit fails when docker is missing"
  exit 1
fi

rm -rf "${earthly_dir:?}/"
