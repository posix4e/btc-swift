# How you hold it

One key, two keys, three. Each step buys something specific, and costs something specific. This page is the long version of the choice; the [front page](/) is the short one.

The rule underneath all of it: **use the smallest policy that fits the money.** A wallet you find annoying is a wallet you will empty into a worse one.

---

## One key

Everything happens on the phone. The key is generated there, stored there, and never sent anywhere. There is no account, no server that knows your addresses, nothing to sign up for.

This is the right shape for money you actually spend. It is the wrong shape for money you cannot afford to lose, for one reason: a single key is a single point of failure. Lose it with no backup and the money is gone. Have it taken and the money is gone.

---

## Two keys — resilience against the maker

Two keys, both required. Nothing moves unless both sign.

The obvious benefit is theft: someone who takes one phone, or finds one recovery phrase, has nothing they can spend. But the reason to reach for two keys is narrower and more interesting than theft, and it is about **the people who built your wallet**.

Every wallet is somebody's software running on somebody's hardware. Both can be wrong:

- **Hardware.** Devices have shipped with keys an attacker could guess, because the random number generator was not as random as believed. Every coin behind those devices was exposed at once, without anyone touching them.
- **Software.** A signing bug, a bad update, a compromised build. The device is fine; the code that drives it is not.

You cannot audit your way out of this. What you can do is refuse to bet everything on one maker being right. Two keys held on devices from two different makers means a flaw in either one is survivable — the attacker who breaks one still needs a signature the broken device cannot produce. Both would have to fail, independently, at the same time.

This is why "two devices" is not the same as "two of my phones". Two devices running the same software share the same mistakes. The independence is the product.

### And nobody has to know you have it

Winnow can combine two keys into one before anything reaches the chain. What gets published is a single 64-byte signature — the same thing an ordinary one-key wallet publishes.

That is worth more than the fee saving.

Ordinary multisig announces itself. When it is spent, the chain reveals the policy it spent under, so anyone reading it learns you keep additional signers and how many signatures standing between them and your money. Combining the keys publishes none of that. Nobody learns there is a second device — which means nobody learns there is a second device worth coming to look for.

The trade: combined keys are all-or-nothing. Two of two, three of three. If you need "any two of these three", that is the next section, and it is visible on the chain when spent.

---

## Three or more — everything else

Any two of three. Any three of five. You choose how many keys exist and how many must agree.

This is the shape for every problem that is not about the maker:

**Losing one.** A phone in a river is an inconvenience rather than a catastrophe. Two of your remaining keys still move the money.

**Being made to move it.** If somebody is standing in your house, you cannot send the money — not because you refuse, but because you genuinely cannot. The other key is elsewhere, held by someone who is not in the room. Coercion only works on people who are able to comply.

**Dying.** If you can no longer sign, the keys you placed with others still can, after whatever real-world checks you set when you built the wallet. An estate settles without you handing anyone your keys while you are alive, and without a lawyer holding your coins.

**Working with an institution.** A company whose business is holding one key can hold one — for a loan against your coins, or a custody arrangement — without ever being able to spend alone. You keep enough keys that they need you. They keep enough that losing your phone is not the end.

The cost is visibility: spending this way publishes the policy. Anyone reading the chain sees that it took two signatures out of three. That is the honest price of being able to lose a key.

---

## What actually travels

Nothing secret. A payment starts as a partly signed transaction — a file of text — and gathers signatures as it goes.

Each holder sees what they are approving before approving it: the amount, the destination, the fee. Signing is a review, not a rubber stamp. The keys never move; only signatures do. When enough signatures exist, anyone can broadcast it, and the payment is ordinary from that moment on.

The technical write-up of both policies, including the exact descriptors and witness shapes, is in the [design paper](/paper).
