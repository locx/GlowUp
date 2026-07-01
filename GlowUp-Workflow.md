# GlowUp Autonomous Workflow

A staged pipeline that analyzes, plans, and improves GlowUp under two human gates — **plan approval** and **final-diff approval**. Everything between runs autonomously: implementation, build/test, self-audit, adversarial review, auto-correction, and a three-round review sweep. A diff reaches final approval only after surviving all of them.

Repo: **Swift / SwiftPM, macOS 13+, no Xcode project**. The thesis is load-bearing — *safety is the product, reclaim is the feature* — so every phase is constrained by the safety architecture, not just code quality.

---

## Invocation & preconditions

Run from repo root with `main` checked out and a **clean working tree**. The orchestrator runs phases **strictly in order** — never reordered, never skipped. Only two pauses are allowed: the **PLAN APPROVAL** and **FINAL DIFF APPROVAL** gates. Any other stop is an exception — a safety invariant is at risk, or a **circuit breaker** trips (3 non-converging attempts on one batch or review round). `<DATE>` = today ISO (`YYYY-MM-DD`); each run owns `docs/audits/<DATE>/`, and a same-day re-run takes the next suffix (`-1`, `-2`, …) so it never overwrites a prior run.

---

## The autonomy contract

```text
1     Repository Intelligence    (Explore + Plan)                       ── autonomous
2     Safety & Production Audit  → analysis_report / plan / tasklist    ── autonomous
   └─ 2b  10× Performance & Scalability pass (folds into the same docs) ── autonomous
3     Tech-Lead Prioritization   (reorder + dedupe + batch)             ── autonomous
3.5   Plan Red-Team             (independent agent tries to break it)   ── autonomous
──────────────────  ⛔ PLAN APPROVAL GATE — human stop #1  ──────────────────
             ── Phases 4–9 run in an isolated git worktree ──
4     Autonomous Execution       (batches; builder build+test; catalog dry-run diff)
5     Implementation Self-Audit  (author reviews own diff)
6 ⇄ 7 Adversarial Review ⇄ Auto-Correction   (loop until two clean passes)
8     Three-Round /code-review Sweep          (3 passes; fix between rounds)
9     Artifact Cleanup                         (prune throwaway files; audit docs stay)
──────────────────  ⛔ FINAL DIFF APPROVAL — human stop #2  ──────────────────
              ── on approval: squash-merge + worktree teardown ──
```

**Two human interactions only:** approve the plan (after 3.5) and approve the diffs (after the 6⇄7 loop, the Phase 8 sweep, and Phase 9 cleanup). No questions between, save the two exception stops above.

**Worktree.** Phases 4–9 run in an isolated git worktree (`superpowers:using-git-worktrees`), never on `main`. At creation, pin `BASE=$(git rev-parse HEAD)` — Phases 5–8 diff against that fixed SHA so movement on `main` can't pollute the review. Confirm `$BASE` equals the SHA the Phase 1 baseline was taken at; if `main` moved in between, re-capture the baseline at `$BASE` so the perf/regression "before" matches the reviewed delta. A fresh worktree has no `.build`, so the first `swift build`/`swift test` is a cold compile (expected). Each green batch is a checkpoint commit; a bad batch rolls back, and `main` stays clean until final approval.

**Subagents work in the worktree and never commit.** Every Phase 4–9 subagent edits and builds inside the worktree path (pass it explicitly — agents don't inherit a cwd). Audit docs live in the *main* worktree (`docs/` is gitignored, so they don't follow into the new worktree); agents read the tasklist there and write code in the worktree. The orchestrator — not subagents — commits each checkpoint after verifying returned test output (the briefing forbids self-authorized git).

**Artifacts.** `analysis_report.md`, `implementation_plan.md`, `tasklist.md`, and the `progress.md` loop-state ledger (see Loop control) live in `docs/audits/<DATE>[-N]/`. `docs/` is gitignored, so checkpoints carry code only (`git add -f` to keep an audit doc in history).

---

## Parallelism & orchestration

Phases run in order; work *within* a phase fans out. The orchestrator barrier-joins, dedupes, and is the **single writer** of every shared artifact — parallel agents **return** findings, never write the same file concurrently.

