"""Generates the "Runs: Show more" boards for the LFG UI Map canvas (tasks-redesign page)."""
import json, os

ROOT = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.join(ROOT, "project")
os.makedirs(PROJ, exist_ok=True)

CLAUDE = "/_blob/ef8009f67260096a5f07e1efb5599f3a"
CODEX = "/_blob/2fe21875806dd4fe485c294ec22000b7"

# Weekdays at 9:00, Thu Oct 15 2026 is today.
UPCOMING = ["Thu, Oct 29", "Wed, Oct 28", "Tue, Oct 27", "Mon, Oct 26", "Fri, Oct 23",
            "Thu, Oct 22", "Wed, Oct 21", "Tue, Oct 20", "Mon, Oct 19", "Fri, Oct 16"]
PAST_DAYS = ["Today", "Wed, Oct 14", "Tue, Oct 13", "Mon, Oct 12", "Fri, Oct 9", "Thu, Oct 8", "Wed, Oct 7",
             "Tue, Oct 6", "Mon, Oct 5", "Fri, Oct 2", "Thu, Oct 1", "Wed, Sep 30", "Tue, Sep 29", "Mon, Sep 28",
             "Fri, Sep 25", "Thu, Sep 24", "Wed, Sep 23", "Tue, Sep 22", "Mon, Sep 21", "Fri, Sep 18",
             "Thu, Sep 17", "Wed, Sep 16", "Tue, Sep 15"]
SUMMARIES = ["Reviewed 14 commits; flagged a send-queue regression", "Reviewed 9 commits; no regressions", None,
             "Reviewed 11 commits; two fixes to the task list", "Reviewed 7 commits; no regressions",
             "Reviewed 12 commits; flagged a slow host reconnect", "Reviewed 4 commits; docs only",
             "Reviewed 10 commits; no regressions", "Reviewed 8 commits; one fix to the send queue",
             "Reviewed 6 commits; no regressions", "Reviewed 13 commits; flagged a list scroll jump",
             "Reviewed 5 commits; no regressions", "Reviewed 9 commits; one fix to push alerts",
             "Reviewed 3 commits; docs only", "Reviewed 11 commits; no regressions",
             "Reviewed 7 commits; one fix to the terminal", "Reviewed 10 commits; no regressions",
             "Reviewed 8 commits; flagged a slow cold launch", "Reviewed 6 commits; no regressions",
             "Reviewed 12 commits; two fixes to sign-in", "Reviewed 4 commits; no regressions",
             "Reviewed 9 commits; no regressions", "Reviewed 7 commits; one fix to the session list"]
MINUTES = [6, 5, 0, 4, 5, 6, 3, 5, 4, 5, 6, 4, 5, 3, 5, 4, 6, 5, 4, 6, 3, 5, 4]

PHONE_RUNS_JS = """
    const line = '#48484A', none = 'transparent', green = '#30D158', red = '#FF453A', grey = '#A1A1A6', ink = '#FFFFFF';
    const upcomingDays = %(upcoming)s;
    const pastDays = %(past_days)s;
    const summaries = %(summaries)s;
    const minutes = %(minutes)s;
    const later = !!st.later, older = st.older ?? 2;
    // Each group shows at most three rows; with more, two runs and a Show more row.
    const upShown = later || upcomingDays.length <= 3 ? upcomingDays : upcomingDays.slice(-2);
    const pastShown = pastDays.length <= 3 ? pastDays : pastDays.slice(0, older);
    const upMore = upcomingDays.length > 3, pastMore = pastDays.length > 3;
    const left = pastDays.length - pastShown.length;
    const rows = [];
    if (upMore) rows.push({ isMore: true, isRun: false, top: true, label: later ? 'Show less' : 'Show more',
      count: later ? '' : (upcomingDays.length - 2) + ' later', railTop: later ? none : line, railBottom: line,
      chevron: later ? 'M6 9l6 6 6-6' : 'M6 15l6-6 6 6', tap: () => this.setState({ later: !later }) });
    upShown.forEach((d, i) => rows.push({ isRun: true, isMore: false, href: '#', node: '#636366', fill: '#000000',
      lineTop: i === 0 && !upMore ? none : line, lineBottom: line, head: d + ' · 9:00 AM', headColor: grey,
      tail: '', tailColor: grey, hasBody: false, body: '', bodyColor: grey }));
    pastShown.forEach((d, i) => {
      const failed = summaries[pastDays.indexOf(d)] == null;
      const lastRow = i === pastShown.length - 1 && !pastMore;
      rows.push({ isRun: true, isMore: false, href: failed ? '#' : 'phone-chat.dc.html', node: failed ? red : green, fill: failed ? red : green,
        lineTop: line, lineBottom: lastRow ? none : line, head: d + ' · 9:00 AM', headColor: ink,
        tail: failed ? 'Retry' : minutes[pastDays.indexOf(d)] + ' min ›', tailColor: failed ? '#409CFF' : grey, hasBody: true,
        body: failed ? 'Failed · model unavailable · no session started' : summaries[pastDays.indexOf(d)], bodyColor: failed ? red : '#D1D1D6' });
    });
    if (pastMore) rows.push({ isMore: true, isRun: false, top: false, label: left ? 'Show more' : 'Show less',
      count: left ? left + ' earlier' : '', railTop: line, railBottom: left ? line : none,
      chevron: left ? 'M6 9l6 6 6-6' : 'M6 15l6-6 6 6',
      tap: () => this.setState({ older: left ? Math.min(pastDays.length, older + 10) : 2 }) });
""" % {"upcoming": json.dumps(UPCOMING), "past_days": json.dumps(PAST_DAYS),
       "summaries": json.dumps(SUMMARIES), "minutes": json.dumps(MINUTES)}

