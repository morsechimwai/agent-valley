import { BillScroll } from '@/components/bill-scroll';
import { HistoryPanel } from '@/components/history-panel';
import { HuntPumpkin } from '@/components/hunt';
import { Word } from '@/components/word';

// History and its PDF as one scene: the heading and its words across the top, then the panel
// with the bill coming out from behind its right edge, under the Export PDF link. On a phone
// they read in order: the cost, the panel, then the bill out from under the panel's foot.
export function Costs() {
  return (
    <section className="wrap section costs">
      <div className="c-head">
        <h2>See what each project cost.</h2>
        <div className="stack">
          <p className="lead">Open History from the chart button at the top of the panel. Pick a day, a week or a month, then go back to any earlier one. Choose a day for its hours, or a project for its sessions.</p>
          <p className="text-muted-foreground">
            At <Word id="api"><abbr title="application programming interface">API</abbr> prices</Word>. Kept on your Mac, even after Claude Code clears its old files. A project you move or rename keeps its history, and two folders that share a name stay two projects.
          </p>
          <HuntPumpkin n={1} />
        </div>
      </div>
      <BillScroll>
        <div className="c-panel">
          {/* The real link is on the panel; this is only the pen pointing at it. */}
          <span className="c-note" aria-hidden="true">
            Export PDF
            {/* The pen of the row's notes (sections/rows.tsx), down onto the link. */}
            <svg viewBox="0 0 72 80">
              <path d="M3 6 C14 5 27 3 38 7 C50 12 57 30 56.5 47 C56.2 58 56 68 56 77" />
              <path d="M48 66 C51 70 54 74 56 77.5 C58.5 73 61 69 65 65" />
            </svg>
          </span>
          <HistoryPanel />
        </div>
        {/* The PDF report's first page, as the app prints it from a made-up September: one frame of the
            report motion, drawn on nothing (testing/site.sh report). It slides out of its slot. */}
        <div className="report" id="report">
          <span className="r-slot">
            <img
              className="r-sheet"
              src="/report-sheet.webp"
              width={1500}
              height={1125}
              alt="The first page of a statement of work for September 2026, all projects: $1,414.66 at API prices, a bar for each day, and what each agent and each model cost."
              loading="lazy"
              decoding="async"
            />
          </span>
          <h3 className="text-[1.5rem]">Hand the month over as a PDF.</h3>
          <p>
            Export <Word id="pdf"><abbr title="Portable Document Format">PDF</abbr></Word> writes a <Word id="statement">statement of work</Word>: every project for you, or one project for your team or a client.
          </p>
        </div>
      </BillScroll>
    </section>
  );
}
