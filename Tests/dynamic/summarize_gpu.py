"""Summarize scoped GPU observations, preserving engine identity and missing data."""
import argparse
import json
import math
import re
from collections import Counter, defaultdict
from pathlib import Path
from statistics import median

from summarize import read


KINDS = ("engine_percent", "dedicated_bytes", "shared_bytes")
INSTANCE = re.compile(r"^pid_([0-9]+)_(.+)$")


def summarize_gpu(csv_path):
    rows = read(csv_path)
    if not rows:
        raise ValueError("Empty CPU observation file")
    identity = (rows[0]["label"], rows[0]["commit"], rows[0]["qpc_frequency"])
    if any((row["label"], row["commit"], row["qpc_frequency"]) != identity for row in rows):
        raise ValueError("Mixed CPU phase identities or clock frequencies")
    batches = defaultdict(list)
    for row in rows:
        batches[int(row["qpc_ticks"])].append(row)
    ticks = sorted(batches)
    path = Path(str(csv_path) + ".gpu.jsonl")
    records = [json.loads(line) for line in path.read_text(encoding="utf-8-sig").splitlines() if line.strip()]
    if len(records) != len(ticks):
        raise ValueError("GPU and CPU observation counts differ")
    samples = defaultdict(dict)
    scopes = defaultdict(set)
    errors = Counter()
    read_ms = []
    for index, (tick, record) in enumerate(zip(ticks, records)):
        batch = batches[tick]
        first = batch[0]
        if record["label"] != first["label"] or record["commit"] != first["commit"]:
            raise ValueError("GPU label/commit does not match CPU observations")
        if (record["qpc_frequency"] != int(first["qpc_frequency"]) or
                record["qpc_begin"] < tick or record["qpc_end"] < record["qpc_begin"] or
                (index + 1 < len(ticks) and record["qpc_end"] >= ticks[index + 1])):
            raise ValueError("GPU observation is outside its CPU sampling batch")
        expected = {int(row["pid"]): (row["role"], row["process"]) for row in batch}
        actual = {item["pid"]: (item["role"], item["process"]) for item in record["scope"]}
        if actual != expected or len(actual) != len(record["scope"]):
            raise ValueError("GPU process scope differs from CPU observations")
        for pid, (role, _) in expected.items():
            scopes[(role, pid)].add(index)
        read_ms.append(record["read_ms"])
        seen = set()
        for entry in record["entries"]:
            kind, instance = entry["kind"], entry["instance"]
            value, status = entry["value"], entry["status"]
            if value is not None and (status not in (0, 1) or not math.isfinite(value)):
                raise ValueError("Invalid PDH status/value pair")
            if not instance:
                if (kind not in (*KINDS, "query") or value is not None or
                        entry["pid"] is not None or entry["role"] is not None):
                    raise ValueError("Provider error contains a process value")
                errors[(kind, status)] += 1
                continue
            match = INSTANCE.fullmatch(instance)
            pid = entry["pid"]
            if (kind not in KINDS or not match or int(match[1]) != pid or
                    pid not in expected or entry["role"] != expected[pid][0]):
                raise ValueError("GPU entry has an unknown counter or process owner")
            key = (entry["role"], pid, kind, match[2])
            if key in seen:
                raise ValueError("Duplicate GPU instance in a sampling batch")
            seen.add(key)
            samples[key][index] = (value, status)
    summaries = []
    for (role, pid, kind, instance), observations in sorted(samples.items()):
        values = [value for value, _ in observations.values() if value is not None]
        scoped_count = len(scopes[(role, pid)])
        summaries.append({"role": role, "pid": pid, "kind": kind, "instance_without_pid": instance,
                          "scoped_batches": scoped_count, "present_batches": len(observations),
                          "valid_batches": len(values), "absent_batches": scoped_count-len(observations),
                          "invalid_batches": len(observations)-len(values),
                          "statuses": dict(Counter(str(status) for _, status in observations.values())),
                          "median": median(values) if values else None,
                          "minimum": min(values) if values else None,
                          "sampled_max": max(values) if values else None})
    coverage = []
    for (role, pid), indices in sorted(scopes.items()):
        for kind in KINDS:
            present, valid = set(), set()
            for (sample_role, sample_pid, sample_kind, _), observations in samples.items():
                if (sample_role, sample_pid, sample_kind) == (role, pid, kind):
                    present.update(observations)
                    valid.update(index for index, (value, _) in observations.items() if value is not None)
            coverage.append({"role": role, "pid": pid, "kind": kind, "scoped_batches": len(indices),
                             "batches_with_instances": len(present), "batches_with_valid_instances": len(valid)})
    return {"label": rows[0]["label"], "commit": rows[0]["commit"], "batches": len(records),
            "read_ms": {"median": median(read_ms), "sampled_max": max(read_ms)},
            "provider_errors": [{"kind": kind, "status": status, "batches": count}
                                for (kind, status), count in sorted(errors.items())],
            "coverage": coverage, "instances": summaries,
            "limits": ["Statistics use valid observations only; absent/invalid counters are counted separately and never replaced with zero.",
                       "Each engine/adapter instance remains separate; percentages are not summed into total GPU utilization.",
                       "Per-process GPU memory can share physical allocations. Do not sum processes or add these counters to private commit.",
                       "An absent process counter does not establish zero GPU use. Sampled maxima are not continuous peaks."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv", type=Path)
    args = parser.parse_args()
    print(json.dumps(summarize_gpu(args.csv), indent=2, allow_nan=False))


if __name__ == "__main__":
    main()