PHONE_RUN_ROW = """
        <sc-if value="{{r.isRun}}" hint-placeholder-val="{{true}}">
        <a href="{{r.href}}" style="display: flex; gap: 12px; align-items: stretch;">
          <span style="width: 16px; flex: 0 0 16px; display: flex; flex-direction: column; align-items: center;">
            <span style="width: 2px; height: 10px; background: {{r.lineTop}};"></span>
            <span style="width: 12px; height: 12px; box-sizing: border-box; border-radius: 50%; border: 2px solid {{r.node}}; background: {{r.fill}}; flex: 0 0 12px;"></span>
            <span style="width: 2px; flex: 1 1 auto; background: {{r.lineBottom}};"></span>
          </span>
          <span style="flex: 1 1 auto; min-width: 0; padding: 5px 0 12px; display: flex; flex-direction: column; gap: 2px;">
            <span style="display: flex; align-items: center; gap: 8px;">
              <span style="flex: 1 1 auto; font-size: 15px; line-height: 20px; font-weight: 600; color: {{r.headColor}};">{{r.head}}</span>
              <span style="font-size: 13px; color: {{r.tailColor}}; font-weight: 600;">{{r.tail}}</span>
            </span>
            <sc-if value="{{r.hasBody}}" hint-placeholder-val="{{true}}">
              <span style="font-size: 15px; line-height: 20px; color: {{r.bodyColor}}; white-space: nowrap; overflow: hidden; text-overflow: ellipsis;">{{r.body}}</span>
            </sc-if>
          </span>
        </a>
        </sc-if>"""

# A: a text link, as the instructions' Show more. Off the rail.
PHONE_MORE_A = """
        <sc-if value="{{r.isMore}}" hint-placeholder-val="{{false}}">
        <button onClick="{{r.tap}}" style="align-self: flex-start; margin-left: 28px; height: 32px; border: 0; background: transparent; padding: 0; font: inherit; font-size: 15px; color: #409CFF; cursor: pointer;">{{r.label}}</button>
        </sc-if>"""

# B: a row on the timeline. The rail continues past it (dashed) while runs are hidden.
PHONE_MORE_B = """
        <sc-if value="{{r.isMore}}" hint-placeholder-val="{{false}}">
        <button onClick="{{r.tap}}" style="display: flex; gap: 12px; align-items: stretch; height: 44px; border: 0; background: transparent; padding: 0; font: inherit; color: inherit; text-align: left; cursor: pointer;">
          <span style="width: 16px; flex: 0 0 16px; display: flex; flex-direction: column; align-items: center;">
            <span style="width: 0; flex: 1 1 auto; border-left: 2px dashed {{r.railTop}};"></span>
            <span style="width: 18px; height: 18px; flex: 0 0 18px; border-radius: 50%; background: #1C1C1E; display: flex; align-items: center; justify-content: center;">
              <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#409CFF" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="{{r.chevron}}"></path></svg>
            </span>
            <span style="width: 0; flex: 1 1 auto; border-left: 2px dashed {{r.railBottom}};"></span>
          </span>
          <span style="flex: 1 1 auto; display: flex; align-items: center; gap: 8px;">
            <span style="flex: 1 1 auto; font-size: 15px; font-weight: 600; color: #409CFF;">{{r.label}}</span>
            <span style="font-size: 13px; color: #A1A1A6;">{{r.count}}</span>
          </span>
        </button>
        </sc-if>"""

