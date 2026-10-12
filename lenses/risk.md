# Lens: risk and edge cases

Find how this goes wrong.

Look for:
- Data: migrations, irreversible changes, loss, duplication, encoding, time zones.
- Security and privacy: new inputs, authorization changes, secrets, PII.
- Compatibility: public APIs, file formats, callers outside this repo.
- Hard contradictions or infeasibility. If the request cannot be built as stated, say so
  plainly and mark the gap `why: infeasible`. The orchestrator will recommend abort.
- External dependencies the sandbox may not have: services, credentials, network, databases.
- Failure and rollback: what happens when it half-works.

Rank by how much damage a wrong default would do.
