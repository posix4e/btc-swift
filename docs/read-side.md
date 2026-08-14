# The Read Side: How a Private Mobile Bitcoin Wallet Learns What's Its Own

*Design paper for btc-swift — a pure-P2P-by-default, fresh-wallet, Taproot-only iOS client.*
*All numbers marked "approx." are order-of-magnitude estimates for orientation, not measurements; they are labeled as such wherever they appear. Exact protocol constants are exact.*

---

## 1. The problem

A Bitcoin wallet is, at its core, a holder of private keys plus the ability to answer four questions about the chain:

1. **"What's mine?"** — which transaction outputs are spendable by my keys. From this follows everything the wallet displays (balance, history) and everything it needs to sign (the UTXOs, their amounts, and their scriptPubKeys — required inputs to the BIP341 signature hash).
2. **"Where's the tip?"** — the current block height, so "confirmed" can mean something.
3. **"What fee should I pay?"** — fee-market information.
4. **"Did my transaction get out, and did it get mined?"** — broadcast and confirmation tracking.

Question 1 is the entire difficulty, and the reason is structural: **the Bitcoin P2P protocol has no address index.** Full nodes validate every transaction but do not maintain a queryable mapping from addresses or scripts to transactions. There is no `getbalance(address)` message on the wire. So for a light client, someone has to scan the blockchain on the wallet's behalf. The design question of this paper is: *who scans, what do they learn, and what does it cost?*

Every realistic answer falls into one of two families:

- **A server scans for you.** You hand the server your addresses (or extended public keys); it queries its index and returns your history. Fast and cheap — and the server learns, and can log, every address you care about, linkable to your IP address.
- **Your phone scans for itself.** The phone downloads a compact per-block summary (a *filter*), checks it locally against its own scripts, and downloads a full block only when a filter indicates the block contains its transactions. Nobody learns anything — but the phone does the work and the bandwidth.

This paper walks through every realistic mechanism in both families, with honest cost/privacy/trust accounting, then walks the actual use cases of this product and concludes which mechanism serves each one — and why the answer, for this product, is client-side scanning by default, with a server only ever as an explicit, warned, user-initiated opt-in.

**Scope note:** btc-swift is a *fresh-wallet* product. Wallets are created new in the app; a new wallet has no history, so scanning runs *forward* from the moment of creation. Existing wallets may be imported **only with their history included** — the user supplies an export bundle (descriptor/keys + known transactions and UTXOs + a last-known height) from their previous wallet software, and the app verifies and updates that history by scanning filters forward from the bundle's height. There is no historical back-scan machinery at all: catch-up cost is proportional to how stale the bundle is, and a bundle exported at the tip costs nothing. This constraint — chosen deliberately — is what makes the pure-P2P answer not merely acceptable but cheap.

---

## 2. The candidate mechanisms

### 2.1 Full node on the phone

Run Bitcoin Core (or equivalent) on the device: download and validate every block.

- **Cost:** the full chain is several hundred GB and growing (exact current size depends on date and pruning; even pruned, initial block download must *process* the entire history — days of CPU and hundreds of GB of transfer). Ruled out for a phone by bandwidth, storage, battery, and App Store reality. Not discussed further.

### 2.2 Central indexer ("esplora"-family APIs)

Public servers (e.g. mempool.space, blockstream.info) run a full node plus an address index, and expose REST endpoints: `GET /address/{addr}/utxo`, `GET /address/{addr}/txs`, `GET /fee-estimates`, `POST /tx`.

- **Cost to user:** kilobytes per query; instant answers; mempool-stage visibility (unconfirmed transactions appear immediately).
- **What leaks:** *everything that matters.* The operator sees every address you query, the set of your addresses (wallet fingerprint), your balance, your counterparties, and your IP address linking them together. "We don't keep logs" is a policy, not a mechanism — the query stream itself is the sensitive data, and it exists the moment you ask.
- **Trust:** you must trust the server's answers about your history. (Partial mitigation exists: when *spending*, the BIP341 sighash commits to input amounts, so a server lying about a UTXO's amount produces an invalid transaction rather than a theft — but a server can still hide payments from you or invent history.)
- **Role in this product:** none by default. It exists in the app only as an **opt-in fast path**, off by default, enabled in settings with an explicit warning naming exactly what is traded away (address set, balances, counterparties, IP) and linking to this section. Informed consent, per user, per install.

### 2.3 Electrum protocol

The Electrum server protocol (address scripthash subscriptions over TCP/SSL) is the same shape as §2.2 — a server-side address index queried with your scripthashes — with the same privacy properties: the server learns every scripthash you subscribe to. Noted for completeness; nothing about it improves on §2.2 for this product's goals.

### 2.4 BIP37 bloom filters — and why they're dead

