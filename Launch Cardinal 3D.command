#!/bin/zsh
task_root="$(cd -- "$(dirname -- "$0")" && pwd)"
cd -- "$task_root" || exit 1
exec /usr/bin/python3 "$task_root/scripts/run.py"
