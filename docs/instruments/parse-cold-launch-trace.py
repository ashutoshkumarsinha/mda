#!/usr/bin/env python3
"""Extract cold_launch_to_editor duration (ms) from trace and/or benchmark result file."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SIGNPOST_NAME = "cold_launch_to_editor"
SUBSYSTEM = "name.aks.mde"


def read_result_file(path: Path) -> float | None:
    if not path.is_file():
        return None
    try:
        return float(path.read_text(encoding="utf-8").strip())
    except ValueError:
        return None


def export_trace_xml(trace_path: Path) -> str:
    result = subprocess.run(
        ["xcrun", "xctrace", "export", "--input", str(trace_path), "--toc"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return ""
    return result.stdout


def export_signpost_intervals(trace_path: Path) -> str:
    result = subprocess.run(
        [
            "xcrun",
            "xctrace",
            "export",
            "--input",
            str(trace_path),
            "--xpath",
            '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost-interval"]',
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return ""
    return result.stdout


def parse_duration_ms_from_xml(xml_text: str) -> float | None:
    if not xml_text.strip():
        return None

    durations_ns: list[int] = []

    for match in re.finditer(
        r'cold_launch_to_editor[^>]*\bduration="(\d+)"',
        xml_text,
        flags=re.IGNORECASE,
    ):
        durations_ns.append(int(match.group(1)))

    for match in re.finditer(
        r'<name>cold_launch_to_editor</name>\s*<duration>(\d+)</duration>',
        xml_text,
        flags=re.IGNORECASE,
    ):
        durations_ns.append(int(match.group(1)))

    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        root = None

    if root is not None:
        for elem in root.iter():
            attrs = {k.lower(): v for k, v in elem.attrib.items()}
            text = (elem.text or "").strip()
            name = attrs.get("name", "") or attrs.get("signpost-name", "") or text
            if SIGNPOST_NAME not in name and SIGNPOST_NAME not in text:
                continue
            if attrs.get("subsystem", SUBSYSTEM) not in ("", SUBSYSTEM):
                continue
            for key in ("duration", "duration-ns", "elapsed"):
                if key in attrs:
                    try:
                        durations_ns.append(int(float(attrs[key])))
                    except ValueError:
                        pass
            duration_child = elem.find("duration")
            if duration_child is not None and duration_child.text:
                try:
                    durations_ns.append(int(float(duration_child.text.strip())))
                except ValueError:
                    pass

    if not durations_ns:
        return None

    max_ns = max(durations_ns)
    if max_ns > 1_000_000:
        return max_ns / 1_000_000.0
    return float(max_ns)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path, nargs="?", help="Path to .trace bundle")
    parser.add_argument(
        "--result-file",
        type=Path,
        help="Benchmark result file written by the app (milliseconds)",
    )
    parser.add_argument(
        "--budget-ms",
        type=float,
        default=2000.0,
        help="NFR-02 budget in milliseconds (default: 2000)",
    )
    parser.add_argument(
        "--tolerance",
        type=float,
        default=1.10,
        help="Allowed over-budget multiplier (default: 1.10)",
    )
    args = parser.parse_args()

    duration_ms: float | None = None
    source = "unknown"

    if args.result_file:
        duration_ms = read_result_file(args.result_file)
        if duration_ms is not None:
            source = "result_file"

    if duration_ms is None and args.trace and args.trace.exists():
        interval_xml = export_signpost_intervals(args.trace)
        duration_ms = parse_duration_ms_from_xml(interval_xml)
        if duration_ms is not None:
            source = "trace_interval"

    if duration_ms is None and args.trace and args.trace.exists():
        toc_xml = export_trace_xml(args.trace)
        duration_ms = parse_duration_ms_from_xml(toc_xml)
        if duration_ms is not None:
            source = "trace_toc"

    if duration_ms is None:
        print(
            "Could not determine cold_launch_to_editor duration. "
            "Ensure -benchmarkColdLaunch is set and -benchmarkColdLaunchResultPath (or MDE_COLD_LAUNCH_RESULT_PATH) is passed, "
            "or enable subsystem name.aks.mde in Instruments os_signpost.",
            file=sys.stderr,
        )
        return 3

    ceiling = args.budget_ms * args.tolerance
    status = "PASS" if duration_ms <= ceiling else "FAIL"
    print(f"cold_launch_to_editor_ms={duration_ms:.2f}")
    print(f"source={source}")
    print(f"budget_ms={args.budget_ms:.2f}")
    print(f"ceiling_ms={ceiling:.2f}")
    print(f"status={status}")

    return 0 if status == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
