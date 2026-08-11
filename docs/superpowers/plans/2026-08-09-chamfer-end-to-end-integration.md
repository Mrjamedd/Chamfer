# Chamfer End-to-End Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Chamfer function from an intentionally unconfigured launch through real vault processing, AI review/application, history/undo, restart, and a vault-settings-only reset.

**Architecture:** Preserve the existing target and service boundaries. Add a persisted partial `VaultConfiguration`, keep `RewritePolicy` fully resolved, expose one optional global model selection, and make `AppModel`/`NoteService`/`RewriteService` coordinate configuration generations so stale asynchronous work cannot survive resets or reconfiguration. Wire deterministic rules and sectioned AI work through the existing safe writer, proposal, review, and history systems.

**Tech Stack:** Swift 6.2 package syntax, macOS 26, SwiftUI, Observation, Swift Testing, Foundation Models, Ollama HTTP, cloud-provider HTTP APIs, FSEvents, security-scoped bookmarks, Keychain, atomic Foundation file I/O.

## Global Constraints

- Never use Computer Use for this project.
- Do not perform visual UI verification; after code-level tests and builds, ask the user to verify visual behavior once.
- Preserve the dirty worktree and do not stage or overwrite unrelated user changes.
- Clear All Vault Settings keeps vault connections and every part of AI configuration.
- No workflow may substitute a default for an unset user choice.
- Note content is never silently overwritten after a stale read or failed validation.
- The test vault contains exactly 20 `.md` files at `/Users/anthonymurphy/Documents/Chamfer Test Vault`.
- Motion follows Reduce Motion and cross-fade accessibility guidance.

---

### Task 1: Persist Partial Vault Intent Without Runtime Defaults

**Files:**
- Modify: `Sources/ChamferCore/RewritePolicy.swift`
- Modify: `Sources/ChamferCore/Vault.swift`
- Modify: `Tests/ChamferCoreTests/RewritePolicyTests.swift`

**Interfaces:**
- Produces: `VaultConfiguration`, `VaultConfiguration.missingFields`, `VaultConfiguration.resolve(modelID:) -> RewritePolicy?`
- Produces: strict `RewritePolicy.init(mode:application:inactivityDelay:sweep:preserved:modelID:)`

- [ ] **Step 1: Write failing tests for empty, partial, and complete configurations**

```swift
@Test func aFreshVaultHasNoSelectedRewriteBehavior() {
    let vault = Vault(url: URL(filePath: "/Vault"), noteCount: 0)
    #expect(vault.configuration == nil)
    #expect(!vault.isConfigured)
}

@Test func aPartialConfigurationCannotResolveBySubstitutingDefaults() {
    let partial = VaultConfiguration(mode: .spelling)
    #expect(partial.missingFields.contains(.application))
    #expect(partial.resolve(modelID: "apple.foundation") == nil)
}

@Test func everyIntentionalChoiceResolvesExactly() throws {
    let configured = VaultConfiguration(
        mode: .grammar,
        application: .review,
        inactivityDelay: 300,
        sweep: .everyHours(6),
        preserved: [.links, .codeBlocks]
    )
    let policy = try #require(configured.resolve(modelID: "local.qwen"))
    #expect(policy.mode == .grammar)
    #expect(policy.modelID == "local.qwen")
}
```

- [ ] **Step 2: Run the focused core tests and confirm they fail because `VaultConfiguration` does not exist**

Run: `./Scripts/test.sh --filter RewritePolicyTests --scratch-path /tmp/chamfer-tdd-policy`

- [ ] **Step 3: Add the optional persisted configuration and remove `Vault.startingPoint`**

```swift
public struct VaultConfiguration: Sendable, Equatable, Codable {
    public var mode: RewriteMode?
    public var application: RewriteApplication?
    public var inactivityDelay: TimeInterval?
    public var sweep: SweepSchedule?
    public var preserved: MarkdownStructure?

    public func resolve(modelID: String?) -> RewritePolicy? {
        guard let mode, let application, let inactivityDelay,
              let sweep, let preserved, let modelID else { return nil }
        return RewritePolicy(mode: mode, application: application,
            inactivityDelay: inactivityDelay, sweep: sweep,
            preserved: preserved, modelID: modelID)
    }
}
```

- [ ] **Step 4: Update core call sites and fixtures to construct complete values explicitly**
- [ ] **Step 5: Run the focused tests and confirm pass or record the existing toolchain blocker**
- [ ] **Step 6: Commit only this coherent slice when verification is available**

### Task 2: Make Global Preferences and Model Selection Genuinely Unconfigured

