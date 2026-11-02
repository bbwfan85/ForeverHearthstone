# 23. Loading a match's art up front

Written 2026-09-25. `./run-tests.sh`: 1018 suites, 0 failures. Lua only --
`/reload` is enough.

| Report | Cause | Fix |
|---|---|---|
| A polymorphed minion showed the bare table for a moment before the Sheep's art appeared | The client reads a texture from disk the first time it is drawn. Deck cards are usually drawn in hand first, but a Sheep, a Frog, a summoned token or an entourage card goes straight onto the table the first time it is ever seen | At the start of every match (practice and duel), `Main:MatchArtIds` lists every card the match can put on the table -- both decks and hands, the heroes and hero powers, every printed entourage, and every card their scripts name, two steps out (tokens that make tokens) -- and `Board:PrefetchArt` draws each one's art once, 2px wide and all but transparent, and keeps it for the match so the client keeps it loaded. The textures are reused from match to match (up to 160) |

Cards generated at random from the whole pool (Unstable Portal, Transform to
a random minion) cannot be known in advance and may still appear a moment
late the first time.
