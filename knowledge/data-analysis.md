# Dataset Analysis & Verification Protocol
Updated: 2026-05-14

This document defines the standard operating procedure for analyzing the impact of new upstream CSV data on the `ngc` tree structure and Nginx output. This should be run whenever new data is fetched with `./test/fetch-data.sh`.

## 1. High-Level Metrics Comparison
Before diving into the code, always compile the release binary and run it to get the raw numbers.
```bash
make release
/usr/bin/time -al ./zig-out/bin/ngc --ipv4 test/geo-whois-asn-country-ipv4-num.csv --ipv6 test/geo-whois-asn-country-ipv6-num.csv --output test/output.txt --static test/private.txt
```
Compare the output to the baseline (or previous run notes). Look specifically for:
*   **Inputs**: Did the database grow?
*   **Data Collisions**: A spike here means the upstream provider introduced new overlapping subnets.
*   **Routing Overrides**: Tells us how hard the Trie had to work to resolve those overlaps.
*   **Outputs (networks generated)**: Determines the final memory/file size impact for the Nginx module.

## 2. Output Churn Profiling
To understand *where* the tree is fragmenting the most, parse the output diff to find the countries with the highest churn.
```bash
# Find countries with the most newly generated network fragments
git diff test/output.txt | grep -E '^(\+|-)[a-fA-F0-9:]' | grep -v '^- ' | awk '{print $2}' | sort | uniq -c | sort -nr | head -n 20
```

## 3. Creating Readable Input Diffs
The raw CSV inputs are just large integers, making `git diff` impossible to read. Use Python to convert the diff into a readable IP format:

**test/analyze_diff.py** (Example for IPv6):
```python
import sys, ipaddress
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    action, rest = line[0], line[1:]
    if ',' in rest:
        start, end_and_cc = rest.split(',', 1)
        end, cc = end_and_cc.split(',', 1)
        print(f"{action} {str(ipaddress.IPv6Address(int(start)))} - {str(ipaddress.IPv6Address(int(end)))} {cc}")
```
Usage:
```bash
git diff test/geo-whois-asn-country-ipv6-num.csv | grep -E '^[-+][0-9]' | python3 test/analyze_diff.py > test/ipv6_diff_readable.txt
```

## 4. Extracting Topological Overlaps (The "Why")
`ngc` resolves overlaps silently. To find exactly *what* upstream overlapping data caused the `Data Collisions` to spike, use a topological sweep in Python:

**test/find_overlaps.py**:
```python
import ipaddress
ranges = []
with open("test/geo-whois-asn-country-ipv6-num.csv", "r") as f:
    for line in f:
        parts = line.strip().split(',')
        if len(parts) >= 3:
            ranges.append((int(parts[0]), int(parts[1]), parts[2]))

ranges.sort(key=lambda x: (x[0], -x[1])) # Sort start asc, end desc
active = []
overlaps = []
for start, end, cc in ranges:
    active = [a for a in active if a[1] >= start]
    for a_start, a_end, a_cc in active:
        if a_cc != cc:
            overlaps.append(((a_start, a_end, a_cc), (start, end, cc)))
            break
    active.append((start, end, cc))

for a, b in overlaps:
    print(f"Parent: {ipaddress.IPv6Address(a[0])} - {ipaddress.IPv6Address(a[1])} {a[2]}")
    print(f"Child:  {ipaddress.IPv6Address(b[0])} - {ipaddress.IPv6Address(b[1])} {b[2]}")
```
You can diff the outputs of this script between old and new git checkouts to isolate *exactly* which dirty ranges the upstream provider just introduced.

## 5. Known Anomaly Checks
Always search the readable diffs for historical anomalies to ensure they haven't regressed:
*   **GE/IE Endless Fragmentation**: Check if massive overlapping blocks are causing `/128` or `/32` cascades for specific countries (e.g. `grep -E "(GE|IE)$" test/ipv4_diff_readable.txt`).
*   **Upstream Cleanups**: Look for massive deletions (`-`) of nested `/64` holes being replaced by unified `/48` blocks.
