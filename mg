#!/usr/bin/env bash
cd "$(dirname "$0")" || exit 1
source ./scripts/reenter-devshell.bash
reenter_devshell "$PWD" "$PWD/${0##*/}" "$@"
exec ./bin/performance-profile run --mode mg "$@"
