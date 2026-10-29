#!/usr/bin/env python3
"""Made-up Claude Code sessions in a fake home folder, for testing the panel and drawing it.

Real sessions rarely wait on anyone while a test runs, and their requests must not be answered
by a test. These can be: nothing here touches your own ~/.claude.

  testing/demo.py start <home>
      Writes seven sessions under <home>/.claude, then keeps the working ones moving for 20
      minutes. testing/pictures.sh runs it in the background and draws the panel over them.
        Refactor checkout flow   working, with three working sub-agents and one finished
        Fix flaky login test     asks a question with three options
        Migrate users table      has a plan waiting for approval
        Deploy preview build     waits for permission to run a command
        Bump dependencies        quiet for twelve minutes
        Update README badges     finished two minutes ago, a dev server and a watch on CI left running
        Fix broken doc links     finished two minutes ago, folded into the idle line

  testing/demo.py ask <home> permission|question
      Sends what the plugin's hook would send for "Deploy preview build" or "Fix flaky login
      test" to the test copy's socket, waits for the panel, and prints its answer. The socket
      is only there once "Answer from the notch" is on in the test copy's settings.
"""
import json
import os
import signal
import stat
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone

ROOT = "/Users/Shared/pt"
PID_FILE = ROOT + "/demo.pid"
LIFETIME = 20 * 60

PUSH = {"command": "git push origin preview", "description": "Push the preview branch"}
CART = {"command": "npm run test:cart -- --coverage", "description": "Check cart coverage"}
QUESTION = {"questions": [{
    "question": "The login test fails only on CI. Which fix do you want?",
    "header": "Fix",
    "multiSelect": False,
    "options": [
        {"label": "Retry the request", "description": "Up to three times"},
        {"label": "Mock the clock", "description": "No real waiting in the test"},
        {"label": "Skip on CI", "description": "Keep it for local runs"},
    ],
}]}

# session id -> (project folder, cwd, branch, model, title)
SESSIONS = {
    "checkout": ("-Users-demo-shop-web", "/Users/demo/shop-web", "checkout-refactor", "claude-opus-5-5", "Refactor checkout flow"),
    "login": ("-Users-demo-api", "/Users/demo/api", "main", "claude-sonnet-5-5", "Fix flaky login test"),
    "migrate": ("-Users-demo-api", "/Users/demo/api", "users-migration", "claude-opus-5-5", "Migrate users table"),
    "deploy": ("-Users-demo-shop-web", "/Users/demo/shop-web", "preview", "claude-sonnet-5-5", "Deploy preview build"),
    "deps": ("-Users-demo-docs-site", "/Users/demo/docs-site", "main", "claude-haiku-5-5", "Bump dependencies"),
    "readme": ("-Users-demo-docs-site", "/Users/demo/docs-site", "main", "claude-haiku-5-5", "Update README badges"),
    "links": ("-Users-demo-docs-site", "/Users/demo/docs-site", "main", "claude-haiku-5-5", "Fix broken doc links"),
}
IDS = {name: f"00000000-0000-4000-8000-{index:012d}" for index, name in enumerate(SESSIONS, 1)}

# What Claude Code's own record says of each session. "deps" says busy while its transcript has
# been silent for twelve minutes: the quiet case that stays listed.
RECORDS = [("checkout", "busy"), ("login", "waiting"), ("migrate", "waiting"), ("deploy", "waiting"), ("deps", "busy"),
           ("readme", "idle")]

STEPS = [
    ("Read", {"file_path": "/Users/demo/shop-web/src/cart/total.ts"}),
    ("Grep", {"pattern": "chargeCustomer\\("}),
    ("Edit", {"file_path": "/Users/demo/shop-web/src/checkout/payment.ts"}),
    ("Bash", {"command": "npm test -- cart", "description": "Run the cart tests"}),
    ("Read", {"file_path": "/Users/demo/shop-web/src/checkout/summary.tsx"}),
    ("Edit", {"file_path": "/Users/demo/shop-web/src/cart/total.test.ts"}),
]


def fake_home(path):
    """The real path of a fake home, or an exit when it is not a safe place to write.

    Every account on this Mac can write to /Users/Shared, so ROOT has to be this user's own
    folder, closed to the others, before anything is written under it or read back from it.
    And a home anywhere else could be a real one: these sessions must never land
    in a real ~/.claude.
    """
    os.makedirs(ROOT, exist_ok=True)
    info = os.lstat(ROOT)
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        sys.exit(f"{ROOT} is a link or belongs to someone else. Remove it and run this again.")
    os.chmod(ROOT, 0o700)
    home = os.path.realpath(path)
    if not home.startswith(ROOT + "/"):
        sys.exit(f"The fake home must be a folder under {ROOT}, not {home}.")
    return home