BIP37 (2012) let a light client upload a *bloom filter* of its keys to a full-node peer, which then forwarded only matching transactions. This is the historically important wrong answer:

- **Privacy catastrophe.** Bloom filters leak far more than intended: false-positive rates are chosen small, filters for multiple addresses correlate, and an observer (or the peer itself) can statistically extract which addresses are actually yours. The research literature demolished this repeatedly (e.g. Gervais et al., "On the Privacy Provisions of Bloom Filters in Lightweight Bitcoin Clients", ACSAC 2014).
- **DoS vector.** Serving BIP37 lets any client force a full node to scan entire blocks against arbitrary filters — CPU for free, on demand.
- **Consequence:** Bitcoin Core has served BIP37 to peers only when explicitly enabled since v0.19 (2019); on today's network it is effectively unavailable. Any design that needs "ask a node about my address" over P2P is a design from 2013.

BIP37 matters here for one reason: it establishes that **server-side matching is inherently leaky**, which is why the modern design inverts it — *the data moves to the client, the matching happens on the client.*

### 2.5 BIP157/158 compact block filters (client-side filtering)

This is the inversion, and the mechanism this product uses by default. Mechanics, precisely:

- **BIP158** defines, for each block, a *basic filter*: take every output scriptPubKey in the block (excluding OP_RETURN outputs) **and** the scriptPubKeys of all outputs *spent* by the block's inputs; hash each with SipHash keyed by the first 16 bytes of the block hash; map into a Golomb-Rice-coded set (GCS) with parameters P=19, M=784931. Result: a per-block data structure of approx. 15–20 KB (recent blocks; smaller for older, emptier blocks) that answers "might script S be in this block?" with **zero false negatives and a false-positive rate the GCS construction leaves tunable in general but the basic filter fixes at 1/784931**.
- **BIP157** wires it into P2P: peers signal `NODE_COMPACT_FILTERS` (service bit 6); clients request `getcfheaders` (a 32-byte commitment chain over the filters), `getcfcheckpt` (checkpoint hashes, for cross-peer comparison), and `getcfilters` (the filters themselves).
- **Client flow:** the wallet derives its own scriptPubKeys locally → downloads the filter for each new block → checks each filter *on the device* against its scripts → on a (rare) match, downloads that one full block (`getdata`) and extracts its transactions. Nothing about the wallet's keys or addresses is ever transmitted.

Costs, stated plainly:

- **Block headers** (needed to know the chain and anchor filter headers): exactly 80 bytes per block — approx. 75 MB for the entire historical chain, and *zero* for a fresh wallet that starts at the tip.
- **Filters, steady state:** ~144 blocks/day × approx. 15–20 KB ≈ **3 MB/day** (approx.) of filter download. A once-daily app open pulls a few MB — comparable to loading a couple of web pages.
- **Matched blocks:** only blocks that actually contain the wallet's transactions, ~1–2 MB each (exact: block size varies up to 4M weight units). For typical personal use this is rare — days to weeks apart.
- **CPU/battery:** hashing and matching a filter against a watch list of thousands of scripts is milliseconds of work per block on a modern phone.

### 2.6 Server-side privacy designs (considered, and why none is the default)

Since the leak in §2.2/§2.3 is the server observing queries, can we build a *server that can't observe*? The candidates:

- **Self-hosting.** Run your own indexer on your own hardware and query only it. Privacy: excellent (you trust yourself). Cost: hardware, setup, and maintenance — outside this product's premise of a self-contained mobile client. (A user who *has* one can point the opt-in esplora setting at their own instance — the best of both worlds, at their initiative.)
- **Tor / VPN to a public indexer.** Hides the client's IP from the operator. The operator still sees — and can correlate and log — the *content*: the set of addresses, which is itself the wallet fingerprint. Partial mitigation only.
- **Oblivious HTTP (OHTTP, RFC 9458).** A two-party relay/gateway split: the relay sees the client's IP but not the query; the gateway sees the query but not the IP. This is Apple Private Relay's architecture and it is genuinely deployable. But the gateway still aggregates the address sets of all users it serves, trust now rests on the relay/gateway non-collusion assumption, and *someone must operate both parties*. Better than Tor, still a server to trust.
- **TEE + no-logs + ORAM ("enclave esplora").** Run the indexer inside a hardware enclave (Intel TDX, AMD SEV-SNP, AWS Nitro) with remote attestation, so the operator cannot read queries even with root; use ORAM (Oblivious RAM) inside the enclave so memory-access patterns don't reveal which addresses are being looked up. Intellectual honesty requires listing the catches:
  - The enclave boundary ends at the network card: the host still observes client IPs, connection timing, and request sizes — traffic analysis outside the enclave — unless expensive padding/batching is added.
  - TEEs have a decade-long side-channel track record (Spectre-class transient execution, controlled-channel/page-fault attacks against SGX, cache attacks). ORAM addresses one class (access patterns); it does not fix microarchitectural leakage, and ORAM over a multi-GB address index carries a real bandwidth/latency multiplier per query.
  - Remote attestation roots trust in the CPU vendor's signing infrastructure and in the reproducible-build chain of the enclave image — a *different* trust assumption, not the absence of one.
  - Someone must procure enclave-capable hardware and operate it forever. "Can it keep no logs and use ORAM?" — yes, approximately, at real cost; but the product question is whether a mobile wallet should depend on anyone's server at all. For this product: not by default, ever.

