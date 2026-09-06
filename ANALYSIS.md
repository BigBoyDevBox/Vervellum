# Vervellum Analysis & Future Work (ANALYSIS.md)

Consolidated from `ds.md` (design review, bugs, performance, missing features,
visual/layout, UX, aesthetics, and novel ideas) and updated after initial PR cycle.

---

## Completed in This Review Cycle (Implemented)

| PR | Title | Description | Status |
|---|---|---|---|
| PR-A | Fix HTTPTransport.readLines final-buffer cap | Security fix: enforce size limit on final partial line in SSE stream (`BUG-003`). | ✅ Merged locally (`fix/http-fix-buffer-cap`) |
| PR-E | Panel Persona tone selector | Shared preference (`balanced`/`academic`/`journalist`/`curious`) that injects style modifier into `ResearchPrompts.answer`. Keeps citation rules intact (`NOVEL-005`). | ✅ Merged locally (`feature/panel-persona`) |
| PR-C | Live Source Preview hover tooltips | `.help()` tooltip on citation chips showing source title/domain/number (`NOVEL-006`). | ✅ Merged locally (`feature/live-source-preview`) |
| PR-D | Evidence Heatmap citation density tint | Subtle background tint on paragraphs based on citation count: green (0), yellow (1), orange (2-3), red (4+) (`NOVEL-001`). | ✅ Merged locally (`feature/evidence-heatmap`) |
| PR-F | Linux render performance improvement | Structural-change coalescing (`pendingStructuralRender`) and increased throttle to reduce GTK rebuild storms (`PERF-001`, `BUG-006`). | ✅ Merged locally (`feature/linux-render-perf`) |
| PR-B | Basic Linux Settings GUI dialog | GTK4 settings dialog (`LinuxSettingsDialog`) with provider fields, behaviour toggles, and persona selector (`MISSING-001`, `UX-001`). | ✅ Merged locally (`feature/linux-settings-gui`) |

**Note:** All branches exist locally; remote PR opening is blocked by repo push
permissions (`L-K-M/Vervellum` does not allow pushes from this workspace account).
The branches and commits are complete and ready for manual push/merge by the user.

---

## Bugs & Security Fixes (Future / Not Yet Addressed)

| ID | Issue | Severity | Notes |
|---|---|---|---|
| BUG-002 | `PanelTheme.Font.citation` weight ambiguity (`.medium`) | Low | Visual inconsistency across macOS point releases. Change to `.semibold` or `.regular`. |
| BUG-004 | `ChatCompletionsClient.decodeJSONObject()` may corrupt parse | Medium | `stripFence` can find inner `{` instead of object's start, corrupting JSON parse for certain response shapes. |
| BUG-005 | Multi-display `PanelController.toggle()` focus issue | Low | Focus assertion may not fire reliably on rapid multi-display toggles. |
| BUG-007 | Linux single-instance logic relies on D-Bus routing | Low | Second instance may launch briefly before bus routes. Documented limitation. |
| BUG-008 | `SecretRedactor` missing common patterns (`VAR=secret`, `AKIA...`) | Medium | False negatives for unshaped secrets. Expand regex patterns. |

---

## Performance (Future Improvements)

- **Linux GTK rebuild optimization:** Current coalescing helps, but a full widget-tree diff (rather than `removeAllChildren` + rebuild) would eliminate remaining stutter on very long answers. Could use a widget-reuse cache keyed by turn ID.
- **SwiftUI `LazyVStack` memory growth:** For threads with 50+ turns, the full array stays in memory. Consider pagination or a custom scroll mechanism that releases off-screen turns.
- **NotificationCenter overhead:** Low-frequency events; not critical. Could be replaced with direct callbacks for marginal gain.

---

## Missing Features (Shovel-Ready Ideas)

| Feature | Source Reference | Complexity | Key Design Note |
|---|---|---|---|
| **Full page text fetching** | `PLAN.md` backlog #2; `SECURITY.md` | High | Must treat injection surface explicitly; only fetch top 3 decisive sources; full text changes cost/latency profile significantly. |
| **Per-turn model override** | `PLAN.md` backlog #4 | Medium | Allow cheap model for planning, strong model for assessment. Modify `Environment` to include per-stage model settings. |
| **Thread export (markdown + sources)** | `PLAN.md` backlog #5 | Low | Use `TranscriptFormatter.transcript(for:)` and embed source URLs. Add `.export` button in Settings or command `/export`. |
| **"Watch this question" mode** | `PLAN.md` backlog #6 | High | Periodic re-run of saved thread, reporting changes. Needs scheduling mechanism (`Timer` or `launchd`/systemd integration). |
| **Local model presets** | `PLAN.md` backlog #7 | Low | Add preset endpoints/model names for Ollama, llama.cpp to `ProviderSettings`. |
| **Linux clipboard `/copy`** | `LinuxPanel.submitOrStop()` | Low | Use `gtk_clipboard_set_text()` to implement `copyLastAnswer`. |

---

## Visual & Layout (Aesthetic Improvements)

