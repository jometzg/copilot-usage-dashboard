---
name: csv-analysis
description: "Analyze CSV file format and schema quality. Use for delimiter detection, header checks, row-shape validation, type drift, malformed quoting, and parser configuration recommendations."
argument-hint: "Path to CSV file(s) and any parsing constraints"
user-invocable: true
---

# CSV Analysis

## What This Skill Does
This skill inspects CSV files for structural correctness, schema consistency, and parsing risks before ingestion.

## When To Use
- You need to validate delimiter, quoting, escaping, and header behavior.
- You suspect malformed rows, inconsistent column counts, or multi-line field issues.
- You need parser settings and schema constraints for reliable ingestion.

## Constraints
- Do not modify files unless explicitly asked.
- Do not invent values when evidence is missing.
- If confidence is low, state assumptions and required additional sample size.

## Procedure
1. Identify file characteristics:
- Detect delimiter (comma, semicolon, tab, pipe).
- Detect quote and escape behavior.
- Verify whether a header row exists and whether header names are usable.
- Note encoding and newline style when detectable.

2. Validate row shape:
- Infer expected column count from header or first consistent row.
- Flag rows with extra or missing fields.
- Flag trailing delimiters, blank rows, and broken multi-line field boundaries.

3. Assess column quality:
- Infer candidate type per column (string, integer, float, date, boolean).
- Identify null tokens and empty-value conventions.
- Flag type drift in the same column.
- Report basic cardinality and representative examples.

4. Detect formatting anomalies:
- Broken quotes or unescaped delimiters in quoted fields.
- Inconsistent date/time formats.
- Locale-dependent numeric formats.
- Leading/trailing whitespace anomalies.

5. Summarize risk and recommendations:
- Rank issues by severity: critical, warning, info.
- Recommend parser settings and schema constraints.
- Propose cleanup strategy when needed.

## Required Output Order
1. File Overview
2. Detected CSV Dialect
3. Schema Snapshot
4. Issues (Critical/Warning/Info)
5. Recommended Parser Configuration
6. Suggested Remediation Steps
7. Confidence and Assumptions

## Parser Recommendation Template
Use this when enough evidence exists:

```yaml
delimiter: ","
quotechar: '"'
escapechar: "\\"
header: true
encoding: "utf-8"
newline: "\n"
strict_column_count: true
null_tokens: ["", "NA", "null", "n/a"]
```

## Practical Guidance
- For large files, sample first rows plus middle and tail segments.
- Use shell-based shape checks for speed, then confirm edge cases with direct file reads.
- Keep observed facts separate from inferred interpretations.