**Files:**
- Modify: `Sources/ChamferCore/AppPreferences.swift`
- Modify: `Sources/ChamferUI/ModelsLandscapeState.swift`
- Modify: `Sources/ChamferUI/ModelsPreferences.swift`
- Modify: `Sources/ChamferUI/ModelsConfigurationSheet.swift`
- Modify: `Sources/ChamferUI/ModelsPageView.swift`
- Modify: `Tests/ChamferCoreTests/ProcessingGuardTests.swift`
- Modify: `Tests/ChamferUITests/ModelsPageTests.swift`
- Modify: `Tests/ChamferUITests/SettingsAccessTests.swift`

**Interfaces:**
- Produces: optional preference choices with safe non-running interpretations
- Produces: `ModelsSelection.activeModelID(defaults:) -> String?`
- Produces: model state with `active: ModelsBackendID?`, `selectedLocalModelID: String?`, and `cloudProvider: CloudProvider?`

- [ ] **Step 1: Write failing tests proving no model, provider, local model, notification, privacy, or login choice exists in empty stores**

```swift
@Test func emptyModelPreferencesDoNotSelectAppleOrALocalModel() {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let state = ModelsPreferences.loadState(defaults: defaults)
    #expect(state.active == nil)
    #expect(state.selectedLocalModelID == nil)
    #expect(ModelsPreferences.loadCloudProvider(defaults: defaults) == nil)
}

@Test func emptyAppPreferencesDoNotClaimUserIntent() {
    let preferences = AppPreferences.unconfigured
    #expect(preferences.localProcessingOnly == nil)
    #expect(preferences.launchAtLogin == nil)
    #expect(NotificationCategory.allCases.allSatisfy {
        preferences.notificationChoice(for: $0) == nil
    })
}
```

- [ ] **Step 2: Run focused UI/core tests and verify the hidden-default assertions fail**
- [ ] **Step 3: Replace fallback expressions (`?? .apple`, `?? "qwen…"`, `?? .openAI`) with optional state**
- [ ] **Step 4: Map an intentionally active model to the actual backend identifier**

```swift
static func activeModelID(defaults: UserDefaults = .standard) -> String? {
    let state = ModelsPreferences.loadState(defaults: defaults)
    switch state.active {
    case .apple: return "apple.foundation"
    case .mlx: return state.selectedLocalModelID.map { "local.\($0)" }
    case .ollama:
        return ModelsPreferences.loadCloudProvider(defaults: defaults)
            .map { "cloud.\($0.rawValue)" }
    case nil: return nil
    }
}
```

- [ ] **Step 5: Render unset choices as “Not configured” and gate activation on real readiness**
- [ ] **Step 6: Run focused tests**

### Task 3: Migrate State Without Inventing Values

**Files:**
- Modify: `Sources/ChamferWatch/StateStore.swift`
- Modify: `Sources/Chamfer/AppModel.swift`
- Modify: `Tests/ChamferWatchTests/StateStoreTests.swift`
- Modify: `Tests/ChamferTests/AppModelLifecycleTests.swift`

**Interfaces:**
- Produces: `StoredState.currentVersion == 2`
- Produces: v1-to-v2 migration from complete `RewritePolicy` to complete `VaultConfiguration`
- Produces: `AppModel.configurationGeneration: UInt64`

- [ ] **Step 1: Add golden JSON tests for fresh v2, v1 migration, partial configuration relaunch, and future-version refusal**
- [ ] **Step 2: Run focused persistence tests and verify v1/partial cases fail**
- [ ] **Step 3: Add explicit legacy decoding structs and convert only values actually present in v1**
- [ ] **Step 4: Restore partial values and keep future-version overwrite protection**
- [ ] **Step 5: Run StateStore and AppModel lifecycle tests**

### Task 4: Add the Confirmed Vault-Settings Reset Boundary

**Files:**
- Modify: `Sources/Chamfer/AppModel.swift`
- Modify: `Sources/Chamfer/NoteService.swift`
- Modify: `Sources/Chamfer/RewriteService.swift`
- Modify: `Sources/Chamfer/ChamferApp.swift`
- Modify: `Sources/ChamferUI/SettingsView.swift`
- Modify: `Tests/ChamferTests/AppModelLifecycleTests.swift`
- Modify: `Tests/ChamferTests/RewriteServiceLifecycleTests.swift`
- Modify: `Tests/ChamferUITests/SettingsAccessTests.swift`