- **Phase 1** — `Explore` fans out by subsystem for large repos; each pass returns its slice, `Plan` writes the one report.
- **Phase 2** — lenses A–D run as parallel auditors returning findings; one synthesis step writes the three docs.
- **Phase 6** — reviewer panel in parallel, then 2–3 parallel skeptics verify each finding (majority to accept a non-safety finding; safety findings always carried).

**Never parallelize task execution.** Batches share files and the behavioral-diff needs a stable before-state, so they run sequentially, one checkpoint at a time. Provably file-disjoint batches *may* run in separate worktrees and merge sequentially with re-verify — a wall-clock win costing merge + re-test; use only when it clearly pays.

For long runs, encode this as a runnable `Workflow` script (`pipeline`/`parallel`/loop-until-dry/verify) for a global token budget and journaled resume.

---

## Non-negotiable guardrails (every phase inherits these)

Paste into each dispatch, alongside the `<HARD-RULES v1>` briefing from `~/.claude/CLAUDE.md` §6 (without it `briefing-gate.sh` blocks the dispatch).

- **Never weaken a safety layer to make a build/feature/test pass — fix the rule or the input.** The architecture is the product: allowlist-first catalog → the **`Vetter.vet`** gate of record (`DenyList.vetoes` on every candidate + `DataStoreGuard.holdsDataStore` on swept/inferred hits) → trash-only/reversible. `Vetter` and `DataStoreGuard` are the most safety-critical code here — audit them explicitly, never route candidates around them.
- **A red `SafetyLintTests`/`CatalogContentTests` means a rule resolves onto protected data — fix the rule, never the assertion.**
- **Catalog edits only in `Sources/GlowKit/Resources/catalog.json`**, obeying the glob/base constraints (symbolic `base`, single-segment `*` — no `**`, absolute paths, or `..`).
- **Risk tiers are sacred:** only caches are `safe`; cookies/history are `privacy`; sessions/local-storage are `stateful`. `stateful`/`privacy` never auto-clean.
- **No anti-snake-oil** (RAM purge, DNS flush, auto-empty Trash, language-pack/iOS-backup deletion).
- **Trash-only, never `rm`.** Dry-run by default, explicit confirm, restore stays reversible.
- **Verification is mandatory and real.** No "passing/fixed" without the actual `swift test` output from the builder this run. A `catalog.json`/sweeper change also needs a **catalog behavioral-diff** (dry-run before/after via `CLI.run(args:…, home:…)`) — unit tests miss newly-flagged paths. A `Trasher`/`RestoreStore`/mover change also needs a **restore round-trip smoke** (real trash → record → restore → assert reversibility **and the negatives**: no `rm`/`unlink` fired, nothing written outside the temp Trash) — dry-run never exercises the undo path, which is the product. **Re-verify** (shorthand below) = builder (`swift build && swift test && bash -n scripts/glowup.sh`) + the catalog behavioral-diff when catalog/sweeper changed + the restore round-trip when a mover/`RestoreStore` changed.

**Circuit breaker** (per batch and per review round, not global): an *attempt* is one fix→re-verify cycle; the counter resets on a fully-green round. After 3 non-converging attempts on the same batch or round, stop and surface to the human — don't churn. This is the only thing that overrides Phase 6's loop-until-two-clean-passes.

---

## Loop control (state · predicates · bounds)

Every repetition here is an explicit, bounded loop with persisted state — so an interrupted run resumes mid-loop and "loop-driven" never means "unbounded." These three blocks are the contract; each phase below names which it uses rather than re-describing the loop inline.

### Loop-state ledger (`progress.md`)

Single source of truth, rewritten by the orchestrator (the single writer) at every checkpoint. A fresh orchestrator **reads this first and resumes from it** — resume is the default path, not a fallback. Fields:

```text
base_sha:          <pinned $BASE; must equal the Phase 1 baseline SHA>
current_phase:     <1 … 9>
batch_index:       <N of B>                      # Phase 4
attempt_count:     <0–3, per batch / per review round>   # circuit breaker; resets on a fully-green round
consecutive_clean: <0–2>                         # Phase 6 exit
seen:              [ "<file:line + finding>", … ]   # Phase 6/8 dedupe; append-only within a run
task_counter:      <tasks completed>             # triggers the repo-wide sanity check
open_findings:     [ … ]                         # carried into the next iteration
```

