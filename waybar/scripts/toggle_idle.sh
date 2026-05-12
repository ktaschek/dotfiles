#!/usr/bin/env bash

PIDFILE="/tmp/swayidle.pid"

if pgrep -x swayidle > /dev/null; then
	pkill swayidle
	echo "off" > /tmp/idle_status
else
	swayidle -w \
		timeout 300 "swaylock -f \
		--screenshots \
		--effect-blur 7x5 \
		--fade-in 0.2 \
		--clock \
		--indicator \
		--indicator-idle-visible \
		--inside-color 1F2430 "\
		timeout 600 'swaymsg "output * dpms off"'\
			resume 'swaymsg "output *dpms on"'\
        before-sleep "swaylock -f \
		--screenshots \
		--effect-blur 7x5 \
		--fade-in 0.2 \
		--clock \
		--indicator \
		--indicator-idle-visible \
		--inside-color 1F2430 "\ &	
	echo "on" > /tmp/idle_status
fi
