#!/bin/bash
# ─────────────────────────────────────────────
# obsidian-task.sh
# Rofi Obsidian TaskNotes creator:
#   - Displays current tasks
#   - Create Task interface using rofi 
# ─────────────────────────────────────────────

source ~/dotfiles/sway/scripts/obsidian-task-lib.sh

declare -a new_task_str="+ New task                                            | scheduled        | due              | est."

_fmt_date() {
    local raw="$1"
    if [[ -z "$raw" ]]; then
        echo "                "   # blank placeholder, same width as YYYY-MM-DD
        return
    fi
    if [[ "$raw" =~ T([0-9]{2}:[0-9]{2}) ]]; then
        echo "${raw%%T*} ${BASH_REMATCH[1]}"
    else
        echo "${raw%%T*}      "
    fi
}


render_children() {
    local parent_title="$1"
    local depth="$2"
    local children="${CHILDREN_OF[$parent_title]}"

    [[ -z "$children" ]] && return

    local indent=""
    for (( d=0; d<depth; d++ )); do indent+="    "; done
    local prefix="<span foreground='#fbf1c7'>${indent}↳ </span>"

    IFS='|' read -ra child_ids <<< "$children"
    for j in "${child_ids[@]}"; do
        # [[ "${STATUSES[$j]}" == "done" ]] && continue

        local sched_display due_display
        sched_display=$(_fmt_date "${SCHEDULED[$j]}")
        due_display=$(_fmt_date "${DUE_DATES[$j]}")

        local child_icon=""
        case "${PRIORITIES[$j]}" in
            high)   child_icon="<span foreground='#ff6666'>▴</span> " ;;
            normal) child_icon="<span foreground='#ffff66'>▸</span> " ;;
            low)    child_icon="<span foreground='#66ff66'>▾</span> " ;;
            *)      child_icon="○ " ;;
        esac

        local time_est=""
        [[ -n "${TIME_ESTIMATES[$j]}" ]] && time_est="~${TIME_ESTIMATES[$j]}m"
        
        local width=125

        local status_icon=""
        [[ "${STATUSES[$j]}" == "in-progress" ]] && status_icon="⟳ " && (( width+=2 ))

        local formatted_field

        if [[ "${STATUSES[$j]}" == "done" ]]; then
            printf -v formatted_field "%-${width}.${width}s" "${prefix}${child_icon}${TITLES[$j]}"
            formatted_field="<span foreground='#928374'><s>${formatted_field}</s></span>"
            echo "${formatted_field} | ${sched_display} | ${due_display} | ${time_est}||IDX:$j"
            continue
        elif is_overdue "$j"; then
            printf -v formatted_field "%-${width}.${width}s" "${prefix}${child_icon}${status_icon}${TITLES[$j]}"
            formatted_field="<span foreground='#ff6666'>${formatted_field}</span>"
        else
            printf -v formatted_field "%-${width}.${width}s" "${prefix}${child_icon}${status_icon}${TITLES[$j]}"
        fi
 
        echo "${formatted_field} | ${sched_display} | ${due_display} | ${time_est}||IDX:$j"
        render_children "${TITLES[$j]}" $(( depth + 1 ))

    done
}


