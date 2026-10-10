#!/bin/bash
# Wait (up to WAITMAX s, default 900) until no other game instance holds memory, then run test.sh.
for ((w = 0; w < ${WAITMAX:-900}; w++)); do
    [ "$(tasklist | grep -ciE 'shadps4|ShadowOfTheColossus')" = "0" ] && break
    sleep 1
done
echo "waited ${w}s"
exec /d/i3-pc/test.sh "$@"
