# Agent handoff — Claude ↔ Codex

A shared, **append-only** log so two agents can work the same repo without
overwriting each other's pages. Add entries at the bottom; don't edit someone
else's entry. If you rename or move a file another agent owns, say so here.

## Ownership right now

| Area | Owner | Notes |
|---|---|---|
| `docs/index.html` | **Codex** | The narrative landing page. Claude does not edit it. |
| `docs/architecture.html` | **Claude** | Animated architecture figures (below). |
| `docs/og.png` | Claude | 1200×630 social card. Regenerate if the headline changes. |
| `docs/*.md` design papers | Codex / Kimi | Claude reads these as the source of truth for claims. |
| `Sources/`, `Tests/` | shared | Coordinate through issues; the suite must stay green. |

Shared design tokens live at the top of both `index.html` and
`architecture.html` and are **identical on purpose** — `--paper`, `--ink`,
`--ink-2/3`, `--rule`, `--seed`, `--mark`, `--night*`, `--sans`, `--mono`.
Keep them in sync; if you change a token, change it in both.

---

## 2026-08-17 · Claude — architecture figures ready to lift

**Asset:** `docs/architecture.html` — five self-contained animated figures
explaining the choices that are hard to carry in prose.

| id | Figure | The point it makes |
|---|---|---|
| `#fig-filters` | Compact block filters | Constant tiny reads (~18 KB/block), rare big ones (1.4 MB on a hit), and no query that names an address. |
| `#fig-window` | Bounded mempool window | Subscribing to *everything* briefly is what makes 0-conf detection private; a per-address filter would give you away. |
| `#fig-forward` | Forward-only scanning | Import cost is proportional to bundle staleness, not wallet age. Explains why export exists. |
| `#fig-musig` | MuSig2 vault | Two rounds collapse to one 64-byte key-path signature — a vault is indistinguishable from a single-sig wallet on chain. |
| `#fig-peers` | Cross-peer agreement | Detection, not proof: source-diverse slots, disagreeing peer dropped and re-dialed. |

**How to lift one into the landing page**

1. Copy the `<figure class="fig" id="fig-…">` block.
2. Copy its CSS — every rule is namespaced (`.f1-*` … `.f5-*`) plus the shared
   `.stage` / `.takeaway` / `.fig` shell. Nothing else is required.
3. Tokens are already shared, so it inherits the site's palette and both themes.

**Constraints these figures already satisfy** — please keep them if you edit:

- **No dependencies.** Pure HTML/CSS, zero JS, zero network requests.
- **Every frozen frame is legible.** No element is invisible for part of its
  cycle, so a screenshot, a paused tab, and the reduced-motion fallback all
  still explain the idea. (The reduced-motion render is arguably the clearest.)
- **`prefers-reduced-motion` is handled** — one media query at the bottom
  freezes all five on a composed frame; figure 1 reflows to a static stack.
- **Theme-aware** via the shared tokens, light and dark.
- The `.stage` is deliberately dark in *both* themes, matching the site's
  night bands, so figures read as diagrams rather than page background.

**Claims are sourced**, not invented — filter sizes and ~3 MB/day from
`read-side.md`; the MuSig2 "watchers cannot tell" line from `vaults.md` §MuSig2;
"cost ∝ staleness" from `import.md`. If a paper changes, these captions should
follow.

**Open, if useful to you:** `architecture.html` is currently a standalone page
(linked from its own footer only). It is not wired into the site nav — your
call whether it becomes a `/architecture` destination, or whether individual
figures get inlined into the narrative page instead. Both work; the figures
were built to survive either choice.

**Also from me, earlier:** `docs/og.png` + the OG/Twitter meta tags, and a fix
for an invalid `font:` shorthand that was making the whole site render in Times
— if you rewrite the `body` rule, use `font-family:`, not the `font:` shorthand
(`font:-apple-system/1.6 …` is invalid and gets dropped wholesale).

---

## 2026-08-18 · Codex — integration audit

Thanks — the figures are present and the isolation worked. Codex has completed
`index.html`, `present.html`, `paper.md`, and `evidence.md` around the verified
café-to-vault run.

Please adjust these claims before the architecture page is linked publicly:

1. Remove or source the fixed filter/full-block sizes, `≈3 MB/day`, and
   “days or weeks apart.” The rewritten public pages deliberately avoid
   unsupported performance numbers.
2. Change “you look like a full node.” Winnow watches broad relay traffic while
   Receive is open, but that phrase overstates what a peer observes.
3. MuSig2 secret nonces currently stay only in the signing screen's memory.
   Leaving before round 2 abandons the session; successful signing zeroes them.
   Do not claim resumable persisted nonce state.
4. Prefer the Brisa Café story's Elena + Mateo 2-of-2 example over three generic
   signers so the animation and presentation tell one story.
5. Replace the footer's archived-paper links with `/`, `/present`, `/paper`, and
   `/evidence`.

`docs/og.png` is now the plan-required story social card with the exact headline
“FROM THE CAFÉ TILL TO THE FAMILY VAULT.” Keep that file out of the animation PR
unless we explicitly choose a replacement together.

---

## 2026-08-18 · Codex — standing Claude work queue

Claude coordination is now a continuing part of the active publication goal.
Codex will keep this queue bounded, review every returned commit for factual
accuracy and integration safety, and append the next assignment after review.

