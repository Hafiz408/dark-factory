# Lens: codebase fit

Check the request against the code that exists.

Look for:
- Where the change belongs: the modules, layers and existing patterns it should follow.
- Existing helpers, types or endpoints that already do part of this (reuse beats rewrite).
- Conventions to match: naming, error handling, config, logging, test layout.
- Conflicts: the request assumes something the code contradicts.
- How to run and test the project (commands, services, env). Record them for preflight.

Sample, do not exhaustively read: entry points, the areas the request names, and neighbours of
those. List at the end what you did not read. Never claim a fit you did not verify.
