# Chamfer End-to-End Integration Design

Date: 2026-08-09

## Outcome

Chamfer will launch with no user-configurable behavior silently selected. A user can intentionally configure a rewrite model and each connected vault, allow a real note to flow through deterministic cleanup and AI rewriting, review the exact proposed revision, safely approve or reject it, undo an applied revision, relaunch without losing actionable state, and clear all vault-specific settings without disconnecting vaults or altering AI configuration.

This is an integration pass over the existing architecture. It retains `AppModel` as the application state owner, `StateStore` as the durable state boundary, `NoteService` as the scanner/watcher coordinator, `ProcessingScheduler` as the trigger coordinator, `RewriteService` as the processing/application coordinator, `ChamferRewrite` as the backend/pipeline layer, and the existing Dashboard/Models/Vaults/Review/Settings surfaces.

## Product Boundaries

The Settings action will be named **Clear All Vault Settings** so its label matches its approved scope.

It clears:

- every connected vault's partial or complete rewrite configuration;
- vault include/exclude rules;
- sweep timestamps and inactivity-trigger bookkeeping derived from those settings;
- pending, failed, or regenerating proposals produced under the cleared settings;
- in-flight rewrite authority, so late results cannot reappear;
- scheduler work derived from cleared settings.

It preserves:

- connected vault bookmarks and permissions;
- indexed note data, which remains useful for search while processing is unconfigured;
- the global AI/model selection, selected local model, selected cloud provider, and Keychain credentials;
- global privacy, notification, and login-item preferences;
- note files;
- snapshots and applied rewrite history.

The action requires an explicit destructive confirmation. It is one coordinated state transition: the UI updates immediately, durable state is flushed, scheduler work is invalidated, and late asynchronous results are rejected by generation checks.

## Configuration Model

### Vault configuration

The current `RewritePolicy?` cannot represent a partially configured vault: the value is either absent or silently complete with initializer defaults. It will be split into two shapes:

- `VaultConfiguration` is persisted user intent. Each user-selected field is optional: rewrite mode, application behavior, inactivity delay, sweep schedule, and Markdown preservation. It exposes `missingFields` and `isComplete`.
- `RewritePolicy` is a fully resolved runtime value. It has no defaulted initializer parameters and cannot be constructed without every required value.

A connected vault owns an optional/empty `VaultConfiguration`. Selecting a value persists that exact partial selection. Processing asks the configuration to resolve only after all vault requirements exist and a global model has been intentionally activated. No downstream code substitutes a value for a missing choice.

The vault setup UI renders an explicit “Not configured” value for every unset field. “Start watching” becomes “Enable rewriting” and remains disabled until all required vault fields and the active model are available. Indexing and search remain active for connected vaults even while rewriting is gated.

### Global preferences

User-visible global toggles also distinguish unset from deliberately on or off. Boolean preferences use optional values and notification categories use explicit per-category choices. Runtime consumers use safe non-mutating interpretations only where absence means “do nothing”: no notifications, no launch at login, no cloud fallback, and no claim that local-only was intentionally enabled. The UI continues to show “Not configured” until the user makes a choice.

### AI configuration

AI configuration remains outside Clear All Vault Settings, per the approved boundary. Its current hidden defaults are removed:

- no backend is active on first launch;
- no local model is selected on first launch;
- no cloud provider is selected on first launch;
- no fallback model is selected on first launch.

The Models page persists intentional selections in its existing model-preferences store. Activating a backend produces one real active model identifier:

- Apple Foundation Models → `apple.foundation`;
- Local Model → the selected installed Ollama model;
- Cloud Model → the selected connected provider.

`RewriteService` resolves the backend from that active selection at processing time. Vault settings no longer carry an independent model choice that can disagree with the Models page. Changing “Use This Model” therefore changes the backend used by subsequent work. Model readiness is checked before note content is sent; missing runtime, missing model, missing credential, and provider failures become actionable failures rather than implicit fallback.

Existing model preferences are migrated when they contain a previously persisted intentional value. Absence remains absence. Keychain values are never copied into JSON or cleared by the vault reset.

## State and Persistence

`StoredState` receives a schema-version bump and decodes the previous schema explicitly. Existing complete vault policies migrate into complete vault configurations. New partial configurations survive relaunch. Existing pending proposals migrate with their reconstructed base/proposed text where possible; proposals that cannot be made safely actionable remain visible as retryable failures rather than being blindly applied.

Model preferences remain in their existing store but expose change observation/callbacks so the Dashboard model page, bottom bar status, and rewrite service read the same current selection. The app no longer creates independent model-state copies that can drift.

History and snapshots remain separate durable application data. Clearing vault settings never rewrites or deletes them. A reset failure is surfaced in Settings and does not display a success state.

## Processing Pipeline

The processing sequence will be explicit and testable:

