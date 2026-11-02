# APIProbe

Read-only API surface report. 290 probes in 13 groups. No automation, no chat to
other players, no CVar writes, no writes outside its own SavedVariables.

Developer diagnostic only; Forever Hearthstone does not require it. Release
packages exclude it, and local install/link scripts only include it when passed
`-IncludeAPIProbe`.

## Install and run (10 steps)

1. Copy the whole `APIProbe/` folder into `World of Warcraft/_retail_/Interface/AddOns/`.
2. Launch the client; at the character screen open **AddOns** and tick **APIProbe**.
3. Tick **Load out of date AddOns** as well if APIProbe is greyed out.
4. Log in. It runs itself once and prints a short summary to chat.
5. Optional: `/apiprobe` re-runs it, `/apiprobe full` dumps everything into chat.
6. Optional opt-in extras (skip if unsure): `/apiprobe net` measures the
   addon-message length limit by whispering **yourself**; `/apiprobe emote` calls
   the emote APIs with an **invalid** token to see if they are protected. Neither
   sends anything to another player. Both are off by default.
7. Type `/reload` — SavedVariables are only written to disk on reload or logout.
8. Open `_retail_/WTF/Account/<ACCOUNT>/SavedVariables/APIProbe.lua`.
9. The `paste` field inside it is the whole report as plain text lines — paste
   that back. The rest of the table is the same data, structured.
10. Re-run on **Forever** the same way (path becomes that client's own `WTF/`).

## Retail results are a PROXY, not ground truth

Retail and Forever are both Mainline (`WOW_PROJECT_MAINLINE`, interface ~16001,
API set ~12.1.5), which is why retail is a usable stand-in. It is **not** the same
client. Forever has its own divergences — secure snippets are reportedly broken
there (`loadstring_untainted` missing), and its build is a separate beta branch.

So: a retail run tells us what Mainline generally offers. It does **not** license
us to depend on anything. Every result must be re-confirmed by running this same
addon on Forever before the client layer relies on it. That is why the report
leads with the interface version, build string and the `WOW_PROJECT_ID` constant
it actually matched — so any pasted result is attributable to a specific client,
and a retail result can never be mistaken for a Forever one.

Treat a disagreement between the two runs as the interesting finding, not as
noise. Diff the two `APIProbe.lua` files directly.

## What the verdicts mean

- `PASS` — the result matched what the project expected.
- `FAIL` — it did not. Expectation is recorded per probe, so a `FAIL` can mean
  "missing but we needed it" **or** "still present when we expected it gone".
- `INFO` — we had no firm expectation; the value is the finding.
- `!! CRITICAL !!` — a `FAIL` on something the design cannot route around.

Nothing is reported as present without being fetched, and where it is safe the
probe also calls it and records the return value. Functions implemented in C
report `C function (arity not introspectable)` rather than a guessed arity.