### Loop predicates (named exit conditions)

- **`green`** — builder passes (`swift build && swift test && bash -n scripts/glowup.sh`) plus the re-verify add-ons (catalog behavioral-diff / restore round-trip) when applicable.
- **`subset`** — `flagged_after ⊆ flagged_before` for a catalog/sweeper change (Phase 4): any path in `after` but not `before` is a finding, even if the total shrank.
- **`two-clean`** — two consecutive review passes surface nothing not already in `seen` (Phase 6).
- **`three-round`** — three `/code-review`-equivalent rounds with the final one clean (Phase 8).

### Loop template (every loop below conforms to this shape)

```text
LOOP <name>
  invariant:  <what stays true each iteration — e.g. safety layers intact>
  body:       <one unit of work>
  exit:       <one named predicate above>
  counter:    attempt_count (persisted in progress.md)
  max-iter:   3 → circuit breaker: stop and surface to the human (overrides any loop-until)
```

The bounded loops: Phase 4 per-batch `(fix → re-verify)*` → `green`; Phase 4 batch sweep `for batch in batches`; Phase 6 `until two-clean`; Phase 8 `three-round`; the repo-wide sanity check each time `task_counter` crosses a 10–15 boundary. Each names its predicate and inherits the circuit breaker — no loop is unbounded.

---

## Phase 1 — Repository Intelligence

**Dispatch:** one `Explore` (fan out by subsystem — safety core · pipeline/scanners · app+CLI · tests — for a large repo), then `Plan` synthesizes hotspots and writes the report. Read-only. Record a **baseline** — current `swift test` result and rough scan cost (candidate count / wall-time), tagged with the commit SHA — so Phase 4 can confirm the pinned `$BASE` matches and later phases attribute regressions to numbers, not vibes.

```text
Senior Swift engineer, repository-intelligence pass on GlowUp (macOS SwiftPM; 3 targets:
GlowKit library, GlowUpApp SwiftUI, glowup CLI). DO NOT edit. Build complete understanding.

STEP 1 — Structure & graph
- target/module layout (GlowKit / GlowUpUI / GlowUpCLI / GlowUpCLIExec / app)
- cleanup pipeline end-to-end: Catalog → Scanner.scan → Resolver.resolve (fnmatch globs,
  DenyList filter) + sweepers (Orphan / WorkspaceStorage / AdvancedScan, under --advanced);
  CleanupScan funnels both through Vetter.vet (DenyList for all hits, DataStoreGuard for swept)
  → Candidate.dedupe → SizeMeasurer → Trasher → RestoreStore.record
- where the 4 safety mechanisms live (catalog allowlist · Vetter · DenyList · DataStoreGuard)
- entry points: GlowUpApp @main, GlowUpCLIExec/main.swift, scripts/glowup.sh fallback

STEP 2 — Architecture
- subsystem responsibilities, AppModel phase machine (idle→scanning→results→cleaning→done)
- injection seams (catalog/inventory/home/mover/storeURL); coupling / layering

STEP 3 — Concerns (observe, don't fix)
- safety first: any path a rule could resolve onto protected data, any trash-only/reversibility bypass
- then: runtime risks, concurrency (@MainActor), perf, dead code, dup logic

STEP 4 — Risk hotspots: most fragile components, highest-debt modules, scaling limits

STEP 5 — Baseline: record the current `swift test` result (pass/fail counts, any pre-existing
  red) and a rough scan cost (candidate count / wall-time), tagged with the current commit SHA
  (git rev-parse HEAD) so Phase 4 can confirm the pinned $BASE still matches.

RETURN (read-only — Plan writes docs/audits/<DATE>/analysis_report.md) these 7 sections:
  1 architecture  2 module/pipeline map  3 subsystem notes
  4 safety-layer audit  5 risk hotspots  6 tech-debt inventory  7 baseline (test state + scan cost)
```

## Phase 2 — Safety & Production Audit (+ 2b: 10× Performance pass)

**Dispatch:** `feature-dev:code-architect` (or `Plan`). Consumes Phase 1, writes the plan, not code. The perf/scalability sweep is a second pass that **folds into the same three docs**. Lenses A–D may fan out as parallel auditors that **return findings**; one synthesis step writes the docs (no concurrent writes).