# C: a capsule button beside the rail.
PHONE_MORE_C = """
        <sc-if value="{{r.isMore}}" hint-placeholder-val="{{false}}">
        <span style="display: flex; gap: 12px; align-items: stretch; height: 52px;">
          <span style="width: 16px; flex: 0 0 16px; display: flex; flex-direction: column; align-items: center;">
            <span style="width: 0; flex: 1 1 auto; border-left: 2px dashed {{r.railTop}};"></span>
            <span style="width: 0; flex: 1 1 auto; border-left: 2px dashed {{r.railBottom}};"></span>
          </span>
          <button onClick="{{r.tap}}" style="flex: 1 1 auto; align-self: center; height: 40px; border: 0; border-radius: 20px; background: #1C1C1E; color: #409CFF; font: inherit; font-size: 15px; font-weight: 600; display: flex; align-items: center; justify-content: center; gap: 6px; cursor: pointer;">
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="{{r.chevron}}"></path></svg>
            {{r.label}}
            <span style="font-weight: 400; color: #A1A1A6;">{{r.count}}</span>
          </button>
        </span>
        </sc-if>"""


def phone_board(title, more_row, initial_state, height, on_rail=True):
    js = PHONE_RUNS_JS if on_rail else (PHONE_RUNS_JS
        .replace("i === 0 && !upMore ? none : line", "i === 0 ? none : line")
        .replace("i === pastShown.length - 1 && !pastMore", "i === pastShown.length - 1"))
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{title}</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<style>
body{{margin:0}}
a{{color:inherit;text-decoration:none}}a:hover{{color:inherit}}
</style>
</helmet>
<div style="width: 390px; height: {height}px; position: relative; overflow: hidden; background: #000000; color: #FFFFFF; font-family: -apple-system, 'SF Pro Text', system-ui, sans-serif; -webkit-font-smoothing: antialiased;">

  <div style="position: absolute; top: 54px; left: 16px; right: 16px; height: 52px; display: flex; align-items: center; gap: 10px;">
    <a href="tA2d-list.dc.html" aria-label="Back to tasks" style="width: 44px; height: 44px; flex: 0 0 44px; border-radius: 22px; background: rgba(44,44,46,0.92); box-shadow: 0 2px 12px rgba(0,0,0,0.5); border: 0.5px solid rgba(255,255,255,0.10); display: flex; align-items: center; justify-content: center;">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M15 5l-7 7 7 7"></path></svg>
    </a>
    <span style="flex: 1 1 auto;"></span>
    <div role="group" aria-label="Task actions" style="height: 48px; border-radius: 24px; background: rgba(44,44,46,0.92); box-shadow: 0 2px 12px rgba(0,0,0,0.5); border: 0.5px solid rgba(255,255,255,0.10); display: flex; align-items: center; padding: 0 4px;">
      <a href="tA2d-edit.dc.html" aria-label="Edit task" style="width: 44px; height: 44px; display: flex; align-items: center; justify-content: center;">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 20h4L19 9l-4-4L4 16z"></path><path d="M13.5 6.5l4 4"></path></svg>
      </a>
      <button aria-label="More task options" style="width: 44px; height: 44px; border: 0; background: transparent; display: flex; align-items: center; justify-content: center; padding: 0;">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="#FFFFFF" aria-hidden="true"><circle cx="5" cy="12" r="1.9"></circle><circle cx="12" cy="12" r="1.9"></circle><circle cx="19" cy="12" r="1.9"></circle></svg>
      </button>
    </div>
  </div>

  <div style="position: absolute; top: 116px; left: 20px; right: 20px; display: flex; flex-direction: column; gap: 8px;">
    <h1 style="margin: 0; font-size: 28px; line-height: 34px; font-weight: 700;">Daily repo review</h1>
    <div style="display: flex; align-items: center; gap: 7px; font-size: 17px; line-height: 22px; color: #D1D1D6;">
      <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M17 2.5l3 3-3 3"></path><path d="M4 11.5v-1a5 5 0 0 1 5-5h11"></path><path d="M7 21.5l-3-3 3-3"></path><path d="M20 12.5v1a5 5 0 0 1-5 5H4"></path></svg>
      <span>Every weekday at 9:00 AM</span>
    </div>
    <div style="display: flex; gap: 6px; flex-wrap: wrap; padding-top: 2px;">
      <span style="height: 26px; padding: 0 9px; border-radius: 8px; background: #1C1C1E; display: flex; align-items: center; gap: 5px; font-size: 13px; color: #D1D1D6;">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><rect x="3" y="4" width="18" height="12" rx="1.5"></rect><path d="M9 20h6M12 16v4"></path></svg>Pro</span>
      <span style="height: 26px; padding: 0 9px 0 7px; border-radius: 8px; background: #1C1C1E; display: flex; align-items: center; gap: 5px; font-size: 13px; color: #D1D1D6;">
        <img src="{CLAUDE}" alt="" width="14" height="14" style="display: block;">Opus 5.5</span>
      <span style="height: 26px; padding: 0 9px; border-radius: 8px; background: #1C1C1E; display: flex; align-items: center; gap: 5px; font-size: 13px; color: #D1D1D6;">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round" aria-hidden="true"><path d="M3 6.5A1.5 1.5 0 0 1 4.5 5H9l2 2.5h8.5A1.5 1.5 0 0 1 21 9v9.5a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 18.5z"></path></svg>~/dev/personal/lfg</span>
    </div>

    <div style="margin-top: 10px; background: #1C1C1E; border-radius: 22px; padding: 16px; display: flex; flex-direction: column; gap: 12px;">
      <div style="display: flex; flex-direction: column; gap: 2px;">
        <span style="font-size: 12px; font-weight: 600; letter-spacing: 0.4px; text-transform: uppercase; color: #A1A1A6;">Next run</span>
        <span style="font-size: 22px; line-height: 28px; font-weight: 600;">Tomorrow, 9:00 AM</span>
        <span style="font-size: 15px; line-height: 20px; color: #A1A1A6;">Friday, Oct 16 · in 22 h 48 min</span>
      </div>
      <div style="display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px;">
        <button style="height: 44px; border: 0; border-radius: 22px; background: #0A6EE0; color: #FFFFFF; font: inherit; font-size: 16px; font-weight: 600; display: flex; align-items: center; justify-content: center; gap: 7px; cursor: pointer;">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M7 4.5v15l13-7.5z"></path></svg>Run now</button>
        <button style="height: 44px; border: 0; border-radius: 22px; background: #2C2C2E; color: #409CFF; font: inherit; font-size: 16px; font-weight: 600; display: flex; align-items: center; justify-content: center; gap: 7px; cursor: pointer;">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><rect x="6" y="4.5" width="4" height="15" rx="1"></rect><rect x="14" y="4.5" width="4" height="15" rx="1"></rect></svg>Pause</button>
      </div>
    </div>

    <div style="margin-top: 12px; display: flex; flex-direction: column; gap: 4px;">
      <span style="font-size: 15px; font-weight: 600; color: #A1A1A6;">Instructions</span>
      <p style="margin: 0; font-size: 16px; line-height: 22px; color: #F2F2F7; display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 3; overflow: hidden;">Review yesterday’s changes in LFG. Summarize the important fixes, flag anything that looks like a regression, and suggest the next most useful task. Keep it under 200 words and link each commit you mention.</p>
      <button style="align-self: flex-start; border: 0; background: transparent; padding: 2px 0; font: inherit; font-size: 15px; color: #409CFF; cursor: pointer;">Show more</button>
    </div>

    <div style="margin-top: 8px; display: flex; align-items: baseline; justify-content: space-between;">
      <span style="font-size: 15px; font-weight: 600; color: #A1A1A6;">Runs</span>
      <span style="font-size: 13px; color: #A1A1A6;">23 runs · 22 completed</span>
    </div>
    <div style="display: flex; flex-direction: column;">
      <sc-for list="{{{{rows}}}}" as="r" hint-placeholder-count="6">{more_row}{PHONE_RUN_ROW}
      </sc-for>
    </div>
  </div>

  <div style="position: absolute; left: 0; right: 0; bottom: 0; height: 130px; background: linear-gradient(rgba(0,0,0,0), rgba(0,0,0,0.96) 50%);"></div>
  <a href="tA2d-chat.dc.html" style="position: absolute; left: 16px; right: 16px; bottom: 28px; height: 52px; border-radius: 26px; background: rgba(44,44,46,0.92); box-shadow: 0 4px 24px rgba(0,0,0,0.5); border: 0.5px solid rgba(255,255,255,0.10); display: flex; align-items: center; gap: 10px; padding: 0 8px 0 18px; box-sizing: border-box;">
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#409CFF" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 3l1.8 4.7L18.5 9.5l-4.7 1.8L12 16l-1.8-4.7L5.5 9.5l4.7-1.8z"></path><path d="M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8z"></path></svg>
    <span style="flex: 1 1 auto; font-size: 17px; color: #8E8E93;">Ask to change this task…</span>
    <span style="width: 36px; height: 36px; border-radius: 18px; background: #3A3A3C; display: flex; align-items: center; justify-content: center;">
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="3" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12 19V5M5 12l7-7 7 7"></path></svg>
    </span>
  </a>
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":390,"height":{height}}}}}'>
class Component extends DCLogic {{
  constructor(props) {{ super(props); this.state = {json.dumps(initial_state)}; }}
  renderVals() {{
    const st = this.state || {{}};{js}
    return {{ rows }};
  }}
}}
</script>
</body>
</html>
"""


# Desktop: dA2 tokens. Every day at 9:00; today is Thu Oct 15.
D_UPCOMING = ["Sun, Oct 25", "Sat, Oct 24", "Fri, Oct 23", "Thu, Oct 22", "Wed, Oct 21",
              "Tue, Oct 20", "Mon, Oct 19", "Sun, Oct 18", "Sat, Oct 17", "Fri, Oct 16"]
D_PAST = ["Today", "Wed, Oct 14", "Tue, Oct 13", "Mon, Oct 12", "Sun, Oct 11", "Sat, Oct 10", "Fri, Oct 9",
          "Thu, Oct 8", "Wed, Oct 7", "Tue, Oct 6", "Mon, Oct 5", "Sun, Oct 4", "Sat, Oct 3", "Fri, Oct 2"]
D_BODIES = ["Three fixes landed; flagged a task-list selection regression", "No regressions; finite-repeat work still uncommitted",
            None, "Quiet day: two docs commits, nothing to review", "Interrupted when the host restarted",
            "Two fixes to the send queue; no regressions", "Reviewed 8 commits; no regressions",
            "Flagged a slow host reconnect", "Reviewed 5 commits; docs only", "Reviewed 9 commits; no regressions",
            "One fix to push alerts; no regressions", "Quiet day: nothing to review", "Reviewed 6 commits; no regressions",
            "Reviewed 10 commits; one fix to the terminal"]
D_MIN = [6, 5, 0, 4, 2, 5, 4, 6, 3, 5, 4, 2, 5, 6]

DESK_JS = """
    const line = 'rgba(255,255,255,0.14)', none = 'transparent', green = '#32D74B', red = '#FF5A50', amber = '#FF9F0A', grey = '#8A8A93', ink = '#F4F4F6', hollow = '#5A5A62';
    const upcomingDays = %(up)s;
    const pastDays = %(past)s;
    const bodies = %(bodies)s;
    const minutes = %(min)s;
    const later = !!st.later, older = st.older ?? 2;
    const upShown = later || upcomingDays.length <= 3 ? upcomingDays : upcomingDays.slice(-2);
    const pastShown = pastDays.length <= 3 ? pastDays : pastDays.slice(0, older);
    const upMore = upcomingDays.length > 3, pastMore = pastDays.length > 3;
    const left = pastDays.length - pastShown.length;
    const rows = [];
    if (upMore) rows.push({ isMore: true, isRun: false, label: later ? 'Show less' : 'Show more',
      count: later ? '' : (upcomingDays.length - 2) + ' later', railTop: later ? none : line, railBottom: line,
      chevron: later ? 'M6 9l6 6 6-6' : 'M6 15l6-6 6 6', tap: () => this.setState({ later: !later }) });
    upShown.forEach((d, i) => rows.push({ isRun: true, isMore: false, node: hollow, fill: 'transparent',
      lineTop: i === 0 && !upMore ? none : line, lineBottom: line, head: d + ' · 9:00 AM', headColor: grey,
      tail: '', tailColor: grey, hasBody: false, body: '', bodyColor: grey }));
    pastShown.forEach((d, i) => {
      const k = pastDays.indexOf(d), failed = bodies[k] == null, interrupted = (bodies[k] || '').startsWith('Interrupted');
      const lastRow = i === pastShown.length - 1 && !pastMore;
      const node = failed ? red : interrupted ? amber : green;
      rows.push({ isRun: true, isMore: false, node, fill: node, lineTop: line, lineBottom: lastRow ? none : line,
        head: d + ' · 9:00 AM', headColor: ink, tail: failed ? 'Retry' : minutes[k] + ' min ↗', tailColor: failed ? '#8FB8FF' : grey,
        hasBody: true, body: failed ? 'Failed · Claude Code exited · no session started' : bodies[k],
        bodyColor: failed ? '#FF6B61' : interrupted ? '#FFB340' : '#C9CBD3' });
    });
    if (pastMore) rows.push({ isMore: true, isRun: false, label: left ? 'Show more' : 'Show less',
      count: left ? left + ' earlier' : '', railTop: line, railBottom: left ? line : none,
      chevron: left ? 'M6 9l6 6 6-6' : 'M6 15l6-6 6 6',
      tap: () => this.setState({ older: left ? Math.min(pastDays.length, older + 10) : 2 }) });
