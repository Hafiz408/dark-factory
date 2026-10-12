#!/usr/bin/env bash
cd "$1" || exit 2
out=$(python3 fizzbuzz.py 15) || { echo "tool does not run"; exit 1; }
[ "$(echo "$out" | sed -n '3p')" = "Fizz" ] && [ "$(echo "$out" | sed -n '5p')" = "Buzz" ] && [ "$(echo "$out" | tail -1)" = "FizzBuzz" ] || { echo "wrong output"; exit 1; }
ls test_*.py tests/*.py >/dev/null 2>&1 || { echo "no tests"; exit 1; }
python3 -m unittest discover -q || { echo "suite red"; exit 1; }
