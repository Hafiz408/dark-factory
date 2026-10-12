#!/usr/bin/env bash
cd "$1" || exit 2
python3 -c "from slug import slugify; assert slugify('Hello,  World!') == 'hello-world'" || { echo "bug not fixed"; exit 1; }
ls test_*.py tests/*.py >/dev/null 2>&1 || { echo "no runner or tests were added"; exit 1; }
python3 -m unittest discover -q || { echo "suite red"; exit 1; }
