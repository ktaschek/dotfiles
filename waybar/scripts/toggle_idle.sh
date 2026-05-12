#!/usr/bin/env bash

PIDFILE="/tmp/swayidle.pid"

if pgrep -x swayidle > /dev/null; then
	pkill swayidle
	echo "off" > /tmp/idle_status
else
	swayidle -w \
		timeout 5 'swaylock f --screenshots --effect-blur 7x5 --effect-vignette 0.5:0.5 --fade-in 0.2'\
		timeout 10 'swaymsg "output * dpms off"'\
			resume 'swaymsg "output *dpms on"'\
        before-sleep 'swaylock -f --screenshots --effect-blur 7x5 --effect-vignette 0.5:0.5 --fade-in 0.2' &	
	echo "on" > /tmp/idle_status
fi
