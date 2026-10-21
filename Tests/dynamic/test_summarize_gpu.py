"""Check missing counters, process scope and timing against synthetic PDH records."""
import csv
import json
import tempfile
import unittest
from pathlib import Path

from summarize_gpu import summarize_gpu


class GpuSummaryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.csv = Path(self.directory.name) / "phase.csv"
        scope = [{"pid": 42, "role": "target", "process": "TranslucentTB"},
                 {"pid": 43, "role": "observer", "process": "powershell"}]
        rows = [{"qpc_ticks": tick, "qpc_frequency": 1000, "label": "fixture", "commit": "synthetic", **owner}
                for tick in (10000, 15000) for owner in scope]
        with self.csv.open("w", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=rows[0])
            writer.writeheader()
            writer.writerows(rows)
        self.records = []
        for tick in (10000, 15000):
            self.records.append({"label": "fixture", "commit": "synthetic", "qpc_begin": tick+1,
                                 "qpc_end": tick+2, "qpc_frequency": 1000, "read_ms": 1,
                                 "scope": scope, "entries": [self.entry("dedicated_bytes", 0)]})
        self.records[0]["entries"].extend([
            {"kind": "engine_percent", "instance": "", "status": 3221228474,
             "value": None, "pid": None, "role": None},
            self.entry("shared_bytes", 0)])
        self.records[1]["entries"].append(self.entry("engine_percent", 0.25, "_eng_0_engtype_3D"))

    @staticmethod
    def entry(kind, value, suffix=""):
        return {"kind": kind, "instance": "pid_42_luid_synthetic_phys_0"+suffix,
                "status": 0, "value": value, "pid": 42, "role": "target"}

    def summarize(self):
        Path(str(self.csv)+".gpu.jsonl").write_text("\n".join(map(json.dumps, self.records)))
        return summarize_gpu(self.csv)

    def test_missing_is_not_zero_and_engines_remain_distinct(self):
        result = self.summarize()
        instances = {item["kind"]: item for item in result["instances"]}
        self.assertEqual(instances["dedicated_bytes"]["median"], 0)
        self.assertEqual(instances["shared_bytes"]["absent_batches"], 1)
        self.assertEqual(instances["engine_percent"]["valid_batches"], 1)
        self.assertEqual(instances["engine_percent"]["median"], 0.25)
        self.assertEqual(result["provider_errors"][0]["batches"], 1)
        observer = [item for item in result["coverage"] if item["role"] == "observer"]
        self.assertTrue(all(item["batches_with_instances"] == 0 for item in observer))
        self.records[1]["entries"].append(self.entry("engine_percent", 0.75, "_eng_1_engtype_3D"))
        engines = [item for item in self.summarize()["instances"] if item["kind"] == "engine_percent"]
        self.assertEqual(len(engines), 2)
        self.assertEqual([item["median"] for item in engines], [0.25, 0.75])

    def test_invalid_counter_value_remains_missing(self):
        entry = self.records[0]["entries"][0]
        entry.update(status=13, value=None)
        dedicated = next(item for item in self.summarize()["instances"] if item["kind"] == "dedicated_bytes")
        self.assertEqual(dedicated["invalid_batches"], 1)
        self.assertEqual(dedicated["valid_batches"], 1)

    def test_rejects_mismatched_or_corrupt_records(self):
        mutations = [lambda item: item.update(label="other"),
                     lambda item: item.update(commit="other"),
                     lambda item: item.update(qpc_end=15000),
                     lambda item: item["scope"].append({"pid": 99, "role": "target", "process": "other"}),
                     lambda item: item["entries"][0].update(pid=99),
                     lambda item: item["entries"][0].update(status=13),
                     lambda item: item["entries"].append(item["entries"][0])]
        original = json.dumps(self.records)
        for mutate in mutations:
            with self.subTest(mutation=mutate):
                self.records = json.loads(original)
                mutate(self.records[0])
                with self.assertRaises(ValueError):
                    self.summarize()
        self.records = json.loads(original)[:-1]
        with self.assertRaises(ValueError):
            self.summarize()


if __name__ == "__main__":
    unittest.main()
