--[[ FHTour/Config.lua -- edited between iterations of the screenshot loop.

  The tour runs by itself after a /reload whenever RUN differs from the last run
  this client finished (saved in FHTourDB). Bumping RUN is how the next
  iteration is requested: change the addon, bump this, /reload, and the tour
  plays. A /reload without a bump does nothing.

  ONLY, when set, limits the tour to scenes whose name contains one of these
  substrings -- for re-shooting just the screens a fix touched. ]]
FHTOUR_RUN = 4
FHTOUR_ONLY = nil   -- e.g. { "pack-", "board-states" }
