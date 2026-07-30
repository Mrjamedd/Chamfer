# Chamfer

A macOS menu bar app that watches folders of Markdown notes and takes the rough
edges off them.

Chamfer is a wrapper, not a note app. It never stores your notes and has no
editor of its own. You keep writing in Obsidian, iA Writer, Drafts or plain
files; Chamfer watches the folder and cleans what lands there.

## Two passes, two levels of trust

**Rules** are deterministic, offline and applied silently a couple of seconds
after you stop typing: heading and list normalisation, blank-line collapsing,
trailing whitespace, consistent quotes, dates and link syntax. Every write is
snapshotted first, so anything can be reverted.

**Rewrites** come from a local language model and are never written on their
own. They land in a review queue as a diff you accept or reject. Code fences,
frontmatter, links and tables are masked out before the model sees them, and a
sanity gate discards any result that comes back the wrong length or with
mangled placeholders.

## Layout

| Target | Job |
| --- | --- |
| `ChamferCore` | Pure logic: document model, rule engine, masking, diffing. No I/O. |
| `ChamferWatch` | FSEvents watching, debounce, atomic writes, snapshot history. |
| `ChamferRewrite` | The `Rewriter` protocol and its local-model backends. |
| `Chamfer` | Menu bar shell, review window, settings. |

## Building and testing

```sh
swift build
```

```sh
Scripts/test.sh
```

`Scripts/test.sh` exists because this machine has Command Line Tools rather
than a full Xcode, so plain `swift test` cannot find the Swift Testing
framework. Use the script, not `swift test`.

## Requirements

macOS 26. The first rewrite backend is Apple's on-device Foundation Models,
which needs Apple Intelligence enabled — without it the rules still run and
rewrites are simply switched off.

## Design

`docs/superpowers/specs/2026-07-30-chamfer-design.md`
