#!/usr/bin/env bash

PIDFILE="/tmp/swayidle.pid"

if pgrep -x swayidle > /dev/null; then
	pkill swayidle
	echo "off" > /tmp/idle_status
else
	swayidle -w \
		timeout 300 'swaylock -f -c 000000'\
		timeout 600 'swaymsg "output * dpms off"'\
			resume 'swaymsg "output *dpms on"'\
		before-sleep 'swaylock -f -c 000000' &
	
	echo "on" > /tmp/idle_status
fi
