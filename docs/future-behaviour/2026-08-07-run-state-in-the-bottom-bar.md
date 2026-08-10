# Future behaviour — surfacing run state in the main window

Date: 2026-08-07
Status: **planning only. Not implemented, and deliberately not in the 1.0 scope.**

This file records a decision and a candidate design for a later release. Nothing
described here should be built without a separate decision to build it.

## The decision for 1.0

Run state is visible in the menu bar panel and nowhere else. The main window
does not show whether Chamfer is watching, sweeping, rewriting, paused, or
degraded.

That is the shipping behaviour, not an oversight.

## What exists today

`RunState` in `ChamferCore/DashboardState.swift` has six cases:

| Case | Meaning |
| --- | --- |
| `idle` | Watching, nothing in progress |
| `sweeping(completed:total:)` | A scheduled sweep is walking a vault |
| `rewriting(noteTitle:)` | A model is working on one note |
| `paused` | New work is not being picked up |
| `rewritingUnavailable(reason:)` | Rules still run, the rewrite pass is off |
| `failed(message:)` | Something stopped, with an explanation |

Two components render it, both in `ChamferUI/Primitives.swift`:

- `RunStateBadge` — a `Pill` with a symbol, one for every case.
- `RunStateBanner` — a full-width tinted explanation. Deliberately renders
  `EmptyView` for everything except `rewritingUnavailable` and `failed`, on the
  principle that a healthy state does not need a paragraph.

Both are already built, already tested, and already exercised by the gallery's
component catalogue. The only place either appears in a real surface is
`MenuBarPanel` — the badge in its header, the banner beneath.

So the gap is not a missing component. It is a missing *placement*.

## Why the main window does not have one

The window is one page and one bar. The appendix to the 1.0 scope states the
rule the interface is built on:

> The bottom bar is only for modes the user lives in, and it does not grow.

A status readout is not a mode. Adding it as a fourth bar item would break that
rule for something the user does not navigate to.

The two obvious alternatives were considered and rejected:

- **A banner above the page.** It would occupy permanent vertical space in a
  window whose whole composition is a single sheet floating on cream, and it
  would be showing "Watching" — a non-event — almost all of the time.
- **A badge in the gutter cluster.** The gutter is for controls that act *on*
  the page: settings, close, versions. It is revealed by reaching for it. A
  status indicator you have to go looking for is not a status indicator, and
  putting a non-interactive element among three buttons muddles what the
  cluster is for.

Leaving it in the menu bar is also honest about where the app lives. Chamfer
keeps working with the window closed; the menu bar is the surface that is always
present, so it is the correct home for "what is happening right now".

## The candidate for later: the bottom bar

If run state is ever surfaced in the main window, the bottom bar is where it
should go — but as a **property of the existing bar**, never as a fourth item.

The bar already has the machinery this would need.

### It already has an idle state

`BarIdleBehaviour` (`ChamferUI/BottomBar.swift`) folds the bar's labels away
after 3.5 seconds of quiet, scales the glyphs down to `idleIconScale`, and
settles the whole slab to `restingOpacity`. The bar is therefore already a
surface that changes character based on what is going on rather than on what the
user clicked. Run state is the same kind of signal.

### It already has a place for transient content

The bar morphs into the search field rather than swapping for it, and grows
upward into a hover list without pushing the page. Both are precedents for the
slab carrying something other than three destinations without becoming a
different object.

### Sketch, not a specification

The shape most consistent with the existing system:

- **`idle`** — no change at all. The healthy state has no treatment, exactly as
  `RunStateBanner` already declines to render for it. This is the important
  half: anything that draws the eye when nothing is wrong will be ignored when
  something is.
- **`sweeping` and `rewriting`** — the slab's edge carries a slow, low-contrast
  progress hairline in `Chamfer.Palette.barRing`, and the bar declines to fold
  into its idle state while work is in flight. Work in progress keeps the bar
  awake; that is the signal, and it costs no layout.
- **`paused`** — the bar settles to a lower `restingOpacity` than
  `BarIdleBehaviour.standard` uses and stays there. The bar is the thing that is
  paused, so the bar is what looks paused.
- **`rewritingUnavailable` and `failed`** — the only two cases that get words.
  These already have a `RunStateBanner`, and it should be reached from the bar
  rather than shown permanently: the Review item's glyph takes a warning
  variant, and the existing hover list carries the banner at its foot, where the
  foot action already sits on the Notes item.

### Constraints any implementation must respect

1. **The bar stays at three items.** No fourth destination, no status item.
2. **`idle` renders nothing.** No "Watching" pill, no green dot.
3. **Nothing new is permanently on screen.** Every treatment above is either a
   change to an existing element's appearance or content inside the hover list
   that already exists.
4. **It must survive the idle collapse.** The bar spends most of its life folded
   with its labels gone; a treatment that only reads while the labels are shown
   is a treatment that is usually invisible.
5. **The menu bar keeps its copy.** This would be an addition, not a move. The
   panel remains the surface that works with the window closed.
6. **Reduced motion.** A progress hairline that animates needs a still variant,
   in line with every other motion in the app.

## Related

- 1.0 scope: `docs/superpowers/specs/2026-08-06-chamfer-v1.0-release-scope.md`,
  in particular the appendix "Keeping the Interface Uncrowded".
- Components that already exist: `RunStateBadge`, `RunStateBanner` in
  `Sources/ChamferUI/Primitives.swift`.
- The bar's idle machinery: `BarIdleBehaviour` in
  `Sources/ChamferUI/BottomBar.swift`.
