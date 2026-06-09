"""Unit tests for gut_report — the GUT result summarizer.

Run from the server dir with stdlib unittest (no third-party deps):

    cd plugins/godot-testing/server && python3 -m unittest discover tests

Fixtures are real GUT output shapes (JUnit XML per addons/gut/junit_xml_export.gd,
stdout per a real headless run).
"""

import os
import sys
import tempfile
import unittest

# Import gut_report from the parent (server/) directory.
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import gut_report  # noqa: E402


# A passing-with-one-pending run (mirrors the real schema: testsuites/testsuite/
# testcase, pending -> <skipped>, per-testcase assertions).
PASSING_XML = """<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="GutTests" failures="0" tests="4" >
  <testsuite name="tests/unit/test_a.gd" tests="3" failures="0" skipped="1" time="0.010000" >
      <testcase name="test_one" assertions="2" status="pass" classname="tests/unit/test_a.gd" time="0.001" >
      </testcase>
      <testcase name="test_two" assertions="5" status="pass" classname="tests/unit/test_a.gd" time="0.002" >
      </testcase>
      <testcase name="test_pending" assertions="1" status="pending" classname="tests/unit/test_a.gd" time="0.003" >
      <skipped message="pending"><![CDATA[headless skip reason]]></skipped></testcase>
  </testsuite>
  <testsuite name="tests/unit/test_b.gd" tests="1" failures="0" skipped="0" time="0.004000" >
      <testcase name="test_three" assertions="3" status="pass" classname="tests/unit/test_b.gd" time="0.004" >
      </testcase>
  </testsuite>
</testsuites>"""

# A run with one failure.
FAILING_XML = """<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="GutTests" failures="1" tests="2" >
  <testsuite name="tests/unit/test_c.gd" tests="2" failures="1" skipped="0" time="0.020000" >
      <testcase name="test_ok" assertions="1" status="pass" classname="tests/unit/test_c.gd" time="0.001" >
      </testcase>
      <testcase name="test_bad" assertions="1" status="fail" classname="tests/unit/test_c.gd" time="0.002" >
      <failure message="failed"><![CDATA[Expected [3] to equal [4]]]></failure></testcase>
  </testsuite>
</testsuites>"""

# Real stdout 'Totals' block (ANSI stripped for readability; the parser strips
# ANSI itself, so an escape is included on one line to exercise that path).
STDOUT_SAMPLE = (
    "* test_something\n"
    "\x1b[1m4/4 passed.\x1b[0m\n"
    "Totals\n"
    "------\n"
    "Scripts              18\n"
    "Tests               175\n"
    "Passing Tests       174\n"
    "Risky/Pending         1\n"
    "Asserts             384\n"
    "Orphans             163\n"
    "Time              0.698s\n"
)


class TestParseJunitXml(unittest.TestCase):
    def _write(self, content: str) -> str:
        fd, path = tempfile.mkstemp(suffix=".xml")
        with os.fdopen(fd, "w") as handle:
            handle.write(content)
        self.addCleanup(os.remove, path)
        return path

    def test_passing_counts(self):
        s = gut_report.parse_junit_xml(self._write(PASSING_XML))
        self.assertIsNotNone(s)
        self.assertTrue(s.passed)
        self.assertEqual(s.scripts, 2)
        self.assertEqual(s.tests, 4)
        self.assertEqual(s.failing, 0)
        self.assertEqual(s.pending, 1)
        self.assertEqual(s.passing, 3)  # 4 - 0 failing - 1 pending
        self.assertEqual(s.asserts, 11)  # 2 + 5 + 1 + 3
        self.assertEqual(s.failures, [])

    def test_failing_extracts_failure_detail(self):
        s = gut_report.parse_junit_xml(self._write(FAILING_XML))
        self.assertIsNotNone(s)
        self.assertFalse(s.passed)
        self.assertEqual(s.failing, 1)
        self.assertEqual(s.passing, 1)
        self.assertEqual(len(s.failures), 1)
        fail = s.failures[0]
        self.assertEqual(fail.test, "test_bad")
        self.assertEqual(fail.script, "tests/unit/test_c.gd")
        self.assertIn("Expected [3] to equal [4]", fail.message)

    def test_missing_file_returns_none(self):
        self.assertIsNone(gut_report.parse_junit_xml("/no/such/file.xml"))

    def test_malformed_xml_returns_none(self):
        self.assertIsNone(gut_report.parse_junit_xml(self._write("<not-xml")))