1. A bookmark-backed connected vault is resolved and indexed.
2. `FolderObserver` coalesces filesystem changes; `NoteService` records the latest per-file change generation.
3. `ProcessingScheduler` checks pause state, complete vault configuration, active model configuration, inactivity or sweep eligibility, inclusion rules, size/encoding, and per-file in-flight ownership.
4. `VaultScanner.read` captures exact source text and modification metadata.
5. `CleanupRules` applies deterministic, idempotent repairs first. In keeping with Chamfer's existing two-level trust model, a changed rules result is snapshotted and safely written automatically, recorded accurately as a rules change in history, and fed back into the index. A stale source refuses the write and remains owed.
6. The note is read again after any rules write so AI always works from the exact current text.
7. `MarkdownMask` protects configured Markdown structures and always-protected payloads.
8. `RewritePipeline` checks backend availability, sends the configured content to the selected real backend, validates placeholders and structural constraints, rejects empty/malformed/unsafe responses, and produces final text.
9. `RewriteGate` validates the complete change and `TextDiff` produces review hunks.
10. A proposal stores the exact base text, exact proposed text, hunks, source metadata, vault/configuration generation, model metadata, and failure/retry state.
11. Review presents the complete original, complete proposal, diff, mode, model, timing, fallback, and outdated state.
12. Approval revalidates file access and current text, snapshots the exact current file, writes atomically, suppresses the matching watcher echo, refreshes the index, records full history, and removes the proposal.
13. Rejection removes only the proposal and leaves the file untouched.
14. Undo snapshots the current version, restores the historical full text atomically, refreshes index/history, and remains undoable itself.

If the configured rewrite mode requires AI and the model is unavailable, the safe deterministic rules pass may still succeed, exactly as the existing product contract promises; no AI-derived text is written and a useful retryable model failure is shown.

## Concurrency and Staleness

Every processing attempt captures:

- file URL and source fingerprint;
- latest watcher change generation;
- vault identifier and vault-settings generation;
- active-model generation;
- service reset generation.

Before creating or applying a proposal, the service compares those values with current state. A changed file, cleared/reconfigured vault, changed model, disconnected vault, rejected/regenerating proposal, pause transition, or reset invalidates the old result. A late task may report a failure only if its proposal is still current; it cannot recreate cleared or rejected work.

Repeated watcher events are coalesced and own-write echoes are consumed once. Per-URL in-flight ownership prevents overlapping rewrites, while a newer edit remains owed after older work completes.

## Review and Outdated Approval

`Proposal` will persist `baseText` and `proposedText`; hunks remain a presentation artifact. This fixes the current contradiction where the UI offers “Apply anyway” but applying hunks to changed text necessarily fails.

For a current proposal, approval requires the current file to equal `baseText` and uses the proposal's exact `proposedText`.

For an outdated proposal, the warning explains that approval replaces newer content. If the user confirms, Chamfer writes the persisted `proposedText` against the exact current text read immediately before the write, snapshots that current text, and records `sourceWasOutdated` plus both versions in history. A concurrent change between warning and write is still refused by `NoteWriter`'s expected-text check.

Regenerate uses the current file as a new base and replaces the old proposal only after the new attempt has safely established its state.

## UI Wiring

The shipping UI audit will address every known disconnected action:

- Settings gets the confirmed vault-reset action plus real pending/success/failure state.
- Models owns one shared persisted state and activation controls affect processing.
- Vault setup shows every unset field and explains missing requirements.
- Review displays complete content plus hunks and all actions call real services.
- The menu-bar Review action routes to the Review destination rather than merely opening the last-selected window.
- The proposal card's empty Open Note closure becomes a required action.
- controls are disabled from real capability/readiness state, with loading and failure labels tied to actual work.

Gallery-only callbacks remain fixture behavior and are not treated as shipping app functionality.

## Test Vault and Integration Exercise

Exactly 20 varied Markdown files will be authored under `~/Documents/Chamfer Test Vault`. Before creating them, the target will be inspected to avoid overwriting unrelated data. The set will cover realistic clean, lightly messy, heavily messy, structured, protected, and mixed-format notes.

Automated integration tests will exercise the real scanner, eligibility, deterministic cleanup, mask/gate/diff pipeline, proposal persistence, safe writer, snapshot store, history, undo, restart restoration, watcher coalescing, reset invalidation, outdated approval, and reconfiguration against real temporary files. Backend tests will cover actual backend selection and availability/error mapping. A live-model smoke path will use the selected real backend only when its runtime/credential is genuinely available and will report an explicit blocked result otherwise; it will never substitute a fake backend while claiming a live success.

Project rules prohibit Computer Use and visual UI verification. Code-level tests/builds and filesystem inspection will be performed here; the final handoff will ask the user to verify visual behavior once.

## Motion and Accessibility

Motion work happens only after the functional pipeline passes code-level verification. The existing `Chamfer.Motion` spring vocabulary remains the single source of truth. Ad hoc curves will be folded into task-appropriate tokens so related transitions are consistent and interrupted springs preserve velocity.

Every large translation, scaling, depth, or multi-element navigation transition will honor Reduce Motion by removing spatial travel and using the existing reduced cross-fade token. Where the system prefers cross-fade transitions, navigation replacements will avoid directional slides. Loading motion will communicate real progress only, and completion animation will occur only after the underlying action succeeds.

The native Apple Design Elements skill is unavailable in this environment and no corresponding local Claude skill was found, so the motion audit uses current first-party SwiftUI accessibility and animation guidance as its reference.

## Verification Standard

New behavior is developed test-first. Tests must initially fail for the intended reason, then pass after the smallest implementation slice. Completion requires fresh evidence from the entire test suite, builds for shipping and gallery targets, code-level integration against the test vault, exact file-count/content checks, persisted-state restart checks, and a clean audit for stubbed shipping actions.

The pre-change suite could not start in the current environment because the active Swift 6.3.3 compiler is incompatible with the installed macOS SDK built by Swift 6.3.2. Verification will retry with an isolated SwiftPM scratch directory and will report the toolchain blocker precisely if it remains after implementation.
