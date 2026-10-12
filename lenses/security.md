# Lens: security

Review the diff and anything it touches for:
- Injection: SQL, shell, template, path traversal, deserialization, SSRF.
- Authentication and authorization: missing checks, trusting client input, IDOR.
- Input validation and output encoding at trust boundaries.
- Secrets in code, config, logs or test fixtures.
- Dependencies: new or upgraded packages, install scripts, known-vulnerable versions.
- Data exposure: over-broad responses, verbose errors, PII in logs.
- Unsafe defaults: permissive CORS, disabled verification, weak crypto.

Run any scanner the repo already configures (for example `npm audit`, `pip-audit`, `bandit`,
`gosec`, `semgrep`). If none exists, say `unscanned` in the verdict line; do not imply a clean
scan.

## Severity rubric

| Finding | Severity |
|---|---|
| Exploitable injection, auth bypass, secret committed, remote code execution | critical |
| Missing authorization on a sensitive path, known-vulnerable dependency in use | high |
| Missing validation with limited reach, verbose errors, weak default | medium |
| Hardening suggestion with no present exploit | low |