class TestParseStdout(unittest.TestCase):
    def test_totals_block_scraped(self):
        s = gut_report.parse_stdout(STDOUT_SAMPLE)
        self.assertEqual(s.source, "stdout")
        self.assertEqual(s.scripts, 18)
        self.assertEqual(s.tests, 175)
        self.assertEqual(s.passing, 174)
        self.assertEqual(s.pending, 1)
        self.assertEqual(s.asserts, 384)
        self.assertEqual(s.orphans, 163)
        self.assertAlmostEqual(s.time, 0.698, places=3)
        self.assertEqual(s.failing, 0)  # 175 - 174 - 1
        self.assertTrue(s.passed)

    def test_empty_output_does_not_crash(self):
        s = gut_report.parse_stdout("")
        self.assertEqual(s.tests, 0)
        self.assertEqual(s.failing, 0)


class TestSummarize(unittest.TestCase):
    def _write(self, content: str) -> str:
        fd, path = tempfile.mkstemp(suffix=".xml")
        with os.fdopen(fd, "w") as handle:
            handle.write(content)
        self.addCleanup(os.remove, path)
        return path

    def test_prefers_xml_and_supplements_orphans_from_stdout(self):
        # XML has no orphans; stdout does. summarize() should merge them.
        s = gut_report.summarize(self._write(PASSING_XML), STDOUT_SAMPLE)
        self.assertEqual(s.source, "junit_xml")
        self.assertEqual(s.tests, 4)        # from XML, not stdout's 175
        self.assertEqual(s.orphans, 163)    # supplemented from stdout

    def test_falls_back_to_stdout_when_xml_absent(self):
        s = gut_report.summarize(None, STDOUT_SAMPLE)
        self.assertEqual(s.source, "stdout")
        self.assertEqual(s.tests, 175)

    def test_falls_back_to_stdout_when_xml_unreadable(self):
        s = gut_report.summarize("/no/such.xml", STDOUT_SAMPLE)
        self.assertEqual(s.source, "stdout")
        self.assertEqual(s.tests, 175)


class TestStripAnsi(unittest.TestCase):
    def test_removes_colour_and_style_codes(self):
        raw = "\x1b[1mBold\x1b[0m \x1b[33myellow warning\x1b[0m plain"
        self.assertEqual(gut_report.strip_ansi(raw), "Bold yellow warning plain")

    def test_removes_underline_and_other_csi(self):
        # Underline (4m), erase-line (K), cursor-up (A) — all CSI sequences.
        self.assertEqual(gut_report.strip_ansi("\x1b[4mU\x1b[K\x1b[2A done"), "U done")

    def test_plain_text_unchanged(self):
        self.assertEqual(gut_report.strip_ansi("no escapes here"), "no escapes here")

    def test_real_gut_line(self):
        # A representative coloured GUT line (bold "30/30 passed.").
        self.assertEqual(
            gut_report.strip_ansi("\x1b[1m30/30 passed.\n\x1b[0m"),
            "30/30 passed.\n",
        )


class TestRenderMarkdown(unittest.TestCase):
    def test_pass_report_has_badge_and_counts(self):
        s = gut_report.parse_stdout(STDOUT_SAMPLE)
        md = gut_report.render_markdown(s, "latest.log")
        self.assertIn("✅ PASS", md)
        self.assertIn("| Tests | 175 |", md)
        self.assertIn("Full output: `latest.log`", md)

    def test_fail_report_lists_failing_tests(self):
        fd, path = tempfile.mkstemp(suffix=".xml")
        with os.fdopen(fd, "w") as handle:
            handle.write(FAILING_XML)
        self.addCleanup(os.remove, path)
        s = gut_report.parse_junit_xml(path)
        md = gut_report.render_markdown(s)
        self.assertIn("❌ FAIL", md)
        self.assertIn("test_bad", md)
        self.assertIn("Expected [3] to equal [4]", md)


if __name__ == "__main__":
    unittest.main()
