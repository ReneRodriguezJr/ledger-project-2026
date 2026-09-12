# Ledger Architecture

## Overview

Ledger is a database storage system built from scratch using **Ada** and **SPARK**.

The system is designed around persistent storage, a write-ahead log (WAL), a B-tree index, and crash recovery. The project also includes a crash-injection testing system that intentionally interrupts the database during persistent-state operations to verify that recovery behaves according to the project's stated recovery guarantee.

The architecture is divided into several major components:

```text
                         Ledger
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
       WAL            Page Manager          B-Tree
        │                  │                  │
        └──────────────────┼──────────────────┘
                           │
                        Recovery
                           │
                    Crash Testing
                           │
                         Oracle
```

## System Components

### Write-Ahead Log (WAL)

The WAL records database operations before changes are made to persistent data.

The WAL is responsible for providing the information required to recover the database after a crash.

The WAL component will define:

- WAL record format
- Record creation
- Record writing
- Record persistence/flush behavior
- Record reading
- WAL replay during recovery

The exact WAL record format and persistence behavior will be finalized as part of the implementation design.

### Page Manager

The page manager provides the interface for reading and writing persistent database pages.

It is responsible for managing the physical representation of persistent data used by the B-tree.

The page manager will define:

- Page format
- Page allocation
- Page reads
- Page writes
- Page persistence/flush behavior

The page manager is also important to crash testing because page writes and persistence operations represent potential persistent-state transitions where an interruption may occur.

### B-Tree

The B-tree provides indexed storage and retrieval.

It will support:

- Insert
- Lookup
- Delete
- Range scan

The B-tree will use the page manager for persistent storage.

The B-tree implementation must maintain its structural invariants so that the index remains valid during normal operation and after recovery.

### Recovery

The recovery component is responsible for restoring the database to a state permitted by the project's recovery guarantee after an interruption.

Recovery will use persistent information, including the WAL and database pages, to determine which operations need to be replayed or discarded.

The recovery design will be finalized after the WAL and page-management persistence behavior have been defined.

## Data Flow

A normal database operation will follow the general sequence:

```text
        Database Operation
                │
                ▼
        Create WAL Record
                │
                ▼
          Write WAL Record
                │
                ▼
          Persist WAL Record
                │
                ▼
          Modify B-Tree/Page
                │
                ▼
            Write Page
                │
                ▼
          Persist Page
```

The exact ordering of these operations is part of the durability design and must satisfy the WAL requirements.

After a crash:

```text
              Crash
                │
                ▼
        Start Recovery
                │
                ▼
        Read Persistent State
                │
                ▼
          Read / Replay WAL
                │
                ▼
       Reconstruct Database
                │
                ▼
       Verify Recovery Result
```

## Persistent State

The database's persistent state consists of information stored on disk and expected to survive process termination or system interruption according to the durability guarantee.

This may include:

- WAL records
- B-tree pages
- Page metadata
- Other persistent metadata required by the storage engine

The exact on-disk representation will be documented once the WAL and page formats have been finalized.

## Crash Testing

Crash testing is a core part of the project rather than an optional test performed at the end.

The crash-testing system will intentionally interrupt the database at persistent-state transitions.

A conceptual operation may contain transitions such as:

```text
1. Create WAL record
2. Write WAL record
3. Persist WAL record
4. Modify page
5. Write page
6. Persist page
```

The crash-injection harness will eventually test the relevant transitions defined by the actual storage implementation.

For each crash point, the test system will:

1. Start from a known database state.
2. Perform a known sequence of operations.
3. Interrupt the process at a defined persistent-state transition.
4. Restart the database.
5. Run recovery.
6. Compare the recovered state against the expected state.
7. Report whether the recovery guarantee was satisfied.

The exact crash points will be determined after the WAL and page-management designs are finalized.

## Recovery Oracle

Crash testing will use an independent **recovery oracle** to determine the expected result of a test.

The oracle represents the correct logical database state for a sequence of operations without depending on the implementation's recovery mechanism.

For example:

```text
Initial State: {}

INSERT A
INSERT B
DELETE A
INSERT C

Expected State:

B
C
```

If the database is interrupted during this sequence, the recovered database will be compared against the oracle's expected state.

The purpose of the oracle is to avoid simply checking whether the database "looks correct." Recovery must be checked against a defined expected result.

## Recovery ↔ Crash Harness / Oracle Interface

The crash-testing harness, recovery system, and oracle must have clearly defined responsibilities so that recovery can be tested independently of the implementation being tested.

### Crash Harness Responsibilities

The crash harness will control when Ledger is intentionally interrupted during a test.

The storage system will expose identifiable crash points around persistent-state transitions. The exact crash points will depend on the final WAL and page-management designs.

Possible persistent-state boundaries include:

- after a WAL record has been written but before it is persisted;
- after a WAL record has been persisted;
- after a database page has been written but before it is persisted;
- after a database page has been persisted;
- other persistence boundaries introduced by the final storage design.

The harness will select a target crash point before running a test. When Ledger reaches that point, the harness will terminate the running database without performing a normal graceful shutdown.