**Interfaces:**
- Produces: `AppModel.clearAllVaultSettings()`
- Produces: `NoteService.clearProcessingTriggers()`
- Produces: `RewriteService.invalidateInFlightWork()`
- Produces: `SettingsView(..., clearAllVaultSettings: @escaping @MainActor () -> Result<Void, VaultSettingsResetFailure>)`

- [ ] **Step 1: Write a lifecycle test with two configured vaults, rules, proposals, history, model preferences, bookmarks, and indexed notes**

```swift
model.clearAllVaultSettings()
#expect(model.dashboard.vaults.allSatisfy { $0.configuration == nil && $0.rules.isEmpty })
#expect(model.dashboard.proposals.isEmpty)
#expect(model.dashboard.history == originalHistory)
#expect(model.dashboard.searchableNotes == originalIndex)
#expect(model.bookmark(for: firstVault.id) == originalBookmark)
```

- [ ] **Step 2: Write an async test proving a model result released after reset creates neither proposal nor write**
- [ ] **Step 3: Run and verify both tests fail**
- [ ] **Step 4: Implement the atomic model mutation, generation increment, trigger clearing, and late-result guard**
- [ ] **Step 5: Add a confirmation dialog whose destructive action reports persistence failure and never claims success early**
- [ ] **Step 6: Run reset-focused tests**

### Task 5: Use the Active Model and Check Availability Before Sending Content

**Files:**
- Modify: `Sources/Chamfer/RewriteService.swift`
- Modify: `Sources/ChamferRewrite/RewriterFactory.swift`
- Modify: `Sources/ChamferRewrite/RewritePipeline.swift`
- Modify: `Tests/ChamferRewriteTests/RewriterTests.swift`
- Modify: `Tests/ChamferRewriteTests/RewritePipelineTests.swift`
- Modify: `Tests/ChamferTests/RewriteServiceLifecycleTests.swift`

**Interfaces:**
- Consumes: `ModelsSelection.activeModelID() -> String?`
- Produces: `RewritePipeline.run` availability check before `rewrite`
- Produces: missing-configuration failure distinct from unavailable-model failure

- [ ] **Step 1: Write tests proving changing active selection changes the resolver input and an unavailable rewriter receives zero rewrite calls**
- [ ] **Step 2: Run and verify failures**
- [ ] **Step 3: Resolve vault policy using the one active global model and check `await rewriter.isAvailable`**
- [ ] **Step 4: Keep fallback opt-in and local-only gating exact; never infer provider/model**
- [ ] **Step 5: Run pipeline/service tests**

### Task 6: Run Deterministic Rules Through Safe Writes and Durable History

**Files:**
- Modify: `Sources/ChamferCore/History.swift`
- Modify: `Sources/ChamferCore/DashboardState.swift`
- Modify: `Sources/Chamfer/RewriteService.swift`
- Modify: `Sources/ChamferUI/ReviewTimelinePage.swift`
- Modify: `Tests/ChamferTests/RewriteServiceLifecycleTests.swift`
- Modify: `Tests/ChamferCoreTests/ReviewTimelineTests.swift`

**Interfaces:**
- Produces: accurate history origin `.rules(ruleIDs:)` versus `.rewrite(...)`
- Produces: `RewriteService.processRules(url:policy:generation:)`

- [ ] **Step 1: Write a real-file test where malformed spacing is snapshotted, atomically normalized, indexed, recorded as rules history, and then offered to AI from the normalized bytes**
- [ ] **Step 2: Write stale-write and idempotence tests**
- [ ] **Step 3: Run and verify the disconnected-rule tests fail**
- [ ] **Step 4: Apply `CleanupRules`, write through `NoteWriter`, update `CleanupRecord` and durable history, then reread before AI**
- [ ] **Step 5: Teach timeline/history summary and undo to represent rules truthfully**
- [ ] **Step 6: Run service, writer, cleanup, history, and timeline tests**

### Task 7: Process AI Section by Section and Preserve Protected Structures

**Files:**
- Create: `Sources/ChamferRewrite/MarkdownSections.swift`
- Modify: `Sources/ChamferRewrite/RewritePipeline.swift`
- Modify: `Sources/ChamferCore/MarkdownMask.swift`
- Modify: `Tests/ChamferRewriteTests/RewritePipelineTests.swift`
- Modify: `Tests/ChamferCoreTests/MarkdownMaskTests.swift`

**Interfaces:**
- Produces: `MarkdownSections.split(_:targetCharacters:) -> [MarkdownSection]`
- Produces: sequential section rewriting with one assembled whole-note gate/diff

