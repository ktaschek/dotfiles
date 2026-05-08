#!/usr/bin/env python3
# ─────────────────────────────────────────────
# obsidian-task-widget.py
# Textual TUI task widget
# Inherits terminal theme (kitty/wayland compatible)
# ─────────────────────────────────────────────

import subprocess, json, os
from datetime import date, datetime, timedelta
from textual.app        import App, ComposeResult
from textual.widgets    import Footer, DataTable, Label, Input
from textual.binding    import Binding
from textual.containers import Vertical
from textual.screen     import Screen
from textual            import on

DUMP_SCRIPT   = os.path.expanduser("~/dotfiles/sway/scripts/obsidian-task-lib.sh")
TASKS_DIR     = os.path.expanduser("~/Documents/Obsidian/TODO/Tasks")
REFRESH_SECS  = 300
DUE_WINDOW    = timedelta(days=1)

PRIORITY_ICON  = {"high": "▴", "normal": "▸", "low": "▾"}
PRIORITY_COLOR = {"high": "#ed8274", "normal": "#fad07b", "low": "#a6cc70"}
ARROW_COLOR    = "#6dcbfa"
ARROW_OVERDUE  = "#ed8274"
INPROG_COLOR   = "#6dcbfa"
DONE_COLOR     = "#686868"
OVERDUE_COLOR  = "#ed8274"
ACCENT_COLOR   = "#ffcc66"

# ── Data ──────────────────────────────────────────────────────────────────────

def load_tasks() -> list[dict]:
    result = subprocess.run(
        ["bash", "-c", "source %s; dump_wrapper" % DUMP_SCRIPT ],
        capture_output=True,
        text=True
    )
    if not result.stdout.strip():
        return []
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return []

def should_show(task: dict, today: date, cutoff: date, shown_titles: set) -> bool:
    status    = task["status"]
    due = (task["due"] or "")[:10]
    scheduled = (task["scheduled"] or "")[:10]
    sched_date = date.fromisoformat(scheduled) if scheduled else None
    due = date.fromisoformat(due) if due else None

    if status == "done":
        return bool(due and due > today)

    if due and due < today:
        return True

    # always show overdue unfinished tasks
    if sched_date and sched_date < today:
        return True

    # always show in-progress
    if status == "in-progress":
        return True

    # show if due within window
    if sched_date and sched_date <= cutoff:
        return True

    if due and due <= cutoff:
        return True

    # show if parent is shown (child follows parent)
    if task["project"] and task["project"] in shown_titles:
        return True

    return False

def build_rows(tasks: list[dict]) -> list[dict]:
    today  = date.today()
    cutoff = today + DUE_WINDOW

    by_title  = {t["title"]: t for t in tasks}
    children  = [t for t in tasks if t["project"]]
    parents   = [t for t in tasks if not t["project"]]

    def sort_key(t):
        order = {"in-progress": 0, "open": 1, "done": 2}.get(t["status"], 1)
        return (order, t["due"] or "9999-99-99")

    # first pass — determine which titles are visible so children can check
    shown_titles: set[str] = set()
    for t in tasks:
        if should_show(t, today, cutoff, shown_titles):
            shown_titles.add(t["title"])

    parents = [t for t in parents if t["title"] in shown_titles]
    parents.sort(key=sort_key)

    rows: list[dict] = []

    def add_task(task: dict, depth: int):
        scheduled  = (task["scheduled"] or "")[:10]
        sched_date = date.fromisoformat(scheduled) if scheduled else None
        due  = (task["due"] or "")[:10]
        due_date = date.fromisoformat(due) if due else None
        overdue    = bool((sched_date and sched_date < today) or (due_date and due_date < today))
        rows.append({
            "task":      task,
            "depth":     depth,
            "overdue":   overdue,
            "scheduled": scheduled,
        })
        kids = [
            c for c in children
            if c["project"] == task["title"]
            and c["title"] in shown_titles
        ]
        kids.sort(key=sort_key)
        for kid in kids:
            add_task(kid, depth + 1)

    for p in parents:
        add_task(p, 0)
    return rows

def mark_status(title: str, status: str):
    subprocess.run([
        "obsidian-cli", "frontmatter", f"{title}.md",
        "-e", "--key", "status", "--value", status
    ])

def delete_task_file(title: str):
    path = os.path.join(TASKS_DIR, f"{title}.md")
    if os.path.exists(path):
        os.remove(path)

