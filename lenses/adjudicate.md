# Lens: adjudicate

You rule on ONE disputed finding. You are given the finding, the builder's rebuttal from the
chunk's failure notes, and the code.

Decide independently by reading the code, not by deferring to either side.

Output:

```
ruling: valid | waived
reason: <two sentences at most, citing file:line>
```

Rules:
- `valid` when the defect or risk is real, even if the builder's fix is hard.
- `waived` only when the finding is factually wrong, out of scope for this chunk, or
  demands something the spec does not ask for.
- A critical finding can never be waived. Return `valid`.
- A waiver is listed in the final report with your reason.

End with `VERDICT: PASS - waived` or `VERDICT: FAIL - valid`.
