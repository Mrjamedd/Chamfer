# Motion changes

This pass keeps motion in the view layer. No animation callback owns business
state, persistence, file access, model work, or review authority; removing the
motion leaves the same actions and state transitions intact.

The shared curves are in `Sources/ChamferUI/Tokens.swift` under
`Chamfer.Motion`: `quick`, `interactive`, `navigation`, `lift`, and `reduced`.
`Chamfer.Motion.reduce(_:when:)` selects the short symmetric cross-fade curve
when macOS Reduce Motion is enabled.

| Screen or component | Added or materially changed motion | Controlling file | Selective disable or revert |
| --- | --- | --- | --- |
| Main navigation and note/home changes | Page changes now cross-fade/offset with a restrained navigation curve; externally requested destinations use the same transition. | `Sources/ChamferUI/DashboardView.swift` | Replace `notePageTransition` and `homeScreenTransition` with `.opacity`, and remove the surrounding `withAnimation` calls. |
| Home activity cards and entry state | Cards arrive as a short stagger, lift on hover, and keep layout continuity as activity changes. | `Sources/ChamferUI/HomeScreenView.swift` | Return `.opacity` from the local transitions and remove `cardLiftCurve`/`cardArriveCurve` animation modifiers. |
| Bottom navigation bar | Opening, resizing, search, idle folding, split controls, counts, and attention dots animate in the bar’s own isolated presentation state. | `Sources/ChamferUI/BottomBar.swift` | Replace the local `openCurve`, `closeCurve`, `resizeCurve`, `searchCurve`, and `splitCurve` values with `Chamfer.Motion.reduced`, or remove their `withAnimation` wrappers. Counts/dots can use `.identity` transitions. |
| Menu-bar panel | The AppKit panel scales from its status-item edge and fades on open/close; it closes immediately under Reduce Motion. | `Sources/ChamferUI/MenuBarController.swift` | Call `orderFrontRegardless()`/`orderOut(nil)` directly and remove `animateIn`, `animateOut`, and `collapsed`. |
| Menu-bar status changes | Status content changes use a reduced-aware presentation transition. | `Sources/ChamferUI/MenuBarPanel.swift` | Remove the transition/animation modifier; menu actions are separate closures. |
| Model landscape/configuration | The selected model control morphs into its configuration surface; activation/collapse, connection state, download state, hover glow, and pressed feedback use shared curves. | `Sources/ChamferUI/ModelsPageView.swift`, `Sources/ChamferUI/ModelsConfigurationSheet.swift`, `Sources/ChamferUI/ModelsLandscapeState.swift` | Set morph progress synchronously in `openConfiguration`/`collapseConfiguration`, replace the sheet transition with `.opacity`, and remove presentation-only `withAnimation` blocks. Model saves and runtime calls remain in their completion/actions. |
| Review timeline | Pending rows visibly move into history, bulk controls fade, expanded diffs resize, outdated confirmation scales/fades, and regeneration shows a slow sheen. | `Sources/ChamferUI/ReviewTimelinePage.swift` | Return `.opacity` from `rowTransition`/`sheetTransition`, remove timeline animation modifiers, and remove the `sheen` branch. Reduce Motion already uses opacity and disables sheen. |
| Vault disclosure/setup | A vault row unfolds from its top edge; setup attention, rule editor, note picker, and disclosure chevron transition without moving business state into animation code. | `Sources/ChamferUI/VaultsPage.swift` | Replace `VaultsPage.disclosure` with `Chamfer.Motion.reduced`, use `.opacity` for the detail/rule transitions, or remove the animation modifiers. |
| Settings and preservation controls | Tab content and optional preservation/rule detail reveal with reduced-aware cross-fades/resizing. | `Sources/ChamferUI/SettingsView.swift`, `Sources/ChamferUI/PolicyEditor.swift` | Remove the local `withAnimation`/`.animation` modifiers; bindings still update immediately. |
| Shared hover/press feedback | Buttons, rings, glows, and transient visibility use the centralized quick/lift curves rather than scattered easing values. | `Sources/ChamferUI/HoverGlow.swift`, `Sources/ChamferUI/Primitives.swift` | Remove the animation modifiers or change their token to `Chamfer.Motion.reduced`. |

To disable nearly all SwiftUI motion for a diagnostic build, change
`Chamfer.Motion.quick`, `interactive`, `navigation`, and `lift` to the same
near-instant animation in `Tokens.swift`. The AppKit menu panel is the one
exception and can be disabled independently as described above.