```text
Using docs/audits/<DATE>/analysis_report.md, run a safety-first production-readiness audit of
GlowUp. Harden safety, fault tolerance, perf, memory; reduce debt; simplify — WITHOUT weakening
any safety layer.

A — Safety integrity (highest priority)
- Can any catalog rule, glob expansion, or scanner resolve onto deny-listed/protected data?
- Every delete path trash-only and reversible? Any rm/unlink leak?
- Risk tiers correct in catalog.json (no privacy/session marked safe)?
B — Correctness & robustness: bugs, unsafe logic, missing validation, error handling, leaks
C — Performance / memory (the 10× pass)
- blocking calls in @MainActor flows; sync I/O on the scan path
- complexity (hidden O(n²) over large candidate sets, redundant glob expansion)
- I/O: expensive scans, redundant stats, SizeMeasurer cost, missing batching/caching
- memory: large candidate sets, copies, Swift anti-patterns (COW misuse, ARC churn, unspecialized generics)
- "10×" is the ambition, not a license to skip numbers: a perf task needs a before/after measure
  (candidate count, scan wall-time, syscall/probe count) — a fix that can't be measured isn't a perf task.
D — Architecture & cleanup: separation, injection, dead code (flag, don't delete), dup utilities

OUTPUT — update IN PLACE in today's audit folder (edit existing sections over new files):
  analysis_report.md     (execution model, bottlenecks, safety)
  implementation_plan.md (phased: A safety/correctness · B perf · C memory · D arch · E cleanup)
  tasklist.md            (one task per fix)

Each task: title · description · rationale · affected files · steps · expected outcome ·
priority(critical/high/med/low) · complexity(small/med/large) · estimate (small <1h, med 1–4h,
large >4h) · dependencies · status (`[ ]` by default) · safety-impact note (touches a safety
layer? if so, how is the invariant preserved?).

GUIDELINES: minimal-diff, match style, prefer stdlib/Foundation, clarity over cleverness,
preserve behavior unless improvement is justified. Tests required for any code change.
```

## Phase 3 — Tech-Lead Prioritization

**Dispatch:** `Plan`. No code. Reorders for safe, high-leverage execution.

```text
Tech lead. Review docs/audits/<DATE>/{analysis_report,implementation_plan,tasklist}.md.
- Plan must address safety FIRST, then reliability, perf, memory, debt.
- Add missing high-impact tasks; merge redundant; split oversized; drop cosmetic-only
  tasks with no evidence in analysis_report.md.
- Sequence to minimize risk: safety-touching tasks get an isolated batch with the safety-lint
  gate as acceptance; any catalog/sweeper batch carries a behavioral-diff as acceptance.
- Flag any task not doable without weakening a safety layer → NEEDS-HUMAN.
OUTPUT: reordered implementation_plan.md + cleaned tasklist.md, batched into dependency-ordered
groups of 2–3 tasks.
```

## Phase 3.5 — Plan Red-Team (adversarial, pre-gate)

**Dispatch:** one independent `Plan` agent told to *break* the plan, not improve it. Read-only. Feeds the gate — does NOT add a second human stop.

```text
Adversarially review docs/audits/<DATE>/{implementation_plan,tasklist}.md before a human
approves. Default to "unsafe or wrong" and try to prove it. Check:
- Safety honesty: any task that in fact requires weakening a DenyList veto, the allowlist, or
  trash-only/reversibility but is NOT marked NEEDS-HUMAN? Flag it.
- Risk-tier drift: any task moving a privacy/session path toward `safe`, or adding a catalog
  rule without a matching SafetyLintTests bait fixture in the same batch?
- "Behavior-preserving" claims that aren't; steps that don't achieve their outcome.
- Catalog/sweeper tasks with NO behavioral-diff step in their batch (unit-only = false green).
- Over-scoped batches (>2–3 real-change tasks) or mis-ordered dependencies.
- Tasks fixing a non-problem (no evidence) — recommend dropping.
Output: per-task verdict (sound / revise / drop / NEEDS-HUMAN) + corrected batch order.
Do NOT propose anything that weakens a safety layer.
```

