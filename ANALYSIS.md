# Vervellum work queue

Baseline: upstream `main` at `5be8eab`. Findings, rationale, reproductions, and the
original implementation order are preserved in [astra.md](astra.md). This document
separates unimplemented work from patches awaiting merge. Nothing listed as pending
is fixed in `main` yet.

**P1:** trust, data loss, blocking behavior. **P2:** usability/performance.
**P3:** expansion. **S/M/L:** local change / several components / design work.
`Core/` means `Sources/VervellumKit/Core/`; `Linux/` means
`Sources/VervellumKit/Linux/`. Visual hypotheses require desktop verification.

## Implemented, awaiting review and merge

Do not reimplement these. Review the linked patch, merge its prerequisite first,
and remove the pending row once upstream contains it. Original failure details
remain in `astra.md` under the same ID.

| ID | Patch | Remaining work |
|---|---|---|
| A41 | [#4 — Swift test portability](https://github.com/L-K-M/Vervellum/pull/4) | Merge first: resolves `UInt.map(Int.init)` ambiguity on Swift 6.0.3. |
| A02 | [#5 — Exact assessment citations](https://github.com/L-K-M/Vervellum/pull/5) | Review Boolean/number bridging on macOS; merge after #4. |
| A03 | [#6 — Self-contained transcripts](https://github.com/L-K-M/Vervellum/pull/6) | Review Copy/CLI output; merge after #4. |
| A21 | [#7 — Linear SSE line framing](https://github.com/L-K-M/Vervellum/pull/7) | Run macOS transport tests; merge after #4. |
| A08 | [#8 — Private result diagnostics](https://github.com/L-K-M/Vervellum/pull/8) | Review retained diagnostic schema; merge after #4. |
| A16 | [#11 — GTK native-close lifecycle](https://github.com/L-K-M/Vervellum/pull/11) | Run Ubuntu CI and GNOME Wayland close/reopen; merge after #4. |

Each independent fix branch shares only #4's one-line test prerequisite. Combined,
they merge without conflicts and pass **226 tests** with Swift 6.0.3/GTK 4.8.3 in a
Debian 12 sysroot, including the GTK lifecycle test under Xvfb. Regression failures
were observed before fixes. The SSE debug stress fixture fell from 0.886s to 0.036s;
this is not a UI performance measurement.

macOS, GNOME Wayland, release packaging, and remote CI have not been verified here.
GLM checks are **SKIPPED**, not successful: upstream disables reviews for fork PRs.
macOS/Linux CI reports `action_required` and needs maintainer approval to run.
No comments/reviews arrived during checks. The account lacks upstream push access,
so direct publication to `main` is blocked; this document and `astra.md` are offered
in [documentation PR #1](https://github.com/L-K-M/Vervellum/pull/1). All PRs remain open.

## Next: trust and data preservation

### A01 · P1/M — Only numbered citations create actionable links

**Where:** `Vervellum/Views/MarkdownText.swift`, `Core/Research/CitationValidator.swift`.

Model Markdown currently creates `AttributedString` link attributes without being
stripped. Post-stream warnings do not prevent activation. Remove model-origin links
before inserting application-owned citation links. Treat literal U+FFFC separately
so it cannot shift placeholder substitution. Keep links inert even while streaming;
do not replace numeric citations with URL allow-list matching.

**Accept:** tests cover Markdown/autolinks, custom schemes, emphasis, literal U+FFFC,
partial streams, and grouped citations. Only app-resolved citation numbers produce
links. Correct the corresponding security claims. See A25 for grouped-source UX.

### A04 · P1/M — Detect incomplete or erroneous answer streams

**Where:** `HTTPTransport.streamJSONEvents`, `ChatCompletionsClient.streamText`.

Malformed JSON frames and error envelopes can be ignored; clean EOF without a finish
reason can pass as success. The non-streaming fallback's `try? messageContent`
discards useful failure classification. Introduce a completion-state parser with an
explicit compatibility policy; preserve partial prose but never assess a failed
answer as though complete. Keep provider errors sanitized.

**Accept:** fixture tests for EOF mid-answer, malformed data, error envelopes,
`length`, filters, fallback JSON, `[DONE]`, and usage-only frames. Document which
explicit completion signals are accepted. Keep this separate from A21's line parser.

### A05 · P1/S — Validate retained prose on every terminal path

**Where:** `Core/Research/ResearchRunner.swift`.

Validation runs only after successful streaming. Validate a stopped/failed answer
once in terminal cleanup and attach notices for invalid references or literal URLs.
Do not flag half-arrived markers during normal streaming.

**Accept:** stop/failure after an invalid marker or URL preserves the prose and its
warning. Successful/direct turns still validate once. Complements A01 and A04.

### A06 · P1/M — Enforce budgets for every stage

**Where:** `Core/Research/ResearchContext.swift`, `ResearchRunner.swift`.

Dropping history cannot fix an oversized question/schema/evidence block; the current
assembler returns it anyway. Assessment bypasses assembly. Size estimates omit array
commas. Bytes are described as characters/tokens; 110 KB is no universal 32k-token
guarantee. Historic answer shortening is silent despite whole-turn-trimming claims.

Give each stage a measured budget and output reserve. Reject oversized current input
visibly, disclose historical shortening, count serialized punctuation, and distinguish
heuristics from provider token limits. Replace repeated array `removeFirst` with
prefix indices.

**Accept:** giant question/schema/answer, Unicode, exact boundaries, zero-history,
and long-history tests. No silently over-budget or silently cropped current input.

### A07 · P1/M — Redact before selection truncation

**Where:** `Vervellum/Selection/SelectedTextReader.swift`, `App/AppDelegate.swift`,
`Core/Platform/SecretRedactor.swift`.

The 8,000-character selection cap can remove a PEM closing delimiter before the
redactor sees it, defeating its complete-block pattern. Partial selections already
need conservative treatment. Return capture metadata, redact bounded captured text
before display truncation, and redact unterminated private-key blocks conservatively.

**Accept:** long complete PEMs, cut-off delimiters, ordinary prose, and visible
truncation/redaction notices. Captured text stays opt-in and is never auto-sent/logged.

### A12 · P1/M — Check archive versions before decoding turns

**Where:** `Core/Store/ThreadArchive.swift`, `ThreadLibrary.swift`.

Full decoding precedes the version check. An unknown future enum can fail decoding,
trigger fallback, and let an older build overwrite the newer file. Decode a minimal
version envelope first; expose missing/corrupt/newer/recovered states to the UI.

**Accept:** unknown verdict/notice/stage and missing fields in a newer document never
allow writes, even with a valid older backup or history disabled. Explain read-only
status rather than pretending saves work.

### A13 · P1/M — Make erasure truthful and durable

**Where:** `ThreadArchive`, macOS engine/store/settings, `LinuxEnvironment`/panel.

History-off and Delete All discard deletion errors. Active research can be saved
again after erasure. Linux startup with history already disabled leaves old files.
Define stored-history deletion versus active-session retention; coordinate their
state and report sanitized deletion errors with retry.

**Accept:** denied deletion, queued writes, completion after Delete All, and relaunch
with history disabled. Primary and backup disappear or a visible error says they did
not. A deleted thread must not silently resurrect.

### A14 · P1/M — Private, recoverable archive writes

**Where:** `Core/Store/ThreadArchive.swift`.

Atomic writes use default temporary permissions before chmod. Backup/permission
failures are swallowed. After backup recovery, rotation can replace the good backup
with a corrupt primary. `isHistoryEnabled` is also read on the write queue while the
UI can mutate it.

Use restrictive temporary-file creation, atomic replacement, validated backup
rotation, and serialized archive state. Keep bytes private before writing content.

**Accept:** permission inspection before content writes, recovery followed by write
failure, backup preservation, concurrent erase/flush, and read-only archive tests.

### A15 · P1/M — Checkpoint active turns and recover interruptions

**Where:** `Vervellum/Research/ResearchEngine.swift`, `Store/ThreadStore.swift`,
`Linux/LinuxPanel.swift`, `Core/Store/ThreadArchive.swift`.

macOS persists the initial and final turn, not streamed snapshots; Linux saves only
at finish. Quit/crash can lose the current answer. Loaded nonterminal turns stay
apparently active, and queued cancelled callbacks can overwrite newer state.

Checkpoint at a bounded cadence and on dismissal/termination. Cancel/snapshot before
shutdown; recover nonterminal turns as interrupted with partial text and retry.
Guard callbacks by run/session identity. Coordinate with A13, not per-token writes.

**Accept:** relaunch from every stage, quit during streaming, immediate cancel/new
run, and old callbacks after history replacement. Verify final snapshots are durable.

### A17 · P1/M — Bound Linux credential subprocesses

**Where:** `LinuxSecretStore`, `ShortcutInstaller`, runner environment acquisition.

Subprocesses have no deadlines and credential reads block GTK during construction
and Ask. Keyring deletion errors are discarded. Backend descriptions follow writes,
not actual reads; environment keys win despite contrary documentation.

Introduce asynchronous bounded acquisition behind the secret service. Terminate
stalled children; return backend and outcome states, explain environment overrides,
and report failed deletion. Keep secrets off argv and out of errors/logs.

**Accept:** hung/missing/failing secret-tool, locked keyring, environment override,
and deletion tests; GTK remains responsive. Correct Linux key-precedence documentation.

### A38 · P1/L — Authenticate distribution and bound updater downloads

**Where:** release workflows, `Core/Updates/`, `Vervellum/Updates/`.

Ad-hoc signing resets selection grants; updates authenticate neither bytes nor Team
ID. Updater networking follows redirects and checks size only after download. GitHub
assets legitimately redirect without provider credentials: use a separate bounded,
credential-free policy, not the research transport's authorization path.

**Accept:** Developer ID/notarization and signature/Team-ID verification; byte/time
caps enforced during download; failure never offers an unverified artifact as
verified. Keep unsigned limitations explicit until implemented. A future apt channel
needs signed repository metadata. Signing requires maintainer-owned credentials.

## Next: reading stability, input, and accessibility

### A19 · P2/M — Follow the stream only while the reader wants it

**Where:** `Vervellum/Views/PanelRootView.swift`.

Every token forces bottom-scroll, defeating reading/selection above it. Verdicts can
then arrive below the viewport without that trigger. Track reader intent and bottom
proximity; detach on deliberate scrolling and offer keyboard-accessible “Latest ↓”.
Resume explicitly or for a newly submitted turn, not because layout changed.

**Accept:** scroll-up, selection, momentum, history switching, resizing, and arriving
findings preserve reading position. New content remains discoverable. No scroll
animation is retargeted per token.

### A20 · P2/M — Coalesce updates; keep rendered identity

**Where:** runner callbacks, macOS engine/Markdown/composer, Linux panel/GTK.

Every delta copies/reports the growing turn and enqueues UI work. macOS reparses text,
citations, and composer layout; GTK queues everything and rebuilds all turn widgets
up to 10 Hz, destroying selection/focus/link state.

Coalesce before UI enqueue; retain every token and the exact terminal frame. Stage
changes remain immediate. Reuse completed GTK turn widgets, update the active answer,
cache immutable parsed blocks, and reuse measured composer layout.

**Accept:** benchmark long threads and bursty streams for bounded queue depth,
responsive Stop, stable completed-turn selection, and exact final text. Keep GLib/
main-queue dispatch in platform layers, never MainActor in Core. Pair with A19.

### A23 · P2/M — Preserve drafts and make commands keyboard-first

**Where:** `PanelRootView`, `ComposerView`, command completions.

Editing is disabled during runs. Clicking a suggestion replaces a nonempty draft;
programmatic `NSTextView.string` replacement is not a reliable undo promise. Recall
stays active after edits, so arrows can discard them. Slash suggestions lack keyboard
selection.

Allow drafting while research runs; distinguish Submit from Stop. Preserve or
explicitly replace drafts on suggestions, end recall after edits, and support
arrows/Tab/Escape in command completion without breaking IME.

**Accept:** multiline drafts, edited recalled text, suggestions during runs, undo,
keypad/modified Return, and CJK composition. No unintended send or data loss.

### A24 · P2/M — Linux keyboard and help must match capabilities

**Where:** `LinuxPanel`, `GTK.observeKeys`, shared command help.

Help advertises macOS-only actions; history/settings/copy print apologies, follow-ups
are inert, and Return during a run invokes Stop. Verify whether the bubble-phase
controller sees Return before GtkTextView consumes it on supported GTK releases.

Generate platform-capability help; add Ctrl-Return, a dedicated Stop shortcut,
clickable follow-ups, and GTK clipboard support through the platform abstraction.

**Accept:** actual GTK key-event tests with IME, Shift-Return, keypad Enter, drafts,
and a live run. Do not consume unrelated editing keys. Coordinate setup/history with A30.

### A25 · P2/M — Stable, inspectable evidence cards

**Where:** `SourcesView`, `MarkdownText`, Linux Pango/panel rendering.

Hover expands summaries and moves rows; keyboard users cannot reach the summary-only
caveat. Linux shows neither summary nor caveat. Grouped answer citations open only
the first source; the macOS tooltip string is built but unused.

Use explicit disclosure or a fixed-size source inspector. Expose every grouped
source, domain/date, exact retrieved snippet, and “Search summary — not the full
page.” Opening several tabs should never be an implicit group action.

**Accept:** keyboard/screen-reader inspection; hover never changes transcript height;
group citations expose all sources. Preserve numeric ownership from A01.

### A26 · P2/M — Scale all evidence and wrap crowded rows

**Where:** `PanelTheme`, `FindingsView`, `SourcesView`, composer geometry.

Text scale affects the answer but not most evidence, questions, controls, or composer.
The verdict/citation HStack cannot wrap. Composer height uses the preferred width,
not the actual clamped window width.

Apply a consistent reading scale to meaningful text, wrap citation chips and long
metadata, and measure actual geometry. Essential information must not depend on tiny
secondary labels.

**Accept:** minimum width, 140% text, long model/domain/date labels, RTL/CJK, many source
chips, and short displays without clipped controls or overflowing content.

### A27 · P2/M — Adaptive contrast and accessible motion

**Where:** macOS theme/background/panel/caret; Linux Pango colors/styles.

Fixed accents/verdict colors, compounded tertiary opacity, a black-only scrim, and
small hard-coded Linux text need contrast measurements. Reduced Transparency still
selects blur, with no explicit opaque fallback. Motion preferences are ignored.

Add semantic light/dark/high-contrast palettes and an opaque fallback. Observe
accessibility changes live; reduce panel, disclosure, and caret motion when requested.

**Accept:** measured contrast over bright/dark content and Adwaita themes; live Reduce
Transparency/Reduce Motion changes; meaning remains readable without color. GUI QA
is required before claiming an aesthetic improvement.

### A28 · P2/M — Accessible history actions and progress

**Where:** `HistoryView`, headers, finding accessibility, status presentation.

History nests a hover-only Delete button inside Open. Icon actions rely on help;
combined finding labels may hide reasoning/actions. Progress has no stable live
announcement.

Separate row actions, label contextual menus, add deletion undo/confirmation, focus
history search on opening, and restore composer focus on exit. Announce stage changes,
not streamed tokens.

**Accept:** VoiceOver/Orca reading order, focus, source actions, errors, no-results
states, and keyboard deletion without hover. Keep controls reachable at larger scale.

### A29 · P2/M — Render common research Markdown correctly

**Where:** shared `MarkdownParser`, both renderers.

Fence closers ignore marker type/length; ATX headings lose literal trailing `#`
(`## C#`). Tables are unsupported. Linux loses nested inline emphasis and wraps code
inside the same label.

First fix matching fences and heading closer rules with tests. Then add compact,
horizontally scrollable tables/code, code-copy actions, and explicit renderer parity.
Keep citations literal in code and render partial constructs during streaming.

**Accept:** mismatched/long fences, C# headings, comparison tables, nested emphasis,
long code, and every incomplete-stream prefix. No dependency or HTML renderer added.

## Reliability and provider compatibility

### A09 · P2/M — Show what each search actually did

**Where:** runner, research models, progress views, answer context.

Plans are passed as `searches_run` even when requests fail. Mixed failure is hidden;
progress counts planned rather than successful searches. Add persisted per-query
pending/running/succeeded/failed state, safe errors, elapsed time, and contribution.

**Accept:** “2/4 succeeded” and incomplete-evidence notice for partial failure; only
successful searches are described as run to the model. Test cancellation/migration.
Keep execution sequential until MCP concurrency support is established.

### A10 · P2/M — Explicit provider and MCP capabilities

**Where:** `SearchMCPClient`, planner schema validation, provider settings/client.

Only two z.ai tool names and one listing page are supported. Argument keys are
validated, not types/enums. Required temperatures exclude some reasoning endpoints.
Document current support; add explicit tool selection, bounded pagination, supported
schema validation, and provider capability presets. Do not infer safety from names.

**Accept:** real-shaped fixtures for tool pages/schema/types/enums and temperature
capabilities, without live keys. Broaden product claims only after support exists.

### A11 · P2/M — Preserve source URLs and result boundaries

**Where:** `SourceHarvester`, `EvidenceExtractor.hits(inParagraph:)`.

Structured URLs undergo prose punctuation stripping and can contain userinfo.
Exact-string dedup keeps tracking/fragment variants. Neighboring link-line snippets
can overlap and assign one result's context to another.

Separate structured validation from prose cleanup; reject credentials, preserve
legitimate URL punctuation, define conservative dedup keys, and partition prose into
non-overlapping result items.

**Accept:** results without blank lines, query punctuation/parentheses, userinfo,
near-duplicates, and distinct pages. Keep extraction permissive without fabricating
which text belongs to which source.

### A18 · P2/M — Truthful configuration and shortcut outcomes

**Where:** `JSONFileSettingsStore`, `ShortcutInstaller`, macOS hotkey/provider UI.

Linux external JSON edits never reload and stale shortcut bookkeeping can overwrite
them. Shortcut writes/Carbon registration failures are ignored. Keychain Clear says
success despite discarded deletion errors.

Add explicit reload/validation before a full settings editor, preserve external
settings during bookkeeping, check every write/registration result, and surface
conflicts/recoverable failures. Do not add another settings file.

**Accept:** external edits while running, read-only files, failed dconf writes,
shortcut conflicts, and failed Keychain deletion never report false success.

### A22 · P2/M — End-to-end deadlines and cancellation tests

**Where:** `Core/Research/HTTPTransport.swift`.

Ten-minute checks happen only on arriving chunks and start after the response head;
they are not an end-to-end deadline. Early-return cancellation relies on continuation
lifetime. Use an independent monotonic per-exchange deadline to cancel the URL task.

**Accept:** no headers, idle body, trickle/keepalive, cancellation before registration,
early matching MCP response, refused redirects, and producer caps. Inject clocks/
transport at the service boundary or use loopback fixtures; never live providers.

### A39 · P2/S — Fail packaging when dependency discovery fails

**Where:** `packaging/build-deb.sh`.

Suppressed `dpkg-shlibdeps` failures trigger a minimal GTK fallback, potentially
publishing missing dynamic dependencies. Fail packaging with safe diagnostics instead.

**Accept:** deliberately unavailable/failed dependency discovery produces no release
package; supported Ubuntu builds still generate and verify all dependencies.

### A40 · P2/M — Behavior coverage and falsifiable documentation

**Where:** tests, CI, README/PLAN/SECURITY/PRIVACY/CICD.

Add runner fixtures, cancellation/deadline tests, rendering-safety coverage, a GTK/
Xcode smoke matrix, long-thread profiling, and accessibility checks. #11 begins GTK
lifecycle coverage; it does not replace Wayland or real-desktop testing.

Correct these concrete overclaims: “every claim” versus eight findings; structurally
impossible model URLs versus actual rendering; summary labels “on every source”;
generic MCP support; Linux key precedence; universal redirect refusal; three workflows
beside four rows. See A01/A10/A17/A25/A38 for implementation dependencies.

**Accept:** docs describe tested guarantees and remaining limits. New tests isolate
settings/secrets/history and exercise behavior, not just optimistic code comments.

## Product extensions after the foundations

### A30 · P2/L — Native Linux setup and history

Build a settings/setup window over existing stores: presets, masked keys, explicit
Save, backend warnings, validation, and an optional connection check that discloses
what leaves the machine. Add searchable history, reopen/delete, and thread export.

**Accept:** clean install without secret-tool, unavailable keyring, no search key,
`/direct` discovery, and settings reload. No new persistence format. Build on A17/A18.

### A31 · P2/M — Retry only the failed assessment

Retain answer/evidence and offer “Retry claim check” separately from “Research again.”
Snapshot settings/model provenance and label stale evidence.

**Accept:** assessment retry makes no search/answer calls, never overwrites a newer
answer, and preserves failure context. Requires clear stage state from A04/A05/A15.

### A32 · P3/M — Evidence lens

Click a claim to highlight its assessed sentence and sources. Offer uncertain-only
filtering, a compact verdict distribution, and “What would change this answer?”
follow-ups. Use structured sentence anchors, not fuzzy string matching.

**Accept:** contradictions stay visible; associations are auditable; no invented
numerical confidence. Start from A25's accessible source inspector.

### A33 · P3/M — Preview plans and choose research depth

Offer Quick/Standard/Deep with explicit search caps and stage-model choices. Allow
query inspection/editing for an opted-in deep run. Show measured timings and
provider-reported usage; do not invent prices.

**Accept:** default asking remains one step, caps are enforced, and extra calls require
explicit depth selection. Use actual outcome tracking from A09.

### A34 · P3/M — Local presets and per-stage models

Test Ollama/llama.cpp endpoints, supported model discovery, context/output limits,
and temperature capabilities. Allow separate planner and assessor models.

**Accept:** local-only/direct versus remote research is unmistakable. Local inference
must not imply remote web-search privacy. Reuse A10/A30 capability/settings work.

### A35 · P3/L — Bounded full-page evidence

Fetch a few decisive pages only after designing isolated credential-free transport,
SSRF/redirect controls, byte/time/MIME limits, extraction, provenance, and untrusted
content boundaries. Distinguish retrieved quotes from search summaries.

**Accept:** hostile/private-network URLs cannot trigger unsafe fetches; no arbitrary
model-directed browsing or HTML execution. Security tests precede quality tuning.

### A36 · P3/S–M — Small delights without another model call

Independent candidates, each with a narrow acceptance target:

- **Copy feedback:** “Copied,” plus answer-only/evidence-inclusive choices.
- **Pocket finding:** pin one compact claim/source card while working elsewhere.
- **Evidence receipt:** export question, model, date, verdicts, limits, and sources.
- **Reading bookmark:** return to the last inspected source rather than the bottom.
- **Challenge this:** visibly seed a disconfirming follow-up; never auto-send it.
- **Quiet completion:** an unobtrusive finished indicator; sound only by opt-in.

Use existing turn data, accessible restrained motion, and honest verdict styling.
Coordinate draft preservation (A23), reader intent (A19), and export completeness (#6).

### A37 · P3/L — Compare research across time

Start with manual “Research again and compare.” Preserve old evidence and distinguish
source additions/removals, changed verdicts, source churn, and changed conclusions.
Only then consider scheduled watches with explicit budgets, retention, provider
disclosure, and notification controls.

**Accept:** old threads are never silently re-sent; comparison remains auditable;
a refreshed source list is not falsely described as a changed answer.

## Execution rules

- Preserve numeric-only citations, uncited-verdict rejection, explicit uncertainty,
  sequential answer/assessment, and visible context trimming.
- Keep Core portable: Foundation/Dispatch only, no UI imports or main-actor hops.
- Keep credentials in existing secret stores, foreign errors sanitized, and research
  redirects refused. Updater fetching is a separate credential-free policy.
- Fix bugs test-first. Put independent changes in separate branches/PRs; record
  platform limitations and remaining validation rather than claiming parity.
- Do not widen scope into a redesign until reader stability, persistence, and trust
  failures are covered. Start with A01, A07, A12–A15/A17; then A19/A20/A25–A28.
- Preserve this queue when merging later analyses: consolidate duplicates, retain
  distinct acceptance criteria, and move implemented items to merge/validation work.
