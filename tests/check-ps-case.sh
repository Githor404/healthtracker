#!/usr/bin/env bash
# R155/R242 -- no PowerShell variable written in two cases ($K and $k are ONE
# variable; a loop over one silently destroys the other, and an assertion against
# the destroyed value passes vacuously). See tests/ps_case_collisions.py.
DIR=$(cd "$(dirname "$0")" && pwd)
python -I "$DIR/ps_case_collisions.py" "$DIR"/*.ps1