def stamp(ago=0.0):
    moment = datetime.now(timezone.utc) - timedelta(seconds=ago)
    return moment.strftime("%Y-%m-%dT%H:%M:%S.") + f"{moment.microsecond // 1000:03d}Z"


def transcript(home, name):
    return os.path.join(home, ".claude/projects", SESSIONS[name][0], IDS[name] + ".jsonl")


def append(path, *lines):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "a") as file:
        for line in lines:
            file.write(json.dumps(line) + "\n")


# Real sub-agent prompts run long: these fill the Asked box past its height cap.
MAP_PROMPT = """Find every place in shop-web that creates, confirms or refunds a payment. Start from src/checkout/index.tsx and follow the imports; the Stripe calls are wrapped in src/payments/, but a few pages still call the SDK directly.

For each call site, write down the file, the function, and whether it passes the cart total in cents or in dollars. The last bug came from one caller sending dollars to a function that expects cents.

Do not change any code. Report the list as a table, and mark the callers that skip src/payments/ so we can move them over later."""

PLAN_PROMPT = """Read src/cart/tax.ts and the tests next to it. We round each line item's tax before adding them up, and the totals on the receipt drift by a cent or two on carts with many cheap items.

Decide where the rounding should happen. Compare rounding per line, rounding once at the subtotal, and rounding once at the grand total. For each, say what a cart of twelve items at 1.99 with 7.25 percent tax would come to, and which one matches what the payment provider charges.

Do not change any code. Answer with your pick first, then the reasons, then the files that would need to change, one per line."""

PLAN_ANSWER = """Round once at the total, not per line.
Per-line rounding adds up to a cent or two on a cart of twelve cheap items.
The payment provider rounds the grand total once, so that is the number to match.
Files to change: src/cart/tax.ts and src/cart/tax.test.ts.
Receipt totals in src/receipt/format.ts need no change."""


def prompt(name, text, ago):
    _, cwd, branch, _, _ = SESSIONS[name]
    return {"type": "user", "timestamp": stamp(ago), "cwd": cwd, "gitBranch": branch, "entrypoint": "cli",
            "sessionId": IDS[name], "message": {"role": "user", "content": text}}


def call(name, tool, tool_input, call_id, ago=0.0, model=None, tokens=42_000):
    _, cwd, branch, own, _ = SESSIONS[name]
    return {"type": "assistant", "timestamp": stamp(ago), "cwd": cwd, "gitBranch": branch, "sessionId": IDS[name],
            "message": {"role": "assistant", "model": model or own, "stop_reason": "tool_use",
                        "usage": {"input_tokens": 1200, "cache_read_input_tokens": tokens, "output_tokens": 380},
                        "content": [{"type": "tool_use", "id": call_id, "name": tool, "input": tool_input}]}}


def result(call_id, text="ok", ago=0.0):
    return {"type": "user", "timestamp": stamp(ago),
            "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": call_id, "content": text}]}}


def say(name, text, ago=0.0, model=None):
    return {"type": "assistant", "timestamp": stamp(ago), "sessionId": IDS[name],
            "message": {"role": "assistant", "model": model or SESSIONS[name][3], "stop_reason": "end_turn",
                        "usage": {"input_tokens": 900, "cache_read_input_tokens": 30_000, "output_tokens": 210},
                        "content": [{"type": "text", "text": text}]}}


def record(home, pid, name, status):
    folder = os.path.join(home, ".claude/sessions")
    os.makedirs(folder, exist_ok=True)
    now = int(time.time() * 1000)
    with open(os.path.join(folder, f"{pid}.json"), "w") as file:
        json.dump({"pid": pid, "sessionId": IDS[name], "startedAt": now, "status": status, "statusUpdatedAt": now}, file)


