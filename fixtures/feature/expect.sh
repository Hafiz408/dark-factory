#!/usr/bin/env bash
cd "$1" || exit 2
[ "$(python3 greet.py --upper bob)" = "HELLO BOB" ] || { echo "--upper missing"; exit 1; }
[ "$(python3 greet.py bob)" = "hello bob" ] || { echo "default behaviour changed"; exit 1; }
python3 -m unittest discover -q || { echo "suite red"; exit 1; }
