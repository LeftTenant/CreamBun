"""Summarize GUT (Godot Unit Test) run results into a compact, structured form.

`run_gut_tests` in mcp_server.py uses this so agents never have to parse free-form
GUT text (which previously pushed them to write throwaway shell/python scripts).

Primary input is GUT's JUnit XML export — a stable schema produced by
addons/gut/junit_xml_export.gd:

    <testsuites name="GutTests" failures="0" tests="175">
      <testsuite name="<script>" tests="30" failures="0" skipped="0" time="..">
        <testcase name=".." assertions="10" status="pass" classname=".." time="..">
        </testcase>
        <testcase name=".." status="fail" ..>
          <failure message="failed"><![CDATA[<first failing message>]]></failure>
        </testcase>
        <testcase name=".." status="pending" ..>
          <skipped message="pending"><![CDATA[<reason>]]></skipped>
        </testcase>
      </testsuite>
    </testsuites>

Notes baked into the parser:
  * `skipped` at the testsuite level == GUT's pending count.
  * Only the FIRST failing/pending message is in the XML; the complete detail
    lives in the saved raw log, which we always retain for the user.
  * `orphans` is not present in the XML — we supplement it from stdout when we can.

Stdout scraping (parse_stdout) is the fallback when the XML is missing or malformed
so we always return *something* rather than hiding results.

Stdlib only — no third-party dependencies.
"""

from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from dataclasses import asdict, dataclass, field

# Matches ANSI terminal escape sequences that GUT sprinkles through its output
# (colour/bold/underline like "\x1b[1m", "\x1b[33m", "\x1b[0m"). We match the full
# CSI form (ESC [ ... final-byte) so cursor/erase codes are caught too, not just
# the colour (SGR "m") ones. These render as colour in a terminal but as literal
# gibberish ("^[[33m") in an editor, so we strip them from human-facing output.
_ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")


@dataclass
class Failure:
    """One failing test: which script/test and the first failure message."""

    script: str
    test: str
    message: str


@dataclass
class Summary:
    """Structured roll-up of a GUT run. Counts plus the list of failures."""

    scripts: int = 0
    tests: int = 0
    passing: int = 0
    failing: int = 0
    pending: int = 0
    asserts: int = 0
    orphans: int = 0
    time: float = 0.0
    failures: list[Failure] = field(default_factory=list)
    # Where this summary came from: "junit_xml" (authoritative) or "stdout"
    # (best-effort fallback). Useful for debugging an unexpected result shape.
    source: str = "junit_xml"

    @property
    def passed(self) -> bool:
        # A run is "passed" when nothing failed. Pending/risky tests do not
        # fail the run (and GUT exits 0 for a pending-only run).
        return self.failing == 0

    @property
    def summary_text(self) -> str:
        """One-line human summary, e.g. '174/175 passed, 1 pending, 0 failing (0.70s)'."""
        return (
            f"{self.passing}/{self.tests} passed, "
            f"{self.pending} pending, {self.failing} failing "
            f"({self.time:.2f}s)"
        )

    def to_dict(self) -> dict:
        """JSON-safe dict (nested Failure dataclasses are expanded)."""
        return asdict(self)


def strip_ansi(text: str) -> str:
    """Remove ANSI terminal escape codes so the text is readable in a plain
    editor. GUT colourises its console output; those codes are noise outside a
    terminal. Used both before scraping stdout and before saving the raw log."""
    return _ANSI_RE.sub("", text)


def _scrape_int(text: str, pattern: str) -> int | None:
    """Return the first int captured by `pattern` (MULTILINE), or None."""
    match = re.search(pattern, text, re.MULTILINE)
    return int(match.group(1)) if match else None