- [ ] **Step 1: Write literal section fixtures proving front matter/code fences are never split and headings establish section boundaries**
- [ ] **Step 2: Write a recording-rewriter test proving a long note is sent in bounded sections, in order, and reassembled exactly**
- [ ] **Step 3: Run and verify whole-note implementation fails**
- [ ] **Step 4: Implement the pure sectioner and section attempts while retaining whole-note final validation**
- [ ] **Step 5: Add mask fixtures for current protected structures and repeated placeholders**
- [ ] **Step 6: Run rewrite and mask tests**

### Task 8: Persist Exact Review Versions and Make Outdated Approval Real

**Files:**
- Modify: `Sources/ChamferCore/Proposal.swift`
- Modify: `Sources/ChamferCore/DashboardState.swift`
- Modify: `Sources/Chamfer/RewriteService.swift`
- Modify: `Sources/ChamferUI/ReviewTimelinePage.swift`
- Modify: `Tests/ChamferCoreTests/ReviewTimelineTests.swift`
- Modify: `Tests/ChamferTests/RewriteServiceLifecycleTests.swift`
- Modify: `Tests/ChamferWatchTests/StateStoreTests.swift`

**Interfaces:**
- Produces: `Proposal.baseText` and `Proposal.proposedText`
- Produces: `RewriteService.apply(_:as:allowOutdated:)`

- [ ] **Step 1: Write a restart test proving complete original/proposed text survives JSON round-trip**
- [ ] **Step 2: Write a real-file outdated approval test: current newer text is snapshotted, exact persisted proposed text is written, and history records outdated replacement**
- [ ] **Step 3: Write a concurrent-change-during-confirmation test proving expected-text refusal**
- [ ] **Step 4: Run and verify current hunk replay fails the intended outdated approval**
- [ ] **Step 5: Persist full versions, use hunks only for display, and require explicit `allowOutdated`**
- [ ] **Step 6: Show full original/proposal content with actual hunks and metadata**
- [ ] **Step 7: Run review, store, service, and writer tests**

### Task 9: Complete Vault Setup, Scheduling, Restart, and Race Wiring

**Files:**
- Modify: `Sources/Chamfer/ProcessingScheduler.swift`
- Modify: `Sources/Chamfer/NoteService.swift`
- Modify: `Sources/Chamfer/RewriteService.swift`
- Modify: `Sources/ChamferUI/PolicyEditor.swift`
- Modify: `Sources/ChamferUI/VaultsPage.swift`
- Modify: `Tests/ChamferTests/ProcessingSchedulerLifecycleTests.swift`
- Modify: `Tests/ChamferTests/NoteServiceLifecycleTests.swift`

**Interfaces:**
- Consumes: complete `VaultConfiguration` plus optional active model
- Produces: precise configuration blocker text and owed-work semantics

- [ ] **Step 1: Add tests for each missing field, missing model, reconfiguration after reset, restart with partial state, schedule completion, and edit-during-rewrite owed state**
- [ ] **Step 2: Run and verify gating failures**
- [ ] **Step 3: Bind each policy control to optional persisted state with “Not configured” display**
- [ ] **Step 4: Gate scheduler without consuming owed work when the missing requirement can later be supplied**
- [ ] **Step 5: Recheck vault/model/reset generations before every proposal or write side effect**
- [ ] **Step 6: Run scheduler/note/service/core schedule tests**

### Task 10: Finish Shipping UI Actions and Shared Navigation

**Files:**
- Modify: `Sources/ChamferCore/DashboardState.swift`
- Modify: `Sources/Chamfer/ChamferApp.swift`
- Modify: `Sources/ChamferUI/DashboardView.swift`
- Modify: `Sources/ChamferUI/MenuBarController.swift`
- Modify: `Sources/ChamferUI/ProposalViews.swift`
- Modify: `Tests/ChamferUITests/BarCountTests.swift`
- Modify: `Tests/ChamferUITests/SettingsAccessTests.swift`

**Interfaces:**
- Produces: shared `DashboardDestination` binding used by window and menu bar
- Produces: required `ProposalCard.onOpen`

- [ ] **Step 1: Write state tests proving menu Review selects Review, Settings reset calls the real coordinator, and Open Note cannot be instantiated with an empty action**
- [ ] **Step 2: Run and verify failures**
- [ ] **Step 3: Move destination state out of Dashboard's private copy and route menu actions to it**
- [ ] **Step 4: Replace every known shipping no-op and audit all shipping Button/Toggle/Picker actions again**
- [ ] **Step 5: Run UI-state tests**

### Task 11: Harden Cloud Requests and Live-Backend Smoke Coverage