# ── Search Screen ─────────────────────────────────────────────────────────────

class SearchScreen(Screen):
    CSS = """
    SearchScreen {
        align: center top;
        background: #21273380;
    }
    #search-input {
        width: 60%;
        height: auto;
        margin-top: 2;
        border: round #6dcbfa;
        background: #212733;
        color: #d9d7ce;
        padding: 0 1;
    }
    Input:focus {
        border: round #ffcc66;
    }
    """

    def __init__(self, rows):
        super().__init__()
        self.all_rows = rows
        self.result_idx = None

    def compose(self) -> ComposeResult:
        yield Input(placeholder="Fuzzy search tasks...", id="search-input")

    def on_mount(self):
        self.query_one(Input).focus()

    @on(Input.Changed)
    def on_search_changed(self, event: Input.Changed):
        pass 

    def on_key(self, event):
        if event.key == "escape":
            self.dismiss(None)
        elif event.key == "enter":
            query = self.query_one(Input).value.strip().lower()
            if not query:
                self.dismiss(None)
                return
            # fuzzy
            for i, row in enumerate(self.all_rows):
                title = row["task"]["title"].lower()
                it = iter(title)
                if all(c in it for c in query):
                    self.dismiss(i)
                    return
            self.dismiss(None)

# ── Main App ──────────────────────────────────────────────────────────────────

