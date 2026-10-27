"""Get updates, with a yes from the mailbox before anyone is on the list.

1. POST `email` (a form, application/x-www-form-urlencoded): we mail a link to that address and add
   nothing yet. The page's script asks for JSON and shows the answer by the box; a form sent without
   scripts gets a small page back. A filled `website` field is a bot: thanked, and dropped.
2. GET the link (?e=&x=&t=): a page with one button. A button, not the link itself, because some mail
   scanners open every link they see.
3. POST the button (e, x, t): the address goes into Resend's contacts.

The link carries its own proof: an HMAC of the address and its expiry, keyed from RESEND_API_KEY, so
nothing waits anywhere between 1 and 3. Needs RESEND_API_KEY (full access) in the Vercel project;
RESEND_SEGMENT_ID, if set, puts each address in that segment too. A Vercel Firewall rule limits each
IP on this path; this file only spaces out the mail to one address.
"""

import hashlib
import hmac
import html
import json
import os
import random
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler
from pathlib import Path

EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
SITE = "https://agentvalley.app"
DAYS = 7
# ponytail: per-instance memory, so a second instance may mail the same inbox again; the Firewall
# rule on this path is the real limit, a shared store if that ever falls short. An address is mailed
# at most once per SPACING, an inbox (all its spellings) at most PER_BOX times.
SENT: dict[str, float] = {}
BOXES: dict[str, list[float]] = {}
SPACING = 600
PER_BOX = 3

# What the mailroom page says in each case: its heading and the line under it. {email} only where the link has
# vouched for the address.
SAID = {
    "ask": ("One more press.", "Press it and <b>{email}</b> goes on the list. We write when a new version is out. Nothing else."),
    "in": ("You're on the list.", "Sunny filed your letter. See you at the next version."),
    "old": ("That link has run out.", "Links last 7 days. Ask again on the page and Sunny brings a fresh one."),
    "failed": ("That one got away from us.", "Try again in a minute."),
    "sent": ("Check your inbox.", "One click there and you're on the list."),
    "full": ("That's all the mail for today.", "We've sent all the mail we can for today. Try again tomorrow."),
}
DMG = "https://github.com/morsechimwai/agent-valley/releases/latest/download/AgentValley.dmg"
try:
    ROOM = (Path(__file__).resolve().parent / "_mailroom.html").read_text()
except OSError:
    # ponytail: without the room the words still show, on a plain page.
    ROOM = '<!doctype html><meta charset="utf-8"><title>Get updates · AgentValley</title><body data-said="{{said}}"><h1>{{title}}</h1><p>{{words}}</p>{{action}}'


def confetti() -> str:
    """Paper squares in the crew's shirt colours, falling once over the room when an address goes on the list."""
    rng = random.Random(7)
    colours = ["#f6a53f", "#4a78c2", "#d9a521", "#e9778f", "#9a62c9", "#2f8f8a", "#fff6e4", "#c22a1c"]
    return "".join(
        f'<i style="--x:{rng.uniform(0, 100):.1f}%;--s:{rng.choice((8, 10, 12))}px;--c:{rng.choice(colours)};'
        f'--t:{rng.uniform(2.2, 3.6):.2f}s;--d:{rng.uniform(.2, 1.4):.2f}s;--r:{rng.choice((-1, 1)) * rng.randint(180, 720)}deg"></i>'
        for _ in range(48)
    )


CONFETTI = confetti()

# The plain words, for mail apps that show no HTML; the HTML is emails/templates/confirm.tsx, rendered by
# `npm run emails` into emails/out with {{link}} and {{days}} left to fill. Neither says the address:
# anyone can type one, with words of their own in it.
MAIL = """Say yes, and we'll write.

Someone, hopefully you, asked for AgentValley news at this address. Open this link and press the button, and we write when a new version is out. Nothing else.

{link}

The link works for {days} days. If it wasn't you, do nothing: we won't write again.

The crew in your notch
https://agentvalley.app
"""
try:
    LETTER = (Path(__file__).resolve().parent.parent / "emails" / "out" / "confirm.html").read_text()
except OSError:
    # ponytail: without the rendered page the mail still goes, in plain words.
    LETTER = ""


def letter(**fill: str) -> str:
    return re.sub(r"\{\{(\w+)\}\}", lambda m: html.escape(fill.get(m[1], m[0])), LETTER)


def resend(path: str, body: dict, method: str = "POST") -> tuple[int, str]:
    request = urllib.request.Request(
        f"https://api.resend.com{path}",
        data=json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {os.environ['RESEND_API_KEY']}",
            "Content-Type": "application/json",
            "User-Agent": "agentvalley.app",
        },
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            return response.status, response.read().decode(errors="replace")
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode(errors="replace")
    except (urllib.error.URLError, TimeoutError):
        return 0, ""


def sign(email: str, expiry: str) -> str:
    key = hashlib.sha256(b"agentvalley confirm\n" + os.environ["RESEND_API_KEY"].encode()).digest()
    return hmac.new(key, f"{email}\n{expiry}".encode(), hashlib.sha256).hexdigest()


def proven(fields: dict) -> str | None:
    """The address a link vouches for, or None when it is forged, broken or past its days."""
    email, expiry, token = (fields.get(k, [""])[0] for k in ("e", "x", "t"))
    if not (email and expiry.isdigit() and token) or int(expiry) < time.time():
        return None
    return email if hmac.compare_digest(sign(email, expiry), token) else None


