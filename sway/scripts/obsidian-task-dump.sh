# obsidian-task-dump.sh
source ~/dotfiles/sway/scripts/obsidian-task-lib.sh
load_tasks
build_children_map
for i in "${!TITLES[@]}"; do
    count_children_into "${TITLES[$i]}" "$i"
done
dump_json