build_menu() {
    local -a sorted
    mapfile -t sorted < <(get_sorted_indices)
    local lines=()
    lines+=("$new_task_str")
    for i in "${sorted[@]}"; do
        local title="${TITLES[$i]}"

        local sched_display due_display
        sched_display=$(_fmt_date "${SCHEDULED[$i]}")
        due_display=$(_fmt_date "${DUE_DATES[$i]}")

        local proj="${PROJECTS[$i]}"

        # Priority icon
        local icon=""
        case "${PRIORITIES[$i]}" in
            high)   icon="<span foreground='#ff6666'>▴</span> " ;;
            normal) icon="<span foreground='#ffff66'>▸</span> " ;;
            low)    icon="<span foreground='#66ff66'>▾</span> " ;;
            *)      icon="○ " ;;
        esac

        if [[ -n "$proj" ]]; then
            continue
        fi

        local time_est=""
        [[ -n "${TIME_ESTIMATES[$i]}" ]] && time_est="~${TIME_ESTIMATES[$i]}m"
        local width=89
        local status_icon=""
        [[ "${STATUSES[$i]}" == "in-progress" ]] && status_icon="⟳ " && (( width+=2 ))

        local formatted_field
        if [[ "${STATUSES[$i]}" == "done" ]]; then
            printf -v formatted_field "%-${width}.${width}s" "${prefix}${icon}${title}"
            formatted_field="<span foreground='#928374'><s>${formatted_field}</s></span>"
        elif is_overdue "$i"; then
            printf -v formatted_field "%-${width}.${width}s" "${icon}${status_icon}${title}"
            formatted_field="<span foreground='#ff6666'>${formatted_field}</span>"
        else
            printf -v formatted_field "%-${width}.${width}s" "${icon}${status_icon}${title}"
        fi

        lines+=("${formatted_field} | ${sched_display} | ${due_display} | ${time_est}||IDX:$i")
 
        mapfile -t child_lines < <(render_children "${TITLES[$i]}" 1 "${sorted[@]}")
        lines+=("${child_lines[@]}")
    done

    printf '%s\n' "${lines[@]}"
}

create_task_form() {
    local title priority scheduled

    title=$(rofi -dmenu -p "Title" -l 0 $ROFI_THEME) || return
    [[ -z "$title" ]] && return

    priority=$(printf 'high\nnormal\nlow' | rofi -dmenu -p "Priority" $ROFI_THEME) || return
    [[ -z "$priority" ]] && priority="normal"

        local date_choice
    date_choice=$(printf 'Tomorrow\nNext week\nNo date\nCustom' | rofi -dmenu -p "Scheduled date" $ROFI_THEME) || return
 
    case "$date_choice" in
        "No date")   scheduled="" ;;
        "Tomorrow")  scheduled=$(date -d "+1 day" +%Y-%m-%d) ;;
        "Next week") scheduled=$(date -d "+7 days" +%Y-%m-%d) ;;
        "Custom")
            scheduled=$(rofi -dmenu -p "Scheduled date (YYYY-MM-DD or YYYY-MM-DD HH:MM)" -l 0 $ROFI_THEME)
            if [[ "$scheduled" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]([0-9]{2}:[0-9]{2})$ ]]; then
                scheduled="${BASH_REMATCH[1]}T${BASH_REMATCH[2]}"
            fi
            ;;
    esac
 
    # If no scheduled date chosen, default to today (creation date)
    [[ -z "$scheduled" ]] && scheduled=$(date +%Y-%m-%d)
 
    local due_choice
    due_choice=$(printf 'No due date\nTomorrow\nNext week\nCustom' | rofi -dmenu -p "Due date" $ROFI_THEME) || return
 
    local due=""
    case "$due_choice" in
        "No due date") due="" ;;
        "Tomorrow")    due=$(date -d "+1 day" +%Y-%m-%d) ;;
        "Next week")   due=$(date -d "+7 days" +%Y-%m-%d) ;;
        "Custom")
            due=$(rofi -dmenu -p "Due date (YYYY-MM-DD or YYYY-MM-DD HH:MM)" -l 0 $ROFI_THEME)
            if [[ "$due" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]([0-9]{2}:[0-9]{2})$ ]]; then
                due="${BASH_REMATCH[1]}T${BASH_REMATCH[2]}"
            fi
            ;;
    esac


    time_est=$(rofi -dmenu -p "Estimated time in minutes (blank to skip)" -l 0 $ROFI_THEME)
    
    local parent_choice
    local task_list
    task_list=$(for i in "${!TITLES[@]}"; do
        [[ "${STATUSES[$i]}" == "done" ]] && continue
        echo "${TITLES[$i]}"
    done | sort)

    parent_choice=$(printf 'None\n%s' "$task_list" | rofi -dmenu -p "Parent task (optional)" $ROFI_THEME)

    local parent=""
    [[ -n "$parent_choice" && "$parent_choice" != "None" ]] && parent="$parent_choice"

    local filename="$OBSI_TASK_DIR/Tasks/$(echo "$title").md"
    local now
    now=$(date -Iseconds)

    {
        echo "---"
        echo "title: $title"
        echo "status: open"
        echo "priority: $priority"
        echo "scheduled: $scheduled"
        [[ -n "$due" ]] && echo "due: $due"
        [[ -n "$time_est" ]] && echo "timeEstimate: $time_est"
        [[ -n "$parent" ]] && echo "projects:" && echo "  - \"[[$parent]]\""
        echo "tags:"
        echo "  - task"
        echo "dateCreated: $now"
        echo "dateModified: $now"
        echo "---"
    } > "$filename"

    notify-send "Task created" "$title"
}