def mailbox(email: str) -> str:
    """One key per inbox: Reader+1@Example.com and reader@example.com are one."""
    name, _, domain = email.lower().rpartition("@")
    return f"{name.split('+')[0]}@{domain}"


def ask(email: str) -> str:
    """Mails the link. Returns sent, full (the plan's mail for the day is gone) or failed."""
    now, exact, box = time.time(), email.lower(), mailbox(email)
    if now - SENT.get(exact, 0) < SPACING:
        # This very address has a fresh link.
        return "sent"
    recent = [t for t in BOXES.get(box, []) if now - t < SPACING]
    if len(recent) >= PER_BOX:
        # Spellings of one inbox (case, +tags) cannot fill it with mail.
        return "failed"
    expiry = str(int(time.time()) + DAYS * 86400)
    link = f"{SITE}/api/subscribe?" + urllib.parse.urlencode({"e": email, "x": expiry, "t": sign(email, expiry)})
    mail = {
        "from": "AgentValley <hello@agentvalley.app>",
        "to": [email],
        "subject": "Confirm your AgentValley updates",
        "text": MAIL.format(link=link, days=DAYS),
    }
    if LETTER:
        mail["html"] = letter(link=link, days=str(DAYS))
    status, body = resend("/emails", mail)
    if 200 <= status < 300:
        SENT[exact] = now
        BOXES[box] = recent + [now]
        return "sent"
    return "full" if "quota" in body else "failed"


def add(email: str) -> bool:
    body = {"email": email, "unsubscribed": False}
    if os.environ.get("RESEND_SEGMENT_ID"):
        body["segments"] = [{"id": os.environ["RESEND_SEGMENT_ID"]}]
    status, answer = resend("/contacts", body)
    created = 200 <= status < 300
    if not created and "already exist" not in answer.lower():
        return False
    # Someone already a contact may have left the list once; their yes from the mailbox puts them back.
    # Sent every time, since Resend does not say whether creating an existing contact changes it.
    status, _ = resend(f"/contacts/{urllib.parse.quote(email, safe='@')}", {"unsubscribed": False}, "PATCH")
    return created or 200 <= status < 300


def page(said: str, email: str = "", fields: dict | None = None) -> str:
    """The mailroom saying `said`. With `fields` (e, x, t from a link that vouched for `email`) it holds the button."""
    title, words = SAID[said]
    if said == "ask":
        hidden = "".join(f'<input type="hidden" name="{k}" value="{html.escape(fields[k][0])}">' for k in ("e", "x", "t"))
        action = f'<div class="actions"><form class="yes" method="post" action="/api/subscribe">{hidden}<button class="btn" type="submit">Yes, send me updates</button></form></div>'
    elif said == "in":
        action = (
            '<div class="stamp" aria-hidden="true">On the list</div>'
            f'<div class="actions"><a class="btn" href="{DMG}">Download for Mac</a><a class="link" href="/">Back to AgentValley</a></div>'
            '<p class="note">Have the app already? It looks for a new version once an hour by itself.</p>'
        )
    elif said == "old":
        action = '<div class="actions"><a class="btn" href="/#updates">Get a fresh link</a><a class="link" href="/">Back to AgentValley</a></div>'
    else:
        action = '<div class="actions"><a class="link" href="/">Back to AgentValley</a></div>'
    fill = {
        "said": said,
        "title": html.escape(title),
        "words": words.replace("{email}", html.escape(email)),
        "action": action,
        "confetti": CONFETTI if said == "in" else "",
    }
    return re.sub(r"\{\{(\w+)\}\}", lambda m: fill.get(m[1], ""), ROOM)


class handler(BaseHTTPRequestHandler):
    def do_GET(self):
        fields = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
        email = proven(fields) if "RESEND_API_KEY" in os.environ else None
        if not email:
            return self.answer(400, "text/html; charset=utf-8", page("old"))
        self.answer(200, "text/html; charset=utf-8", page("ask", email, fields))

    def do_POST(self):
        size = int(self.headers.get("Content-Length") or 0)
        fields = urllib.parse.parse_qs(self.rfile.read(min(size, 2048)).decode(errors="replace"))
        email = (fields.get("email") or [""])[0].strip()
        ready = "RESEND_API_KEY" in os.environ
        if self.headers.get("Sec-Fetch-Site", "same-origin") != "same-origin":
            # Another site's page cannot sign its visitors up; browsers say where a post comes from.
            said = "failed"
        elif "t" in fields:
            # The button on the link's page.
            confirmed = proven(fields) if ready else None
            said = "in" if confirmed and add(confirmed) else "old" if ready and not confirmed else "failed"
        elif fields.get("website", [""])[0]:
            said = "sent"
        elif len(email) > 254 or not EMAIL.match(email) or not ready:
            said = "failed"
        else:
            said = ask(email)
        ok = said in ("sent", "in")
        if "application/json" in (self.headers.get("Accept") or ""):
            self.answer(200 if ok else 502, "application/json", json.dumps({"ok": ok, "said": said}))
        else:
            self.answer(200 if ok else 502, "text/html; charset=utf-8", page(said))

    def answer(self, status: int, kind: str, text: str):
        data = text.encode()
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()
        self.wfile.write(data)