**Files:**
- Modify: `Sources/ChamferRewrite/CloudAPI.swift`
- Modify: `Sources/ChamferRewrite/OllamaAPI.swift`
- Modify: `Tests/ChamferRewriteTests/RewriterTests.swift`
- Create: `Tests/ChamferTests/LiveBackendSmokeTests.swift`

**Interfaces:**
- Produces: current provider model identifiers and explicit timeout/malformed/empty mappings
- Produces: opt-in `CHAMFER_RUN_LIVE_AI=1` smoke test that never falls back to a fake backend

- [ ] **Step 1: Verify provider model identifiers against current official provider documentation**
- [ ] **Step 2: Add request-fixture tests for exact provider endpoints/bodies and malformed/empty/error responses**
- [ ] **Step 3: Add an opt-in live smoke that resolves the intentionally selected backend, checks availability, rewrites one controlled note, and reports a real blocked reason when unavailable**
- [ ] **Step 4: Run deterministic backend tests, then live smoke only when the environment is configured**

### Task 12: Build the Exact Test Vault and Exercise the Full Filesystem Workflow

**Files:**
- Create: `TestVault/01-grocery-list.md` through `TestVault/20-mixed-format-note.md`
- Create: `Scripts/install-test-vault.sh`
- Create: `Tests/ChamferTests/EndToEndVaultTests.swift`

**Interfaces:**
- Produces: exactly 20 source-controlled realistic Markdown fixtures
- Produces: installer targeting `/Users/anthonymurphy/Documents/Chamfer Test Vault` without overwriting unrelated content

- [ ] **Step 1: Write the integration test that rejects any fixture count other than 20 and exercises scanner → rules → model double at only the external AI boundary → proposal → approve/reject → snapshot/history/undo → persistence restore**
- [ ] **Step 2: Run and verify missing fixture failure**
- [ ] **Step 3: Author 20 meaningfully distinct notes covering the requested categories and protected structures**
- [ ] **Step 4: Implement installer preflight: fail if target exists with unrelated entries; otherwise copy the exact fixture set**
- [ ] **Step 5: Install to Documents with explicit sandbox approval and verify `find ... -name '*.md'` returns exactly 20**
- [ ] **Step 6: Run the integration test and inspect before/after bytes for approve, reject, and undo**

### Task 13: Apply the Motion/Accessibility System After Functionality

**Files:**
- Modify: `Sources/ChamferUI/Tokens.swift`
- Modify: `Sources/ChamferUI/BottomBar.swift`
- Modify: `Sources/ChamferUI/HomeScreenView.swift`
- Modify: `Sources/ChamferUI/ModelsPageView.swift`
- Modify: `Sources/ChamferUI/VaultsPage.swift`
- Modify: `Sources/ChamferUI/ReviewTimelinePage.swift`
- Modify: `Tests/ChamferUITests/BottomBarTests.swift`
- Modify: `Tests/ChamferUITests/HomeScreenTests.swift`
- Modify: `Tests/ChamferUITests/ModelsPageTests.swift`

**Interfaces:**
- Produces: centralized task-oriented motion tokens and reduced cross-fade replacements

- [ ] **Step 1: Add pure response tests showing reduced motion removes translation/scale/depth and chooses cross-fade timing**
- [ ] **Step 2: Run and verify ad hoc motion does not satisfy the response tests**
- [ ] **Step 3: Replace duplicate springs with `Chamfer.Motion` tokens and gate all large spatial transitions with Reduce Motion**
- [ ] **Step 4: Ensure loading/success motion follows actual asynchronous state**
- [ ] **Step 5: Run UI-state tests without visual UI verification**

### Task 14: Final Verification and Stub Audit

**Files:**
- Modify as required by failures only
- Update: `README.md`

**Interfaces:**
- Produces: reproducible verification evidence and accurate documentation

- [ ] **Step 1: Run `rg` audits for empty shipping actions, hidden default substitutions, direct unsafe writes, and disconnected cleanup/model calls**
- [ ] **Step 2: Run `./Scripts/test.sh --scratch-path /tmp/chamfer-final-tests`**
- [ ] **Step 3: Run `swift build --scratch-path /tmp/chamfer-final-build` and build the gallery target**
- [ ] **Step 4: Run the end-to-end vault test, persistence restart test, and opt-in real-model smoke when available**
- [ ] **Step 5: Verify exactly 20 Markdown files in the Documents test vault and confirm no source-controlled fixture was changed by tests**
- [ ] **Step 6: Update README with the exact configuration and test-vault workflow**
- [ ] **Step 7: Apply the verification-before-completion checklist and report any environment blocker without converting it into a success claim**
