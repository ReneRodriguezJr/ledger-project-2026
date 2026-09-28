# Crash and recovery starter: validation

The Ada source was compiled and the PowerShell harness was run against the
actual compiled Ledger executable in a Linux x86-64 environment using
GNAT 13.3.0 and PowerShell 7.4.10. Compiler warnings were treated as errors.

| Check | Observed result |
| --- | --- |
| Default record `1 100` | PASS; writer forcibly killed, recovery and inspection exited successfully. |
| Alternate record `7 250` | PASS; confirms recovery uses the input record rather than a hardcoded result. |
| Normal write `3 450`, crash setting absent | Completed normally; storage updated and no crash marker created. |
| Replay deliberately replaced with a no-op in a separate test copy | FAIL, exit code 1; inspection detected the missing store. |
| PowerShell parser | No syntax errors. |

The default run observed writer exit code 137 on Linux, recovery exit code 0,
and inspection exit code 0. The test accepts any nonzero writer exit code
after its explicit kill; Windows need not use the same number.

The replay mutation was confined to a separate validation copy. The delivered
source includes the real demo replay. The archive contains source and docs,
not a precompiled Linux executable or the tools used for validation.

Windows PowerShell 5.1, Alire 2.1.1, and GNAT 16.1.0 were not available in
this validation environment, so the user's exact Windows/Alire build remains
to be run with the commands in the walkthrough. The uploaded `alire.toml` and
`ledger.gpr` are unchanged. No power-loss test or SPARK proof was performed.
