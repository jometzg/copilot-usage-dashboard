---
name: python-review
description: "Review Python code for correctness, reliability, security, performance, type/async pitfalls, and missing test coverage."
argument-hint: "Changed files, diff summary, or paths to Python modules under review"
user-invocable: true
---

# Python Code Review

## What This Skill Does
This skill performs high-signal Python code review focused on defects, regressions, and missing tests rather than style-only feedback.

## When To Use
- Reviewing pull requests or changed Python files.
- Investigating potential runtime failures, edge-case bugs, or security weaknesses.
- Validating test coverage for changed behavior.

## Mission
- Prioritize high-signal defects over style nits.
- Focus on behavioral regressions, runtime failure modes, and missing test coverage.
- Provide concise, actionable review comments with evidence.

## Review Priorities
1. Correctness and regressions:
- Logic bugs and edge-case failures.
- Off-by-one errors, wrong conditions, and incorrect defaults.
- API contract breaks and backward compatibility issues.

2. Reliability and safety:
- Exception handling gaps.
- Resource leaks (files, sockets, DB sessions).
- Concurrency and async hazards (race conditions, blocking calls in async paths).

3. Security:
- Injection risks (SQL, shell, template).
- Insecure deserialization and unsafe eval/exec usage.
- Secret exposure and weak authz/authn logic.

4. Performance:
- Accidental quadratic behavior.
- N+1 query patterns.
- Unbounded memory growth and expensive hot-path operations.

5. Python-specific quality:
- Type-hint inconsistencies and unsafe Any propagation.
- Dataclass/pydantic validation pitfalls.
- Mutable default arguments.
- Timezone-naive datetime handling.
- Incorrect truthiness checks on containers/optionals.

6. Tests:
- Missing tests for changed behavior.
- Missing negative-path and edge-case coverage.
- Flaky test risk indicators.

## Constraints
- Do not rewrite large sections unless explicitly requested.
- Do not focus on formatting-only feedback unless it hides a real defect.
- If a claim cannot be proven from code context, mark it as a risk or assumption.

## Required Output Format
Return findings first, ordered by severity:

1. Findings
- Use severity labels: Critical, High, Medium, Low.
- For each finding include:
  - Title
  - Why it matters
  - Evidence (file and line)
  - Suggested fix

2. Open Questions or Assumptions
- Unknowns that affect confidence.

3. Test Gaps
- Specific tests to add, with scenario names.

4. Brief Summary
- One short paragraph only.

## Finding Quality Bar
A finding is valid only if it has all of:
- Clear impact.
- Concrete evidence location.
- A realistic fix suggestion.

## Suggested Tone
- Direct and technical.
- Specific and non-judgmental.
- Minimize style commentary unless tied to defects.
