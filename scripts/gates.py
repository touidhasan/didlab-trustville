#!/usr/bin/env python3
"""
The market-standard gates. See docs/STANDARD.md for what they mean and why.

    python3 scripts/gates.py natspec   [--all]   every external member documented
    python3 scripts/gates.py coverage  [--all]   lines / branches / functions floors
    python3 scripts/gates.py slither   [--all]   no Low+ findings without a written reason
    python3 scripts/gates.py list                which contracts are held to the standard

THE RATCHET. A gate that fails on day one for twenty-five contracts is a gate everyone
learns to ignore — which is exactly what happened to the old secrets check. So these gates
are strict only for contracts listed in contracts/hardened.txt. A module's hardening pull
request adds its contracts to that file; from then on CI holds them to the standard and
they cannot slide back. Everything else is reported, not enforced.

`--all` reports on every contract without failing, which is how you see the road ahead.

Run from anywhere; everything is resolved relative to the repository.
"""
import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONTRACTS = os.path.join(ROOT, "contracts")
HARDENED = os.path.join(CONTRACTS, "hardened.txt")

# ---------------------------------------------------------------------- thresholds
#
# Chosen from the baseline on 2026-09-29, not from a blog post. The whole project stood at
# 88.9% lines and 46.8% branches; the most carefully tested contract (PrivacyLab) at 100%
# and 86.7%. Branch coverage is the one that matters — an untested `else` is where the
# money leaves — and 85% is demanding without rewarding tests written only to move a number.
LINES_MIN = 95.0
BRANCHES_MIN = 85.0
FUNCTIONS_MIN = 100.0

# Members inherited from OpenZeppelin that carry no NatSpec upstream. We cannot document
# code we do not own without forking it, so these are exempt BY NAME. Anything declared in
# our own src/ has no such excuse — including our overrides of these, which take @inheritdoc.
INHERITED_UNDOCUMENTED = {
    "DEFAULT_ADMIN_ROLE()": "AccessControl",
    "CANCELLER_ROLE()": "TimelockController",
    "EXECUTOR_ROLE()": "TimelockController",
    "PROPOSER_ROLE()": "TimelockController",
    "BALLOT_TYPEHASH()": "Governor",
    "EXTENDED_BALLOT_TYPEHASH()": "Governor",
    "onERC1155Received(address,address,uint256,uint256,bytes)": "TimelockController",
    "onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)": "TimelockController",
    "decimals()": "ERC20",
    "nonces(address)": "Nonces",
}

# Slither impacts that fail a hardened contract. Informational and Optimization findings are
# printed for the reviewer but do not block: naming-convention alone produces dozens, and a
# gate drowned in style advice stops being read.
BLOCKING_IMPACTS = {"High", "Medium", "Low"}

# A suppression without a reason is a finding with the evidence removed.
DISABLE_RE = re.compile(r"slither-disable-(next-line|line|start|end)\b(.*)")


def hardened():
    if not os.path.exists(HARDENED):
        return []
    names = []
    with open(HARDENED) as f:
        for raw in f:
            line = raw.split("#", 1)[0].strip()
            if line:
                names.append(line)
    return names


def all_contracts():
    src = os.path.join(CONTRACTS, "src")
    return sorted(f[:-4] for f in os.listdir(src) if f.endswith(".sol"))


def targets(report_all):
    return all_contracts() if report_all else hardened()


def forge_inspect(contract, field):
    out = subprocess.run(
        ["forge", "inspect", contract, field, "--json"],
        cwd=CONTRACTS, capture_output=True, text=True,
    )
    if out.returncode != 0:
        # Some forge versions do not accept --json for every field; retry without it.
        out = subprocess.run(
            ["forge", "inspect", contract, field],
            cwd=CONTRACTS, capture_output=True, text=True,
        )
    if out.returncode != 0:
        sys.exit(f"forge inspect {contract} {field} failed:\n{out.stderr}")
    return json.loads(out.stdout or "{}")


def nothing_to_do(gate):
    print(f"{gate}: no contracts are held to the standard yet (contracts/hardened.txt is empty).")
    print(f"{gate}: run with --all to see where every contract stands.")
    return 0


# -------------------------------------------------------------------------- natspec
def natspec(report_all):
    names = targets(report_all)
    if not names:
        return nothing_to_do("natspec")

    failures = 0
    for c in names:
        mi = forge_inspect(c, "methodIdentifiers")
        ud = forge_inspect(c, "userdoc")
        dd = forge_inspect(c, "devdoc")
        abi = forge_inspect(c, "abi")

        problems = []
        if not dd.get("title"):
            problems.append("no @title on the contract")
        if not ud.get("notice"):
            problems.append("no @notice on the contract")

        documented = set(ud.get("methods", {})) | set(dd.get("methods", {}))
        state_vars = set(dd.get("stateVariables", {}))
        for m in mi:
            if m in documented or m.split("(")[0] in state_vars or m in INHERITED_UNDOCUMENTED:
                continue
            problems.append(f"undocumented function  {m}")

        for kind in ("event", "error"):
            key = kind + "s"
            doc_names = {k.split("(")[0] for k in list(ud.get(key, {})) + list(dd.get(key, {}))}
            for item in abi:
                if item.get("type") == kind and item["name"] not in doc_names:
                    problems.append(f"undocumented {kind:8} {item['name']}")

        status = "ok" if not problems else f"{len(problems)} missing"
        print(f"natspec  {c:22} {status}")
        for p in problems:
            print(f"           {p}")
        if problems and not report_all:
            failures += 1

    return 1 if failures else 0