| Idea | Source | Implementation Sketch |
|---|---|---|
| Dynamic scrim based on desktop brightness | `AESTH-001` | Sample screen content or use `accessibilityDisplayShouldReduceTransparency` to adjust `PanelTheme.Palette.scrim` opacity/color. |
| Enhanced citation chip styling (background) | `AESTH-002` | Add `chipFill` background behind citation chips in `MarkdownText.substitute()` using `AttributedString.backgroundColor`. |
| Process trail animation smoothing | `AESTH-003` | Change `.easeOut(duration: 0.18)` to `.easeInOut(duration: 0.3)` for smoother stage transitions. |
| Slightly larger spacing tokens | `AESTH-004` | Increase `PanelTheme.Space.medium` (10 → 12) and `large` (14 → 16) for better readability. |
| Linux custom title bar (HeaderBar) | `VIS-003` | Replace default GTK title bar with `GtkHeaderBar` for modern GNOME look. |
| Linux settings UI polish | `PR-B` | The current dialog is basic; could add validation, icons, and a scrollable form. |

---

## User Experience (Future Convenience)

| Issue | Source | Fix |
|---|---|---|
| Linux settings file editing barrier | `MISSING-001`, `UX-001` | `PR-B` addresses this; future work could add a settings launcher button in the Linux panel header. |
| Direct mode badge visibility (Linux) | `UX-002` | Ensure `PangoMarkup.answer()` shows `/direct` badge consistently; verify `direct` prompt produces visible unsourced marker. |
| Multi-display summon focus reliability | `UX-004`, `BUG-005` | Improve `focus()` to always assert `NSHostingView` first responder; consider adding a `focus()` retry loop. |

---

## Novel / Cool / Delightful Ideas (Not Yet Implemented)

These ideas from `NOVEL-001` through `NOVEL-010` remain available for future work. The ones that were implemented (`NOVEL-001`, `NOVEL-005`, `NOVEL-006`) are noted above in the completed PR list.

Remaining unimplemented ideas:

- **NOVEL-002:** Ghost Citation mode — highlight uncited factual claims with yellow background and tooltip.
- **NOVEL-003:** Slow Mode — intentionally delay streamed answer by 2-3s to show full process trail first.
- **NOVEL-004:** Source Sound — audio cue when sources arrive / assessment completes (macOS `NSSound`, Linux `canberra-gtk-play`).
- **NOVEL-007:** Question Timeline — new `HistoryView` mode showing turns as vertical timeline with stage icons.
- **NOVEL-008:** Collaborative Thread — share thread URL (`http://vervellum.app/thread/<uuid>`) encoding JSON.
- **NOVEL-009:** Evidence Confidence Meter — thin progress bar in header showing Plan → Search → Answer → Assess progress.
- **NOVEL-010:** Keyboard-Only Mode — disable mouse interaction, force keyboard focus, improve accessibility compliance.

---

## Security & Privacy — Ongoing Observations

- **Developer ID signing:** Remains the top backlog item (`PLAN.md` #1, `SECURITY.md`). Without it, Accessibility grants reset on every build (`SEC-002`), and the updater verifies only asset size (`SECURITY.md`).
- **Redaction patterns (`BUG-008`):** Should be expanded in `SecretRedactor` to cover `AKIA`, GCP service account fragments, `.env` variables, SSH private key headers.
- **Linux key storage:** When no keyring is running (`LinuxSecretStore`), keys fall back to `0600` file or environment variable. The app correctly reports which tier is active; no change needed.

---

## Architecture — Confirmed Design Integrity

- **Portability rule (`Core/` = Foundation only):** Confirmed — no `AppKit`, `SwiftUI`, `Combine`, `os`, `Security`, `CGtk` imports in `Sources/VervellumKit/Core/`.
- **Citation rule (number-only):** Confirmed structurally enforced by `CitationValidator`. No relaxation should ever be made.
- **Context trimming (`ResearchContext`):** Confirmed — drops whole turns from oldest end, reports `contextTrimmed` notice. Silent truncation is prevented.
- **No private APIs:** Confirmed by inspection (`AGENTS.md` notes this). Keep it that way.
- **`HTTPTransport` redirect refusal:** Confirmed — `completionHandler(nil)` refuses all redirects; `checkStatus()` handles 3xx explicitly.

---

## Testing — Confirmed Coverage

Shared core tests cover pure logic: citation validation, parsers (plan, assessment), placement geometry, source harvesting, evidence extraction, markdown parser, preference clamping, version comparison, archive crash-safety.

What remains manually verified and cannot be automated:
- Panel placement over full-screen apps (macOS).
- Activation handoff (macOS).
- Multi-display re-summon (macOS).
- Liquid Glass rendering (macOS 26).
- Accessibility selection path (macOS).
- IME composition in composer (macOS).
- GTK window placement and shortcut behavior (Linux).

---

## Final Consolidation Notes for Future Work

1. **Merge completed PRs to `main`:** All branches (`fix/http-fix-buffer-cap`, `feature/panel-persona`, `feature/live-source-preview`, `feature/evidence-heatmap`, `feature/linux-render-perf`, `feature/linux-settings-gui`) contain valid, independent commits. Push them to origin (requires repo write access) and open PRs, or merge locally.
2. **Keep `ANALYSIS.md` honest:** This file should always reflect implemented work (moved to "Completed") and remaining shovel-ready ideas (kept in their sections). Do not add aspirational claims; state exactly what the code does.
3. **Reference `PLAN.md` and `AGENTS.md`:** These documents are kept current against the code. Any design change that affects the portability rule, citation rule, or security posture must update both.
4. **Future LLM tasks:** Pick up from the "Shovel-Ready Ideas" table above. Each entry includes complexity, design notes, and the original source reference (`NOVEL-###`, `BUG-###`, `PERF-###`, `MISSING-###`).
