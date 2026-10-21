"""Summarize native measurement CSVs without treating missing counters as zero."""
import argparse
import bisect
import csv
import json
from collections import Counter, defaultdict
from pathlib import Path
from statistics import median


def read(path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def number(row, field):
    value = row.get(field, "")
    return float(value) if value else None


def summarize(rows, diagnostic):
    rows = sorted(rows, key=lambda row: float(row["qpc_ticks"]))
    first, last = rows[0], rows[-1]
    duration = (float(last["qpc_ticks"]) - float(first["qpc_ticks"])) / float(first["qpc_frequency"])
    if duration < 300 and not diagnostic:
        raise ValueError("Measurement shorter than 300s; use --diagnostic for smoke data")
    result = {"pid": first["pid"], "process": first["process"], "role": first["role"],
              "samples": len(rows), "duration_seconds": duration,
              "errors": dict(Counter(row["errors"] for row in rows if row.get("errors")))}
    cpu_first, cpu_last = number(first, "cpu_seconds"), number(last, "cpu_seconds")
    cpu = None if cpu_first is None or cpu_last is None or duration <= 0 else 100 * (cpu_last - cpu_first) / duration
    if cpu is not None and cpu < 0:
        raise ValueError("CPU counter went backwards")
    result["cpu_one_core_percent"] = cpu
    result["cpu_normalized_percent"] = None if cpu is None else cpu / int(first["logical_processors"])
    for field in ("private_bytes", "working_set_bytes", "handles", "gdi_objects", "user_objects"):
        values = [number(row, field) for row in rows]
        available = [value for value in values if value is not None]
        quarter = max(1, len(available) // 4)
        result[field] = {"available_samples": len(available),
                         "median": median(available) if available else None,
                         "sampled_max": max(available) if available else None,
                         "last_minus_first": values[-1]-values[0] if values[-1] is not None and values[0] is not None else None,
                         "last_quarter_median_minus_first_quarter": median(available[-quarter:])-median(available[:quarter]) if available else None}
    for field in ("dynamic_samples", "dynamic_changes", "dynamic_applications", "captured_frames", "capture_timeouts", "capture_failures",
                  "fixture_animation_ticks", "fixture_paints"):
        start, end = number(first, field), number(last, field)
        result[field + "_per_second"] = None if start is None or end is None or duration <= 0 else (end - start) / duration
    return result


def dwm_cpu(auxiliary, start, end):
    """Interpolate cumulative CPU at common-QPC endpoints, with bounded gaps."""
    if start["pid"] != end["pid"] or start["qpc_frequency"] != end["qpc_frequency"]:
        raise ValueError("DWM endpoint identity or clock changed")
    rows = sorted((r for r in auxiliary if r.get("role") == "compositor" and r["pid"] == start["pid"] and
                   r["qpc_frequency"] == start["qpc_frequency"] and number(r, "cpu_seconds") is not None),
                  key=lambda r: int(r["qpc_ticks"]))
    ticks = [int(r["qpc_ticks"]) for r in rows]

    def at(tick):
        index = bisect.bisect_left(ticks, tick)
        if index < len(ticks) and ticks[index] == tick:
            return number(rows[index], "cpu_seconds")
        if index == 0 or index == len(ticks):
            raise ValueError("DWM observer does not bracket the measurement")
        a, b = rows[index-1], rows[index]
        gap = (ticks[index]-ticks[index-1]) / float(a["qpc_frequency"])
        if a["pid"] != b["pid"] or gap > 6:
            raise ValueError("DWM observer gap or process restart at endpoint")
        weight = (tick-ticks[index-1]) / (ticks[index]-ticks[index-1])
        return number(a, "cpu_seconds") + weight*(number(b, "cpu_seconds")-number(a, "cpu_seconds"))

    duration = (int(end["qpc_ticks"])-int(start["qpc_ticks"])) / float(start["qpc_frequency"])
    return {"cpu_one_core_percent": 100*(at(int(end["qpc_ticks"]))-at(int(start["qpc_ticks"])))/duration,
            "method": "linear interpolation of cumulative DWM CPU at common QPC endpoints; observer gaps <=6s"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="+", type=Path)
    parser.add_argument("--dwm-observer", type=Path)
    parser.add_argument("--diagnostic", action="store_true")
    args = parser.parse_args()
    auxiliary = read(args.dwm_observer) if args.dwm_observer else []
    result = {"diagnostic_only": args.diagnostic, "measurements": []}
    for path in args.files:
        rows = read(path)
        if not rows:
            raise ValueError(f"Empty file: {path}")
        if any(row["label"].startswith("SMOKE-") for row in rows) and not args.diagnostic:
            raise ValueError("SMOKE labels cannot be used as resource benchmark results")
        groups = defaultdict(list)
        for row in rows:
            groups[(row["label"], row["role"], row["pid"])].append(row)
        for (label, role, _), group in groups.items():
            item = {"label": label, "commit": group[0]["commit"], **summarize(group, args.diagnostic)}
            if role == "compositor" and auxiliary:
                ordered = sorted(group, key=lambda row: int(row["qpc_ticks"]))
                try:
                    item["separate_observer_cpu"] = dwm_cpu(auxiliary, ordered[0], ordered[-1])
                except ValueError as error:
                    item["separate_observer_error"] = str(error)
            result["measurements"].append(item)
    print(json.dumps(result, indent=2, allow_nan=False))


if __name__ == "__main__":
    main()
