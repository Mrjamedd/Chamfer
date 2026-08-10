# Chamfer

A local-first macOS Markdown app that takes the rough edges off notes.

Point it at one or more folders of `.md` and `.txt` notes. It watches them,
then runs each vault either after an edited note goes quiet or on a recurring
schedule—the two triggers are deliberately mutually exclusive. It keeps a
complete local history so anything it did can be undone. It is not a note
editor and does not want to be one: it works around whatever you already use.

A fresh install is deliberately inert. Connecting a vault only grants access
and starts indexing/watching it; Chamfer does not alter a note until every
setting for that vault has been chosen and a model has been explicitly
activated. “Not configured” is stored as a real state, never replaced with a
recommended value behind the scenes.

`ChamferGallery` is the design harness. It runs the same interface on fixtures
and opens a real `Example.md` in a plain-text editor, so every surface can be
reviewed without connecting a vault. `--scenario` opens a dashboard state,
`--tab` a destination, `--height` a window size, and `--models` a model
situation—`notInstalled`, `downloading`, `installed`, `active`, `cloud`,
`cloudPanel`, `noRuntime`—so every state of the Models page can be reviewed on a
machine that has none of them installed.

## Two passes, two levels of trust

**Rules** are deterministic and offline: heading/list spacing, blank-line
collapsing, trailing-whitespace cleanup and a final newline. They run according
to the vault's explicitly chosen trigger policy. Every write is snapshotted
first and recorded in history, so it can be reverted.

**Rewrites** come from the downloaded local model, or from the cloud model if
one has been explicitly connected and activated. They either land in the review
queue or are applied automatically, depending on the vault's deliberate choice.
Code fences, frontmatter, links and tables can be masked before the model sees
them, and a sanity gate discards any result that comes back the wrong length or
with mangled placeholders. Long notes are segmented on Markdown boundaries and
reassembled byte-for-byte.

There is one model at a time and no fallback. When the active model cannot run,
that is reported; nothing is quietly retried somewhere the user did not choose.

Review proposals persist the complete source and complete candidate in
addition to the visible hunks. Approval uses that exact candidate. If the note
has changed in the meantime, ordinary approval is refused; the separate
“Apply anyway” confirmation is the only path that may replace newer writing,
and the replaced version remains undoable.

## The model is the Mac's, not a menu

Chamfer inspects the machine—unified memory first, then the processor and the
free space where Ollama keeps its blobs—and picks exactly one supported model
from a fixed ladder. There is no model picker. `LocalModelSelection` is the only
thing that decides, it is a pure function of `DeviceProfile`, and every other
part of the app asks it rather than remembering an answer. A vault stores
`local.ollama`, never a model name, so a folder configured on one Mac resolves
to the right model on another instead of triggering a second download.

Installation is idempotent at three depths: the runtime is asked what is on disk
before anything is fetched, a second request for a download already in flight
joins it rather than starting another, and a pull is believed only if the model
is present afterwards. An interrupted download therefore reads as absent and can
be retried, and repeated launches or a re-entered setup flow cost nothing.

## Base, Balanced, Max

One control decides how much inference work a note is worth. The modes are not
labels over the same behaviour: each sets the document segment size, the
characters per request, the context window, the generation budget, whether the
neighbouring text is supplied, whether the model may deliberate, and how many
checking passes run after the rewrite—none, one, or two. `ModelEffortProfile` is
the single source of truth, read by the pipeline, the Ollama client and the
dashboard alike, so what the panel promises and what the model is asked to do
cannot disagree.

## Layout

| Target | Job |
| --- | --- |
| `ChamferCore` | Pure logic: document model, rule engine, masking, diffing, eligibility, scheduling. No I/O. |
| `ChamferWatch` | FSEvents watching, vault scanning, atomic writes, snapshots, persistence. |
| `ChamferRewrite` | The `Rewriter` protocol, its backends, device-to-model selection, the installer, and the pipeline that drives them. |
| `ChamferUI` | The design system and every view composed from it. |
| `Chamfer` | The app shell: window, menu bar, settings, and the services that join the layers. |

## Where things are kept

Model selection is not stored at all—it is recomputed from the hardware. What is
stored is which path was activated and which of the three modes is chosen.

Vault state and the pending queue live in
`~/Library/Application Support/Chamfer/state.json`, complete rewrite history in
`history.json`, and every replaced version under `Snapshots/`. Model selection
is stored in macOS preferences and provider credentials stay in Keychain.
Nothing is written into a connected vault except an eligible note being
cleaned or rewritten.

Individual notes can be excluded through the native macOS file picker. The
stored rule is relative to the vault, so it survives the vault moving, and
folder-level include/exclude rules remain available for broader scope.

“Clear All Vault Settings” clears only per-vault rewrite choices, schedules,
folder rules, sweep timestamps and pending reviews. Vault connections and
indexes remain; model selection, provider credentials, app-wide preferences,
note files, snapshots and history are deliberately preserved.

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

`TestVaultFixtures/` is the tracked source for the 20-note integration vault.
The working copy used for manual end-to-end testing lives at
`~/Documents/Chamfer Test Vault` and contains exactly those 20 Markdown files.

## Requirements

macOS 26 or later. The local model runs through Ollama's server, and Chamfer
provisions it: on launch it downloads `ollama-darwin.tgz`, checks it against the
published SHA-256, unpacks it into Chamfer's own Application Support and runs it
as a **child process on a private port**. Nothing is asked of you, nothing needs
a password, and nothing is installed into `/Applications`.

Deliberately the standalone server rather than `Ollama.app`. Installing a second
application — with its own icon, menu bar item and a daemon that outlives
Chamfer — is out of scope for a notes app. The published tarball is the same
server and the same Metal runners with no UI wrapper around them. So:

- Nothing appears in `/Applications`, the Dock or the menu bar.
- The server is Chamfer's child process. Quit Chamfer and it goes.
- It listens on `127.0.0.1:11913`, so it cannot collide with an Ollama you run
  yourself — and if you already run one on the usual port, Chamfer uses yours and
  downloads nothing.
- Models are stored under Chamfer rather than in `~/.ollama`, so deleting
  Chamfer and its Application Support removes everything it ever fetched.

Ollama is MIT licensed; the licence notice ships beside the binaries.

Provisioning runs on every launch rather than behind a first-run flag: when a
server is already answering it costs one request to localhost, and an attempt
that failed gets another try next time instead of being remembered as done.

## Design

`docs/superpowers/specs/2026-07-30-chamfer-design.md`

## Version 1.0 scope

`docs/superpowers/specs/2026-08-06-chamfer-v1.0-release-scope.md`
