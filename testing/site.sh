#!/bin/bash
# The website in site/, a Next.js app built to plain files in site/out: makes its pictures,
# checks it and serves it on this Mac. Files served as they are live in site/public.
#
#   testing/site.sh mascots   Writes every person and the mug as SVG to site/public/mascots, from
#                             the app's own cells and colours (SiteMascotsTests).
#   testing/site.sh og        Builds the site and saves the top of the page at 1200×630 as
#                             site/public/og.png, the picture a link to the site shows where it is shared.
#   testing/site.sh icon      Writes AppIcon.icns, the app's icon, from site/public/mark.svg.
#   testing/site.sh webicons  Writes site/public/favicon.ico and site/public/apple-touch-icon.png
#                             from site/public/mark.svg.
#   testing/site.sh social    Writes docs/social-preview.png at 1280×640, the picture GitHub shows
#                             for a link to the repo: the crew, the name and the line under it.
#                             It goes up by hand, in the repo's Settings, under Social preview.
#   testing/site.sh logo      Writes docs/logo.svg and docs/logo-dark.svg, the full logo for the
#                             README: the crew of mark.svg beside the name of logo.svg, as the
#                             footer lays them out. The dark copy has light letters for GitHub's dark theme.
#   testing/site.sh lineup    Writes docs/crew-lineup.svg, the seven of us at work for the top of the
#                             README, from the site's mascots, moving as in the app.
#   testing/site.sh photo     Writes docs/crew-photo.webp, the crew photo framed as the site shows it,
#                             for the README.
#   testing/site.sh rows      Builds the site and writes docs/row-notes.png, the enlarged row with its
#                             notes in pen as the site draws it, for the README.
#   testing/site.sh report    Draws the report motion from the app: the History page and the two
#                             PDFs of a made-up September (ReportMotionAssetsTests), their totals
#                             in site/motion; then, with Remotion, the first page's head that the
#                             site shows, on nothing (site/public/report-sheet.webp). Remotion fetches
#                             its Chrome on its first render.
#   testing/site.sh history   Builds the site and writes docs/history.png for the README: the site's
#                             History panel with the PDF's first page coming out from under it, and
#                             a pen arrow from Export PDF to the page, on the page's cream.
#   testing/site.sh needs-you Draws the needs-you motion's pictures from the app: the panel shut
#                             while three made-up sessions work, shut with the red 1, open on the
#                             request and open once it is allowed (NeedsYouMotionAssetsTests), as
#                             WebP in site/public/needs-you; then, with Remotion, the still the
#                             site shows where nothing moves, and docs/needs-you.gif for the README.
#   testing/site.sh crew      Builds the site and, with Remotion, draws the crew at work: the stills
#                             the site shows where nothing moves, wide and tall (site/public/crew),
#                             and docs/crew.gif on the page's cream for the README.
#   testing/site.sh display   With Remotion, the notch gliding between a MacBook and a big display:
#                             the still the site shows where nothing moves (site/public/display),
#                             docs/display.gif for the README and docs/distribution/display-motion.mp4
#                             for posts.
#   testing/site.sh check     Installs, tests and builds the site; every line of the spec's copy is
#                             on the page, every file it points to is there, nothing is loaded
#                             from another site, and the browser tests pass.
#   testing/site.sh serve     Serves the built site, site/out, at http://localhost:8765.
set -euo pipefail
cd "$(dirname "$0")/.."

# Serves the built site on a port. Python's file server queues only 5 connections by default;
# a browser asks for more at once and the rest are reset, so some pictures never arrive. exec:
# run in the background, the server is the job itself, so the caller's kill reaches it.
serve_out() {
    exec python3 -c "import functools,http.server as h; h.ThreadingHTTPServer.request_queue_size=128; h.test(HandlerClass=functools.partial(h.SimpleHTTPRequestHandler,directory='site/out'),ServerClass=h.ThreadingHTTPServer,port=$1,bind='127.0.0.1')"
}

case "${1:-}" in
mascots)
    mkdir -p site/public/mascots
    SITE_MASCOTS_OUT="$PWD/site/public/mascots" swift test --filter SiteMascotsTests
    ls site/public/mascots | wc -l
    ;;
