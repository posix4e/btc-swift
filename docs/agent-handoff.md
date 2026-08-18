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