# ------------------------------------------------------------------------- coverage
def parse_lcov(path):
    files, cur = {}, None
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line.startswith("SF:"):
                cur = line[3:]
                files[cur] = {"LF": 0, "LH": 0, "BRF": 0, "BRH": 0, "FNF": 0, "FNH": 0}
            elif cur and ":" in line:
                k, v = line.split(":", 1)
                if k in files[cur]:
                    files[cur][k] = int(v)
    return files


def pct(hit, found):
    return 100.0 if found == 0 else 100.0 * hit / found


def coverage(report_all):
    names = targets(report_all)
    if not names:
        return nothing_to_do("coverage")

    lcov = os.path.join(CONTRACTS, "lcov.info")
    if not os.path.exists(lcov):
        sys.exit("coverage: contracts/lcov.info not found. Run first:\n"
                 "  (cd contracts && forge coverage --report lcov --no-match-coverage '(test|script|lib)/')")
    files = parse_lcov(lcov)

    failures = 0
    print(f"coverage floors: lines {LINES_MIN:.0f}%  branches {BRANCHES_MIN:.0f}%  functions {FUNCTIONS_MIN:.0f}%")
    for c in names:
        rel = f"src/{c}.sol"
        row = next((v for k, v in files.items() if k.endswith(rel)), None)
        if row is None:
            print(f"coverage {c:22} NOT MEASURED — no tests reach it")
            failures += 0 if report_all else 1
            continue
        lines = pct(row["LH"], row["LF"])
        branches = pct(row["BRH"], row["BRF"])
        funcs = pct(row["FNH"], row["FNF"])
        short = []
        if lines < LINES_MIN:
            short.append("lines")
        if branches < BRANCHES_MIN:
            short.append("branches")
        if funcs < FUNCTIONS_MIN:
            short.append("functions")
        mark = "ok" if not short else "below: " + ", ".join(short)
        print(f"coverage {c:22} lines {lines:6.2f}%  branches {branches:6.2f}%  functions {funcs:6.2f}%   {mark}")
        if short and not report_all:
            failures += 1
    return 1 if failures else 0


# -------------------------------------------------------------------------- slither
def slither(report_all):
    names = targets(report_all)
    if not names:
        return nothing_to_do("slither")

    report = os.path.join(CONTRACTS, "slither.json")
    if not os.path.exists(report):
        sys.exit("slither: contracts/slither.json not found. Run first:\n"
                 "  (cd contracts && slither . --json slither.json)")
    with open(report) as f:
        detectors = json.load(f).get("results", {}).get("detectors", [])

    wanted = {f"src/{c}.sol": c for c in names}
    failures = 0
    per = {c: [] for c in names}

    for r in detectors:
        path = None
        for e in r.get("elements", []):
            p = e.get("source_mapping", {}).get("filename_relative")
            if p:
                path = p
                break
        if path is None:
            continue
        for suffix, c in wanted.items():
            if path.endswith(suffix):
                per[c].append(r)

    for c in names:
        blocking = [r for r in per[c] if r["impact"] in BLOCKING_IMPACTS]
        info = [r for r in per[c] if r["impact"] not in BLOCKING_IMPACTS]

        # Every suppression in the file must say why.
        unexplained = []
        src_path = os.path.join(CONTRACTS, "src", f"{c}.sol")
        if os.path.exists(src_path):
            with open(src_path) as f:
                for n, line in enumerate(f, 1):
                    m = DISABLE_RE.search(line)
                    if m and m.group(1) != "end":
                        rest = m.group(2)
                        if "--" not in rest or not rest.split("--", 1)[1].strip():
                            unexplained.append(n)

        ok = not blocking and not unexplained
        print(f"slither  {c:22} {'ok' if ok else 'FAIL'}   "
              f"{len(blocking)} blocking, {len(info)} informational, {len(unexplained)} unexplained suppressions")
        for r in blocking:
            first = r["description"].strip().split("\n")[0]
            print(f"           [{r['impact']}] {r['check']}: {first[:140]}")
        for n in unexplained:
            print(f"           src/{c}.sol:{n}  slither-disable without '-- reason'")
        if not ok and not report_all:
            failures += 1

    return 1 if failures else 0


def main():
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        print(__doc__)
        return 0
    cmd, report_all = sys.argv[1], "--all" in sys.argv[2:]
    if cmd == "list":
        names = hardened()
        print("\n".join(names) if names else "(none yet)")
        return 0
    gates = {"natspec": natspec, "coverage": coverage, "slither": slither}
    if cmd not in gates:
        sys.exit(f"unknown gate {cmd!r}; one of: {', '.join(gates)}, list")
    return gates[cmd](report_all)


if __name__ == "__main__":
    sys.exit(main())
