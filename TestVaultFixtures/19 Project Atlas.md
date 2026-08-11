---
status: active
owner: Anthony
review: 2026-08-15
---

# Project Atlas

Atlas is a small command-line tool for checking a folder of reports before they are archived.

## Requirements

- Never modify an input file.
- Produce one JSON summary per run.
- Report unreadable files without stopping the rest of the scan.
- Paths in output must remain relative to the selected root.

## Current interface

```bash
atlas check ./reports --format json
```

Expected result:

```json
{
  "checked": 42,
  "warnings": 3,
  "failed": 0
}
```

## open questions

- Should warnings change the exit code?
- how do we handle symbolic links that leave the root
- The summary filename needs to be predictable but must not overwrite a prior run.
