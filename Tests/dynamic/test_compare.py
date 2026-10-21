"""Require comparable, live, fully bracketed phases even when status says complete."""
import csv
import json
import tempfile
import unittest
from pathlib import Path

from compare import compare
from summarize import dwm_cpu


class ComparisonTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        builds = {name: {"commit": ("b" if name == "baseline" else "a")*40, "sha256": str(index)*64}
                  for index, name in enumerate(("baseline", "gdi", "dxgi"))}
        self.write_json("builds.json", builds)
        (self.root/"status.txt").write_text("complete")
        self.labels = []
        for repeat in range(1, 4):
            order = ("baseline", "gdi", "baseline", "dxgi", "baseline") if repeat % 2 else ("baseline", "dxgi", "baseline", "gdi", "baseline")
            for phase, backend in enumerate(order):
                label = f"Right-Static-r{repeat}-p{phase}-{backend}"
                self.labels.append(label)
                ordinal = (repeat-1)*5+phase
                start = 1000000+ordinal*500000
                pid = 100+ordinal
                receipt = {"label": label, "commit": builds[backend]["commit"],
                           "executable_sha256": builds[backend]["sha256"], "pid": pid,
                           "diagnostic_only": False, "warmup_seconds": 120, "duration_seconds": 305,
                           "start_qpc": start, "end_qpc": start+426000, "qpc_frequency": 1000, "gpu_enabled": False}
                self.write_json(label+".json", receipt)
                self.write_json(label+"-exit.json", {"action": "Exit", "pid": pid, "exited": True})
                rows = []
                for offset in (120000, 425000):
                    for role, process, owner in (("target", "TranslucentTB", pid), ("shell", "explorer", 2), ("compositor", "dwm", 3)):
                        seconds = (offset-120000)/1000
                        rate = 0.005 if backend == "gdi" and role == "target" else 0.01
                        rows.append({"label": label, "commit": builds[backend]["commit"], "role": role,
                                     "process": process, "pid": owner, "logical_processors": 2,
                                     "qpc_ticks": start+offset, "qpc_frequency": 1000,
                                     "taskbar_edge": "Right", "taskbar_dpi": 96, "taskbar_left": 1218,
                                     "taskbar_top": 0, "taskbar_right": 1280, "taskbar_bottom": 800,
                                     "errors": "", "cpu_seconds": 10+rate*seconds, "private_bytes": 1048576,
                                     "dynamic_stats_available": "True", "capture_stats_available": "True",
                                     "dynamic_timer": 1, "dynamic_paused": 0, "dynamic_rgb": 2121888,
                                     "captured_frames": 10+int(seconds)*2, "capture_failures": 0,
                                     "dynamic_samples": 10+int(seconds)*2})
                self.write_rows(label, rows)

    def write_json(self, name, value):
        (self.root/name).write_text(json.dumps(value))

    def write_rows(self, label, rows):
        with (self.root/(label+".csv")).open("w", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=rows[0])
            writer.writeheader()
            writer.writerows(rows)

    def test_complete_suite_preserves_negative_deltas_and_absolute_phases(self):
        result = compare(self.root, [])
        self.assertEqual(len(result["phase_summaries"]), 15)
        self.assertEqual(len(result["comparisons"]), 6)
        self.assertEqual(result["gpu_phase_summaries"], [])
        self.assertAlmostEqual(result["aggregates"]["gdi"]["combined_cpu_delta_one_core_percent"]["median"], -0.5)

    def test_rejects_corrupt_receipts_even_if_marked_complete(self):
        label = self.labels[1]
        path = self.root/(label+".json")
        original = path.read_text()
        for change in ({"executable_sha256": "f"*64}, {"pid": 999}, {"warmup_seconds": 121},
                       {"duration_seconds": 299}, {"end_qpc": 0}, {"diagnostic_only": True}):
            with self.subTest(change=change):
                receipt = json.loads(original)
                receipt.update(change)
                self.write_json(path.name, receipt)
                with self.assertRaises(ValueError):
                    compare(self.root, [])
        path.write_text(original)
        self.write_json(label+"-exit.json", {"action": "Exit", "pid": 101, "exited": False})
        with self.assertRaises(ValueError):
            compare(self.root, [])

    def test_rejects_stopped_sampler_and_geometry_changes(self):
        label = self.labels[1]
        with (self.root/(label+".csv")).open() as stream:
            original = list(csv.DictReader(stream))
        for field, value in (("dynamic_timer", "0"), ("dynamic_paused", "1"), ("dynamic_rgb", "0"),
                             ("captured_frames", "0"), ("capture_failures", "1"), ("taskbar_dpi", "120")):
            with self.subTest(field=field):
                rows = [dict(row) for row in original]
                rows[3][field] = value  # Target at the final observation.
                self.write_rows(label, rows)
                with self.assertRaises(ValueError):
                    compare(self.root, [])

    def test_rejects_mixed_candidate_revisions(self):
        manifest = json.loads((self.root/"builds.json").read_text())
        manifest["dxgi"]["commit"] = "c"*40
        self.write_json("builds.json", manifest)
        with self.assertRaises(ValueError):
            compare(self.root, [])

    def test_dwm_observer_must_match_the_measured_process(self):
        auxiliary = [{"role": "compositor", "pid": "99", "qpc_ticks": str(tick), "qpc_frequency": "1000", "cpu_seconds": str(tick/1000)}
                     for tick in (1000, 6000)]
        start = {"pid": "3", "qpc_ticks": "2000", "qpc_frequency": "1000"}
        end = {**start, "qpc_ticks": "5000"}
        with self.assertRaises(ValueError):
            dwm_cpu(auxiliary, start, end)


if __name__ == "__main__":
    unittest.main()