Fold confirmed findings into the plan/tasklist before presenting. Safety findings are never silently dismissed.

---

## ⛔ PLAN APPROVAL GATE

Present, then **STOP**:

- batched task list (title · priority · complexity · estimate · safety-impact),
- scope roll-up (total task count + per-batch counts; effort sum + per-batch subtotals),
- execution order and which batches touch safety layers,
- any `NEEDS-HUMAN` items.

Use the plan schema `| file | change | why | verify |`. Do not proceed until explicitly approved.

---

## Phase 4 — Autonomous Execution

Execute batch-by-batch in the worktree. **No further questions** unless a task requires weakening a safety invariant — then stop and ask.

**Per batch:**

1. Implement the 2–3 tasks (minimal diff, match style, touched comments WHY-only/≤2 lines, no tracker IDs, edit over create).
2. Dispatch **`apple-platform-build-tools:builder`**: `swift build` → `swift test` (includes `SafetyLintTests` + `CatalogContentTests`) → `bash -n scripts/glowup.sh`. This is the `green` predicate.
3. **If `catalog.json` or a sweeper changed** — run a behavioral diff, not just unit tests. The shipped `glowup` always scans the real `$HOME` (resolved via `FileManager`, ignoring the env var), so drive the diff through the injectable `CLI.run(args:…, home:…)` seam (`CLIRunTests` already exercises temp-home injection). A throwaway test points `home:` at a temp fixture dir and calls `CLI.run` with `["--dry-run","--json"]` then `["--dry-run","--advanced","--json"]`, captured before vs after (`--json` = stable parseable diff). Plant **sweeper** fixtures (orphans, workspace storage, project artifacts), not just catalog-named paths — `rebuildable` and most swept hits come from sweepers, so catalog-only fixtures give false confidence. Acceptance is the `subset` predicate: any path in `after` but not `before` is a finding to justify or revert, even if the total shrank (a swap can hold the count constant while trading a benign path for a protected one). The rule's new `SafetyLintTests` bait fixture must land **in this batch**, not just be checked at plan time. Save both runs to the audit folder.
4. **If `Trasher`/`RestoreStore`/a mover changed** — run a restore round-trip smoke: via the real mover, trash planted fixtures into a temp Trash, `RestoreStore.record`, then restore and assert the bytes/paths return **and** that reuse-detection refuses the restore once the Trash entry's mtime is tampered — plus the negatives: no `rm`/`unlink` fired, nothing landed outside the temp Trash. Dry-run never exercises the undo path. Save the result to the audit folder.
5. **If red:** fix forward in the same batch (systematic-debugging, not assertion-weakening); re-run via builder. This is **LOOP per-batch** `(fix → re-verify)*` exiting on `green`; `attempt_count` caps at 3 → circuit breaker stops and surfaces.
6. **On green,** the orchestrator commits the checkpoint (subagents never self-commit). Record: tasks, files, test summary, catalog-diff + restore-smoke result.
7. **Track progress inline.** Flip each finished task to `[x]` in tasklist.md, then echo a checklist in chat — this batch's tasks done, next batch's still-open, a running tally — and flag any task that ran >1.5× its estimate:

   ```text
   Batch <N> of <B> done — <M>/<T> tasks (<P>%), ~<spent>h of ~<total>h est.
   ✅ <id> — <title>   (est <e>h / actual <a>h)
   ⬜ next: <id> — <title>   ·   ⬜ <id> — <title>
   ```

Dispatch text inherits the guardrails + circuit breaker; it just names the batch:
`Implement batch <N> from docs/audits/<DATE>/tasklist.md in the worktree, per the Phase 4
per-batch procedure (builder build/test; catalog behavioral-diff and restore round-trip where
they apply; do NOT commit). Report: tasks, files, test result, catalog-diff + restore-smoke
result, progress checklist.`

## Phase 5 — Implementation Self-Audit (1st pass)

Author reviews own work before any external reviewer. Phases 5–8 operate on the **cumulative branch diff** (`git diff $BASE..HEAD` — exactly what *this branch* changed), since each batch is committed.

