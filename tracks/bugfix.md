# Track: bugfix

## Refine asks
- Exact reproduction steps, and the environment (version, OS, data) where it happens.
- Expected vs actual behaviour, in observable terms.
- Blast radius: who is affected, since when, anything that changed recently.
- Is there an error message, log or stack trace? Ask for it verbatim.

## Plan shape
1. Root-cause hypothesis with the file and function it points to, and the evidence.
2. Minimal diff: the smallest change that removes the cause, not the symptom.
3. Every other caller of the code being changed (fix it once where all callers route through).

## Chunks
- Chunk 01 is ALWAYS a failing reproduction test. It must be red against the unfixed code. The
  tester verifies this before any fix is accepted.
- Chunk 02 is the fix. Further chunks only for additional callers or a regression guard.
- Typical size: 1 to 3 chunks.

## QA scenarios
- The original symptom is gone, stated as observable behaviour.
- Adjacent behaviour that shares the code path is unchanged.
- One scenario for the same defect class at a neighbouring call site.

## Done means
The reproduction test is green, the full suite is green, and no scenario regressed.

## Extra rules
- Do not refactor around the bug. Cleanup is a separate request.
- If the cause cannot be reproduced, end Refine with a question, not a guess.