The pattern across §2.6: every server-side fix moves or shrinks the trust rather than deleting it, and every one requires operating infrastructure. Client-side filtering (§2.5) is the only mechanism that requires trusting no one with the read path.

### 2.7 Honest weaknesses of compact filters

Filters win the privacy argument; they lose elsewhere. Said louder than the strengths:

1. **Filters are not consensus-committed.** A malicious peer can serve a filter that *omits* your transaction (lying by omission), causing the wallet to miss a payment. Mitigation: fetch `cfcheckpt`/`cfheaders` from ≥2 independent peers and disconnect peers that disagree — disagreement is detectable, though the protocol cannot by itself prove which peer lied. A future consensus change committing filters to blocks would close this; it does not exist today. Residual risk: a *partitioned* client (all reachable peers colluding) can be lied to — the standard eclipse-attack caveat for all light clients.
2. **No mempool view.** Filters cover confirmed blocks only. An incoming payment is invisible until it is mined (≈10 minutes, sometimes much longer). The UI must say exactly that — "payment confirmed" appears late, not "payment incoming" early. This is the single largest UX cost of the default design. (The opt-in esplora path shows mempool-stage transactions — one of the things the warning dialog can honestly list as the trade.)
3. **Bandwidth is real, if modest.** ~3 MB/day (approx.) steady state is trivial on Wi-Fi and fine on cellular, but it is not zero, and a phone that hasn't synced in a month downloads ~100 MB (approx.) of filters to catch up.
4. **Fee estimation is blind.** Without a mempool view, the wallet cannot see the current fee market. Mitigations: BIP133 `feefilter` messages from peers give the network's *minimum relay fee* floor; feerates of transactions in matched blocks give some signal; beyond that, conservative static presets with user override. The result is cruder than any mempool-aware estimator — the price of asking no one. Owned. (Again: the opt-in path gets real fee estimates.)
5. **Fresh-wallet scope is what makes this viable.** Filters are cheap *because* scanning starts at creation and runs forward. Recovering an old wallet *privately from the chain* would mean back-scanning gigabytes of historical filters (approx.; multiple GB for a multi-year-old mainnet wallet) — so this product doesn't do that. Instead, **import requires the history to come with the wallet**: an export bundle from the previous wallet software carrying the descriptor/keys, the known transactions and UTXOs, and a last-known height. The app verifies the bundle by scanning filters forward from that height — discovering any spends since — which keeps the no-back-scan property absolute and makes import cost proportional to the bundle's staleness, not to the wallet's age.

---

## 3. Use-case walkthrough: what serves what, and why

| # | Use case | Default mechanism | One-sentence rationale |
|---|----------|-------------------|------------------------|
| 1 | Fresh wallet, first launch | Nothing to scan; record creation height; sync filters forward from tip | A new key has no past — the read side starts empty and cheap by construction. |
| 2 | Daily open / ongoing sync | `getcfilters` for blocks since stored checkpoint (~3 MB/day, approx.), match locally, fetch matched blocks only | Client-side matching means the phone learns its own history without anyone else learning it. |
| 3 | Receiving a payment | Visible **at block confirmation** via filter match; UI shows "confirmed" only | Filters see blocks, not the mempool — honesty in the UI instead of a fake "incoming" state. |
| 4 | Sending | UTXOs/amounts/scripts already local from scanning; fee from `feefilter` floor + observed feerates + presets; broadcast via P2P relay (`inv` → `getdata` → `tx`) to ≥3 peers, rebroadcast until mined | Everything needed to build and sign is already on the device; relay needs no account, no API, no server. |
| 5 | Watching a single address | One more scriptPubKey in the local match list — same filter stream, zero extra bandwidth | The P2P protocol has no per-address query (BIP37 is dead); the granularity is per-block filters regardless of watch-list size. |
| 6 | Multisig vault (k-of-n or MuSig2 n-of-n) | Identical machinery — watch list derived from the vault's `tr()` descriptor | A vault is just a different set of scripts; the read side doesn't care. |
| 7 | Balance & history display | Local storage, populated by §2.5 matches | After sync, display is a database read — no network at all. |
| 8 | "Where's the tip?" | 80-byte block headers over P2P (`getheaders`), PoW + chainwork-checked | Headers are the sync clock and the anchor for the filter-header chain. |
| 9 | "Did my tx get out?" | Peer `inv` gossip for propagation signal; confirmation observed via filter match | Relay acceptance plus eventual inclusion are both observable without any server. |
| 10 | Importing an existing wallet | User supplies a history bundle (descriptor/keys + known txs/UTXOs + height); app verifies by forward filter-scan from that height | Your old wallet already did the scanning — bring its answers with you, then let filters check and continue them. |
| 11 | Optional: everything, faster | User opts into an esplora backend in settings, past a warning naming the leak (address set, balances, IP) and linking to §2.2 | It's the user's threat model; the app's job is to make the trade explicit, not to make it for them. |

