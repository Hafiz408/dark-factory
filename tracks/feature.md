# Track: feature

## Refine asks
- Acceptance criteria as testable statements.
- Edge cases: empty, large, invalid, concurrent, permission-denied.
- Integration points: what existing code, data or services this touches.
- Explicitly out of scope.
- Who can use it, and what existing users must not notice.

## Plan shape
1. Map existing patterns first: where similar things live, how they are structured and tested.
2. Reuse before writing: existing helpers, types, components.
3. Vertical slices through the existing layers, thinnest end-to-end slice first.

## Chunks
- At most 5 user acceptance criteria and at most 8 files: one chunk, with its edge cases.
- Otherwise chunk 01 is the thinnest end-to-end slice through the real entry point, using
  existing patterns; later chunks add further behaviours, each with its own edge cases.
- Typical size: 1 to 5 chunks.

## QA scenarios
- Each acceptance criterion as a user journey.
- The zero, boundary and unauthorized cases.
- At least one existing behaviour next to the feature that must be unchanged.

## Done means
Acceptance criteria met, the full suite green, and all scenarios pass.

## Extra rules
- Follow the conventions of the surrounding code. Do not introduce a new pattern or dependency
  when an existing one fits.
- Do not change unrelated behaviour.
