# Design notes

Building Amber from the game design document (GDD) meant making calls wherever the document is silent or ambiguous. This file lists those calls so you can keep or overturn each one. Almost all of them are one number or one switch in [`scripts/core/tuning.gd`](scripts/core/tuning.gd).

## Interpretations of the GDD

**Downed, caught and turned.** The GDD uses all three words; here is the state machine they became.
- Two hits put a survivor down. The first gives an adrenaline burst (6.2 m/s for 2.6 s).
- A downed survivor is infected and starts a 90 s turn timer. They can crawl.
- Reaching your own base adds 120 s, once per down. This is the GDD's "about two extra minutes".
- A killer **catches** a downed survivor by holding interact for 3.5 s. A stun interrupts the catch.
- Only a **cure** (buy it, then hold E on the downed survivor) or a **Medic's revive** (once per match) brings someone back. They return wounded.
- If the timer runs out, the survivor **turns**. Inside their own base, they're dazed for 10 s and then reveal the base's structures, traps and hatch to the killers, as the GDD says.

**Cures.** The GDD says "each person can make only one", so each survivor can **buy** one cure per match at a terminal. There are 5 per match, priced at $200.

**Pot halving and bounty.** The duo's pot is halved when a partner is caught, and also when one turns. The lost half becomes the bounty on the killer who caught them, with a $40 minimum. The first duo to stun that killer collects it, with a flare or a trap. The GDD names a bounty but no value; recycling the lost half makes revenge worth something.

**Win conditions.** These follow the GDD:
- Each duo wins by escaping.
- The killers win only if they catch every survivor.
- Caught survivors win with the killers.

The results screen also lists every player's outcome, so partial wins are visible. Some matches never end on their own, which would make them drag (outcome 9 on the GDD's list). To prevent that, the **final push** is announced at 20:00 and the company **purges** the town at 27:00. Anyone still inside then counts as caught.

**Brute charge.** "Knocks down survivors" is read as a forceful, unparryable hit that shoves the survivor aside, not as an instant down. With instant downs the Brute caused 40% of all downs in testing. Set `CHARGE_INSTANT_DOWN = true` to change it.

**Lurker tongue.** This works like Left 4 Dead's Smoker, which the GDD references.
- The tongue flies 13 m and pulls the survivor in. The Lurker can't move while pulling and stays revealed.
- On arrival it **holds the survivor for 2.5 s**, then strikes.
- Breaking it: a partner holds interact for 0.8 s, or someone stuns the Lurker. It also snaps on corners or if line of sight breaks.
- Elite Lurkers' tongues have half the range and twice the cooldown, and only pull: they never strike.

**Tracker.** While stalking it's invisible to survivors beyond 3 m and moves at 6.6 m/s. It can't see survivors, only footprints, blood and noise. The **scent mask** wipes nearby trails and stops masked survivors leaving new ones for 20 s.

**Perfect parry.** The window is 0.12 s (the GDD says "about a tenth"). A parry nullifies the hit and pays $20, but only once per killer per duo every 45 s, so survivors can't farm parries (outcome 2).

**Lurker "weak once spotted".** A survivor looking at the Lurker within 14 m for 2.2 s, or a floodlight, marks it as spotted. A spotted Lurker is slower and announced to survivors.

**The worse trap.** One random duo starts in a mine cell. Its two levers must be held at the same time, which forces cooperation. That duo starts with +$60 so bad luck isn't a pure loss.

**Rushing penalties.** Smashing cell doors and boarded passages is very loud, and it frees survivors too. Killers also **tire**: after 28 s of continuous chasing they drop to 88% speed for 6 s, which a running survivor can outpace.

**Bases.**
- Claim a spot by holding E on open ground. Bases must be at least 26 tiles apart and away from the Nest.
- The base radius is 12 m.
- A base is revealed to killers for 35 s after each stage. A running generator is heard nearby every 22 s.
- A base is revealed for good once its helicopter is called or a member turns inside it.
- Killers smash the station: it has 300 HP and takes 30% of normal damage. A broken station blocks building until repaired for 15% of the stage cost.

**Escape hatch.** It goes on a wall or rock face at your base. It turns that wall into a survivor-only passage, hidden from killer players and killer bots until found. Lockdown seals it too.

**Helicopter.** Arrives 90 s after the call. While a main killer is in the landing zone it hovers, but for at most 30 s in total, so killers can't block it forever (outcome 3). Then there's a 15 s boarding window. A survivor whose partner is gone can board alone. If the duo misses the helicopter, it can call again.