""" % {"up": json.dumps(D_UPCOMING), "past": json.dumps(D_PAST), "bodies": json.dumps(D_BODIES), "min": json.dumps(D_MIN)}


def desk_board():
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Desktop · Runs, Show more</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<style>
body{{margin:0;background:#1B1B1E}}
a{{color:inherit;text-decoration:none}}a:hover{{color:inherit}}
button{{font:inherit;color:inherit}}
</style>
</helmet>
<div style="width: 400px; height: 1000px; box-sizing: border-box; display: flex; flex-direction: column; background: #1B1B1E; color: #F4F4F6; font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif; font-size: 13px; line-height: 1.35">

  <div style="display: flex; align-items: center; gap: 6px; height: 52px; padding: 0 12px 0 14px; flex: none">
    <div style="display: flex; gap: 8px; flex: none; margin-right: 6px" aria-hidden="true">
      <span style="width: 12px; height: 12px; border-radius: 6px; background: #FF5F57"></span>
      <span style="width: 12px; height: 12px; border-radius: 6px; background: #FEBC2E"></span>
      <span style="width: 12px; height: 12px; border-radius: 6px; background: #28C840"></span>
    </div>
    <a href="dA2-list.dc.html" aria-label="Back to tasks" style="width: 30px; height: 30px; display: flex; align-items: center; justify-content: center; border-radius: 15px; background: rgba(255,255,255,0.07)">
      <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true"><path d="M10 3.5 5.5 8l4.5 4.5"></path></svg>
    </a>
    <span style="flex: 1"></span>
    <div role="group" aria-label="Task actions" style="height: 30px; display: flex; align-items: center; padding: 0 2px; border-radius: 15px; background: rgba(255,255,255,0.07)">
      <a href="dA2-edit.dc.html" aria-label="Edit task" title="Edit task" style="width: 32px; height: 30px; display: flex; align-items: center; justify-content: center">
        <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 20h4L19 9l-4-4L4 16z"></path><path d="M13.5 6.5l4 4"></path></svg>
      </a>
      <button aria-label="More task options" title="More" style="width: 32px; height: 30px; display: flex; align-items: center; justify-content: center; border: 0; padding: 0; background: transparent">
        <svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true"><circle cx="3.5" cy="8" r="1.3" fill="currentColor"></circle><circle cx="8" cy="8" r="1.3" fill="currentColor"></circle><circle cx="12.5" cy="8" r="1.3" fill="currentColor"></circle></svg>
      </button>
    </div>
  </div>

  <div style="flex: 1; min-height: 0; display: flex; flex-direction: column; gap: 8px; padding: 6px 18px 0">
    <h1 style="margin: 0; font-size: 22px; line-height: 28px; font-weight: 700">Daily project review</h1>
    <div style="display: flex; align-items: center; gap: 7px; font-size: 14px; color: #C9CBD3">
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M17 2.5l3 3-3 3"></path><path d="M4 11.5v-1a5 5 0 0 1 5-5h11"></path><path d="M7 21.5l-3-3 3-3"></path><path d="M20 12.5v1a5 5 0 0 1-5 5H4"></path></svg>
      <span>Every day at 9:00 AM</span>
    </div>
    <div style="display: flex; flex-wrap: wrap; gap: 6px">
      <span style="height: 24px; display: flex; align-items: center; gap: 5px; padding: 0 8px; border-radius: 7px; background: rgba(255,255,255,0.07); font-size: 12px; color: #C9CBD3">
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><rect x="3" y="4" width="18" height="12" rx="1.5"></rect><path d="M9 20h6M12 16v4"></path></svg>Pro</span>
      <span style="height: 24px; display: flex; align-items: center; gap: 5px; padding: 0 8px 0 6px; border-radius: 7px; background: rgba(255,255,255,0.07); font-size: 12px; color: #C9CBD3">
        <img src="{CLAUDE}" alt="" width="13" height="13" style="display: block">opus</span>
      <span style="height: 24px; display: flex; align-items: center; gap: 5px; padding: 0 8px; border-radius: 7px; background: rgba(255,255,255,0.07); font-size: 12px; color: #C9CBD3">
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M3 6.5A1.5 1.5 0 0 1 4.5 5H9l2 2.5h8.5A1.5 1.5 0 0 1 21 9v9.5a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 18.5z"></path></svg>~/dev/personal/lfg</span>
    </div>

    <section aria-label="Next run" style="margin-top: 8px; display: flex; flex-direction: column; gap: 12px; padding: 14px; border-radius: 16px; background: #26262B">
      <div style="display: flex; flex-direction: column; gap: 2px">
        <span style="font-size: 11px; font-weight: 700; letter-spacing: 0.04em; text-transform: uppercase; color: #8A8A93">Next run</span>
        <span style="font-size: 19px; line-height: 25px; font-weight: 650">Tomorrow, 9:00 AM</span>
        <span style="font-size: 13px; color: #A8A8B0">Friday, Oct 16 · in 13 h 56 min</span>
      </div>
      <div style="display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px">
        <button style="height: 34px; display: flex; align-items: center; justify-content: center; gap: 6px; border: 0; border-radius: 17px; background: #3B8EFF; color: #FFFFFF; font-weight: 600; cursor: pointer">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M7 4.5v15l13-7.5z"></path></svg>Run now</button>
        <button style="height: 34px; display: flex; align-items: center; justify-content: center; gap: 6px; border: 0; border-radius: 17px; background: rgba(255,255,255,0.09); color: #9CC2FF; font-weight: 600; cursor: pointer">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><rect x="6" y="4.5" width="4" height="15" rx="1"></rect><rect x="14" y="4.5" width="4" height="15" rx="1"></rect></svg>Pause</button>
      </div>
    </section>

    <section aria-label="Instructions" style="margin-top: 10px; display: flex; flex-direction: column; gap: 4px">
      <h2 style="margin: 0; font-size: 12px; font-weight: 600; color: #8A8A93">Instructions</h2>
      <p style="margin: 0; font-size: 14px; line-height: 20px; color: #E4E5EA; display: -webkit-box; -webkit-box-orient: vertical; -webkit-line-clamp: 3; overflow: hidden">Review yesterday’s changes in lfg. Summarize fixes and regressions, flag anything that touched sendq.ts or journal-pump.ts, and suggest one next step. Keep it under 200 words and link each commit you mention.</p>
      <button style="align-self: flex-start; border: 0; background: transparent; padding: 2px 0; font-size: 13px; color: #8FB8FF; cursor: pointer">Show more</button>
    </section>

    <div style="margin-top: 6px; display: flex; align-items: baseline; justify-content: space-between">
      <h2 style="margin: 0; font-size: 12px; font-weight: 600; color: #8A8A93">Runs</h2>
      <span style="font-size: 12px; color: #8A8A93">14 runs · 12 completed</span>
    </div>
    <div style="display: flex; flex-direction: column">
      <sc-for list="{{{{rows}}}}" as="r" hint-placeholder-count="6">
        <sc-if value="{{{{r.isMore}}}}" hint-placeholder-val="{{{{false}}}}">
        <button onClick="{{{{r.tap}}}}" style="display: flex; gap: 12px; align-items: stretch; height: 34px; border: 0; background: transparent; padding: 0; text-align: left; cursor: pointer">
          <span style="flex: 0 0 14px; min-width: 0; display: flex; flex-direction: column; align-items: center">
            <span style="width: 0; flex: 1; border-left: 2px dashed {{{{r.railTop}}}}"></span>
            <span style="flex: 0 0 16px; width: 16px; height: 16px; border-radius: 8px; background: rgba(255,255,255,0.09); display: flex; align-items: center; justify-content: center">
              <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="#8FB8FF" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="{{{{r.chevron}}}}"></path></svg>
            </span>
            <span style="width: 0; flex: 1; border-left: 2px dashed {{{{r.railBottom}}}}"></span>
          </span>
          <span style="flex: 1; display: flex; align-items: center; gap: 8px">
            <span style="flex: 1; font-size: 13px; font-weight: 600; color: #8FB8FF">{{{{r.label}}}}</span>
            <span style="font-size: 12px; color: #8A8A93">{{{{r.count}}}}</span>
          </span>
        </button>
        </sc-if>
        <sc-if value="{{{{r.isRun}}}}" hint-placeholder-val="{{{{true}}}}">
        <a href="#" style="display: flex; gap: 12px; align-items: stretch">
          <span style="flex: 0 0 14px; display: flex; flex-direction: column; align-items: center">
            <span style="width: 2px; height: 9px; background: {{{{r.lineTop}}}}"></span>
            <span style="flex: 0 0 11px; width: 11px; height: 11px; box-sizing: border-box; border-radius: 6px; border: 2px solid {{{{r.node}}}}; background: {{{{r.fill}}}}"></span>
            <span style="width: 2px; flex: 1; background: {{{{r.lineBottom}}}}"></span>
          </span>
          <span style="flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px; padding: 4px 0 11px">
            <span style="display: flex; align-items: center; gap: 8px">
              <span style="flex: 1; font-size: 13px; font-weight: 600; color: {{{{r.headColor}}}}">{{{{r.head}}}}</span>
              <span style="font-size: 12px; font-weight: 600; color: {{{{r.tailColor}}}}">{{{{r.tail}}}}</span>
            </span>
            <sc-if value="{{{{r.hasBody}}}}" hint-placeholder-val="{{{{true}}}}">
              <span style="font-size: 13px; color: {{{{r.bodyColor}}}}; white-space: nowrap; overflow: hidden; text-overflow: ellipsis">{{{{r.body}}}}</span>
            </sc-if>
          </span>
        </a>
        </sc-if>
      </sc-for>
    </div>
  </div>

  <div style="flex: none; padding: 12px 14px 16px; background: linear-gradient(rgba(27,27,30,0), #1B1B1E 30%)">
    <a href="desk-iterm.dc.html" style="width: 100%; height: 40px; display: flex; align-items: center; justify-content: center; gap: 8px; border-radius: 20px; background: rgba(255,255,255,0.09); color: #F4F4F6; font-weight: 600">
      <svg width="15" height="15" viewBox="0 0 16 16" fill="none" stroke="#8FB8FF" stroke-width="1.5" aria-hidden="true"><path d="M3 4.5A1.5 1.5 0 0 1 4.5 3h7A1.5 1.5 0 0 1 13 4.5v5a1.5 1.5 0 0 1-1.5 1.5H7l-3 2.5V11A1.5 1.5 0 0 1 3 9.5z"></path></svg>
      Change with chat
      <svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="#8A8A93" stroke-width="1.8" aria-hidden="true"><path d="M5.5 10.5 10.5 5.5M6.5 5.5h4v4"></path></svg>
    </a>
    <div style="margin-top: 6px; text-align: center; font-size: 11px; color: #8A8A93">Opens a Claude Code session in iTerm with this task’s settings.</div>
  </div>
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":400,"height":1000}}}}'>
class Component extends DCLogic {{
  renderVals() {{
    const st = this.state || {{}};{DESK_JS}
    return {{ rows }};
  }}
}}
</script>
</body>
</html>
"""


