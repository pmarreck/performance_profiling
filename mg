#!/usr/bin/env bash
cd "$(dirname "$0")" || exit 1
exec ./bin/performance-profile run --mode mg "$@"