One use case is deliberately **absent** from the default path:

- **Mempool-stage payment notification** — impossible without a mempool view; the default UI is designed around it rather than pretending otherwise. (Available via the opt-in path, and listed as such in the warning dialog.)

---

## 4. Conclusion

For a fresh-wallet product, the read side reduces to a steady-state stream of ~3 MB/day (approx.) of compact filters, matched on-device, with full blocks fetched only on hits. No server learns anything because no server is asked anything. The costs — confirmation-time payment visibility, crude fee estimation, reliance on honest filter peers cross-checked by header comparison — are real, bounded, and stated to the user instead of hidden. Every server-based alternative either resurrects BIP37's mistake (letting someone else match against your addresses) or requires operating trusted infrastructure (self-host, OHTTP pair, TEE+ORAM enclave); those are the user's to choose, knowingly, one toggle away — never the default.

**v1 is therefore: block headers + BIP157/158 compact filters + P2P transaction relay, over `Network.framework`, talking only to full-node peers that signal `NODE_COMPACT_FILTERS` — with an esplora fast path available strictly as an opt-in behind an explicit privacy warning.**

---

## 5. Future hardening

Three known paths would strengthen this design further. None is buildable today on this product's constraints; all are worth stating so the current trade-offs are legible against them.

### 5.1 Consensus-committed block filters

- **What:** a soft fork committing each block's BIP158 filter (or filter header) into the block itself, so a peer serving a wrong filter is *provably* wrong against the header chain.
- **Fixes:** §2.7.1 outright — lying by omission becomes impossible, not merely detectable-by-disagreement.
- **Costs:** a consensus change; outside anyone's roadmap control. Until then, multi-peer `cfcheckpt`/`cfheaders` comparison is the mitigation.

### 5.2 PoW fraud proofs

- **What:** a compact, relayable proof that some block in a chain is invalid, so light clients needn't accept majority chainwork on faith.
- **Fixes:** the eclipse-amplified trust assumptions that all light clients carry — a partitioned client fed a fabricated chain tip.
- **Costs:** producing or consuming fraud proofs requires validation infrastructure (a script engine, chain state) that this product deliberately does not carry; and full validation on-device means downloading every block (~150–300 MB/day approx. vs. ~3 MB/day of filters) — bandwidth, not storage, is the mobile constraint. Utreexo-style accumulators solve UTXO-set storage; they do not shrink the blocks. If a future revision ever embeds real validation, reusing an existing consensus engine rather than reimplementing one is the only sane path.

### 5.3 Utreexo proof-based import verification

- **What:** with the draft Utreexo peer services (BIP181/182/183, work in progress), a peer could serve a Merkle proof that an imported output is still in the accumulator — i.e., still unspent.
- **Fixes:** the import flow's one remaining cost — verifying a history bundle by forward-scanning filters from its height (§2.7.5). Proof-based verification is O(1) per UTXO and independent of bundle staleness.
- **Costs:** the BIPs are drafts and no serving network exists. The import-bundle format is versioned, so a `proof` field can be added non-destructively when the ecosystem arrives.

---

## 6. References

- [BIP37: Connection Bloom filtering](https://bips.dev/37/) (and its privacy critique: Gervais et al., ACSAC 2014)
- [BIP133: feefilter message](https://bips.dev/133/)
- [BIP157: Client Side Block Filtering](https://bips.dev/157/)
- [BIP158: Compact Block Filters for Light Clients](https://bips.dev/158/)
- [RFC 9458: Oblivious HTTP](https://www.rfc-editor.org/rfc/rfc9458)
- Neutrino (lightninglabs/neutrino) — reference BIP157/158 light-client implementation
- [BIP341: Taproot](https://bips.dev/341/) · [BIP340: Schnorr](https://bips.dev/340/) · [BIP86](https://bips.dev/86/) · [BIP352: Silent Payments](https://bips.dev/352/) · [BIP327: MuSig2](https://bips.dev/327/) · [BIP388](https://bips.dev/388/) · [BIP370: PSBTv2](https://bips.dev/370/)
