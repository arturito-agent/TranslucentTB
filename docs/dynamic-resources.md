# Dynamic resource comparison

GDI is selected for the first version using the existing approximate VM
measurements. On 2026-10-21 the owner accepted this precision and requested no
further resource measurements. The remaining matrix was intentionally stopped;
it is not presented as a completed nine-condition comparison. Final package
verification and publication are still pending.

GDI uses roughly 9 MiB of application private commit in the observed static and
changing phases. DXGI has lower static CPU, but higher observed system memory
and substantially higher DWM CPU with changing content. This supports choosing
the simpler GDI backend for this experimental VM release; it does not establish
universal efficiency or measurements for every taskbar position/workload.

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
increment extends above the initial 5 MiB memory reference. The owner accepted these approximations alongside the changing-content evidence
below to choose GDI, without extending the matrix.

## Right taskbar, changing content — one complete repetition

One complete five-phase repetition brackets GDI and DXGI with the original
baseline. Each phase has 120 seconds warmup and 305 seconds measured. Pinned
builds, full phase timing, real geometry/DPI, progressing fixture/capture/color
counters, matched GPU scopes, separate DWM CPU and graceful exits were checked.
The incomplete later repetition is not used for the table below.

| Increment against baseline | GDI | DXGI |
| --- | --- | --- |
| Combined CPU, % of one core | about 0.15 | about 1.79 |
| DWM CPU, % of one core | about 0.10 | about 1.60 |
| Combined private commit, MiB | about -0.80 | about 3.80 |
| Application private commit, MiB | about 0.17 | about 0.58 |

Absolute application private-commit medians are about 9.14 MiB for GDI and
9.55 MiB for DXGI; working sets are about 12.58 and 13.05 MiB. Negative bracketed
memory differences reflect observed baseline/process variation, not negative
allocations. These are single-repetition estimates, not a precision guarantee.
DWM stayed elevated throughout the DXGI interval and returned near its preceding
baseline afterward; diagnostic subintervals are not independent repetitions.

## Interpretation and limits

GDI exceeds the initial static CPU engineering reference of 0.1% of one core.
The observed cost remains small in absolute VM terms, but the initial target
must not be reported as passed. Application-only private-memory increments are
below 1 MiB in the observed cases. Existing multi-position functional tests
establish operation and movement; they do not establish per-position CPU/RAM.
No new 60-minute formal stability result, full interaction matrix, physical-GPU
energy result, or statistical latency claim is asserted.

## Reproduce the analysis

The changing-content estimate is available as a [single-repetition comparison](dynamic-results/resource-right-changing-r1-e4f0.json)
and [reviewed raw data](dynamic-results/resource-right-changing-r1-e4f0-data.zip)
(SHA-256 `559d0ef6137266497aa763961970c02105664e6273ed5b20aaea48f08f155e74`). To reproduce its individual phase summaries:

```sh
python3 Tests/dynamic/summarize.py /path/to/data/Right-Changing-r1/*.csv --dwm-observer /path/to/data/dwm-right-changing-r1.csv
```

For each role, subtract the average of adjacent baseline phase summaries from
the candidate (phases 1 and 3), then sum target, shell and compositor CPU/private
commit. This is one complete repetition; the stricter full-suite comparator
continues to require all fifteen phases and must not be used to label this data
as a complete three-repeat suite.


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
