#!/bin/bash

pkill sstpc
/etc/sstp-connector/update-resolv-conf down
pkill -f /etc/sstp-connector/connect.sh

exit 0;
