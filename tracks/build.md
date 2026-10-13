# Track: build

## Refine asks
- Who uses it and the two or three core journeys, in order of importance.
- What is in the first version and what is cut.
- Stack and platform constraints, or permission to choose (then choose the most boring option).
- Data: what is stored, where, how long.
- How it will be run and how success is checked.

## Plan shape
1. Architecture in one page: components, data flow, the boundary between them.
2. Walking skeleton first: the smallest thing that starts, responds and is testable.
3. Feature slices on top, each shippable on its own.
4. Test runner and run instructions are part of the skeleton, not an afterthought.

## Chunks
- Chunk 01 is the walking skeleton: it starts, answers one request or command, and has one
  passing test. It also establishes the commands for build, test and run.
- Later chunks are vertical feature slices in priority order.
- Typical size: 3 to 8 chunks. A chunk is one concern, not one command or route: group the
  slices that share a module and a test file. Split only on a real dependency or size limit.

## QA scenarios
- Each core journey end to end against the running application.
- Start-up from a clean checkout using only the documented commands.
- One failure scenario per journey (bad input, missing data).

## Done means
The application starts from a clean checkout, the journeys pass, and the suite is green.

## Extra rules
- No framework or dependency without a stated reason in `plan.md`.
- Keep it small. Anything not needed by a core journey belongs to a later version.
