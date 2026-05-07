#!/usr/bin/env bash

if pgrep -x swayidle > /dev/null; then
	echo " activated"
else
	echo " deactivated"
fi