class TaskWidget(App):

    CSS = """
    App {
        background: transparent;
    }
    Screen {
        background: transparent;
        layers: base overlay;
    }

    DataTable {
        height: 1fr;
        background: transparent;
        border: none;
        scrollbar-background: transparent;
        scrollbar-color: #343f4c;
        scrollbar-color-hover: #6dcbfa;
    }

    DataTable > .datatable--header {
        height: 1;
        text-style: bold;
        background: #30394a;
        color: #6dcbfa;
    }

    DataTable > .datatable--cursor {
        background: #343f4c;
        color: #d9d7ce;
        text-style: bold;
    }

    DataTable > .datatable--odd-row {
        # background: #202b36;
        background: transparent;
        color: #d9d7ce;
    }

    DataTable > .datatable--even-row {
        background: transparent;
        color: #d9d7ce;
    }

    DataTable > .datatable--highlight {
        background: #343f4c;
        color: #d9d7ce;
    }

    #status-bar {
        height: 1;
        background: #30394a;
        color: #686868;
        padding: 0 1;
        dock: bottom;
    }

    Footer {
        background: #30394a;
        color: #686868;
    }

    Footer > .footer--key {
        background: #343f4c;
        color: #6dcbfa;
        text-style: bold;
    }

    Footer > .footer--description {
        color: #686868;
    }
    """

    BINDINGS = [
        Binding("q",          "quit",         "Quit"),
        Binding("r",          "refresh",      "Refresh"),
        Binding("/",          "search",       "Search"),
        Binding("right",      "advance",      "Advance status"),
        Binding("left",       "decrease",     "Decrease status"),
        Binding("delete",     "delete_task",  "Delete"),
        Binding("up,k",       "cursor_up",    "Up",    show=False),
        Binding("down,j",     "cursor_down",  "Down",  show=False),
    ]

    def __init__(self):
        super().__init__()
        self.rows: list[dict] = []

    def compose(self) -> ComposeResult:
        yield DataTable(cursor_type="row", zebra_stripes=True)
        yield Label("", id="status-bar")
        yield Footer()

    def on_mount(self):
        table = self.query_one(DataTable)
        table.add_columns("  ", "Task", "Scheduled", "Due", "Est")
        self._load_and_refresh()
        self.set_interval(REFRESH_SECS, self._load_and_refresh)

    # ── Internal ──────────────────────────────────────────────────────────────

    def _load_and_refresh(self):
        tasks      = load_tasks()
        self.rows  = build_rows(tasks)
        self._repopulate()

    def _repopulate(self):
        table = self.query_one(DataTable)
        pos   = table.cursor_row
        table.clear()

        for row in self.rows:
            task     = row["task"]
            depth    = row["depth"]
            overdue  = row["overdue"]
            in_prog  = task["status"] == "in-progress"
            done     = task["status"] == "done"
            priority = task["priority"]

            indent  = "    " * depth
            arrow   = "↳ " if depth else ""
            s_icon  = "⟳ " if in_prog else "✓ " if done else ""
            p_icon  = PRIORITY_ICON.get(priority, "○")
            p_color = PRIORITY_COLOR.get(priority, "#d9d7ce")

            title_text = f"{indent}{arrow}{s_icon}{task['title']}"
            sched_text = row["scheduled"] or "no date"
            due_text = task["due"] or "no date"
            est_text   = f"~{task['timeEstimate']}m" if task["timeEstimate"] else ""

            # color logic
            if done and overdue:
                p_icon_r     = f"[{DONE_COLOR} dim]{p_icon}[/]"
                title_render = f"[{DONE_COLOR} dim strike]{title_text}[/]"
                sched_render = f"[{DONE_COLOR} dim]{sched_text}[/]"
            elif overdue:
                p_icon_r     = f"[bold {OVERDUE_COLOR}]{p_icon}[/]"
                title_render = f"[bold {OVERDUE_COLOR}]{title_text}[/]"
                sched_render = f"[bold {OVERDUE_COLOR}]{sched_text}[/]"
                if depth:
                    title_render = f"[{OVERDUE_COLOR}]{indent}↳ [/][bold {OVERDUE_COLOR}]{s_icon}{task['title']}[/]"
            elif in_prog:
                p_icon_r     = f"[{p_color}]{p_icon}[/]"
                title_render = f"[bold {INPROG_COLOR}]{title_text}[/]"
                sched_render = f"[{INPROG_COLOR}]{sched_text}[/]"
            elif done:
                p_icon_r     = f"[{DONE_COLOR}]{p_icon}[/]"
                title_render = f"[{DONE_COLOR} strike]{title_text}[/]"
                sched_render = f"[{DONE_COLOR}]{sched_text}[/]"
            else:
                p_icon_r     = f"[{p_color}]{p_icon}[/]"
                title_render = title_text
                if depth:
                    title_render = f"{indent}[{ARROW_COLOR}]↳ [/]{s_icon}{task['title']}"
                sched_render = sched_text

            sched_render = sched_text
            due_render = due_text
            table.add_row(
                p_icon_r,
                title_render,
                sched_render,
                due_render,
                f"[dim]{est_text}[/]",
            )

        # restore cursor position
        if self.rows:
            table.move_cursor(row=min(pos, len(self.rows) - 1))

    def _set_status(self, msg: str):
        self.query_one("#status-bar", Label).update(msg)

    def _current_row(self) -> dict | None:
        table = self.query_one(DataTable)
        if not self.rows or table.cursor_row >= len(self.rows):
            return None
        return self.rows[table.cursor_row]

    # ── Actions ───────────────────────────────────────────────────────────────

    def action_refresh(self):
        self._load_and_refresh()
        self._set_status("Refreshed.")

    def action_cursor_up(self):
        self.query_one(DataTable).action_cursor_up()

    def action_cursor_down(self):
        self.query_one(DataTable).action_cursor_down()

    def action_search(self):
        def handle(idx):
            if idx is not None:
                self.query_one(DataTable).move_cursor(row=idx)
        self.push_screen(SearchScreen(self.rows), handle)

    def action_advance(self):
        row = self._current_row()
        if not row:
            return
        task   = row["task"]
        status = task["status"]

        if status == "open":
            mark_status(task["title"], "in-progress")
            self._set_status(f"Started: {task['title']}")
        elif status == "in-progress":
            if task["hasChild"] > 0:
                self._set_status(f"Finish children first ({task['hasChild']} remaining).")
                return
            mark_status(task["title"], "done")
            self._set_status(f"Done: {task['title']}")
        elif status == "done":
            mark_status(task["title"], "open")
            self._set_status(f"Reopened: {task['title']}")

        self._load_and_refresh()

    def action_decrease(self):
        row = self._current_row()
        if not row:
            return
        task   = row["task"]
        status = task["status"]
        
        if status == "in-progress":
            mark_status(task["title"], "open")
            self._set_status(f"Stopped: {task['title']}")
        elif status == "done":
            mark_status(task["title"], "in-progress")
            self._set_status(f"Started: {task['title']}")

        self._load_and_refresh()

    def action_delete_task(self):
        row = self._current_row()
        if not row:
            return
        task = row["task"]
        if task["hasChild"] > 0:
            self._set_status(f"Cannot delete '{task['title']}' — has open children.")
            return
        delete_task_file(task["title"])
        self._load_and_refresh()
        self._set_status(f"Deleted: {task['title']}")


if __name__ == "__main__":
    TaskWidget().run()