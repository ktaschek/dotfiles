#!/bin/bash

# Block characters: index 0 = empty, 8 = full
blocks=(
  	"████"
	"███▉"
	"███▊"
	"███▋"
	"███▌"
	"███▍"
	"███▎"
	"███▏"
	"███░"
	"██▉░"
	"██▊░"
	"██▋░"
	"██▌░"
	"██▍░"
	"██▎░"
	"██▏░"
	"██░░"
	"█▉░░"
	"█▊░░"
	"█▋░░"
	"█▌░░"
	"█▍░░"
	"█▎░░"
	"█▏░░"
	"█░░░"
	"▉░░░"
	"▊░░░"
	"▋░░░"
	"▌░░░"
	"▍░░░"
	"▎░░░"
	"▏░░░"
	"░░░░"
)

num_blocks = 33


tomat status --format json | while IFS= read -r line; do
    percent=$(echo "$line" | jq -r '.percent // 0')
    text=$(echo "$line"    | jq -r '.text // ""')
    tooltip=$(echo "$line" | jq -r '.tooltip // ""')
    class=$(echo "$line"   | jq -r '.class // ""')

    # Map percent (0–100) to index (0–32)
    index=$(( percent * num_blocks / 100 ))
    # Clamp
    (( index > num_blocks )) && index=num_blocks
    (( index < 0  )) && index=0

    bar="${blocks[$index]}"

    jq -cn \
        --arg text "$bar $text" \
        --arg tooltip "$tooltip" \
        --arg class "$class" \
        '{text: $text, tooltip: $tooltip, class: $class}'
done