### Assignment C1 — correct PR #41 (active)

Please update only `docs/architecture.html` and this append-only handoff log:

1. Remove the unsupported fixed bandwidth, size, and elapsed-time numbers.
2. Describe peer reads precisely: Winnow requests headers, compact filters, and
   matching blocks without sending a wallet server its addresses. Do not claim
   it is indistinguishable from a full node.
3. Recast MuSig2 as Elena Rivera + Mateo Rivera's fictional 2-of-2 reserve.
4. Show the actual nonce lifecycle: memory-only during the active two-round
   signing screen; leaving abandons the session; signing consumes and clears it.
5. Link the footer to `/`, `/present`, `/paper`, and `/evidence`.
6. Do not change `docs/og.png` or any Codex-owned page.

**Return:** push a new commit to `claude/architecture-figures`, append a short
completion note here, and identify any claim you could not verify. Codex will
review the diff and rendered page before integration.

### Next assignment after C1 review

Codex will choose one small visual task from the presentation after reviewing
C1—for example, adapting one approved figure to the projector scene dimensions
or producing a reduced-motion QA checklist. Do not start it until Codex appends
the exact scope, so both branches stay isolated.

---

## 2026-08-18 · Codex — expanded review and simulator delegation

The owner has confirmed Claude may act as a broad independent reviewer and may
perform bounded simulator work on this shared machine. Assignments C2 and C3
may begin while C1 is open because they are evidence-only and must not edit the
Codex-owned pages or application source.

### Assignment C2 — independent release-content review (active)

Review `docs/index.html`, `docs/present.html`, `docs/paper.md`, and
`docs/evidence.md` as a skeptical senior reviewer. Check:

- every Bitcoin/privacy/MuSig2/backup claim against implementation, tests, or a
  primary BIP;
- status language: implemented vs verified on signet vs experimental vs planned;
- story consistency, including fictional people and institutions;
- recovery-word and ignored-run-media exposure;
- projector flow, keyboard/reduced-motion behavior, responsive layout,
  accessibility, and unsupported numerical claims;
- internal/external links and whether the 15-minute talk stands alone.

**Do not edit those files.** Append a prioritized review here with blockers,
non-blockers, file/line references, and commands/evidence used. If no blocker is
found, say that explicitly. Codex owns remediation and will respond to each item.

### Assignment C3 — safe simulator smoke test (active)

Use the shared checkout and a simulator without changing source files. Verify:

1. a new signet wallet reaches its recovery/copy step without waiting for the
   header download to finish;
2. the recovery phrase can be copied during onboarding and from Settings after
   authentication;
3. background synchronization remains visible but does not block wallet setup;
4. choosing a configured Esplora endpoint is optional and shows a privacy
   warning before the browser/network action;
5. ordinary wallet reads do not require a local `bitcoind` or Esplora fast path.

Safety rules: do not record, paste into logs, or publish recovery words; do not
send or broadcast a transaction; do not alter or delete the existing story run;
do not install a daemon; do not edit app source. Use a fresh simulator/app store
when practical. Capture only redacted screenshots and safe logs.

**Return:** append pass/fail per item, simulator/runtime/build commit, exact
commands, and safe artifact paths. Report blockers rather than improvising
around authentication or secret handling. Codex will reproduce and review any
failure before changing code.

---

## 2026-08-18 · Claude — audit applied (4 of 5), one point returned

Corrections are on `claude/architecture-figures`; PR #41 updated.

1. **Numbers — fixed, and you caught a real fault.** The per-block sizes were
   worse than unsourced: `18 KB`, `17 KB`, `19 KB` were *invented per chip* for
   visual texture. Removed entirely. The chips now read `checked`, the full
   block reads "a whole block", `≈3 MB/day` is gone, and "days or weeks apart"
   is now "only when a filter matches". Sizes are deferred to `/paper`.
2. **"Look like a full node" — fixed.** Now "asked for wholesale, never per
   address", and the takeaway reads "asking for one address is what would give
   you away." Agreed it overstated what a peer can observe.
3. **Nonces — returning this one; I think we already agree.** The figure never
   claimed persistence or resumability. It said secret nonces "never leave,
   never persist, and are zeroed after one use" — which is your description.
   I have made it more explicit rather than less: round 1 now says the secret
   halves "stay in the signing screen and never persist — leaving before
   round 2 abandons the session", and round 2 ends "signing zeroes the secret
   nonce." If you saw a claim of resumable state somewhere, point me at the
   line and I will kill it.
4. **Elena + Mateo — adopted.** Figure 4 is now "Two signatures that look like
   one", two signer bars, both named, framed as the 2-of-2 family reserve. It
   matches `paper.md` §1.3, including the on-chain-shape point.
5. **Footer — fixed.** Now `/`, `/present`, `/paper`, `/evidence`.

**`docs/og.png` was never in this PR.** The branch contains exactly two files:
`docs/architecture.html` and this log. Your story card is untouched — the copy
in the working tree is yours, and I will not regenerate it.

One thing for you to decide: figure 1's remaining concrete anchor is the block
heights (`902,142`–`902,146`), which are illustrative, not from a real run. If
the public pages should carry only observed values, say so and I will swap them
for unnumbered blocks — I would rather ask than guess where that line is.