def parse_junit_xml(path: str) -> Summary | None:
    """Parse GUT's JUnit XML at `path`. Return None if missing/unparseable.

    ElementTree resolves CDATA transparently, so `<failure>`/`<skipped>` text
    comes back as plain strings.
    """
    try:
        root = ET.parse(path).getroot()
    except (ET.ParseError, FileNotFoundError, OSError, ValueError):
        return None
    if root.tag != "testsuites":
        return None

    summary = Summary(source="junit_xml")
    summary.tests = int(root.get("tests", 0) or 0)
    summary.failing = int(root.get("failures", 0) or 0)

    suites = root.findall("testsuite")
    summary.scripts = len(suites)

    total_time = 0.0
    for suite in suites:
        summary.pending += int(suite.get("skipped", 0) or 0)
        total_time += float(suite.get("time", 0) or 0)
        suite_name = suite.get("name", "")
        for case in suite.findall("testcase"):
            summary.asserts += int(case.get("assertions", 0) or 0)
            if case.get("status") == "fail":
                fail_el = case.find("failure")
                message = (fail_el.text or "").strip() if fail_el is not None else ""
                summary.failures.append(
                    Failure(
                        script=case.get("classname", suite_name),
                        test=case.get("name", ""),
                        message=message,
                    )
                )

    summary.time = round(total_time, 3)
    # Derive passing rather than trusting a separate attribute; keeps the four
    # counts internally consistent even if GUT's schema shifts.
    summary.passing = summary.tests - summary.failing - summary.pending
    return summary


def parse_stdout(raw: str) -> Summary:
    """Fallback summary scraped from GUT's stdout 'Totals' block.

    Less precise than the XML (failure attribution is best-effort) but always
    available. Used only when the JUnit XML could not be read.
    """
    text = strip_ansi(raw)
    summary = Summary(source="stdout")

    summary.scripts = _scrape_int(text, r"^\s*Scripts\s+(\d+)") or 0
    summary.tests = _scrape_int(text, r"^\s*Tests\s+(\d+)") or 0
    summary.passing = _scrape_int(text, r"^\s*Passing Tests\s+(\d+)") or 0
    summary.pending = _scrape_int(text, r"^\s*Risky/Pending\s+(\d+)") or 0
    summary.asserts = _scrape_int(text, r"^\s*Asserts\s+(\d+)") or 0
    summary.orphans = _scrape_int(text, r"^\s*Orphans\s+(\d+)") or 0

    time_match = re.search(r"^\s*Time\s+([\d.]+)s", text, re.MULTILINE)
    summary.time = float(time_match.group(1)) if time_match else 0.0

    # Failing = whatever the totals don't account for. GUT does not print a
    # clean per-test failure list we can rely on here, so we record the count
    # and leave detailed attribution to the retained raw log.
    summary.failing = max(summary.tests - summary.passing - summary.pending, 0)
    return summary


def summarize(xml_path: str | None, raw_stdout: str) -> Summary:
    """Build a Summary, preferring the JUnit XML and falling back to stdout.

    When the XML parses, we still scrape `orphans` from stdout because the XML
    schema omits it.
    """
    summary = parse_junit_xml(xml_path) if xml_path else None
    if summary is not None:
        orphans = _scrape_int(strip_ansi(raw_stdout), r"^\s*Orphans\s+(\d+)")
        if orphans is not None:
            summary.orphans = orphans
        return summary
    return parse_stdout(raw_stdout)


def render_markdown(summary: Summary, log_relpath: str = "latest.log") -> str:
    """Render `summary` as a human-friendly Markdown report."""
    badge = "✅ PASS" if summary.passed else "❌ FAIL"
    lines = [
        f"# GUT Test Report — {badge}",
        "",
        summary.summary_text,
        "",
        "| Metric | Count |",
        "| --- | --- |",
        f"| Scripts | {summary.scripts} |",
        f"| Tests | {summary.tests} |",
        f"| Passing | {summary.passing} |",
        f"| Failing | {summary.failing} |",
        f"| Pending | {summary.pending} |",
        f"| Asserts | {summary.asserts} |",
        f"| Orphans | {summary.orphans} |",
        f"| Time | {summary.time:.3f}s |",
        "",
    ]

    if summary.failures:
        lines += ["## Failures", ""]
        for fail in summary.failures:
            lines += [
                f"### {fail.script} → `{fail.test}`",
                "",
                "```",
                fail.message or "(no message captured — see full log)",
                "```",
                "",
            ]

    lines += ["---", f"Full output: `{log_relpath}`", ""]
    return "\n".join(lines)