```text
Audit the changes (cumulative branch diff vs base) against docs/audits/<DATE>/tasklist.md.
Verify: tasks satisfied · no broken imports/build · no regressions · safety layers intact
(SafetyLintTests + CatalogContentTests green) · comments WHY-only ≤2 lines · no pre-existing
code reformatted/renamed · diff ≤2× minimal.
List incomplete items · risky changes · new debt, severity each (critical/major/minor).
```

## Phase 6 — 2nd-Pass Adversarial Review

Independent review before the user sees it. Dispatch in parallel, each told to *refute*:

- **`feature-dev:code-reviewer`** — bugs, logic, conventions, regressions across the diff.
- **`feature-dev:code-explorer`** — only if the change spans subsystems; trace that no caller/injection seam broke.
- **`code-simplifier:code-simplifier`** — over-complex changes, single-use wrappers, speculative abstraction.
- **`axiom:swift-performance-analyzer`** — Swift perf anti-patterns introduced.
- **`axiom:swiftui-architecture-auditor`** — only if `GlowUpUI/` changed (logic-in-view, state, testability).
- **`axiom:concurrency-auditor`** — only if `@MainActor`/async/actor boundaries changed.
- **`axiom:testing-auditor`** — test quality, flaky patterns, missing assertions on new tests.
- **`axiom:storage-auditor`** — only if trashing/restore/file-location logic changed (data-loss risk, load-bearing here).

```text
Adversarially review the full branch diff (git diff $BASE..HEAD, not the working tree — clean
after each commit). Default to "this is wrong" and prove it. Priority: (1) does any change let a
rule resolve onto protected data or bypass trash-only/reversibility? (2) correctness regressions
(3) your domain lens. Cite file:line, mark real/uncertain + severity. Do NOT propose weakening
safety assertions.
```

Merge + dedupe, then **verify each finding** with 2–3 independent skeptics in parallel (each prompted to *refute*); accept a non-safety finding only on majority, so false positives don't reach Phase 7. Safety findings are always carried, never dismissed as "uncertain".

**LOOP until `two-clean`:** after Phase 7 fixes a round, re-run this pass. Maintain the `seen` set keyed by `file:line + finding`; each round, drop findings already in it and add newly surfaced ones — dedup against `seen`, **not** against what was accepted, so a rejected or partly-fixed finding can't re-trip the loop forever. The `two-clean` predicate exits: two consecutive passes surface nothing new (track via `consecutive_clean`). Circuit breaker applies — 3 non-converging cycles → stop and surface.

## Phase 7 — Auto-Correction

```text
Using merged Phase 5+6 findings, correct the implementation. Minimal fixes, no unrelated
refactors. Re-verify to green (builder + catalog behavioral-diff / restore round-trip as
applicable — see guardrails). Restate findings resolved and any NEEDS-HUMAN.
```

---

## Phase 8 — Three-Round /code-review Sweep

Multi-batch changes hide integration bugs that per-batch review misses once everything lands. After 6⇄7 is clean, run the **`three-round` loop**: three full rounds over the cumulative changed files — fix between rounds, never carry an unresolved correctness finding forward.

`/code-review high` with no PR argument bundles the *session* branch's commits against their base — so it only sees this work if the session is on the audit branch. Here the session stays on `main` while the work sits in a detached worktree, so `/code-review` usually can't see it. The faithful equivalent, and the default: dispatch an independent reviewer (`feature-dev:code-reviewer` / `general-purpose`) over `git diff $BASE..HEAD` in the worktree — the same delta Phases 5–7 used — one round per sweep, fixing between rounds (same triage, same circuit breaker).

- **Round 1** — over changed files. Triage correctness bugs first, then reuse/simplification/efficiency. Fix via Phase 7; re-verify to green.
- **Round 2** — on the updated diff; new findings often surface only after round-1 fixes. Fix and re-verify.
- **Round 3** — confirmation pass; expect zero new correctness findings. If any appear, fix and run ONE more confirming round. Circuit breaker still applies.

Use `high` (local), not `ultra` (cloud, billed, user-triggered only). Record each round's findings + resolutions into `docs/audits/<DATE>/`. A finding requiring a weakened safety layer is NEEDS-HUMAN, never auto-fixed.

## Phase 9 — Artifact Cleanup

Prune throwaway scaffolding so the approval diff is exactly the intended change. Runs **inside the worktree, before** the final diff; the worktree is torn down only after approval.

