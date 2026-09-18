#!/usr/bin/env python3
"""
run_regression.py - multi-seed regression driver for the AXI4-Lite-to-APB
bridge testbench (Vivado XSim). Compiles once, runs every test in
verification_plan.md section 4 across N seeds, merges functional coverage,
and prints a pass/fail table.

Usage:
    python run_regression.py
    python run_regression.py --tests test_smoke,test_wstrb --seeds 10
    python run_regression.py --seeds 50 --seed-start 1000

A run is a FAIL if: xsim exits non-zero, UVM_FATAL/UVM_ERROR count is
nonzero, or an SVA assertion fired (SVA uses $error, not `uvm_error, so it
never shows up in UVM's own report counts and has to be grepped separately).
"""

import argparse
import platform
import re
import subprocess
import sys
from pathlib import Path

# Windows Python's subprocess needs the .bat wrappers to run these tools
# directly (they are launcher scripts, not .exe); Git Bash's own bash/python
# resolves the extension-less names fine either way.
_BAT = ".bat" if platform.system() == "Windows" else ""
XVLOG = "xvlog" + _BAT
XELAB = "xelab" + _BAT
XSIM = "xsim" + _BAT
XCRG = "xcrg" + _BAT

SIM_DIR = Path(__file__).resolve().parent
RESULTS_DIR = SIM_DIR.parent / "results"
LOG_DIR = RESULTS_DIR / "logs"
COV_DIR = RESULTS_DIR / "cov"
COV_REPORT_DIR = RESULTS_DIR / "cov_report"

FILELIST = SIM_DIR / "filelist.f"
SNAPSHOT = "axi2apb_snap"

ALL_TESTS = [
    "test_smoke",
    "test_random_rw",
    "test_wait_state",
    "test_error_resp",
    "test_back2back",
    "test_wstrb",
    "test_backpressure",
    "test_reset_mid_txn",
    "test_idle",
    "test_stress",
]

UVM_ERROR_RE = re.compile(r"UVM_ERROR\s*:\s*(\d+)")
UVM_FATAL_RE = re.compile(r"UVM_FATAL\s*:\s*(\d+)")
SVA_ERROR_RE = re.compile(r"^Error:", re.MULTILINE)


def run(cmd, **kwargs):
    print(f"+ {' '.join(cmd)}")
    return subprocess.run(cmd, cwd=SIM_DIR, **kwargs)


def compile_and_elaborate():
    print("=== compiling ===")
    r = run([XVLOG, "-sv", "-L", "uvm", "-f", FILELIST.as_posix()])
    if r.returncode != 0:
        sys.exit("compile failed")

    print("=== elaborating ===")
    r = run([XELAB, "-L", "uvm", "-timescale", "1ns/1ps", "top", "-s", SNAPSHOT])
    if r.returncode != 0:
        sys.exit("elaboration failed")


def run_one(test, seed, verbosity):
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    COV_DIR.mkdir(parents=True, exist_ok=True)

    run_id = f"{test}_{seed}"
    args_file = SIM_DIR / f".run_{run_id}.args"
    args_file.write_text(
        f"-testplusarg UVM_TESTNAME={test}\n"
        f"-testplusarg UVM_VERBOSITY={verbosity}\n"
        f"-sv_seed {seed}\n"
        f"-R\n"
    )

    log_path = LOG_DIR / f"{run_id}.log"
    try:
        result = run(
            [
                # .as_posix(): xsim processes its argument list through an
                # internal Tcl layer, which interprets backslashes as escape
                # sequences - a Windows path like "results\cov" arrives as
                # "resultscov". Forward slashes are accepted on Windows and
                # sidestep this entirely.
                XSIM, SNAPSHOT, "-f", args_file.as_posix(),
                "-cov_db_dir", COV_DIR.as_posix(), "-cov_db_name", run_id,
            ],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
            timeout=600,
        )
        log_text = result.stdout
        returncode = result.returncode
    except subprocess.TimeoutExpired as e:
        log_text = (e.stdout or "") + "\n*** TIMEOUT ***\n"
        returncode = -1
    finally:
        args_file.unlink(missing_ok=True)

    log_path.write_text(log_text)

    num_errors = sum(int(m) for m in UVM_ERROR_RE.findall(log_text))
    num_fatals = sum(int(m) for m in UVM_FATAL_RE.findall(log_text))
    sva_failures = len(SVA_ERROR_RE.findall(log_text))

    passed = (
        returncode == 0
        and num_errors == 0
        and num_fatals == 0
        and sva_failures == 0
        and "$finish called" in log_text
    )

    return {
        "test": test,
        "seed": seed,
        "passed": passed,
        "returncode": returncode,
        "uvm_errors": num_errors,
        "uvm_fatals": num_fatals,
        "sva_failures": sva_failures,
        "log": str(log_path.relative_to(RESULTS_DIR.parent)),
    }


