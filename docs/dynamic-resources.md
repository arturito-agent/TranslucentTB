# Dynamic resource comparison

One of nine position/workload combinations is complete. The first version,
backend selection and remaining static/interaction/changing comparisons are
still in progress. These results describe the existing Windows VM.

## Environment and method

Windows 11 LTSC 26100.8875; two logical CPUs, 6 GiB; Basic Display Adapter;
one 1280×800 SDR display at 100% scale; ExplorerPatcher 26100.8457.70.3 classic
taskbar. See [build identity](dynamic-builds.md) for the matched binaries.

Each repetition brackets both candidates with baselines, sharing the middle
baseline. The second repetition reverses API order. Every phase has 120 seconds
warmup and 305 seconds measured. Process observations run every five seconds;
a separate privileged DWM CPU observer runs every two seconds. Increment equals
candidate minus the mean of adjacent baselines. The original baseline uses
Opaque; the static fixture and Dynamic render the same RGB.

CPU is percent of one logical core: divide by two for this VM's total-CPU view.
Combined values include TranslucentTB, Explorer and DWM; workload, harness and
observers remain separate. Ranges show three repetitions, not a confidence
interval or causal guarantee. Negative process deltas are retained. Use Windows
QPC for durations; guest UTC timestamps were not synchronized with the host.

## Right taskbar, static content

All fifteen phases pass full validation: pinned hashes, exact geometry/DPI,
warmup/duration, owned exits, progressing sampler, correct RGB, unchanged capture
failure totals, matched GPU batches and separate DWM CPU coverage.

| Increment against baseline | GDI median [range] | DXGI median [range] |
| --- | --- | --- |
| Combined CPU, % of one core | 0.369 [0.226–0.384] | 0.091 [0.042–0.111] |
| Combined private commit, MiB | 0.723 [0.283–0.797] | 5.125 [3.051–8.451] |
| Application private commit, MiB | 0.176 [0.170–0.275] | 0.570 [0.557–0.574] |

| Absolute application footprint | GDI median | DXGI median |
| --- | --- | --- |
| Private commit, MiB | 9.203 | 9.602 |
| Working set, MiB | 12.586 | 13.330 |

DXGI's per-process shared GPU gauge is 3.906 MiB in all three candidate phases;
GDI's corresponding gauge is zero. These gauge observations must not be added
to private commit or summed across processes as physical allocations. Initial
invalid engine-rate batches remain explicitly unavailable.

GDI exceeds the initial 0.1%-of-one-core static CPU reference in all three
repetitions. DXGI's median is below it, but one repetition exceeds it. Both
application-only private increments are below 1 MiB; DXGI's combined system
increment extends above the initial 5 MiB memory reference. The remaining
positions/workloads must inform the final backend choice.

## Reproduce the analysis

- [Complete comparison JSON](dynamic-results/resource-right-static-e4f0.json).
- [Reviewed raw synthetic data](dynamic-results/resource-right-static-e4f0-data.zip),
  SHA-256 `1b3bd7718db5baf3db06a558a73a0594ab4df4ecdbf2750b7728d8cefa0e37ba`.

Extract the data and run from the source checkout:

```sh
python3 Tests/dynamic/compare.py /path/to/data/Right-Static --dwm-observer /path/to/data/dwm-right-static.csv
```

Only executable paths in builds.json are normalized to relative release folders;
measured CSV/GPU data and phase/exit receipts are unchanged. The normalized data
produces exactly the same comparison as the private collection. See the
[validation report](dynamic-validation.md) for physical-GPU, energy, display,
contrast and unavailable session/scaling limits.