def start(home):
    for name, (_, _, _, _, title) in SESSIONS.items():
        append(transcript(home, name), {"type": "ai-title", "aiTitle": title})

    # Its task list, as TaskCreate and TaskUpdate write it: two done, one under way, two to do.
    to_do = ["Map the payment call sites", "Plan the tax rounding fix", "Split checkout into step pages",
            "Write cart total tests", "Run the cart tests"]
    tasks = []
    for n, subject in enumerate(to_do, 1):
        tasks += [call("checkout", "TaskCreate", {"subject": subject, "description": subject}, f"t{n}", 189),
                  dict(result(f"t{n}", ago=189), toolUseResult={"task": {"id": str(n), "subject": subject}})]
    for n, (task, status) in enumerate([("1", "completed"), ("2", "completed"), ("3", "in_progress")]):
        tasks += [call("checkout", "TaskUpdate", {"taskId": task, "status": status}, f"u{n}", 25), result(f"u{n}", ago=25)]
    append(transcript(home, "checkout"),
           prompt("checkout", "Split the checkout page into steps and keep the totals right.", 190), *tasks[:10],
           call("checkout", "Agent", {"description": "Map payment call sites"}, "c1", 180), result("c1", ago=179), *tasks[10:],
           call("checkout", "Read", {"file_path": "/Users/demo/shop-web/src/checkout/index.tsx"}, "c2", 20))
    subagents = os.path.join(os.path.dirname(transcript(home, "checkout")), IDS["checkout"], "subagents")
    moving = {transcript(home, "checkout"): ("claude-opus-5-5", "c2")}
    for agent, kind, task, model in [("map", "Explore", "Map payment call sites", "claude-haiku-5-5"),
                                     ("tests", "general-purpose", "Write cart total tests", "claude-sonnet-5-5")]:
        path = os.path.join(subagents, f"agent-{agent}.jsonl")
        append(path, prompt("checkout", MAP_PROMPT if agent == "map" else task, 170), call("checkout", "Grep", {"pattern": "PaymentIntent"}, f"{agent}0", 15, model))
        with open(path[:-len(".jsonl")] + ".meta.json", "w") as file:
            json.dump({"agentType": kind, "description": task}, file)
        moving[path] = (model, f"{agent}0")
    plan = os.path.join(subagents, "agent-plan.jsonl")
    append(plan, prompt("checkout", PLAN_PROMPT, 175),
           call("checkout", "Read", {"file_path": "/Users/demo/shop-web/src/cart/tax.ts"}, "p1", 160), result("p1", ago=158),
           say("checkout", PLAN_ANSWER, 150))
    with open(plan[:-len(".jsonl")] + ".meta.json", "w") as file:
        json.dump({"agentType": "Plan", "description": "Plan the tax rounding fix"}, file)
    # Stands still on a command no other agent runs, so a request for it matches this row alone.
    verify = os.path.join(subagents, "agent-verify.jsonl")
    append(verify, prompt("checkout", "Run the cart tests", 165), call("checkout", "Bash", CART, "v0", 30, "claude-sonnet-5-5"))
    with open(verify[:-len(".jsonl")] + ".meta.json", "w") as file:
        json.dump({"agentType": "general-purpose", "description": "Run the cart tests"}, file)

    append(transcript(home, "login"), prompt("login", "The login test is flaky. Fix it.", 240),
           call("login", "Bash", {"command": "npm test -- login", "description": "Run the login test"}, "l1", 200), result("l1", ago=150),
           call("login", "AskUserQuestion", QUESTION, "l2", 95))
    append(transcript(home, "migrate"), prompt("migrate", "Plan the users table migration.", 400),
           call("migrate", "Read", {"file_path": "/Users/demo/api/db/schema.sql"}, "m1", 380), result("m1", ago=378),
           call("migrate", "ExitPlanMode", {"plan": "1. Add the column. 2. Backfill. 3. Drop the old one."}, "m2", 310))
    append(transcript(home, "deploy"), prompt("deploy", "Push the preview build.", 130),
           call("deploy", "Bash", {"command": "npm run build", "description": "Build the storefront"}, "d1", 120), result("d1", ago=50),
           call("deploy", "Bash", PUSH, "d2", 40))
    append(transcript(home, "deps"), prompt("deps", "Bump the dependencies.", 800),
           call("deps", "Bash", {"command": "npm install", "description": "Install the new versions"}, "b1", 720))
    append(transcript(home, "readme"), prompt("readme", "Fix the badges in the README.", 200),
           call("readme", "Edit", {"file_path": "/Users/demo/docs-site/README.md"}, "r1", 150), result("r1", ago=148))
    # Idle with no jobs and no record: the one session that folds into the idle line.
    append(transcript(home, "links"), prompt("links", "Fix the broken links in the docs.", 200),
           call("links", "Edit", {"file_path": "/Users/demo/docs-site/guide/setup.md"}, "k1", 150), result("k1", ago=148),
           say("links", "All links resolve now.", 120))

    # A record counts only while the process that wrote it lives, so each gets one of its own.
    sleepers = {}
    for name, status in RECORDS:
        sleepers[name] = subprocess.Popen(["sleep", str(LIFETIME + 60)])
    time.sleep(0.2)
    for name, status in RECORDS:
        record(home, sleepers[name].pid, name, status)
    with open(os.path.join(home, "demo.json"), "w") as file:
        json.dump({name: sleeper.pid for name, sleeper in sleepers.items()}, file)
    # Its jobs, shaped like the tests' JobLines. They start after its record: a job older than the
    # process that holds its session died with an earlier one. A millisecond later at least: in
    # the same one, the two dates read back in either order. Its turn still ended two minutes
    # ago, the last line's time, or the card would read as at work for the ten seconds done waits.
    # Should both jobs land in one millisecond, their ids keep the shell first.
    time.sleep(0.01)
    append(transcript(home, "readme"),
           call("readme", "Bash", {"command": "npm run dev", "description": "Serve the docs site", "run_in_background": True}, "r2", 125),
           dict(result("r2"), toolUseResult={"stdout": "", "stderr": "", "interrupted": False, "isImage": False,
                                             "noOutputExpected": False, "backgroundTaskId": "bdocs1srv"}),
           call("readme", "Monitor", {"description": "CI run for the badge fix", "timeout_ms": 900_000, "persistent": True,
                                      "command": "gh run watch"}, "r3", 123),
           dict(result("r3"), toolUseResult={"taskId": "bwatch2ci", "timeoutMs": 900_000, "persistent": True}),
           say("readme", "Badges point at the new CI now.", 120))

    def stop(*_):
        for sleeper in sleepers.values():
            sleeper.terminate()
        sys.exit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    os.makedirs(os.path.dirname(PID_FILE), exist_ok=True)
    with open(PID_FILE, "w") as file:
        file.write(str(os.getpid()))
    print(f"Demo sessions written to {home}.", flush=True)

    turn, until = 0, time.time() + LIFETIME
    while time.time() < until:
        time.sleep(9)
        turn += 1
        for index, (path, (model, open_id)) in enumerate(list(moving.items())):
            tool, tool_input = STEPS[(turn + index * 2) % len(STEPS)]
            next_id = f"h{turn}-{index}"
            append(path, result(open_id), call("checkout", tool, tool_input, next_id, model=model, tokens=42_000 + turn * 1800))
            moving[path] = (model, next_id)
    stop()


