#!/bin/bash

if pgrep sstpc >/dev/null; then
   pkill -TERM sstpc
   sleep 1
fi

/etc/sstp-connector/update-resolv-conf down

exit 0
