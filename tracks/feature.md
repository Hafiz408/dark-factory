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
- Chunk 01 is the thinnest end-to-end slice that exercises the new behaviour through the real
  entry point, using existing patterns.
- Later chunks widen it: validation, edge cases, permissions, polish.
- Typical size: 3 to 8 chunks.

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