def ask(home, what):
    name, tool, tool_input, call_id = {"permission": ("deploy", "Bash", PUSH, "d2"), "question": ("login", "AskUserQuestion", QUESTION, "l2")}[what]
    socket = os.path.join(home, "Library/Application Support/AgentValley/answers.sock")
    if not os.path.exists(socket):
        sys.exit('No socket: turn on "Answer from the notch" in the test copy\'s settings first.')
    body = json.dumps({"hook_event_name": "PermissionRequest", "session_id": IDS[name], "transcript_path": transcript(home, name),
                       "cwd": SESSIONS[name][1], "tool_name": tool, "tool_input": tool_input})
    print(f"Request sent for \"{SESSIONS[name][4]}\". Waiting for the panel (up to 5 minutes)...", flush=True)
    answer = subprocess.run(["/usr/bin/curl", "-q", "--silent", "--fail", "--max-time", "300", "--unix-socket", socket,
                             "--header", "Content-Type: application/json", "--data-binary", body, "http://notch/permission-request"],
                            capture_output=True, text=True).stdout.strip()
    if not answer:
        print("The panel gave no answer: Claude Code would go on asking in the terminal.")
        return
    print("The panel answered:", answer)
    # What Claude Code writes next: the call gets its result, the turn ends, the session goes idle.
    append(transcript(home, name), result(call_id, "done"), say(name, "Done."))
    with open(os.path.join(home, "demo.json")) as file:
        record(home, int(json.load(file)[name]), name, "idle")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "start":
        start(fake_home(sys.argv[2]))
    elif len(sys.argv) == 4 and sys.argv[1] == "ask" and sys.argv[3] in ("permission", "question"):
        ask(fake_home(sys.argv[2]), sys.argv[3])
    else:
        sys.exit(__doc__)
