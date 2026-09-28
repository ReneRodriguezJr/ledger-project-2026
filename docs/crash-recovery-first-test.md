# Your first crash and recovery test

The goal is to see one known record survive an abrupt Ledger process crash.
Your teammates have not implemented their components yet, so `Demo_Backend`
temporarily supplies a tiny one-record log and storage file. Your reusable
work is the deliberate crash hook, the harness, and the independent comparison.

## Run it on Windows

1. Extract the provided project ZIP to a new folder.
2. Open the folder that contains `alire.toml` and `ledger.gpr`.
3. Open PowerShell there: type `powershell` into File Explorer's address bar
   and press Enter.
4. Build:

   ```powershell
   alr build
   ```

5. If the build succeeds, run:

   ```powershell
   alr exec -- powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\crash_recovery.ps1
   ```

`alr exec` gives the test the selected Alire toolchain's environment. The
PowerShell execution-policy option applies to this invocation; it does not
change your saved system execution policy. No Python installation is needed.

The output should include:

```text
Starting with an empty test database.
Requested write: 1 100
Crash point reached: WAL closed; storage has not been updated.
Ledger forcibly terminated.
Ledger restarted; WAL replay completed.
Expected: 1 100
Recovered: 1 100
PASS: record recovered after the injected process crash.
```

It also prints process exit codes and the evidence folder. The killed writer
has a nonzero exit code; the recovery and inspection processes must return 0.
The harness itself returns 0 for PASS and 1 for FAIL. In the same terminal,
`$LASTEXITCODE` shows the last command's exit code.

To try a different record, use:

```powershell
alr exec -- powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\crash_recovery.ps1 -TestKey 7 -TestValue 250
```

Every run creates a fresh directory. Existing database files are not deleted
or reused. If a build or test fails, retain its output and the evidence folder.

## What the files do

| File | Responsibility |
| --- | --- |
| `src/ledger.adb` | Small command-line driver: write, recover, or inspect. |
| `src/crash_points.ads` | Declares the deliberate crash hook. |
| `src/crash_points.adb` | Signals the selected point and pauses for the harness to kill Ledger. |
| `src/demo_backend.ads` and `.adb` | Temporary one-record WAL, storage, and replay. |
| `tests/crash_recovery.ps1` | Starts and kills Ledger, restarts it, compares, and reports PASS/FAIL. |

In Ada, `.ads` is the package specification: the operations other code may
call. `.adb` contains their implementation. `with Demo_Backend;` makes the
package available to another source file. A `procedure` performs an action;
a `function` returns a value.

## The three lines that establish the crash point

Inside `ledger.adb`, the write path is:

```ada
Demo_Backend.Write_WAL (Data);
Crash_Points.After_WAL_Persist;
Demo_Backend.Apply_To_Store (Data);
```

1. `Write_WAL` writes `1 100` to `wal.txt`, flushes the Ada stream, and closes
   it. Returning normally means the file operation succeeded.
2. The hook looks for `LEDGER_CRASH_POINT=after_wal_persist`. The harness sets
   that variable only for the writer child. The hook creates `crash.ready`
   and waits without proceeding to the next line.
3. The harness sees the marker, confirms `store.txt` does not exist, and uses
   the operating system to forcibly kill that exact child process. Ada does
   not get an opportunity to perform a normal shutdown.
4. Consequently, `Apply_To_Store` is never reached in this writer process.

The marker is only a test signal. It neither proves a disk flush nor contains
the expected record. Its meaning comes from where the hook is placed. A new
folder per run prevents an old marker from triggering the next test early.

Without the test environment variable, the hook returns immediately and a
normal `demo-write` reaches the storage update.

## What restart and replay actually do

The harness starts another `ledger` process in the same test directory with
`demo-recover`. Its `Demo_Backend.Replay` reads `wal.txt`, parses the record,
and writes the recovered record to `store.txt`.

The harness then starts `demo-dump` in a third process. This reads **storage**,
not the WAL. It prints the recovered record in a simple canonical format.
Missing files, invalid records, and extra record lines cause an error exit.

