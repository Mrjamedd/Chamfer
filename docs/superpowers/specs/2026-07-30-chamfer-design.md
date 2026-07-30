# Chamfer — Design

Date: 2026-07-30
Status: approved, ready for implementation planning

## Problem

Notes get written fast and messy: inconsistent heading levels, four blank lines
in a row, mixed bullet characters, typos, half-finished sentences. Cleaning
them by hand is tedious enough that it never happens, so the mess accumulates
until the notes are unpleasant to read.

Existing note apps will not fix this. They are editors, not janitors.

## What Chamfer is

A macOS menu bar app that watches folders of Markdown notes and cleans what
lands in them. It is a wrapper around whatever note app the user already uses —
Obsidian, iA Writer, Ulysses external folders, Drafts, plain files — because
all of those are `.md` and `.txt` on disk. Chamfer stores no notes and has no
editor.

Two passes, deliberately given different levels of trust.

### Rule pass — automatic

Deterministic, offline, pure-function transformations, applied without asking
roughly two seconds after the file stops changing:

- normalise heading levels and the blank lines around them
- one bullet character throughout
- collapse runs of blank lines
- strip trailing whitespace
- consistent quote style
- consistent date format
- normalise link syntax
- fix ordered-list numbering

These are safe because they are predictable and reversible. Every write is
preceded by a snapshot of the original bytes.

### Rewrite pass — reviewed

A local language model fixes typos, grammar and structure. It never writes to a
note. It produces a proposal; the menu bar icon badges; the user opens the
review window, reads a diff, and accepts or rejects.

The asymmetry is the point. A weak local model is good enough to be useful and
not good enough to be trusted unattended.

## Architecture

Four SwiftPM targets, so the logic is testable without launching an app.

| Target | Responsibility | Depends on |
| --- | --- | --- |
| `ChamferCore` | Document model, rule engine, masking, sanity gate, diffing. Pure — no file I/O, no network, no UI. | — |
| `ChamferWatch` | FSEvents watching, debounce, echo suppression, atomic writes, snapshot history. | `ChamferCore` |
| `ChamferRewrite` | `Rewriter` protocol and its local-model backends. | `ChamferCore` |
| `Chamfer` | Menu bar shell, review window, settings, security-scoped bookmarks. | all three |

Each target answers the three questions cleanly: `ChamferCore` transforms text
values and depends on nothing; `ChamferWatch` turns filesystem events into
settled-note events and writes bytes safely; `ChamferRewrite` turns a passage
into a better passage; `Chamfer` is the only target that knows there is a user.

## Data flow

1. FSEvents reports activity in a watched folder.
2. Debounce ~2s so a note being actively typed into does not fire per keystroke.
3. Drop the event if the file's hash matches what Chamfer last wrote — without
   this the app reacts to its own edits forever.
4. Drop the event if the file is excluded: `.obsidian`, `.git`, dotfiles,
   non-text extensions.
5. Rule pass runs. If the text changed: snapshot the original, then write
   atomically (temp file plus rename) so a note app reading concurrently never
   sees a half-written file.
6. Rewrite pass runs per section. Result becomes a pending proposal in the
   store. Menu bar badges.
7. User accepts: snapshot, then atomic write. User rejects: proposal is
   discarded and that section's hash is remembered so it is not re-proposed
   unchanged.

## Protecting notes from a weak model

This is the part that decides whether the app is usable.

**Masking.** Before a section reaches the model, code fences, YAML
frontmatter, wikilinks, URLs, math and tables are replaced with placeholder
tokens, and restored afterwards. A 3B model will otherwise reformat a code
block or "correct" a wikilink.

**Section-at-a-time.** Never the whole note. Keeps each request inside a
context length the model handles well and keeps a bad result contained.

**Sanity gate.** A proposal is discarded, not shown, when the output length
differs from the input by more than ~40%, or when any masked placeholder is
missing, duplicated or altered. Showing nothing beats showing garbage.

**Snapshots.** Both passes snapshot before writing. Any note is revertible to
any earlier state from the review window.

## Model backend

Undecided, and deliberately deferred behind the `Rewriter` protocol.

The first implementation is Apple's on-device Foundation Models, because it
needs no download, no install, no API key and no network. Ollama over localhost
and a bundled MLX model are both plausible later; each is one new file
conforming to `Rewriter`, with no change anywhere else.

## Error handling

- **No Apple Intelligence.** Rules keep working. Rewrites are disabled and the
  settings window says why in plain language. The app is degraded, not broken.
- **Folder permission lost.** Security-scoped bookmarks are re-requested with a
  clear prompt naming the folder; watching pauses rather than silently failing.
- **Model timeout or error.** Proposal is dropped. No retry storm, no user
  interruption.
- **Write failure.** Original is left untouched, since writes go temp-then-
  rename. Failure is surfaced in the review window.

## Testing

- Rules are pure functions, so they get golden-file tests: an input `.md` and
  the expected output `.md`, one pair per rule plus combined cases.
- The masking and sanity gate get unit tests with deliberately hostile inputs —
  nested code fences, links inside headings, tables with pipes in cells.
- The review flow is tested against a fake `Rewriter`, so the suite never needs
  Apple Intelligence and runs offline in CI.
- `ChamferWatch` gets tests over a temp directory covering debounce, echo
  suppression and atomic write behaviour.
- Built test-first.

`Scripts/test.sh` wraps `swift test` with the Command Line Tools framework
search paths; plain `swift test` fails on this machine.

## Development approach

This project is also a place to practise dashboard UI, so it is built UI-first
against a fake data layer rather than backend-first.

`ChamferFixtures` produces a `DashboardState` for each scenario the dashboard
has to survive: first run, resting, 200 pending, one 12,400-word note, a
code-heavy note, mid-sweep, rewrites unavailable, folder unreachable, failed.
Those scenarios are the design brief — a layout that only holds up under the
typical case is not finished.

`ChamferUI` holds the design system and depends only on `ChamferCore`, so it
cannot reach for app state and stays reusable by construction.
`ChamferGallery` is an executable that renders every scenario and every
component. It exists because this machine has Command Line Tools rather than
Xcode, so there is no preview canvas:

```sh
swift run ChamferGallery --scenario flooded
```

## Visual language

Deep beige canvas, pale beige cards floating on it, dark ink for type. The
theme is fixed rather than appearance-following: the beige is the identity.

Hovering never recolours a card. It rises, takes a heavier shadow, and a pink
glitter diffusion blooms around its edges — soft bloom plus individual
twinkling specks, so it reads as glitter rather than as a flat pink mist. The
same treatment applies to sidebar rows, so pointing at something feels
identical everywhere. It lives in one place, `HoverGlow`, and is applied with
`.chamferHoverGlow(isActive:cornerRadius:)`.

Real wiring comes last. The watcher and the model backend fill the same
`DashboardState` the fixtures produce today, so no view changes when they land.

## Scope

**v1:** one watched folder, the eight rules above, the review queue with
accept/reject per note, snapshot history with revert, menu bar UI, Foundation
Models backend.

**Explicitly not v1:** splitting or filing or tagging notes, Apple Notes
support, multiple model backends, sync, per-hunk accept/reject, an iOS app.

## Notes for implementation

- The menu bar surface must be an `NSStatusItem` plus a transparent `NSPanel`,
  not `MenuBarExtra`. On macOS 26 `MenuBarExtra` draws a glass sheet behind its
  window that cannot be removed; Lintel hit this and had to migrate.
- Package targets macOS 26 outright rather than gating Foundation Models calls
  behind availability checks.