og)
    npm --prefix site run build >/dev/null
    serve_out 8766 >/dev/null 2>&1 &
    server=$!
    disown "$server"
    trap 'kill $server' EXIT
    sleep 1
    # A browser of its own, so the person's open Chrome is not the one asked. Its clock is set past
    # Halloween, which the page turns on by the visitor's date: the picture outlives the season.
    (cd site && OUT="$PWD/public/og.png" node --input-type=module - <<'JS'
import { chromium } from '@playwright/test';
const browser = await chromium.launch({ channel: 'chrome' });
const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, reducedMotion: 'reduce' });
await page.clock.setFixedTime(new Date(2026, 11, 1, 12));
await page.goto('http://127.0.0.1:8766/', { waitUntil: 'networkidle' });
await page.evaluate(() => document.fonts.ready);
await page.screenshot({ path: process.env.OUT });
await browser.close();
JS
    )
    sips -g pixelWidth -g pixelHeight site/public/og.png | tail -2
    ;;
social)
    # Every mark and logo pixel lands on whole pixels: the crew at 14 to one, the name at 8.
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    cat > "$work/social.html" <<HTML
<!doctype html><style>
@font-face{font-family:"Plex Mono";src:url(file://$PWD/testing/fonts/IBMPlexMono-Regular.woff2)}
html,body{margin:0;height:100%;background:#f1e8d4}
body{display:flex;flex-direction:column;align-items:center;justify-content:center}
.mark svg{display:block;width:224px;height:182px}
.logo svg{display:block;width:704px;height:96px;margin-top:56px}
p{margin:40px 0 0;font:30px "Plex Mono";color:#4d4439}
</style>
<div class="mark">$(cat site/public/mark.svg)</div><div class="logo">$(cat site/public/logo.svg)</div>
<p>A small valley of programmers in your notch.</p>
HTML
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --user-data-dir="$work/profile" \
        --hide-scrollbars --allow-file-access-from-files --virtual-time-budget=2000 --window-size=1280,640 \
        --screenshot="$PWD/docs/social-preview.png" "file://$work/social.html" 2>/dev/null
    sips -g pixelWidth -g pixelHeight docs/social-preview.png | tail -2
    ;;
photo)
    # The crew photo as the site's credits show it, print, date stamp and caption, on nothing,
    # for the README, where no CSS can frame it: docs/crew-photo.webp at twice its size.
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    cat > "$work/photo.html" <<HTML
<!doctype html><style>
@font-face{font-family:"Plex Mono";src:url(file://$PWD/testing/fonts/IBMPlexMono-Regular.woff2)}
@font-face{font-family:"Plex Mono";font-weight:600;src:url(file://$PWD/testing/fonts/IBMPlexMono-SemiBold.woff2)}
html,body{margin:0;background:transparent}
.photo{position:absolute;left:40px;top:30px;width:532px;padding:14px 14px 18px;border-radius:3px;background:#fbf7ee;color:#2a2118;transform:rotate(-2.5deg);box-shadow:0 22px 40px -16px rgba(0,0,0,.35),0 1px 3px rgba(0,0,0,.2)}
.snap{position:relative;aspect-ratio:4/3;overflow:hidden;background:#6f7477;filter:sepia(.18) saturate(.92)}
.snap img{display:block;width:100%;height:100%;object-fit:cover}
.snap::after{content:"";position:absolute;inset:0;background:radial-gradient(ellipse at center,transparent 55%,rgba(30,15,5,.5))}
.stamp{position:absolute;z-index:1;right:5%;bottom:4%;color:#ff8a1f;font:600 .95rem "Plex Mono";letter-spacing:.08em;opacity:.9}
p{display:grid;gap:2px;margin:14px 0 0;padding:0 4px;font:400 .9375rem/1.5 "Plex Mono"}
b{font-weight:600}
</style>
<div class="photo"><div class="snap"><img src="file://$PWD/site/public/crew-photo.webp"><span class="stamp">'69 7 20</span></div>
<p><b>The AgentValley crew</b><span>Go take a break.</span><span>We'll call you when we need you.</span></p></div>
HTML
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --user-data-dir="$work/profile" \
        --hide-scrollbars --allow-file-access-from-files --default-background-color=00000000 \
        --force-device-scale-factor=2 --virtual-time-budget=2000 --window-size=640,580 \
        --screenshot="$work/photo.png" "file://$work/photo.html" 2>/dev/null
    python3 -I -c 'import sys; from PIL import Image; Image.open(sys.argv[1]).save(sys.argv[2], quality=86, method=6)' \
        "$work/photo.png" docs/crew-photo.webp
    ls -l docs/crew-photo.webp
    ;;
rows)
    # At twice its size, on the page's cream with round corners: it reads on GitHub's dark theme too.
    npm --prefix site run build >/dev/null
    serve_out 8766 >/dev/null 2>&1 &
    server=$!
    disown "$server"
    work=$(mktemp -d)
    trap 'kill $server; rm -rf "$work"' EXIT
    sleep 1
    (cd site && OUT="$work/rows.png" node --input-type=module - <<'JS'
import { chromium } from '@playwright/test';
const browser = await chromium.launch({ channel: 'chrome' });
// Reduced motion: the arrows stand drawn from the start.
const page = await browser.newPage({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 2, reducedMotion: 'reduce' });
await page.goto('http://127.0.0.1:8766/');
const figure = page.locator('figure.notes');
await figure.scrollIntoViewIfNeeded();
await page.evaluate(() => document.fonts.ready);
const box = await figure.boundingBox();
// As much cream beside the black box as above and below it.
await page.screenshot({ path: process.env.OUT, clip: { x: box.x - 32, y: box.y, width: box.width + 64, height: box.height } });
await browser.close();
JS
    )
    python3 -I - "$work/rows.png" docs/row-notes.png <<'PY'
import sys
from PIL import Image, ImageDraw
picture = Image.open(sys.argv[1]).convert('RGBA')
corners = Image.new('L', picture.size, 0)
ImageDraw.Draw(corners).rounded_rectangle((0, 0, *picture.size), radius=36, fill=255)
picture.putalpha(corners)
picture.save(sys.argv[2], optimize=True)
PY
    ls -l docs/row-notes.png
    sips -g pixelWidth -g pixelHeight docs/row-notes.png | tail -2
    ;;
report)
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    REPORT_MOTION_OUT="$work" swift test --filter ReportMotionAssetsTests >/dev/null
    for n in all shop-web; do sips -s format png -Z 2400 "$work/report-$n.pdf" --out "$work/report-$n.png" >/dev/null; done
    # What Remotion reads: the page cut to the panel; each PDF page 1300 wide, enough for the
    # camera's 2.35 times; the font. Kept out of site/public, which serves only what the site shows.
    mkdir -p "$work/public"
    python3 -I - "$work" "$work/public" <<'PY'
import sys
from PIL import Image
work, out = sys.argv[1], sys.argv[2]
for n in ('all', 'shop-web'):
    page = Image.open(f'{work}/history-{n}.png').convert('RGBA')
    page.crop(page.getbbox()).save(f'{out}/history-{n}.webp', quality=86, method=6)
    sheet = Image.open(f'{work}/report-{n}.png').convert('RGB')
    sheet.resize((1300, round(1300 * sheet.height / sheet.width)), Image.LANCZOS).save(f'{out}/report-{n}.webp', quality=86, method=6)
PY
    cp "$work/totals.json" site/motion/report-totals.json
    cp site/node_modules/geist/dist/fonts/geist-mono/GeistMono-Bold.woff2 "$work/public/"
    # The camera held on the first page's head (BEATS.zoomA), on nothing, cut to the page and its shadow.
    (cd site && npx remotion still motion/index.tsx ReportMotion "$work/still.png" --frame=120 --scale=1.25 \
        --props='{"loop":false,"bare":true}' --public-dir="$work/public" --log=error)
    python3 -I -c 'import sys; from PIL import Image; i = Image.open(sys.argv[1]).convert("RGBA"); i.crop(i.getchannel("A").getbbox()).save(sys.argv[2], quality=86, alpha_quality=90, method=6)' \
        "$work/still.png" site/public/report-sheet.webp
    ls -l site/public/report-sheet.webp site/motion/report-totals.json
    sips -g pixelWidth -g pixelHeight site/public/report-sheet.webp | grep pixel
    ;;
history)
    # At twice its size on the page's cream with round corners, as docs/row-notes.png: it reads on
    # GitHub's dark theme too. The panel and the sheet are the site's own, set out on a card.
    npm --prefix site run build >/dev/null
    serve_out 8766 >/dev/null 2>&1 &
    server=$!
    disown "$server"
    work=$(mktemp -d)
    trap 'kill $server; rm -rf "$work"' EXIT
    sleep 1
    (cd site && OUT="$work/history.png" node --input-type=module - <<'JS'
import { chromium } from '@playwright/test';
const browser = await chromium.launch({ channel: 'chrome' });
const page = await browser.newPage({ viewport: { width: 1280, height: 1000 }, deviceScaleFactor: 2, reducedMotion: 'reduce' });
await page.goto('http://127.0.0.1:8766/');
const sheet = page.locator('#report img');
await sheet.evaluate((img) => { img.loading = 'eager'; });
await page.waitForFunction(() => document.querySelector('#report img').complete);
await page.evaluate(() => document.fonts.ready);
// The panel 470 wide, its top 60 down to leave room for the arrow; the sheet behind it, 414 wide,
// its head 28 under the panel's foot; the card ends where the sheet has faded out.
const height = await page.evaluate(() => {
  const card = Object.assign(document.createElement('div'), { id: 'card' });
  card.style.cssText = 'position:fixed;inset:0 auto auto 0;width:620px;overflow:hidden;background:var(--background);z-index:9999';
  const panel = document.querySelector('section.costs .hist').cloneNode(true);
  panel.style.cssText = 'position:absolute;left:28px;top:60px;width:470px;z-index:1';
  const sheet = document.querySelector('#report img').cloneNode(true);
  card.append(panel, sheet);
  document.body.append(card);
  const top = panel.getBoundingClientRect().bottom - 28;
  sheet.style.cssText = `position:absolute;left:186px;top:${top}px;width:414px;height:auto`;
  card.insertAdjacentHTML('beforeend', `<svg width="620" height="${top + 80}" style="position:absolute;inset:0;z-index:2;overflow:visible" fill="none" stroke="var(--pen)" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">
    <path d="M 268 52 C 290 16, 420 10, 520 20 C 600 30, 612 120, 606 260 C 602 ${top - 120}, 598 ${top - 40}, 586 ${top + 20}"/>
    <path d="M 573 ${top + 6} L 586 ${top + 23} L 599 ${top + 7}"/></svg>`);
  const height = Math.ceil(top + 414 * sheet.naturalHeight / sheet.naturalWidth + 8);
  card.style.height = `${height}px`;
  return height;
});
await page.screenshot({ path: process.env.OUT, clip: { x: 0, y: 0, width: 620, height } });
await browser.close();
JS
    )
    python3 -I - "$work/history.png" docs/history.png <<'PY'
import sys
from PIL import Image, ImageDraw
picture = Image.open(sys.argv[1]).convert('RGBA')
corners = Image.new('L', picture.size, 0)
ImageDraw.Draw(corners).rounded_rectangle((0, 0, *picture.size), radius=36, fill=255)
picture.putalpha(corners)
picture.save(sys.argv[2], optimize=True)
PY
    ls -l docs/history.png
    sips -g pixelWidth -g pixelHeight docs/history.png | tail -2
    ;;
needs-you)
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    NEEDS_YOU_MOTION_OUT="$work" swift test --filter NeedsYouMotionAssetsTests >/dev/null
    # All four cut by one box, the open panel's, so they lie over one another in the motion.
    mkdir -p site/public/needs-you "$work/public"
    python3 -I - "$work" site/public/needs-you <<'PY'
import sys
from PIL import Image
work, out = sys.argv[1], sys.argv[2]
names = ('shut-working', 'shut-asking', 'open-asking', 'open-allowed')
pictures = {n: Image.open(f'{work}/{n}.png').convert('RGBA') for n in names}
left = pictures['open-asking'].getbbox()[0]
box = (left, 0, left + 1088, 850)
# Where the motion (site/motion/needs-you-motion.tsx: PANEL, ISLAND, HEIGHT) expects the app's
# shapes, in the cut pictures' pixels. When the app draws them elsewhere, change both.
expected = {'open-asking': (0, 0, 1088, 850), 'open-allowed': (0, 0, 1088, 748), 'shut-working': (244, 0, 844, 76), 'shut-asking': (244, 0, 844, 76)}
for n, want in expected.items():
    got = pictures[n].crop(box).getbbox()
    if got != want:
        sys.exit(f'{n} is drawn at {got}, the motion expects {want}: change site/motion/needs-you-motion.tsx with it.')
for n, picture in pictures.items():
    picture.crop(box).save(f'{out}/{n}.webp', quality=88, method=6)
PY
    # The entry loads the report's font for every composition.
    cp site/public/needs-you/shut-*.webp site/public/needs-you/open-*.webp site/node_modules/geist/dist/fonts/geist-mono/GeistMono-Bold.woff2 "$work/public/"
    # The terminal waiting, the red 1 and the pointer on the notch (BEATS.pointIn's end).
    (cd site && npx remotion still motion/index.tsx NeedsYouMotion "$work/still.png" --frame=58 --scale=1.25 \
        --props='{"base":""}' --public-dir="$work/public" --log=error)
    python3 -I -c 'import sys; from PIL import Image; Image.open(sys.argv[1]).convert("RGB").save(sys.argv[2], quality=86, method=6)' \
        "$work/still.png" site/public/needs-you/still.webp
    (cd site && npx remotion render motion/index.tsx NeedsYouMotion ../docs/needs-you.gif --codec=gif --every-nth-frame=2 --scale=0.5 \
        --props='{"base":""}' --public-dir="$work/public" --log=error --overwrite)
    ls -l site/public/needs-you docs/needs-you.gif
    if [ "$(stat -f %z docs/needs-you.gif)" -gt 5242880 ]; then
        echo "docs/needs-you.gif is over 5 MB: lower its --scale." >&2
        exit 1
    fi
    ;;
crew)
    # The crew at work (site/motion/crew-motion.tsx) in the page's pen, Caveat: the build has the copy
    # next/font keeps, the latin one.
    npm --prefix site run build >/dev/null
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    mkdir -p "$work/public/mascots" site/public/crew
    hand=$(python3 -I - site/out/_next/static <<'PY'
import glob, re, sys
for css in glob.glob(f'{sys.argv[1]}/chunks/*.css'):
    for face in re.findall(r'@font-face\{[^}]*\}', open(css).read()):
        if 'Caveat' in face and 'range:U+??' in face:
            print(re.search(r'url\([^)]*/media/([^)]+\.woff2)\)', face).group(1))
            sys.exit()
sys.exit('No latin Caveat in the build.')
PY
)
    cp "site/out/_next/static/media/$hand" "$work/public/Caveat.woff2"
    cp site/node_modules/geist/dist/fonts/geist-mono/GeistMono-Bold.woff2 "$work/public/"
    cp site/public/mascots/*.svg "$work/public/mascots/"
    # Both rows at work and the pen on what we hold (crew-motion.tsx: NOTES[2]), on nothing.
    for c in CrewMotion:still CrewMotionTall:still-tall; do
        (cd site && npx remotion still motion/index.tsx "${c%%:*}" "$work/${c##*:}.png" --frame=280 --scale=2 \
            --props="{\"base\":\"\",\"hand\":true,\"tall\":$([ "${c%%:*}" = CrewMotionTall ] && echo true || echo false)}" \
            --public-dir="$work/public" --log=error)
        python3 -I -c 'import sys; from PIL import Image; Image.open(sys.argv[1]).save(sys.argv[2], quality=86, alpha_quality=90, method=6)' \
            "$work/${c##*:}.png" "site/public/crew/${c##*:}.webp"
    done
    (cd site && npx remotion render motion/index.tsx CrewMotion ../docs/crew.gif --codec=gif --every-nth-frame=4 --scale=0.75 \
        --props='{"base":"","hand":true,"paper":"#f4ecd9"}' --public-dir="$work/public" --log=error --overwrite)
    ls -l site/public/crew docs/crew.gif
    sips -g pixelWidth -g pixelHeight site/public/crew/*.webp docs/crew.gif | grep pixel
    if [ "$(stat -f %z docs/crew.gif)" -gt 5242880 ]; then
        echo "docs/crew.gif is over 5 MB: lower its --scale." >&2
        exit 1
    fi
    ;;
display)
    # The notch gliding between a MacBook and a big display (site/motion/display-motion.tsx).
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    mkdir -p "$work/public/mascots" site/public/display docs/distribution
    cp site/node_modules/geist/dist/fonts/geist-mono/GeistMono-Bold.woff2 "$work/public/"
    cp site/public/mascots/*.svg "$work/public/mascots/"
    # Settled at the top of the big display (BEATS.away and back), on nothing.
    (cd site && npx remotion still motion/index.tsx DisplayMotion "$work/still.png" --frame=200 \
        --props='{"base":""}' --public-dir="$work/public" --log=error)
    python3 -I -c 'import sys; from PIL import Image; Image.open(sys.argv[1]).save(sys.argv[2], quality=88, alpha_quality=90, method=6)' \
        "$work/still.png" site/public/display/still.webp
    (cd site && npx remotion render motion/index.tsx DisplayMotion ../docs/display.gif --codec=gif --every-nth-frame=2 --scale=0.75 \
        --props='{"base":"","paper":"#f4ecd9"}' --public-dir="$work/public" --log=error --overwrite)
    # For X and Bluesky; docs/distribution stays out of the public repo (publish.sh).
    (cd site && npx remotion render motion/index.tsx DisplayMotion ../docs/distribution/display-motion.mp4 --codec=h264 --crf=16 --scale=2 \
        --props='{"base":"","paper":"#f4ecd9"}' --public-dir="$work/public" --log=error --overwrite)
    ls -l site/public/display docs/display.gif docs/distribution/display-motion.mp4
    if [ "$(stat -f %z docs/display.gif)" -gt 5242880 ]; then
        echo "docs/display.gif is over 5 MB: lower its --scale." >&2
        exit 1
    fi
    ;;
lineup)
    # The seven of us at the top of the README, each at work as in the app: the strip of what we hold
    # stepping on the app's 0.4 s tick (LOOP in site/motion/crew-motion.tsx), and Sunny waving.
    # One SVG of the site's own mascots; GitHub plays its CSS inside the picture.
    python3 -I - site/public/mascots docs/crew-lineup.svg <<'PY'
import re, sys
src, out = sys.argv[1], sys.argv[2]
inner = lambda name: re.sub(r'^.*?<svg[^>]*>|</svg>\s*$', '', open(f'{src}/{name}.svg').read(), flags=re.S)
crew = [('guru', 'wave'), ('walrus', 'typing'), ('engineer', 'running'), ('pearls', 'calling'),
        ('coder', 'thinking'), ('afro', 'searching'), ('beatnik', 'reading')]
style = ['@keyframes a{0%{opacity:1}50%{opacity:0}}@keyframes b{0%{opacity:0}50%{opacity:1}}',
         '.a{animation:a .8s steps(1) infinite}.b{opacity:0;animation:b .8s steps(1) infinite}']
faces = []
for i, (who, doing) in enumerate(crew):
    x = i * 15
    if doing == 'wave':
        body = f'<g class="a">{inner(f"{who}-wave0")}</g><g class="b">{inner(f"{who}-wave1")}</g>'
    else:
        n = 24 if doing == 'thinking' else 8
        # Out of step with each other, as on the site: a third of a round apart.
        style.append(f'.s{i}{{animation:f{n} {n * 0.4:g}s steps({n}) {-(i % 3) * 2.8:g}s infinite}}')
        body = f'<g class="s{i}">{inner(f"{who}-{doing}-run")}</g>'
    faces.append(f'<svg x="{x}" width="12" height="12" viewBox="0 0 12 12" overflow="hidden">{body}</svg>')
style += ['@keyframes f8{to{transform:translateX(-104px)}}', '@keyframes f24{to{transform:translateX(-312px)}}',
          '@media (prefers-reduced-motion:reduce){*{animation:none!important}}']
open(out, 'w').write('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 102 12" width="408" height="48" shape-rendering="crispEdges">'
                     f'<style>{"".join(style)}</style>{"".join(faces)}</svg>\n')
PY
    ls -l docs/crew-lineup.svg
    ;;
logo)
    # The crew (16×13) and the name (88×12) in one drawing, bottom edges level and four mark pixels
    # apart, as the footer sets them. Shown at four screen pixels to one, every rect stays crisp.
    python3 -I - site/public/mark.svg site/public/logo.svg docs <<'PY'
import re, sys
inner = lambda p: re.sub(r'^.*?<svg[^>]*>|</svg>\s*$', '', open(p).read(), flags=re.S)
mark, name = inner(sys.argv[1]), inner(sys.argv[2])
for out, letters, dots in (('logo.svg', '#23190F', '#B8A685'), ('logo-dark.svg', '#E6EDF3', '#6E6553')):
    drawn = name.replace('#23190F', letters).replace('#B8A685', dots)
    open(f'{sys.argv[3]}/{out}', 'w').write(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 13" width="432" height="52" shape-rendering="crispEdges">'
        f'<g>{mark}</g><g transform="translate(20 1)">{drawn}</g></svg>\n')
PY
    ls -l docs/logo.svg docs/logo-dark.svg
    ;;
webicons)
    # The crew of site/public/mark.svg for browsers: favicon.ico (32 and 16, the mark on nothing, one
    # mark pixel to two pixels and to one) and apple-touch-icon.png (180, on its black, which
    # the phone rounds). Every mark pixel lands on whole pixels.
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    shot() { # size, background, mark width, left, top, out
        printf '<!doctype html><style>html,body{margin:0;background:%s}svg{position:absolute;left:%spx;top:%spx;width:%spx}</style>%s' \
            "$2" "$4" "$5" "$3" "$(cat site/public/mark.svg)" > "$work/$6.html"
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --user-data-dir="$work/profile" \
            --hide-scrollbars --default-background-color=00000000 --window-size="$1,$1" \
            --screenshot="$work/$6.png" "file://$work/$6.html" 2>/dev/null
    }
    shot 180 '#141010' 144 18 32 touch
    shot 32 transparent 32 0 3 f32
    shot 16 transparent 16 0 2 f16
    cp "$work/touch.png" site/public/apple-touch-icon.png
    python3 -I -c 'import sys; from PIL import Image; Image.open(sys.argv[1]).save(sys.argv[3], sizes=[(32, 32), (16, 16)], append_images=[Image.open(sys.argv[2])])' \
        "$work/f32.png" "$work/f16.png" site/public/favicon.ico
    ls -l site/public/apple-touch-icon.png site/public/favicon.ico
    ;;
icon)
    # The crew of site/public/mark.svg on a black tile, on Apple's 1024 grid: an 824 tile with 185
    # corners. Every pixel of the mark is 40 points and lands on whole pixels down to 128.
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    cat > "$work/icon.html" <<HTML
<!doctype html><style>html,body{margin:0;background:transparent}
i{position:absolute;left:100px;top:100px;width:824px;height:824px;border-radius:185px;background:#141010}
svg{position:absolute;left:192px;top:248px;width:640px;height:520px}</style><i></i>$(cat site/public/mark.svg)
HTML
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --user-data-dir="$work/profile" \
        --hide-scrollbars --default-background-color=00000000 --window-size=1024,1024 \
        --screenshot="$work/1024.png" "file://$work/icon.html" 2>/dev/null
    mkdir "$work/AppIcon.iconset"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$work/1024.png" --out "$work/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
        sips -z $((s * 2)) $((s * 2)) "$work/1024.png" --out "$work/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$work/AppIcon.iconset" -o AppIcon.icns
    ls -l AppIcon.icns
    ;;
check)
    page=site/out/index.html
    fail=0
    npm --prefix site ci --silent
    npm --prefix site test --silent || fail=1
    npm --prefix site run build --silent >/dev/null || { echo "build failed"; exit 1; }
    # 1. The page's words against the copy deck, in checkouts that keep one.
    if [ -x testing/copy-check.sh ]; then testing/copy-check.sh "$page" || fail=1; fi
    # 2. Every file the page points to is there. /api/ is Vercel's functions (site/api), not files.
    while IFS= read -r ref; do
        [[ $ref == /api/* ]] && continue
        [ -e "site/out/${ref#/}" ] || { echo "missing file: $ref"; fail=1; }
    done < <(grep -oE '(src|href)="[^"#:]+"|url\([^):]+\)' "$page" | sed -E 's/^(src|href)="//; s/"$//; s/^url\(//; s/\)$//' | sort -u)
    # 3. Nothing is loaded from another site: links may leave, resources may not. The canonical
    #    link and the funnies' feed link name the site's own addresses and load nothing. Product
    #    Hunt's badge is the one exception, as in e2e/seo.spec.ts: it loads from their embed.
    if grep -oE '<[^>]+>' "$page" | grep -E '(src|srcset)="https?:|url\(["'"'"']?https?:|<link[^>]+href="https?:' | grep -vE 'rel="(canonical|alternate)"|https://api\.producthunt\.com/widgets/embed-image/'; then
        echo "external resource"; fail=1
    fi
    # 4. In a browser: the head and SEO, Copy, the notch, History, motion, no scripts, every
    #    width, and WCAG AAA (site/e2e).
    npm --prefix site run e2e --silent >/dev/null || { echo "browser tests failed: npm --prefix site run e2e"; fail=1; }
    [ "$fail" = 0 ] && echo "site check: ok"
    exit "$fail"
    ;;
serve)
    serve_out 8765
    ;;
*)
    sed -n '2,/^set /p' "$0" | sed '$d'
    exit 1
    ;;
esac
