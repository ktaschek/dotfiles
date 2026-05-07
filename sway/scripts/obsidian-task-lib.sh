# ─────────────────────────────────────────────
# obsidian-task-lib.sh
# Library of overlapping functions between scripts.
# ─────────────────────────────────────────────


OBSI_TASK_DIR="$HOME/Documents/Obsidian/TODO"

declare -a TITLES STATUSES PRIORITIES SCHEDULED TIME_ESTIMATES COMPLETED_DATES PROJECTS BLOCKED_BY HAS_CHILD
declare -a CONTEXTS
declare -a TAGS
declare -A CHILDREN_OF

# Parse tasks properties into the lists
parse_task() {
    local input="$1"
    local index=${#TITLES[@]} 

    # Defaults

    TITLES[$index]=""
    STATUSES[$index]=""
    PRIORITIES[$index]=""
    SCHEDULED[$index]=""
    TIME_ESTIMATES[$index]=""
    COMPLETED_DATES[$index]=""
    PROJECTS[$index]=""
    BLOCKED_BY[$index]=""
    CONTEXTS[$index]=""
    TAGS[$index]=""
    HAS_CHILD[$index]=0

    local in_tags=0
    local in_contexts=0
    local in_projects=0

    while IFS= read -r line; do
        line="${line%$'\r'}"
        [[ "$line" == "---" ]] && continue  

        if [[ "$line" =~ ^[[:space:]]+-[[:space:]]+(.*) ]]; then
            local val="${BASH_REMATCH[1]}"
            if [[ $in_tags -eq 1 ]]; then
                TAGS[$index]+="${TAGS[$index]:+|}$val"
            elif [[ $in_contexts -eq 1 ]]; then
                CONTEXTS[$index]+="${CONTEXTS[$index]:+|}$val"
            elif [[ $in_projects -eq 1 ]]; then
                val="${val//\[\[/}"; val="${val//\]\]/}"
                val="${val//\"/}"; val="${val//\'/}"   # add single quote strip
                PROJECTS[$index]="$val"
            fi
            continue
        fi

        in_tags=0; in_contexts=0; in_projects=0

        # key: value
        if [[ "$line" =~ ^([a-zA-Z]+):[[:space:]]*(.*) ]]; then
            local key="${BASH_REMATCH[1]}"
            local val="${BASH_REMATCH[2]}"

            val="${val#\"}"; val="${val%\"}"
            val="${val#\'}"; val="${val%\'}"
            case "$key" in
                title)         TITLES[$index]="$val" ;;
                status)        STATUSES[$index]="$val" ;;
                priority)      PRIORITIES[$index]="$val" ;;
                scheduled)     SCHEDULED[$index]="$val" ;;
                timeEstimate)  TIME_ESTIMATES[$index]="$val" ;;
                completedDate) COMPLETED_DATES[$index]="$val" ;;
                blocked_by)    BLOCKED_BY[$index]=true;;
                tags)          in_tags=1 ;;
                projects)      in_projects=1 ;;
                context)       in_contexts=1;;
            esac
        fi
    
    done <<< "$input"
}

# Search through tasks in task directory and iterate through each, parsing and loading into the arrays
load_tasks() {
    mapfile -t TASKS_MD < <(
    find "$OBSI_TASK_DIR/Tasks" -maxdepth 1 \
        | grep -ie "\.md$"\
        | sort  
)

    if [[ ${#TASKS_MD[@]} -eq 0 ]]; then
        notify-send "Obsidian Task Search" "No tasks found in $OBSI_TASK_DIR/Tasks"
    fi

    IDX=0

    for task in "${TASKS_MD[@]}"; do
        parse_task "$(cat "$task")"
    done
}

get_sorted_indices() {
    local -a pairs=()
    for i in "${!TITLES[@]}"; do 
        [[ "${STATUSES[$i]}" == "done" ]] && continue
        local date="${SCHEDULED[$i]:-9999-99-99}"
        date="${date%%T*}"
        pairs+=("$date $i")
    done

    printf '%s\n' "${pairs[@]}" | sort | awk '{print $2}'
}

is_overdue() {
    local raw="$1"
    [[ -z "$raw" ]] && return 1
    local date="${raw%%T*}"
    [[ "$date" < "$(date +%Y-%m-%d)" ]]
}


build_children_map() {
    for j in "${!PROJECTS[@]}"; do
        local parent="${PROJECTS[$j]}"
        [[ -z "$parent" ]] && continue
        CHILDREN_OF[$parent]+="${CHILDREN_OF[$parent]:+|}$j"
    done
}

count_children() {
    local parent_title="$1"
    local count=0
    local children="${CHILDREN_OF[$parent_title]}"
    [[ -z "$children" ]] && echo 0 && return

    IFS='|' read -ra child_ids <<< "$children"
    for j in "${child_ids[@]}"; do
        [[ "${STATUSES[$j]}" == "done" ]] && continue
        (( count++ ))
        (( count += $(count_children "${TITLES[$j]}") ))
    done
}

count_children_into() {
    local parent_title="$1"
    local target_idx="$2"
    local children="${CHILDREN_OF[$parent_title]}"
    [[ -z "$children" ]] && return

    IFS='|' read -ra child_ids <<< "$children"
    for j in "${child_ids[@]}"; do
        [[ "${STATUSES[$j]}" == "done" ]] && continue
        (( HAS_CHILD[$target_idx]++ ))
        count_children_into "${TITLES[$j]}" "$target_idx"
    done
}

dump_json() {
    echo "["
    local first=1
    for i in "${!TITLES[@]}"; do
        [[ "${STATUSES[$i]}" == "done" ]] && continue
        [[ $first -eq 0 ]] && echo ","
        first=0
        printf '{"idx":%d,"title":%s,"status":%s,"priority":%s,"scheduled":%s,"timeEstimate":%s,"project":%s,"hasChild":%d}' \
            "$i" \
            "$(echo "${TITLES[$i]}"    | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')" \
            "$(echo "${STATUSES[$i]}"  | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')" \
            "$(echo "${PRIORITIES[$i]}"| python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')" \
            "$(echo "${SCHEDULED[$i]}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')" \
            "$(echo "${TIME_ESTIMATES[$i]}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')" \
            "$(echo "${PROJECTS[$i]}"  | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))')" \
            "${HAS_CHILD[$i]}"
    done
    echo "]"
}

dump_wrapper() {
    load_tasks
    build_children_map
    for i in "${!TITLES[@]}"; do
        count_children_into "${TITLES[$i]}" "$i"
    done
    dump_json
}