main() {
    load_tasks
    build_children_map

    for i in "${!TITLES[@]}"; do
        count_children_into "${TITLES[$i]}" "$i"
    done

    local menu chosen
    menu=$(build_menu)

    chosen=$(echo "$menu" | \
        sed 's/||IDX:[0-9]*//' | \
        rofi -dmenu -p "Tasks" -i \
            -markup-rows \
            -kb-remove-char-forward "" \
            -kb-move-char-back "Control+Shift+y" \
            -kb-move-char-forward "Control+Shift+t" \
            -kb-custom-1 "Delete"\
            -kb-custom-2 "Left" \
            -kb-custom-3 "Right" \
            $ROFI_THEME)

    local rofi_exit=$?
    [[ -z "$chosen" && $rofi_exit -eq 1 ]] && exit 0


    if [[ "$chosen" == "$new_task_str" ]]; then
        create_task_form
        exit 0
    fi

    # Recover the index from the original (un-stripped) menu line
    local idx
    idx=$(echo "$menu" | grep -F "${chosen}" | grep -oP '(?<=IDX:)\d+' | head -1)

    [[ -z "$idx" ]] && exit 0

    # DEL key
    if [[ $rofi_exit -eq 10 ]]; then
        if [[ ${HAS_CHILD[$idx]} -gt 0 ]]; then
            notify-send "Cannot Delete" "'${TITLES[$idx]}' has open child(ren): Complete or Delete First" 
        else
            local filepath="$OBSI_TASK_DIR/Tasks/${TITLES[$idx]}.md"
            rm "$filepath"
            notify-send "Task deleted" "${TITLES[$idx]}"
        fi

        bash ~/dotfiles/sway/scripts/obsidian-task.sh
        exit 0
    fi

    # Arrow keys
    if [[ $rofi_exit -eq 12 ]]; then
        if [[ ${STATUSES[$idx]} == "open" ]]; then
            obsidian-cli frontmatter "${TITLES[$idx]}.md" -e --key status --value "in-progress"
            bash ~/dotfiles/sway/scripts/obsidian-task.sh
            exit 0
        elif [[ ${STATUSES[$idx]} == "in-progress"  && ${HAS_CHILD[$idx]} -eq 0 ]]; then
            obsidian-cli frontmatter "${TITLES[$idx]}.md" -e --key status --value "done"
            bash ~/dotfiles/sway/scripts/obsidian-task.sh
            exit 0
        fi
    fi

    if [[ $rofi_exit -eq 11 ]]; then
        if [[ ${STATUSES[$idx]} == "in-progress" ]]; then
            obsidian-cli frontmatter "${TITLES[$idx]}.md" -e --key status --value "open"
            bash ~/dotfiles/sway/scripts/obsidian-task.sh
            exit 0
        elif [[ ${STATUSES[$idx]} == "done" ]]; then
            obsidian-cli frontmatter "${TITLES[$idx]}.md" -e --key status --value "in-progress"
            bash ~/dotfiles/sway/scripts/obsidian-task.sh
            exit 0
        fi
    fi
}

[[ "${BASH_SOURCE[0]}" == "$0" ]] && main