**Shops.** 4 terminals. Every 5 minutes, 2 random ones open for 60 s. Survivors get a 20 s warning and see which ones will open; killers find out only when they open. A fixed schedule at fixed spots would invite camping.

**Knockdown items.** Four flare guns. A flare knocks a killer down for 5 s (the Brute for 3.25 s), within 11 m and a 28° cone. Survivors see every flare on their map. Killers see 22 m hot zones that shift every 55 s and vanish once a flare is picked up.

**Betrayal.** Only parts **stored** at a base can be stolen. Installed parts are safe, which matches "can't sabotage another duo's radio".
- Stealing takes 7 s and is very loud.
- A thief is marked if another survivor sees them within 16 m, or with a 25% chance when the robbed duo is still alive.
- Marked thieves are announced to everyone.

**Elites.**
- Main killers are faster than survivors. Elites are slower than a running survivor (3.75 m/s against 4.1).
- Elites see 11 m (main killers 13.5 m), swing slower, have 60% powers, and respawn at the Nest after 30 s.
- They gain XP from catches (3) and assists (1) and reach level 3 at most, choosing a skill branch each level.
- Every branch has an effect, for example Vents lets an Elite Lurker use squeeze gaps and Pack speeds up nearby killers.

**Nest.**
- It fills from catches (+22), broken structures (+3), station damage, radio stages (+9, +12 and +15) and a helicopter call (+35), plus a small passive trickle.
- It fills 1.5× faster during the final push.
- The event has a 50 s cooldown.
- Swarm sends 4 temporary AI "husks" at the target base. They can wound but not catch.

## The GDD's open questions

**Do route-editing charges refill?** Yes, but slowly. Each main killer starts with 3 charges, and every time the Nest fires each main killer gains +1, to a maximum of 5. Smashing boarded passages costs no charge. Collapsing a tunnel is refused if it would cut the map in two.

**Exact prices and timers.** A full first pass is in `tuning.gd`. The headline numbers:

| | |
|---|---|
| Stage costs | $40, $120, $190 (plus parts) |
| Build times | 16 / 26 / 36 s (Engineers ×1.6 faster, Medics ×0.7 slower) |
| Starting pot | $40 and 2 scrap |
| Cash caches | 90 on the map, $14–38 each |
| Cure | $200, 5 per match |
| Killer speeds | Tracker 4.35, Lurker 4.25, Brute 4.15 m/s; survivors run at 4.1 and walk at 2.9 |
| Killers released | 0:40 |
| Final push | 20:00 |
| Purge | 27:00 |

**Meta progression and lore.** Left out, as the GDD defers both.

## Balance status (bots against bots)

`scripts/tests/sim.gd` runs whole matches with all 13 slots as bots. The final batch, 16 matches on seeds 1–16 at Normal difficulty:

| | |
|---|---|
| Average match length | **18:22** (shortest 9:46, longest 27:00; 1 reached the 27:00 purge) |
| Survivors escaping | **10 of 160** (0.62 per match), in 5 of 16 matches |
| Antenna built | 69 of 80 duos, on average at 2:46 |
| Generator built | 44 duos, on average at 5:52 |
| Transmitter built | 13 duos, on average at 8:42 |
| Helicopters called / survivors escaped | 12 / 10 |

The killers win most matches. Survivors who get their radio finished usually get out. The rest are run down while scavenging stage-3 parts from the lab, the deep mines and the high ground.

How to read it: bots are a proxy. Killer bots hunt by sight and sound with a short reaction delay. Survivor bots crouch-sneak, break line of sight, use squeeze gaps, flee to their base and defend the landing zone. A human survivor will do things bots don't, and so will a human killer. Use the Easy, Normal and Hard setting to compensate.

What moved the numbers most during tuning, in case you want to push further:

- **The elite snowball is the biggest lever.** With elites switched off (`ELITES_ENABLED = false`), matches ran about 4 minutes longer and many more duos finished the transmitter. This is outcome 1 on the GDD's list. Weaker elites (speed, sight, swing, respawn) are the main defence. `ELITES_CAN_CATCH = false` turns elites into pure pressure.
- **One-shot powers dominated.** The Brute's instant-down charge and an unbreakable tongue accounted for half of all downs before they were changed.
- **Killer senses:** `KILLER_SIGHT` (13.5 m in fog), `BOT_REACTION` and the noise radii decide how often survivors get found.
- **Pace:** `STAGE_COST`, `CASH_*`, `PART_COUNTS` and `ITEM_SPOT_RANGE` set how quickly radios get built.

To get closer to the GDD's 25 minutes, the next things to try are:
- slightly slower killers;
- fewer active elites at once;
- a longer boarding window, since a few duos died standing at their own landing zone.
