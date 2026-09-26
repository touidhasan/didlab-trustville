# Incident write-up

Copy this file to `docs/incidents/YYYY-MM-DD-short-name.md` and fill it in.

One is required for each lab where something broke — a failed deploy, a drained pool, a
stuck key, a transaction that did the wrong thing. "Nothing broke" is an acceptable answer
only if it is true, and over six labs it will not be.

**Blameless means blameless.** Name systems, not people. "The deploy script's last step
gave away admin rights before the treasury was created" is useful. "I forgot" is not — it
describes the outcome, not the cause, and produces no fix. The question is never who was
careless; it is what made the careless thing easy and the correct thing hard.

---

## Summary

<!-- Two sentences. What broke, and what was the effect? -->

## Impact

<!-- Who or what was affected, and how much. Funds, time, data, other people's work.
     If nothing was lost, say so and say why not — that is often the interesting part. -->

## Timeline

<!-- Times and facts, no interpretation. Include how it was noticed. -->

| Time | What happened |
| --- | --- |
| | |

## What happened

<!-- The mechanism. A reader should be able to reproduce the failure from this section. -->

## Why it happened

<!-- Keep asking why until you reach something that can be changed. Stop when the answer
     is a design decision, a missing check, or a misleading interface -- not a person. -->

## How it was found

<!-- Did a test catch it, a monitor, a user, or luck? If luck, that is itself a finding. -->

## What stops it happening again

| Action | Kind | Status |
| --- | --- | --- |
| | prevent / detect / reduce impact | |

<!-- Prevention alone is not enough. Something will get through, so what will notice it? -->

## What went right

<!-- Real teams record this. A guard that fired, a test that caught it, a rollback that
     worked. It tells you which defences to keep paying for. -->