def merge_coverage(run_ids):
    if not run_ids:
        return
    print("=== merging coverage ===")
    COV_REPORT_DIR.mkdir(parents=True, exist_ok=True)
    # No -db_name: xcrg merges every database under -dir when it's omitted.
    # (It does not accept a comma- or repeat-flag list of db names - only
    # exactly one or none.)
    r = run([
        XCRG,
        "-dir", COV_DIR.as_posix(),
        "-report_dir", COV_REPORT_DIR.as_posix(),
        "-report_format", "html",
    ])
    if r.returncode != 0:
        print("WARNING: coverage merge failed - see xcrg output above", file=sys.stderr)
    else:
        print(f"coverage report: {COV_REPORT_DIR / 'dashboard.html'}")


def print_summary(results):
    by_test = {}
    for r in results:
        by_test.setdefault(r["test"], []).append(r)

    print("\n" + "=" * 78)
    print(f"{'Test':<22} {'Seeds':>6} {'Pass':>6} {'Fail':>6}  Failing seeds")
    print("-" * 78)

    total_pass = total_fail = 0
    for test in ALL_TESTS:
        runs = by_test.get(test, [])
        if not runs:
            continue
        passed = [r for r in runs if r["passed"]]
        failed = [r for r in runs if not r["passed"]]
        total_pass += len(passed)
        total_fail += len(failed)
        failing_seeds = ", ".join(str(r["seed"]) for r in failed)
        print(f"{test:<22} {len(runs):>6} {len(passed):>6} {len(failed):>6}  {failing_seeds}")

    print("-" * 78)
    total = total_pass + total_fail
    rate = (100.0 * total_pass / total) if total else 0.0
    print(f"{'TOTAL':<22} {total:>6} {total_pass:>6} {total_fail:>6}  pass rate {rate:.1f}%")
    print("=" * 78)

    if total_fail:
        print("\nFailing run logs:")
        for r in results:
            if not r["passed"]:
                print(f"  {r['test']} seed={r['seed']}: {r['log']}")

    return total_fail == 0


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--tests", default=",".join(ALL_TESTS),
                     help="comma-separated test list (default: all)")
    ap.add_argument("--seeds", type=int, default=5,
                     help="seeds per test (verification_plan.md specifies 50 "
                          "for a closure regression; default 5 for a quick run)")
    ap.add_argument("--seed-start", type=int, default=1,
                     help="first seed value; seeds used are "
                          "[seed-start, seed-start+seeds)")
    ap.add_argument("--verbosity", default="UVM_MEDIUM")
    ap.add_argument("--skip-compile", action="store_true",
                     help="reuse an already-elaborated snapshot")
    ap.add_argument("--no-coverage-merge", action="store_true")
    args = ap.parse_args()

    tests = [t.strip() for t in args.tests.split(",") if t.strip()]
    unknown = set(tests) - set(ALL_TESTS)
    if unknown:
        sys.exit(f"unknown test(s): {', '.join(sorted(unknown))}")

    if not args.skip_compile:
        compile_and_elaborate()

    results = []
    run_ids = []
    for test in tests:
        for seed in range(args.seed_start, args.seed_start + args.seeds):
            r = run_one(test, seed, args.verbosity)
            results.append(r)
            run_ids.append(f"{test}_{seed}")
            status = "PASS" if r["passed"] else "FAIL"
            print(f"[{status}] {test} seed={seed} "
                  f"(errors={r['uvm_errors']} fatals={r['uvm_fatals']} "
                  f"sva_failures={r['sva_failures']})")

    if not args.no_coverage_merge:
        merge_coverage(run_ids)

    all_passed = print_summary(results)
    sys.exit(0 if all_passed else 1)


if __name__ == "__main__":
    main()