The test's expected value was fixed before the writer started. It does not
come from replay or the WAL. For the default test, the complete expected
logical state is one key/value pair: `{1: 100}`. The comparison requires the
one recovered pair to match exactly. The demo's one-record parser rejects
additional record lines, so extra records cannot silently pass this check.

## Evidence and failure conditions

Inside `test-output/crash-.../`, successful runs retain:

| Evidence | Meaning |
| --- | --- |
| `expected.txt` | Independent expected record, created before the crash. |
| `wal.txt` | WAL left behind by the killed process. |
| `crash.ready` | The writer reached the enabled hook. |
| `store.txt` | Store created during replay. |
| `actual.txt` | Logical storage contents reported by `demo-dump`. |
| `report.txt` | Requested operation, observed stages, result, and exit codes. |
| `write`, `recovery`, `inspection` logs | Standard output and errors for each child that ran. |

FAIL is reported for a missing crash point, early process exit, timeout,
storage update before the crash, recovery/inspection failure, or mismatched
state. Files and logs available up to the failure remain for diagnosis.
The timeout defaults to 10 seconds per stage; this tiny test should finish
quickly. The harness cleans up only processes it started, using their process
objects rather than killing every executable named Ledger.

## The exact claim this demonstration supports

The demo starts empty and treats its one complete closed WAL record as a
committed operation. It checks that this operation is restored after the
Ledger process is abruptly killed, while the OS and machine continue running.

`Ada.Text_IO.Flush` and `Close` flush the application stream to the operating
system. They do not establish an `fsync`/`FlushFileBuffers` power-loss
guarantee. The hook's name identifies its future location after the real WAL
durability operation. This temporary backend does not implement a production
append log, multiple transactions, torn-record handling, a B-tree, or formal
proofs. These are outside this first milestone.

The main program and demo/instrumentation packages explicitly use
`SPARK_Mode => Off` because this starter performs file and process-related
I/O. No SPARK proof is claimed. The future data-processing core can still be
implemented and proved separately.

## Connect your teammates' components later

Keep the crash hook and external test structure. Replace the temporary backend
calls after the team agrees on its interfaces:

- `Write_WAL`: call the real WAL operation. Place the hook only after its
  persistence operation reports success and the chosen record is committed.
- `Apply_To_Store`: call the real storage insertion/update operation.
- `Replay`: trigger the real WAL replay and storage reconstruction.
- `Read_Store`/`demo-dump`: expose the logical contents through the real
  storage API so the harness still verifies storage independently.

The test's current checks for `wal.txt` and absence of `store.txt` are specific
to this demo. Update those checks when the real backend uses different files
or creates an empty store at startup. The invariant stays the same: the
record must not have reached normal storage before the crash, and the
committed record must be present after recovery.

If the real WAL has explicit transactions/commit records, adapt the expected
state to that commit rule; persistence of an uncommitted record alone does
not make it recoverable as a committed operation.

## Add the work to your existing Git repository

The downloaded ZIP is a project snapshot, not a Git checkout. After trying it,
open your actual repository, check `git status`, and use a feature branch for
the changes:

```powershell
git switch -c feature/crash-recovery-demo
```

Copy the changed/new `src` files, `tests/crash_recovery.ps1`, this document,
and the README/`.gitignore` updates into that checkout. Keep the existing
`.git` directory. `ledger.gpr` and `alire.toml` are unchanged. Build and run the
test there before making your normal commit/PR. Generated `test-output/`,
`bin/`, `obj/`, `config/`, and `alire/` directories are ignored.

## API references

- [Alire: running commands in the project environment](https://alire.ada.dev/docs/)
- [Microsoft: Process.Kill](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.process.kill?view=netframework-4.8)
- [Microsoft: ProcessStartInfo.EnvironmentVariables](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.processstartinfo.environmentvariables)

## Verification performed for this starter

See `validation.md` for the checks actually run and the platform limits.