The goal is to reproduce interruptions at specific persistence boundaries rather than rely on random process termination.

### Recovery Interface

After an injected crash, the harness will restart Ledger using the same persistent database and WAL files produced before the interruption.

Recovery must run before the recovered database is considered ready for normal use.

At a high level, recovery will:

1. Inspect the persistent database state.
2. Read available WAL records.
3. Determine which logged operations must be replayed or ignored.
4. Restore the database to a state permitted by the recovery guarantee.
5. Make the recovered logical state available for verification.

The crash harness does not determine how recovery works internally. It only triggers the restart and observes the resulting database state.

### Oracle Responsibilities

The recovery oracle will maintain an expected logical model of the database independently of Ledger's B-tree, WAL, and recovery implementations.

For each test, the oracle will know:

- the initial logical database state;
- the sequence of operations requested;
- which persistence boundary was reached before the crash;
- which operations are guaranteed to be durable according to the recovery guarantee.

The oracle will use this information to determine the state, or set of states, that is valid after recovery.

An operation that reached the defined durability point must appear after recovery. An operation that had not yet reached that point may be allowed to disappear, depending on the final recovery guarantee.

This prevents the test system from incorrectly requiring every operation attempted before a crash to survive.

### Recovery Verification

After recovery completes, the harness will inspect the logical contents of the recovered database and compare them with the state permitted by the oracle.

The comparison should use the database's normal logical operations rather than depend directly on internal recovery data structures.

A test passes when the recovered state satisfies the recovery guarantee.

A test fails when, for example:

- an operation guaranteed to be durable is missing;
- an operation appears in a state that the recovery guarantee does not permit;
- recovery cannot successfully open the database;
- the recovered B-tree cannot perform normal lookup or scan operations;
- persistent state is structurally invalid after recovery.

### Failure Evidence

When a recovery test fails, the harness should record enough information to reproduce and diagnose the failure.

The recorded information should include:

- initial database state;
- operation sequence;
- injected crash point;
- expected state or allowed states;
- actual recovered state;
- whether recovery completed successfully;
- relevant WAL or persistence information needed for debugging.

The exact logging format will be determined during implementation.

### High-Level Test Flow

```text
Known Initial State
        |
        v
Operation Sequence --------> Recovery Oracle
        |                         |
        v                         |
Ledger Execution                 |
        |                         |
        v                         |
Persistent-State Transition      |
        |                         |
        v                         |
Injected Crash                   |
        |                         |
        v                         |
Restart Ledger                   |
        |                         |
        v                         |
Run Recovery                     |
        |                         |
        v                         |
Recovered Logical State ---------+
        |
        v
Compare With Allowed Oracle State
        |
        +----> PASS / FAIL
```

The exact crash points and durability rules remain open design decisions until the WAL and page-management interfaces have been finalized.

## SPARK Verification

SPARK will be used to formally verify important parts of the system.

The initial verification focus will include the parsing and page-management core and the absence of runtime errors.

Additional contracts and invariants may be added to critical components as the architecture develops.

Verification results will be documented honestly, including:

- Properties that were successfully proved.
- Properties that could not be proved.
- Reasons a proof could not be completed.
- Changes made to the implementation or contracts to resolve proof obligations.

## Recovery Guarantee

The project will define an explicit recovery guarantee describing what the database is required to preserve after a crash.

The guarantee will specify:

- Which operations are guaranteed to survive.
- Which operations may be lost.
- What state is considered valid after recovery.
- What persistence event determines whether an operation is durable.
- How crash testing demonstrates that the guarantee is satisfied.

The final guarantee will be agreed upon by the team before the crash-testing implementation is finalized.

## Component Ownership

| Component | Primary Responsibility |
| --- | --- |
| WAL | Log format, writing, persistence, reading, and replay |
| Page Manager | Persistent page representation and page I/O |
| B-Tree | Index structure and database operations |
| Recovery | Database restoration after interruption |
| Crash Testing | Crash injection, recovery tests, and validation |
| Oracle | Independent expected-state verification |
| SPARK | Formal contracts, proofs, and verification results |

Component ownership does not prevent collaboration. Components will need clearly defined interfaces so that independently developed pieces can work together.

## Design Decisions

Important architectural decisions will be recorded here as the project develops.

Examples include:

- WAL record format
- Page format
- B-tree node representation
- WAL persistence semantics
- Page persistence semantics
- Recovery algorithm
- Crash-injection points
- Recovery guarantee
- SPARK contracts and invariants

Major changes to these decisions should be discussed by the team before implementation.

## Open Questions

The following decisions remain open during the initial architecture phase:

- What exactly constitutes a durable WAL record?
- What is the exact WAL record format?
- What is the page format?
- How are B-tree nodes represented on disk?
- What are the exact persistent-state transitions?
- What is the final recovery algorithm?
- What operations are guaranteed to survive a crash?
- Which components and functions will receive SPARK contracts?
- How will crash injection be implemented?

These questions should be resolved as the corresponding components are designed.