**Remove** (scratch, never shipped): throwaway behavioral-diff and restore round-trip tests, temp-home fixture dirs, temp-Trash dirs, stray `/tmp/*` staging files, dead debug scratch (commented probes, ad-hoc prints).

**Keep** (local audit trail): `docs/audits/<DATE>/{analysis_report,implementation_plan,tasklist}.md` (tasklist all `[x]`); the before/after behavioral-diff and restore-smoke captures; per-batch checkpoint commits.

Verify cleanup broke nothing: re-run the builder and confirm `git status` shows no untracked scratch. Emit any destructive removal (`rm`, etc.) for the user — never batch-delete autonomously (`~/.claude/CLAUDE.md` §1.2); `/tmp/*` is the only exception.

---

## ⛔ FINAL DIFF APPROVAL

Present, terse:

- what changed and why (batch by batch),
- completed tasklist (all `[x]`, with final estimate-vs-actual),
- `swift test` output proving green (builder, this run) + catalog behavioral-diff and restore-smoke results if touched,
- 2nd-pass findings and their fixes,
- 3-round sweep results (per-round findings + fixes; final round clean),
- confirmation Phase 9 cleanup ran (no scratch in the diff),
- any remaining `NEEDS-HUMAN` items.

The per-batch checkpoints are scaffolding — the granular trail already lives in `docs/audits/<DATE>/`, so `main` does not need that history. **Squash the worktree branch into a single commit on `main`** (`git merge --squash` then one commit, or `gh pr merge --squash` if a PR was opened), with the batch-by-batch summary above as the commit body. **Merge/push only after this approval and an explicit imperative** (`~/.claude/CLAUDE.md` §1.1) — see `superpowers:finishing-a-development-branch`. On merge, tear down the worktree. If rejected, discard it — nothing reached `main`.

Tradeoff: squashing drops per-batch bisectability on `main`, but each batch was verified green in isolation and the cumulative diff survived Phases 5–8, so bisect value is low — and `docs/audits/<DATE>/` preserves the per-batch detail if ever needed.

---

## Repository-wide sanity check (each time `task_counter` crosses a 10–15 boundary)

```text
Repo-wide sanity review after recent batches:
- safety intact: allowlist-first, DenyList veto un-bypassed, trash-only, restore reversible —
  SafetyLintTests + CatalogContentTests green
- module boundaries clean, no new circular deps, no privacy/session path marked safe
- no perf/memory regression in scan→measure→trash
Run the builder for the full suite; run the behavioral-diff for catalog/sweeper changes and the
restore round-trip for trash/restore changes. Recommend fixes if anything is red.
```

---

## Quick reference

| Need | Use |
| --- | --- |
| Map / explore code | `Explore` (read-only) |
| Plan / architect | `Plan` or `feature-dev:code-architect` |
| Trace a subsystem | `feature-dev:code-explorer` |
| Parallelize | Phase 1 Explores by subsystem · Phase 2 lenses A–D · Phase 6 panel + verify-per-finding (barrier-join, dedupe) · per-batch worktrees only if file-disjoint |
| Build & test | `apple-platform-build-tools:builder` (absorbs verbose logs) |
| Independent review | `feature-dev:code-reviewer` (+ `code-simplifier`, Axiom auditors) |
| Verify gate | `swift build` · `swift test` · `swift test --filter SafetyLintTests` · `bash -n scripts/glowup.sh` |
| Catalog gate (rule/sweeper) | before/after dry-run diff via `CLI.run(args:…, home:…)` against temp fixtures (`subset`) |
| Restore gate (trash/restore/mover) | real trash → record → restore round-trip; assert reversibility + mtime reuse-detection |
| Final bug sweep | 3 rounds over `$BASE..HEAD` (fix between) — `/code-review high` if on the branch, else a reviewer agent over the diff |
| Progress tracking | flip tasklist `[ ]`→`[x]` per batch; echo ✅/⬜ checklist + M/T %, batch N of B, est-vs-actual |
| Artifact cleanup | prune throwaway diff/fixture/scratch files; keep `docs/audits/<DATE>/`; teardown worktree post-merge |

**The one rule over all others:** a green build is never worth a weakened safety layer. Fix the rule or the input — never the assertion.