def pill_board():
    chip_p = "height: 26px; padding: 0 9px 0 7px; border-radius: 8px; background: #1C1C1E; display: flex; align-items: center; gap: 5px; font-size: 13px; color: #D1D1D6;"
    chip_m = "height: 24px; display: flex; align-items: center; gap: 5px; padding: 0 8px 0 6px; border-radius: 7px; background: rgba(255,255,255,0.07); font-size: 12px; color: #C9CBD3"
    label = "font-size: 12px; font-weight: 600; color: #8A8A93; width: 110px; flex: none;"
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Model pill with the agent logos</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<style>
body{{margin:0}}
</style>
</helmet>
<div style="width: 560px; height: 300px; box-sizing: border-box; display: flex; flex-direction: column; font-family: -apple-system, 'SF Pro Text', system-ui, sans-serif; -webkit-font-smoothing: antialiased; color: #FFFFFF;">
  <div style="flex: 1; background: #000000; padding: 24px 24px; display: flex; flex-direction: column; gap: 14px; justify-content: center;">
    <span style="font-size: 13px; font-weight: 600; color: #A1A1A6;">Phone · task view chips (model names read as people write them)</span>
    <div style="display: flex; align-items: center; gap: 10px;">
      <span style="{label}">Claude Code</span>
      <span style="{chip_p}"><img src="{CLAUDE}" alt="" width="14" height="14" style="display: block;">Opus 5.5</span>
      <span style="{chip_p}"><img src="{CLAUDE}" alt="" width="14" height="14" style="display: block;">Claude default</span>
    </div>
    <div style="display: flex; align-items: center; gap: 10px;">
      <span style="{label}">Codex</span>
      <span style="{chip_p}"><img src="{CODEX}" alt="" width="15" height="15" style="display: block;">GPT-6 Astra</span>
      <span style="{chip_p}"><img src="{CODEX}" alt="" width="15" height="15" style="display: block;">Codex default</span>
    </div>
  </div>
  <div style="flex: 1; background: #1B1B1E; padding: 24px 24px; display: flex; flex-direction: column; gap: 14px; justify-content: center;">
    <span style="font-size: 12px; font-weight: 600; color: #8A8A93;">Mac · task view chips (raw model ids)</span>
    <div style="display: flex; align-items: center; gap: 10px;">
      <span style="{label}">Claude Code</span>
      <span style="{chip_m}"><img src="{CLAUDE}" alt="" width="13" height="13" style="display: block">opus</span>
    </div>
    <div style="display: flex; align-items: center; gap: 10px;">
      <span style="{label}">Codex</span>
      <span style="{chip_m}"><img src="{CODEX}" alt="" width="14" height="14" style="display: block">gpt-6-astra</span>
    </div>
  </div>
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":560,"height":300}}}}'>
class Component extends DCLogic {{
  renderVals() {{ return {{}}; }}
}}
</script>
</body>
</html>
"""


BOARDS = {
    "tA2d-runs-link.dc.html": phone_board("Runs · A: text link", PHONE_MORE_A, {"later": False, "older": 2}, 1000, on_rail=False),
    "tA2d-runs-rail.dc.html": phone_board("Runs · B: row on the timeline", PHONE_MORE_B, {"later": False, "older": 2}, 1000),
    "tA2d-runs-button.dc.html": phone_board("Runs · C: button", PHONE_MORE_C, {"later": False, "older": 2}, 1000),
    "tA2d-runs-rail-open.dc.html": phone_board("Runs · B, both groups opened once", PHONE_MORE_B, {"later": True, "older": 12}, 1760),
    "dA2-runs-rail.dc.html": desk_board(),
    "tA2d-model-pill.dc.html": pill_board(),
}

for name, html in BOARDS.items():
    with open(os.path.join(PROJ, name), "w") as f:
        f.write(html)
    print("wrote", name, len(html))
