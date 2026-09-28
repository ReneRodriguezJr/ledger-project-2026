# Crash Recovery: First End-to-End Test

## Purpose

This document describes Team B's first working crash-recovery test for Ledger.

The goal of this milestone is intentionally small: prove that Ledger can write one record to a temporary write-ahead log (WAL), be forcibly terminated before the storage file is updated, restart, replay the WAL, and recover the expected record.

This is a walking-skeleton test used to prove that the end-to-end recovery path exists while the team learns Ada and SPARK. It is not the final WAL, storage engine, B-tree, or formal recovery proof.

## Recovery Property Tested

For this starter test, the selected crash point occurs after the WAL file has been written and closed but before the storage file has been updated.

The test expects the WAL record to be available after a process crash so that recovery can replay it into storage.

For the current milestone:

> If the WAL record has reached the selected persistence boundary before the process is killed, restarting Ledger and replaying the WAL must restore the expected record.

Closing the WAL is used as the persistence boundary for this process-crash demonstration. This test does **not** prove durability across operating-system failure, power loss, or hardware cache loss.

## Test Path

```text
Start from empty test state
        |
        v
Request one record
        |
        v
Write record to WAL
        |
        v
Close WAL
        |
        v
Signal crash point
        |
        v
Harness forcibly terminates Ledger
        |
        v
Confirm storage was not updated
        |
        v
Restart Ledger
        |
        v
Replay WAL into storage
        |
        v
Inspect recovered record
        |
        v
Compare expected vs. recovered
        |
        +----> PASS / FAIL
```

## Relevant Files

- `src/ledger.adb` — exposes the demo commands used by the harness.
- `src/crash_points.ads`
- `src/crash_points.adb` — provides the deliberate crash-point mechanism.
- `src/demo_backend.ads`
- `src/demo_backend.adb` — temporary one-record WAL/storage implementation used for the learning milestone.
- `tests/crash_recovery.ps1` — starts Ledger, waits for the crash point, forcibly terminates the writer, restarts recovery, inspects the result, and reports PASS or FAIL.
- `test-output/` — generated evidence from individual crash-recovery runs.

The demo backend is temporary. It allows the crash/recovery path to be developed before the team's final WAL and storage components are available.

## How to Run the Test

From PowerShell or Command Prompt in the repository root:

```powershell
alr build
```

Run the default test:

```powershell
alr exec -- powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\crash_recovery.ps1
```

Run the test with another record:

```powershell
alr exec -- powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\crash_recovery.ps1 -TestKey 7 -TestValue 250
```

Using more than one input helps demonstrate that recovery is using the test input rather than a hard-coded recovered value.

## Observed Windows Results

The test was run on the Ledger development environment on Windows.

### Test 1 — Default Record

Requested record:

```text
1 100
```

Observed result:

```text
Starting with an empty test database.
Requested write: 1 100
Crash point reached: WAL closed; storage has not been updated.
Ledger forcibly terminated.
Ledger restarted; WAL replay completed.
Expected: 1 100
Recovered: 1 100
write exit code: -1
recovery exit code: 0
inspection exit code: 0
PASS: record recovered after the injected process crash.
```

Evidence directory:

```text
test-output/crash-20260928-015534-e25b8687bf9f4637abbd717b9ab8d695
```

### Test 2 — Alternate Record

Requested record:

```text
7 250
```

Observed result:

```text
Starting with an empty test database.
Requested write: 7 250
Crash point reached: WAL closed; storage has not been updated.
Ledger forcibly terminated.
Ledger restarted; WAL replay completed.
Expected: 7 250
Recovered: 7 250
write exit code: -1
recovery exit code: 0
inspection exit code: 0
PASS: record recovered after the injected process crash.
```

Evidence directory:

```text
test-output/crash-20260928-015558-33db7110a13f4448a62b56831d36fb79
```

The nonzero writer exit code is expected because the harness deliberately terminates that process. Recovery and inspection are expected to exit successfully.

## Pass Criteria

The starter crash-recovery test passes only when all of the following are true:

- Ledger reaches the intended crash point.
- The WAL exists before the process is killed.
- The storage file has not already been updated at the crash point.
- The writer process is forcibly terminated.
- Ledger restarts successfully.
- Recovery replays the WAL.
- The recovered record exactly matches the independently supplied expected key and value.
- Recovery exits successfully.
- Inspection exits successfully.

## What This Test Demonstrates

The current test demonstrates that:

1. A deliberate crash can be triggered at a known point.
2. The process can be terminated before the normal storage update occurs.
3. WAL information survives that process termination in the current test environment.
4. Ledger can restart and replay the available WAL.
5. Recovered state can be compared with an expected value.
6. The harness produces repeatable PASS/FAIL evidence.

This gives Team B a working end-to-end crash-recovery path that can later be connected to the team's real WAL and storage implementation.

## Current Limitations

This is intentionally a small learning milestone.

It does not currently prove:

- power-loss durability;
- explicit operating-system or hardware-cache flushing guarantees;
- recovery of multiple transactions;
- recovery from a partially written WAL record;
- full B-tree recovery;
- every possible persistent-state transition;
- concurrency behavior;
- checkpointing;
- formal correctness of the recovery algorithm;
- complete SPARK verification of the storage engine.

The current `demo_backend` is temporary and should eventually be replaced or connected to the team's real WAL and storage components.

## Team Integration

The current crash/recovery harness is designed so the temporary backend can be replaced incrementally.

- The WAL work can replace the temporary WAL write/read logic while keeping the crash harness.
- The storage work can replace the temporary recovered-state representation.
- The crash/recovery work can continue using deliberate crash points and independent expected values.
- SPARK verification can be added to small core packages as the real Ada implementation develops.

The immediate priority is to preserve the working end-to-end path while replacing temporary pieces one at a time.

## Next Small Steps

The next crash/recovery work should stay limited to core learning goals:

1. Connect the harness to the team's real WAL implementation.
2. Keep one known crash point after WAL persistence and before storage update.
3. Replace the temporary recovered storage state when the storage component is ready.
4. Add one additional crash point only after the first integrated path is stable.
5. Keep saving reproducible evidence for each test run.

The project should favor a small working Ada implementation over expanding into the full original storage-engine scope.
