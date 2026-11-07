--[[ Client/UI/Widgets.lua

  EVERY PIECE OF THE GAME THAT IS MADE OF FRAMES.

  Cards, pools, hero portraits, mana crystals, the rope, toasts and particles.
  It was all inside Board.lua; it moved here the moment a second screen needed
  cards, because a second hand-rolled card widget is a second place for a card
  to look wrong.

  THE ONE RULE THAT SHAPES EVERYTHING HERE: no art is required. Every widget
  renders completely from solid colours and text, and any texture it is given is
  layered on top when it happens to work. There is no API that can tell us
  whether a texture path exists -- SetTexture on a bad path draws nothing and
  reports success -- so "it looks plain" is the failure mode, never "it looks
  broken" (docs/06).

  POOLING: WoW cannot destroy a frame. Everything variable in number is acquired
  from a pool and released, never discarded, or a page turn leaks a screenful of
  frames for the rest of the session.
]]
local ADDON, ns = ...

local W = {}
ns.Widgets = W

local ART = "Interface\\AddOns\\ForeverHearthstone\\Art\\"

--[[ TYPEFACES. Hearthstone sets names and titles in Belwe, rules text in
     Franklin Gothic and numbers in heavy lining figures; WoW's Friz Quadrata
     is none of them and is the single biggest "this is a WoW window" tell.
     The shipped faces are open-licensed stand-ins (tools/fetch_fonts.py).

     A font file the client cannot open leaves a string with no font at all,
     and a fontless string ERRORS on SetText -- so every face is probed once
     here and any that fails falls back to Friz, rather than blanking the UI. ]]
local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
ns.Fonts = {
  TITLE  = ART .. "Fonts\\Vollkorn-Black.ttf",
  BODY   = ART .. "Fonts\\LibreFranklin-SemiBold.ttf",
  -- the keywords in rules text (Taunt, Battlecry:) are set in a heavier weight
  BOLD   = ART .. "Fonts\\LibreFranklin-ExtraBold.ttf",
  NUMBER = ART .. "Fonts\\Coustard-Black.ttf",
}
do
  local probe = CreateFrame and CreateFrame("Frame"):CreateFontString(nil, "OVERLAY")
  for role, path in pairs(ns.Fonts) do
    local ok = probe and probe:SetFont(path, 12, "")
    if not probe or ok == false or probe:GetFont() ~= path then ns.Fonts[role] = FALLBACK_FONT end
  end
end
local FONT = ns.Fonts.TITLE
local BODY_FONT, NUMBER_FONT = ns.Fonts.BODY, ns.Fonts.NUMBER
local BOLD_FONT = ns.Fonts.BOLD

--[[ ONE PALETTE, ONE SET OF TEXT STYLES (docs/24).

     Every screen used to choose its own size, colour and outline at each call
     site, so the same kind of text drifted from screen to screen: three body
     sizes, two dialog faces, titles at three heights, labels that kept
     whatever colour the previous screen had left on them. Now a label names a
     ROLE and gets all of it from here.

     Sizes are for a 720px-tall window and follow the window's height between
     each role's min and max, so a large window does not shrink its text to a
     corner and a small one still reads. ]]
W.Colors = {
  gold      = { 1, .83, .46 },   -- screen titles on dark
  goldLight = { 1, .86, .52 },   -- headers and captions on dark
  cream     = { 1, .95, .84 },   -- names and labels on dark
  creamDim  = { .86, .80, .68 },
  bodyLight = { 1, .93, .80 },   -- running text on dark
  ink       = { .36, .20, .08 },   -- titles printed on parchment
  inkBody   = { .20, .12, .06 },   -- running text on parchment
  button    = { .22, .12, .055 },  -- lettering carved into a plaque
  count     = { 1, .86, .50 },   -- owned counts, deck-list counts
  white     = { 1, 1, 1 },
  black     = { .04, .03, .01 },
  danger    = { .55, .08, .04 },
}
local C = W.Colors

W.Style = {
  screenTitle = { font = "TITLE",  size = 30, min = 20, max = 44, color = C.gold,      flags = "OUTLINE", shadow = true },
  plaqueTitle = { font = "TITLE",  size = 24, min = 12, max = 40, color = C.white,     flags = "OUTLINE", shadow = true },
  caption     = { font = "TITLE",  size = 19, min = 13, max = 28, color = C.goldLight, flags = "OUTLINE", shadow = true },
  subtitle    = { font = "TITLE",  size = 15, min = 11, max = 22, color = C.goldLight, flags = "OUTLINE" },
  header      = { font = "TITLE",  size = 15, min = 11, max = 22, color = C.goldLight, flags = "OUTLINE" },
  heroName    = { font = "TITLE",  size = 24, min = 16, max = 34, color = C.goldLight, flags = "OUTLINE", shadow = true },
  label       = { font = "TITLE",  size = 15, min = 10, max = 21, color = C.cream,     flags = "OUTLINE" },
  pageTitle   = { font = "TITLE",  size = 22, min = 14, max = 30, color = C.ink },
  pageText    = { font = "TITLE",  size = 14, min = 10, max = 19, color = C.ink },
  button      = { font = "TITLE",  size = 15, min = 10, max = 20, color = C.button },
  buttonLarge = { font = "TITLE",  size = 24, min = 15, max = 32, color = C.button },
  playButton  = { font = "TITLE",  size = 26, min = 16, max = 36, color = { 1, .97, .86 }, flags = "OUTLINE", shadow = true },
  body        = { font = "BODY",   size = 14, min = 10, max = 19, color = C.bodyLight },
  bodyInk     = { font = "BODY",   size = 14, min = 10, max = 19, color = C.inkBody },
  dialog      = { font = "BODY",   size = 16, min = 12, max = 22, color = C.bodyLight, shadow = true },
  number      = { font = "NUMBER", size = 14, min = 9,  max = 22, color = C.white,     flags = "OUTLINE" },
  count       = { font = "NUMBER", size = 12, min = 9,  max = 18, color = C.count,     flags = "OUTLINE" },
  tooltipTitle= { font = "TITLE",  size = 15, min = 12, max = 20, color = { .28, .14, .04 } },
  tooltipBody = { font = "BODY",   size = 13, min = 11, max = 18, color = C.inkBody },
  nameplate   = { font = "TITLE",  size = 14, min = 10, max = 18, color = C.cream },
  nameplateSub= { font = "BODY",   size = 11, min = 8,  max = 14, color = C.creamDim },
  banner      = { font = "TITLE",  size = 56, min = 28, max = 84, color = { 1, .86, .40 }, flags = "THICKOUTLINE" },
  result      = { font = "TITLE",  size = 54, min = 28, max = 80, color = C.white,     flags = "THICKOUTLINE" },
  endTurn     = { font = "TITLE",  size = 15, min = 7,  max = 24, color = C.black },
  speech      = { font = "BODY",   size = 16, min = 10, max = 22, color = { .06, .05, .04 } },
  mark        = { font = "TITLE",  size = 12, min = 8,  max = 18, color = C.white,     flags = "OUTLINE" },
  reveal      = { font = "TITLE",  size = 22, min = 12, max = 30, color = C.white,     flags = "THICKOUTLINE" },
  -- a digit on a gem (a deck tile's mana crystal): Hearthstone's heavy edge
  gemDigit    = { font = "TITLE",  size = 18, min = 10, max = 30, color = C.white,     flags = "THICKOUTLINE" },
}

-- The size a role asks for in a window `frameH` pixels tall.
function W.StyleSize(role, frameH)
  local st = W.Style[role] or W.Style.body
  local s = st.size * (frameH and frameH > 0 and frameH / 720 or 1)
  return math.floor(math.max(st.min, math.min(st.max, s)) + 0.5)
end

function W.StyleFont(role)
  local st = W.Style[role] or W.Style.body
  return ns.Fonts[st.font] or FALLBACK_FONT, st.flags or ""
end

--[[ Give a label its role: face, size, colour, outline, shadow. `frameH` is
     the window's height (nil: the 720px design size); `size` overrides the
     role's size where the label is sized from its own geometry (a mana
     readout drawn into a painted lozenge). The role is remembered so the
     screen's layout can re-apply it when the window is resized
     (W.RestyleAll). A label under W.AutoFit keeps fitting to its box. ]]
local styled = setmetatable({}, { __mode = "k" })
function W.ApplyStyle(fs, role, frameH, size, color)
  local st = W.Style[role] or W.Style.body
  local font, flags = W.StyleFont(role)
  fs.styleFixed = size ~= nil or nil
  fs.styleColor = color
  size = math.floor(size or W.StyleSize(role, frameH))
  fs.styleRole = role
  styled[fs] = true
  local fo = rawget(fs, "fitOpts")
  if fo then fo.min = math.max(5, math.min(st.min, size)) end
  fs:SetFont(font, size, flags)
  local c = color or st.color
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
  if fs.SetShadowColor then
    if st.shadow then fs:SetShadowColor(0, 0, 0, .85); fs:SetShadowOffset(1, -1)
    else fs:SetShadowColor(0, 0, 0, 0); fs:SetShadowOffset(0, 0) end
  end
  return size
end

--[[ A BACKGROUND THAT KEEPS ITS SHAPE (like CSS object-fit: cover). The
     tavern cabinet and the pack room were stretched to the window, so a wide
     window flattened their candles and a tall one pulled them thin. This
     crops the source by texcoords to the frame's aspect instead. `srcW`,
     `srcH` are the PAINTED area's pixel size (not the power-of-two canvas it
     was padded into), `u1`,`v1` where that area ends in the canvas. `focusY`
     (0 top .. 1 bottom, default .5) says which part of a tall crop to keep. ]]
function W.CoverTexture(tex, frameW, frameH, srcW, srcH, u1, v1, focusY)
  u1, v1 = u1 or 1, v1 or 1
  local crop = { l = 0, r = 1, t = 0, b = 1, w = frameW, h = frameH }
  if frameW > 0 and frameH > 0 then
    local fa, sa = frameW / frameH, srcW / srcH
    if fa > sa then        -- window wider than the art: crop top and bottom
      local keep = sa / fa
      crop.t = (1 - keep) * (focusY or .5); crop.b = crop.t + keep
    else                   -- narrower: crop the sides evenly
      local keep = fa / sa
      crop.l = (1 - keep) / 2; crop.r = crop.l + keep
    end
  end
  if tex then tex:SetTexCoord(crop.l * u1, crop.r * u1, crop.t * v1, crop.b * v1) end
  return crop
end

--[[ Where a point painted at (fx, fy) -- fractions of the art, from its
     top-left -- lands in the frame after W.CoverTexture's crop: x right and
     y DOWN from the frame's top-left. And how many frame pixels one whole
     width / height of the art spans, for sizing things painted into it. ]]
function W.CoverPoint(crop, fx, fy)
  return (fx - crop.l) / (crop.r - crop.l) * crop.w, (fy - crop.t) / (crop.b - crop.t) * crop.h
end
function W.CoverSpan(crop)
  return crop.w / (crop.r - crop.l), crop.h / (crop.b - crop.t)
end

--[[ DIGITS RIDE HIGH IN A CENTRED LINE. A font string is centred by its line
     box, which keeps room below the baseline for descenders no digit has:
     Coustard's digits sit 4.5% of the font size above the middle (measured:
     ascent 103, descent 39, digit ink 0..75 per 100). A number placed by its
     centre on a gem is lowered by this much of its size. ]]
W.DIGIT_RISE = 0.045

--[[ A WIN-LOSS RECORD, colour coded: wins green, losses red. `onLight` is for
     dark ink on parchment (the main menu's record card), where the bright
     pair used on the dark board plates would wash out. `sep` sits between. ]]
W.RECORD_COLOURS = {
  dark  = { win = "ff7ee07e", loss = "ffff6b5b" },
  light = { win = "ff1f7a2c", loss = "ffa8231a" },
}
function W.RecordText(wins, losses, onLight, sep)
  local c = W.RECORD_COLOURS[onLight and "light" or "dark"]
  return ("|c%s%d W|r%s|c%s%d L|r"):format(c.win, wins or 0, sep or "  ", c.loss, losses or 0)
end

--[[ LETTERBOX BANDS for a picture drawn at its own shape inside a larger
     window. Next to each edge of the picture: a strip of the picture itself,
     MIRRORED at its own scale so the scenery carries on for a moment, a shade
     fading that strip out, and plain near-black beyond it -- Hearthstone's own
     letterbox. Stretching a sliver of the picture across the whole gap (what
     the pack room and main menu did) smeared its frame into streaks.
       bands = W.EdgeBands(parent, texturePath, sublevel)
       bands:Place(frameW, frameH, art, uv)
     `art` is the picture's rect {x, y, w, h}, from the frame's BOTTOM-left;
     `uv` = {l, r, t, b} the texcoords drawn in it. ]]
W.EDGE_MIRROR = 0.06     -- the mirrored strip, as a fraction of the picture's width or height
--[[ `opts.plainTop`: no mirrored strip above the picture, only the dark fill.
     The pack room's title plaque is painted into its top edge, and mirroring
     that strip put an upside-down "Open Packs" above the room. ]]
function W.EdgeBands(parent, path, sublevel, opts)
  sublevel = sublevel or 0
  local o = { parts = {}, plainTop = opts and opts.plainTop }
  for i = 1, 4 do     -- left, right, below, above
    local p = {}
    p.fill = parent:CreateTexture(nil, "BACKGROUND", nil, sublevel)
    p.fill:SetColorTexture(0.025, 0.02, 0.022, 1)
    p.band = parent:CreateTexture(nil, "BACKGROUND", nil, sublevel)
    p.band:SetTexture(path)
    p.shade = parent:CreateTexture(nil, "BACKGROUND", nil, sublevel + 1)
    p.shade:SetTexture(ART .. "page-shade.tga"); p.shade:SetVertexColor(0, 0, 0, 1)
    for _, r in pairs(p) do r:Hide() end
    o.parts[i] = p
  end
  local function put(r, x, y, w, h, parentFrame)
    if w < 1 or h < 1 then r:Hide(); return end
    r:ClearAllPoints(); r:SetPoint("BOTTOMLEFT", parentFrame, "BOTTOMLEFT", x, y)
    r:SetSize(w, h); r:Show()
  end
  function o:Place(fw, fh, art, uv)
    local ml, mr = art.x, fw - art.x - art.w
    local mb, mt = art.y, fh - art.y - art.h
    local du, dv = uv.r - uv.l, uv.b - uv.t
    local sw, sh = math.min(ml, mr, art.w * W.EDGE_MIRROR), math.min(mb, mt, art.h * W.EDGE_MIRROR)
    sw, sh = math.max(0, sw), math.max(0, sh)
    local su, sv = sw / art.w * du, sh / art.h * dv
    local L, R, B, T = self.parts[1], self.parts[2], self.parts[3], self.parts[4]
    -- left and right: page-shade.tga is dark at u=0
    put(L.fill, 0, art.y, ml - sw, art.h, parent)
    put(L.band, ml - sw, art.y, sw, art.h, parent); L.band:SetTexCoord(uv.l + su, uv.l, uv.t, uv.b)
    put(L.shade, ml - sw, art.y, sw, art.h, parent); L.shade:SetTexCoord(0, 0, 0, 1, 1, 0, 1, 1)
    put(R.fill, art.x + art.w + sw, art.y, mr - sw, art.h, parent)
    put(R.band, art.x + art.w, art.y, sw, art.h, parent); R.band:SetTexCoord(uv.r, uv.r - su, uv.t, uv.b)
    put(R.shade, art.x + art.w, art.y, sw, art.h, parent); R.shade:SetTexCoord(1, 0, 1, 1, 0, 0, 0, 1)
    -- below and above span the whole width (the picture fills it then)
    put(B.fill, 0, 0, fw, mb - sh, parent)
    put(B.band, art.x, mb - sh, art.w, sh, parent); B.band:SetTexCoord(uv.l, uv.r, uv.b, uv.b - sv)
    put(B.shade, art.x, mb - sh, art.w, sh, parent); B.shade:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)
    local th, tv = sh, sv
    if self.plainTop then th, tv = 0, 0 end
    put(T.fill, 0, art.y + art.h + th, fw, mt - th, parent)
    put(T.band, art.x, art.y + art.h, art.w, th, parent); T.band:SetTexCoord(uv.l, uv.r, uv.t + tv, uv.t)
    put(T.shade, art.x, art.y + art.h, art.w, th, parent); T.shade:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
  end
  function o:Hide()
    for _, p in ipairs(self.parts) do for _, r in pairs(p) do r:Hide() end end
  end
  function o:SetVertexColor(r, g, b, a)
    for _, p in ipairs(self.parts) do p.band:SetVertexColor(r, g, b, a) end
  end
  return o
end

-- A new label in a role.
function W.StyledText(parent, role, layer, frameH)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  W.ApplyStyle(fs, role, frameH)
  return fs
end

--[[ Re-apply every styled label under `root` at the window's new height.
     Labels with an explicit geometric size (ApplyStyle's `size`) are re-sized
     by their own layout code instead, and are skipped (styleFixed). ]]
function W.RestyleAll(root, frameH)
  frameH = frameH or (root.GetHeight and root:GetHeight()) or 720
  local function under(r)
    local p = r
    for _ = 1, 40 do
      if p == nil then return false end
      if p == root then return true end
      p = p.GetParent and p:GetParent() or nil
    end
    return false
  end
  for fs in pairs(styled) do
    if not rawget(fs, "styleFixed") and under(fs) then
      local c = rawget(fs, "styleColor")
      W.ApplyStyle(fs, rawget(fs, "styleRole"), frameH, nil, c)
    end
  end
end

--[[ FITTING TEXT TO ITS BOX -- WITHOUT AN ELLIPSIS, EVER.

     Hearthstone never truncates a card name or a label: long text is set
     smaller. WoW truncates with "..." the moment a string is wider than the
     width it was given, and -- the bug this replaces -- once a width or height
     has been SET, GetStringWidth/GetStringHeight report the CLIPPED size. So
     every "shrink while too big" loop that ran after SetWidth never shrank
     anything, and "Goldshire Footman" became "Goldshire Fo...".

     So: measure unconstrained first (GetUnboundedStringWidth for one line; a
     free height for wrapped text), step the size down to `min`, and only then
     apply the box. Returns the size used.

       o = { text, w, h, font, size, min, flags, lines (1 = single line) } ]]
local function unboundedWidth(fs)
  if fs.GetUnboundedStringWidth then return fs:GetUnboundedStringWidth() end
  return fs:GetStringWidth()
end
W.UnboundedWidth = unboundedWidth

function W.FitText(fs, o)
  local font, flags = o.font or FONT, o.flags or ""
  local size = math.max(1, math.floor(o.size or 12))
  local minSize = math.max(1, math.floor(o.min or math.min(size, 7)))
  local lines = o.lines or 1
  local w, h = math.max(1, o.w or 100), math.max(1, o.h or size * 1.3 * lines)
  fs:SetFont(font, size, flags)
  if o.text ~= nil then
    local was = rawget(fs, "fitting"); fs.fitting = true
    fs:SetText(o.text)
    fs.fitting = was
  end
  if lines <= 1 then
    fs:SetWordWrap(false)
    fs:SetWidth(0); fs:SetHeight(0)
    while size > minSize and (unboundedWidth(fs) > w or size * 1.05 > h) do
      size = size - 1
      fs:SetFont(font, size, flags)
    end
  else
    fs:SetWordWrap(true)
    if fs.SetMaxLines then fs:SetMaxLines(0) end
    fs:SetWidth(w); fs:SetHeight(0)
    local function tooBig()
      if fs:GetStringHeight() > h then return true end
      -- a single word wider than the box would be split or clipped
      for word in tostring(fs:GetText() or ""):gmatch("%S+") do
        if #word > 9 then
          local keep = fs:GetText()
          local was = rawget(fs, "fitting"); fs.fitting = true
          fs:SetText(word)
          local ww = unboundedWidth(fs)
          fs:SetText(keep)
          fs.fitting = was
          if ww > w then return true end
        end
      end
      return false
    end
    while size > minSize and tooBig() do
      size = size - 1
      fs:SetFont(font, size, flags)
    end
  end
  fs:SetSize(w, h)
  return size
end

--[[ A label that STAYS fitted: whenever its text or its box changes it is
     re-fitted, so a caller that sets the text later (most of the menus) cannot
     reintroduce the ellipsis. `o` is as for W.FitText, minus `text`; the box
     is updated with W.SetFitBox. ]]
local function refit(fs)
  local o = rawget(fs, "fitOpts")
  if not o or rawget(fs, "fitting") then return end
  fs.fitting = true
  W.FitText(fs, o)
  fs.fitting = false
end

function W.AutoFit(fs, o)
  fs.fitOpts = o
  if not rawget(fs, "fitWrapped") then
    fs.fitWrapped = true
    local set, setFont = fs.SetText, fs.SetFont
    fs.SetText = function(self, t)
      set(self, t)
      refit(self)
      return self
    end
    --[[ A caller choosing a font sets the size the label TRIES for; the fit
         may still set it smaller. The fitter's own SetFont calls (while
         `fitting`) must not overwrite that request. ]]
    fs.SetFont = function(self, font, size, flags)
      local ok = setFont(self, font, size, flags)
      local fo = rawget(self, "fitOpts")
      if fo and not rawget(self, "fitting") then
        fo.font, fo.size, fo.flags = font, size, flags
        fo.min = math.max(5, math.floor((size or 12) * 0.5))
        refit(self)
      end
      return ok
    end
    -- Likewise a caller sizing the label is sizing the BOX the text fits in.
    local setSize, setW, setH = fs.SetSize, fs.SetWidth, fs.SetHeight
    fs.SetSize = function(self, a, b)
      local fo = rawget(self, "fitOpts")
      if fo and not rawget(self, "fitting") then fo.w, fo.h = a, b; refit(self); return self end
      return setSize(self, a, b)
    end
    fs.SetWidth = function(self, a)
      local fo = rawget(self, "fitOpts")
      if fo and not rawget(self, "fitting") then fo.w = a; refit(self); return self end
      return setW(self, a)
    end
    fs.SetHeight = function(self, a)
      local fo = rawget(self, "fitOpts")
      if fo and not rawget(self, "fitting") then fo.h = a; refit(self); return self end
      return setH(self, a)
    end
  end
  refit(fs)
  return fs
end

function W.SetFitBox(fs, w, h, size)
  local o = rawget(fs, "fitOpts")
  if not o then return end
  o.w, o.h = w, h
  if size then o.size = size end
  refit(fs)
end
-- Fixed-size corners keep the carved frame crisp at any aspect ratio.
function W.SkinMenuPanel(frame, style)
  frame.panelStyle=style or "leather"
  frame.bg=frame:CreateTexture(nil,"BACKGROUND")
  frame.bg:SetAllPoints()
  frame.bg:SetTexture(ART .. (style=="paper" and "menu-parchment.tga" or "menu-leather.tga"))
  frame.borderPieces={}
  if style=="button" then
    --[[ THE PLAQUE IS A 3-SLICE. Stretched whole, a short button (Main Menu
         at 112x28) squashed the gilded end caps into slivers and a long one
         smeared them. Caps keep their proportions; only the stone middle
         stretches. Callers that re-skin the button with other art (page
         arrows, the round close button, the Play button) just SetTexture on
         `bg` as before: the caps follow bg's texture and visibility. ]]
    local bg=frame.bg
    frame.caps={frame:CreateTexture(nil,"BACKGROUND"),frame:CreateTexture(nil,"BACKGROUND")}
    for _,cap in ipairs(frame.caps) do cap:SetTexture(ART .. "tavern-button.tga") end
    local setTexture,hide,show,setShown,tint=bg.SetTexture,bg.Hide,bg.Show,bg.SetShown,bg.SetVertexColor
    bg.SetTexture=function(self,path,...)
      -- the plaque and its amber Play variant share one canvas and one 3-slice
      frame.threeSlice=(path==ART .. "tavern-button.tga" or path==ART .. "play-button.tga")
      if frame.threeSlice then for _,cap in ipairs(frame.caps) do cap:SetTexture(path) end end
      local r=setTexture(self,path,...)
      W.LayoutMenuPanel(frame)
      return r
    end
    local function caps(shown) for _,cap in ipairs(frame.caps) do cap:SetShown(shown and rawget(frame,"threeSlice") or false) end end
    bg.Hide=function(self) hide(self); frame.bgHidden=true; caps(false) end
    bg.Show=function(self) show(self); frame.bgHidden=nil; caps(true) end
    bg.SetShown=function(self,s) setShown(self,s); frame.bgHidden=(not s) or nil; caps(s) end
    bg.SetVertexColor=function(self,...) tint(self,...); for _,cap in ipairs(frame.caps) do cap:SetVertexColor(...) end end
    bg:SetTexture(ART .. "tavern-button.tga")
    return
  end
  for i=1,9 do
    local t=frame:CreateTexture(nil,"BORDER")
    t:SetTexture(ART .. (style=="button" and "menu-border.tga" or "menu-chest.tga"))
    frame.borderPieces[i]=t
  end
end

-- tavern-button.tga: the gilded caps end 230px in from each side of 1024,
-- and the plaque's body runs v .08-.92 of 256.
local CAP_U, PLAQUE_V0, PLAQUE_V1 = 230/1024, .08, .92
local CAP_ASPECT = (230/1024*1024) / ((PLAQUE_V1-PLAQUE_V0)*256)

function W.LayoutMenuPanel(frame)
  if rawget(frame,"caps") then
    local bg=frame.bg
    local w,h=frame:GetWidth(),frame:GetHeight()
    bg:ClearAllPoints()
    if rawget(frame,"threeSlice") then
      -- a short plaque (the corner's Main Menu) keeps room for its word
      local capW=math.min(h*CAP_ASPECT,w*.2)
      local l,r=frame.caps[1],frame.caps[2]
      l:ClearAllPoints(); l:SetPoint("TOPLEFT",frame,"TOPLEFT",0,0); l:SetSize(math.max(1,capW),math.max(1,h))
      r:ClearAllPoints(); r:SetPoint("TOPRIGHT",frame,"TOPRIGHT",0,0); r:SetSize(math.max(1,capW),math.max(1,h))
      l:SetTexCoord(0,CAP_U,PLAQUE_V0,PLAQUE_V1); r:SetTexCoord(1-CAP_U,1,PLAQUE_V0,PLAQUE_V1)
      bg:SetPoint("TOPLEFT",frame,"TOPLEFT",capW,0); bg:SetSize(math.max(1,w-capW*2),math.max(1,h))
      bg:SetTexCoord(CAP_U,1-CAP_U,PLAQUE_V0,PLAQUE_V1)
      for _,cap in ipairs(frame.caps) do cap:SetShown(not rawget(frame,"bgHidden")) end
    else
      bg:SetAllPoints()
      for _,cap in ipairs(frame.caps) do cap:Hide() end
    end
    return
  end
  if not frame.borderPieces then return end
  local w,h=frame:GetWidth(),frame:GetHeight()
  local edge=math.min(rawget(frame,"panelEdge") or 18,w/3,h/3)
  local xs,ys={0,edge,w-edge,w},{0,edge,h-edge,h}
  local us,vs={0,.075,.925,1},{0,.18,.82,1}
  if frame.panelStyle~="button" then
    -- Only the chest's carved perimeter; baked labels and shop art are excluded.
    us={160/950,222/950,717/950,780/950}
    vs={15/594,76/594,414/594,475/594}
  end
  for row=1,3 do for col=1,3 do
    local t=frame.borderPieces[(row-1)*3+col]
    t:ClearAllPoints(); t:SetPoint("TOPLEFT",frame,"TOPLEFT",xs[col],-ys[row])
    t:SetSize(math.max(1,xs[col+1]-xs[col]),math.max(1,ys[row+1]-ys[row]))
    t:SetTexCoord(us[col],us[col+1],vs[row],vs[row+1])
    if frame.panelStyle=="button" or (row==2 and col==2) then t:Hide() else t:Show() end
  end end
end

--[[ THE STONE FACE a plaque's word has to fit on: its width less the gilded
     end caps, and the height between its gold rims. The label was fitted to
     `w - 20`, which is wider than the stone on any plaque whose caps are wider
     than 10px -- so in a tall window, where the style asks for its largest
     size, "Main Menu" and "Choose Deck" ran out over the gold. ]]
function W.MenuFaceBox(w, h)
  local capW = math.min(h * CAP_ASPECT, w * .2)
  return math.max(1, w - 2 * capW * .8), math.max(1, h * .64)
end

--[[ Deck boxes on a page (My Decks, Practice): as many rows as keep the boxes
     large, filled from the top-left. Returns rows, cols, box w, box h.
     A box is .78 as wide as it is tall; `capH` stops a tall window drawing a
     single box the size of the page. More rows win while their boxes are at
     least 85% the size of the largest possible -- so a page holds more decks
     when that costs little, and one row when a wide, short window has room
     for nothing else. ]]
function W.DeckGrid(innerW, innerH, gap, capH, maxRows)
  local best = 0
  local options = {}
  for rows = 1, maxRows or 4 do
    for cols = 1, 10 do
      local bh = math.min((innerH - (rows - 1) * gap) / rows,
                          ((innerW - (cols - 1) * gap) / cols) / .78, capH)
      if bh > 0 then
        options[#options + 1] = { rows = rows, cols = cols, bw = bh * .78, bh = bh }
        if bh > best then best = bh end
      end
    end
  end
  local pick
  for _, o in ipairs(options) do
    if o.bh >= best * .85 and (not pick or o.rows * o.cols > pick.rows * pick.cols
        or (o.rows * o.cols == pick.rows * pick.cols and o.bh > pick.bh)) then
      pick = o
    end
  end
  return pick.rows, pick.cols, pick.bw, pick.bh
end

function W.MenuPanel(parent,style)
  local f=CreateFrame("Frame",nil,parent)
  W.SkinMenuPanel(f,style)
  f:SetScript("OnSizeChanged",function() W.LayoutMenuPanel(f) end)
  return f
end
-- Shared carved plaque and resize affordance across the out-of-match screens.
function W.MenuButton(parent, label, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:EnableMouse(true); b:RegisterForClicks("LeftButtonUp")
  W.SkinMenuPanel(b,"button")
  b.panelEdge=6
  b.text = b:CreateFontString(nil, "OVERLAY")
  b.text:SetPoint("CENTER")
  b.text:SetWordWrap(false)
  W.AutoFit(b.text, { w = 80, h = 20, font = FONT, size = 13, min = 7 })
  W.ApplyStyle(b.text, "button")
  b.text:SetText(label or "")
  b:SetScript("OnSizeChanged",function(_,w,h)
    W.LayoutMenuPanel(b)
    local o = rawget(b.text, "fitOpts")
    local fw, fh = W.MenuFaceBox(w, h)
    if o then W.SetFitBox(b.text, fw, fh)
    else b.text:SetSize(fw, fh) end
  end)
  b.label = b.text
  local function feedback(hovered, pressed)
    b.bg:SetVertexColor(pressed and .72 or 1, hovered and .94 or 1, hovered and .78 or 1, 1)
    for _,piece in ipairs(b.borderPieces) do
      piece:SetVertexColor(1, hovered and .88 or 1, hovered and .55 or 1, 1)
    end
    -- Plaques carry dark lettering; buttons drawn over art set textColor.
    local c = rawget(b, "textColor") or (rawget(b, "playStyle") and W.Style.playButton.color) or W.Colors.button
    b.text:SetTextColor(c[1], c[2], c[3])
    b.text.styleColor = c   -- a window resize re-styles the label in this colour
  end
  function b:SetEnabledLook(enabled)
    self.enabled = enabled
    self:SetAlpha(enabled and 1 or 0.45)
    feedback(false,false)
  end
  b:SetEnabledLook(true)
  b:SetScript("OnClick", function(...)
    if b.enabled then
      if ns.Sounds then ns.Sounds.Play("menu_click") end
      return onClick(...)
    end
    -- a greyed button may still say why it cannot be pressed
    local why = rawget(b, "onDisabledClick")
    if why then return why(...) end
  end)
  b:SetScript("OnEnter", function()
    if b.enabled then
      feedback(true,false)
      if ns.Sounds then ns.Sounds.PlayMenuHover() end
    end
  end)
  b:SetScript("OnLeave", function() feedback(false,false) end)
  b:SetScript("OnMouseDown", function() if b.enabled then feedback(true,true) end end)
  b:SetScript("OnMouseUp", function() feedback(false,false) end)
  b:SetScript("OnHide", function() feedback(false,false) end)
  return b
end

--[[ HEARTHSTONE'S GOLD RIM, at any aspect. menu-border.tga is a thin gilded
     frame; drawn as eight fixed-size pieces (no centre) it stays crisp around a
     tall deck box or a wide banner alike, where a stretched copy would thicken
     two of its sides. Returns a handle whose Layout follows the host's size. ]]
--[[ CARD TEXT WITHOUT ITS MARKUP, for anywhere that shows it as one plain
     string (tooltips, history, search). The printed text keeps Hearthstone's
     <b> around its keywords for the card face (W.RichText). ]]
function W.PlainText(text)
  return ((text or ""):gsub("<[^>]+>", ""))
end

--[[ RICH TEXT: RULES TEXT WITH ITS KEYWORDS IN BOLD, AS HEARTHSTONE SETS IT.

     A WoW FontString has one font, so "Battlecry: Deal 2 damage" cannot be
     half bold. The text is split into words, each word into runs of regular
     and bold (a keyword can end in plain punctuation: "<b>Taunt</b>."), and
     every run is its own FontString, laid out here: lines wrapped greedily to
     the box, each centred, the block centred down the box -- the size stepped
     down until it all fits, exactly as W.FitText does for plain text.

       rt = W.RichText(parentFrame, anchorRegion)
       rt:Set(text, { w, h, size, min, color = {r,g,b,a}, at = {region, x, y} })
     `at` is the box's TOP-CENTRE, as an offset from `region`'s CENTER (the
     card's own frame); without it the runs hang from `anchorRegion`'s
     TOPLEFT. rt:SetShown / Show / Hide follow the region they stand in for.

     Every run is given its SIZE (its measured width, a little spare, one
     line's height). Left to size itself from its text, a pooled FontString
     reused for a longer word could keep the old, narrower width in the
     client, and the word was clipped or dropped: "thi turn only", "Deal 1
     damage to enemy minions". And the runs are placed from the card frame,
     not from the hidden body FontString, whose own box the client is free to
     settle differently.

     A LEANING CARD (a fanned hand) is turned by a Rotation animation, and the
     live client turns each small region about its OWN centre, not the card's
     (the cost digits work round the same thing, see GLYPH_INK). So every word
     was tilted where it stood on an upright card: a staircase of words sliding
     off the card, onto or under its neighbours. The runs are therefore
     anchored by their CENTRES, and rt:SetRotation(rot) puts each centre where
     it falls on the turned card; the client then tilts each word in place and
     together they read as one turned text. ]]
local function richWords(text)
  local words, cur = {}, nil
  local bold, pos = false, 1
  text = tostring(text or "")
  local function add(seg)
    for c in seg:gmatch(".") do
      if c == " " then cur = nil
      else
        if not cur then cur = { pieces = {} }; words[#words + 1] = cur end
        local last = cur.pieces[#cur.pieces]
        if last and last.bold == bold then last.text = last.text .. c
        else cur.pieces[#cur.pieces + 1] = { text = c, bold = bold } end
      end
    end
  end
  while pos <= #text do
    local a, b, close = text:find("<(/?)b>", pos)
    if not a then add(text:sub(pos)); break end
    add(text:sub(pos, a - 1))
    bold = close == ""
    pos = b + 1
  end
  -- any other tag is dropped
  for _, w in ipairs(words) do
    for _, piece in ipairs(w.pieces) do piece.text = piece.text:gsub("<[^>]+>", "") end
  end
  return words
end
W.RichWords = richWords

function W.RichText(parent, anchor)
  local rt = { parent = parent, anchor = anchor, pool = {}, used = 0, shown = true,
                centres = {}, rot = 0 }
  rt.measure = parent:CreateFontString(nil, "OVERLAY")
  rt.measure:Hide()
  local function width(text, font, size)
    rt.measure:SetFont(font, size, "")
    rt.measure:SetWidth(0); rt.measure:SetHeight(0)
    rt.measure:SetText(text)
    return unboundedWidth(rt.measure)
  end
  -- `force`: at the smallest size a word wider than the box sits on a line of
  -- its own (and overflows) rather than the whole text becoming one line
  local function layout(words, size, maxW, force)
    local space = math.max(1, width("a a", BODY_FONT, size) - width("aa", BODY_FONT, size))
    local lines, line, lineW = {}, {}, 0
    for _, word in ipairs(words) do
      local ww = 0
      for _, piece in ipairs(word.pieces) do
        piece.w = width(piece.text, piece.bold and BOLD_FONT or BODY_FONT, size)
        if piece.w <= 0 and piece.text ~= "" then rt.unmeasured = true end
        ww = ww + piece.w
      end
      word.w = ww
      if ww > maxW and not force then return nil end  -- one word will not fit at this size
      local need = (#line > 0 and space or 0) + ww
      if #line > 0 and lineW + need > maxW then
        lines[#lines + 1] = { words = line, w = lineW }
        line, lineW = { word }, ww
      else
        line[#line + 1] = word; lineW = lineW + need
      end
    end
    if #line > 0 then lines[#lines + 1] = { words = line, w = lineW } end
    return lines, space
  end
  function rt:Set(text, o)
    self.text, self.opts = text, o
    for i = 1, self.used do self.pool[i]:Hide() end
    self.used = 0
    local words = richWords(text)
    if #words == 0 then return end
    local size = math.max(1, math.floor(o.size or 12))
    local minSize = math.max(1, math.floor(o.min or math.min(size, 5)))
    local lines, space
    self.unmeasured = nil
    while true do
      lines, space = layout(words, size, o.w)
      if lines and #lines * size * 1.2 <= o.h then break end
      if size <= minSize then lines, space = layout(words, size, o.w, true); break end
      size = size - 1
    end
    --[[ A font the client has not finished loading measures 0 wide. Lay the
         text out again shortly, once it has (a few tries, then give up). ]]
    if self.unmeasured and (self.retries or 0) < 5 and C_Timer and C_Timer.After then
      self.retries = (self.retries or 0) + 1
      C_Timer.After(0.2, function() if self.text == text and self.opts == o then self:Set(text, o) end end)
    elseif not self.unmeasured then
      self.retries = nil
    end
    self.size = size
    local lineH = size * 1.2
    local top = math.max(0, (o.h - #lines * lineH) / 2)
    local c = o.color or { 1, 1, 1, 1 }
    for li, line in ipairs(lines) do
      local x = math.max(0, (o.w - line.w) / 2)
      local y = top + (li - 1) * lineH
      for wi, word in ipairs(line.words) do
        if wi > 1 then x = x + space end
        for _, piece in ipairs(word.pieces) do
          self.used = self.used + 1
          local fs = self.pool[self.used]
          if not fs then
            fs = self.parent:CreateFontString(nil, "OVERLAY")
            fs:SetWordWrap(false)
            fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")   -- placed by its top-left corner
            self.pool[self.used] = fs
          end
          fs:SetFont(piece.bold and BOLD_FONT or BODY_FONT, size, "")
          fs:SetText(piece.text)
          fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
          -- its own size, with spare so a measuring rounding never clips it
          local fw = math.max(1, piece.w) + math.ceil(size * 0.35)
          fs:SetSize(fw, lineH)
          fs:ClearAllPoints()
          local at = o.at
          if at then
            -- its centre on the upright card; SetRotation turns it with the card
            self.centres[self.used] = { at[1], at[2] - o.w / 2 + x + fw / 2, at[3] - y - lineH / 2 }
          else
            self.centres[self.used] = nil
            fs:SetPoint("TOPLEFT", self.anchor, "TOPLEFT", x, -y)
          end
          fs:SetShown(self.shown)
          x = x + piece.w
        end
      end
    end
    self:SetRotation(self.rot)
  end
  -- place every run's centre where it falls on the card turned by `rot`
  function rt:SetRotation(rot)
    self.rot = rot or 0
    local c, s = math.cos(self.rot), math.sin(self.rot)
    for i = 1, self.used do
      local p = self.centres[i]
      if p then
        local fs = self.pool[i]
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", p[1], "CENTER", p[2] * c - p[3] * s, p[2] * s + p[3] * c)
      end
    end
  end
  function rt:SetShown(shown)
    self.shown = shown and true or false
    for i = 1, self.used do self.pool[i]:SetShown(self.shown) end
  end
  -- the runs actually on screen, in reading order (tests read the words back)
  function rt:Runs()
    local out = {}
    for i = 1, self.used do out[i] = self.pool[i] end
    return out
  end
  return rt
end

function W.GoldFrame(host, edge, layer)
  local g = { pieces = {}, edge = edge or 10, host = host }
  for i=1,9 do
    if i~=5 then
      local t=host:CreateTexture(nil,layer or "OVERLAY")
      t:SetTexture(ART .. "menu-border.tga")
      g.pieces[#g.pieces+1]={t,i}
    end
  end
  function g:Layout(w,h)
    w,h=w or host:GetWidth(),h or host:GetHeight()
    local e=math.min(self.edge,w/3,h/3)
    local xs,ys={0,e,w-e,w},{0,e,h-e,h}
    local us,vs={0,.07,.93,1},{0,.17,.83,1}
    for _,p in ipairs(self.pieces) do
      local t,i=p[1],p[2]; local row,col=math.floor((i-1)/3)+1,(i-1)%3+1
      t:ClearAllPoints(); t:SetPoint("TOPLEFT",host,"TOPLEFT",xs[col],-ys[row])
      t:SetSize(math.max(1,xs[col+1]-xs[col]),math.max(1,ys[row+1]-ys[row]))
      t:SetTexCoord(us[col],us[col+1],vs[row],vs[row+1])
    end
  end
  function g:SetShown(shown) for _,p in ipairs(self.pieces) do p[1]:SetShown(shown) end end
  function g:SetVertexColor(r,gg,b,a) for _,p in ipairs(self.pieces) do p[1]:SetVertexColor(r,gg,b,a or 1) end end
  return g
end

--[[ HEARTHSTONE'S TOOLTIP PANEL: warm parchment in a dark bevelled rim with a
     gold hairline (hs-tooltip.tga, tools/build_hs_ui.py), drawn as a 9-slice
     so it stays crisp at any size. Returns a Frame; `f.title` and `f.text`
     are ready-made labels, dark brown on parchment as in Hearthstone's
     keyword boxes. ]]
function W.HSPanel(parent, edge)
  local f = CreateFrame("Frame", nil, parent)
  f.pieces = {}
  for i = 1, 9 do
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetTexture(ART .. "hs-tooltip.tga")
    f.pieces[i] = t
  end
  f.edge = edge or 16
  f.title = W.StyledText(f, "tooltipTitle")
  f.title:SetJustifyH("CENTER")
  f.text = W.StyledText(f, "tooltipBody")
  f.text:SetJustifyH("CENTER")
  f.text:SetWordWrap(true)
  local function layout(w, h)
    local e = math.min(f.edge, w / 2, h / 2)
    local xs, ys = {0, e, w - e, w}, {0, e, h - e, h}
    local c = 24 / 128
    local us, vs = {0, c, 1 - c, 1}, {0, c, 1 - c, 1}
    for row = 1, 3 do for col = 1, 3 do
      local t = f.pieces[(row - 1) * 3 + col]
      t:ClearAllPoints(); t:SetPoint("TOPLEFT", f, "TOPLEFT", xs[col], -ys[row])
      t:SetSize(math.max(1, xs[col + 1] - xs[col]), math.max(1, ys[row + 1] - ys[row]))
      t:SetTexCoord(us[col], us[col + 1], vs[row], vs[row + 1])
    end end
  end
  f:SetScript("OnSizeChanged", function(_, w, h) layout(w, h) end)
  --[[ Fill the panel with a title and/or body at width `w`; it sizes itself
       to the text, plus `extra` pixels below it for rows the caller lays out
       itself. ]]
  function f:SetContent(title, body, w, extra)
    w = math.max(80, w or 220)
    local pad = 14
    local y = -pad
    self.title:ClearAllPoints(); self.text:ClearAllPoints()
    if title and title ~= "" then
      self.title:SetWidth(w - pad * 2); self.title:SetText(title)
      self.title:SetPoint("TOP", self, "TOP", 0, y)
      self.title:Show()
      y = y - self.title:GetStringHeight() - 4
    else
      self.title:SetText(""); self.title:Hide()
    end
    if body and body ~= "" then
      self.text:SetWidth(w - pad * 2); self.text:SetHeight(0); self.text:SetText(body)
      self.text:SetPoint("TOP", self, "TOP", 0, y)
      self.text:Show()
      y = y - self.text:GetStringHeight()
    else
      self.text:SetText(""); self.text:Hide()
    end
    y = y - (extra or 0)
    self:SetSize(w, -y + pad)
    layout(w, -y + pad)
  end
  return f
end

--[[ A CONFIRMATION: the window dims, a carved leather panel holds the message
     in the `dialog` style, and two plaques answer it. The disenchant and the
     leave-duel dialogs were built separately and had drifted apart in face,
     size and spacing; both are this now.
       d = W.Dialog(parent, globalName, {{label, onClick}, {label, onClick}})
       d.message:SetText(...); d:Show() ]]
function W.Dialog(parent, name, buttons, o)
  o = o or {}
  local d = CreateFrame("Button", name, parent)
  d:SetAllPoints(); d:EnableMouse(true); d:SetFrameLevel(o.level or 600)
  d.dim = d:CreateTexture(nil, "BACKGROUND"); d.dim:SetAllPoints(); d.dim:SetColorTexture(0, 0, 0, .78)
  local pw, ph = o.w or 440, o.h or 210
  -- o.paper: Hearthstone's own parchment popup, dark ink on tan (docs/39)
  local panel = W.MenuPanel(d, o.paper and "paper" or "leather"); panel:SetSize(pw, ph); panel:SetPoint("CENTER")
  panel:SetFrameLevel(d:GetFrameLevel() + 1)
  d.panel = panel
  d.message = W.StyledText(panel, "dialog")
  d.message:SetSize(pw - 60, ph - 98); d.message:SetPoint("TOP", panel, "TOP", 0, -24)
  d.message:SetJustifyH("CENTER"); d.message:SetJustifyV("MIDDLE"); d.message:SetWordWrap(true)
  -- ink on parchment: the same dialog role, dark instead of light
  if o.paper then W.ApplyStyle(d.message, "dialog", nil, nil, C.inkBody) end
  d.buttons = {}
  local n = #buttons
  for i, spec in ipairs(buttons) do
    local b = W.MenuButton(panel, spec[1], spec[2])
    b:SetFrameLevel(d:GetFrameLevel() + 10); b:SetSize(172, 40)
    b:SetPoint("BOTTOM", panel, "BOTTOM", (i - (n + 1) / 2) * 188, 24)
    d.buttons[i] = b
  end
  if name and UISpecialFrames then table.insert(UISpecialFrames, name) end
  return d
end

--[[ A SCREEN'S TITLE PLAQUE: the riveted stone plaque from Hearthstone's Open
     Packs room (tools/build_title_plaque.py), as a 3-slice, with the title in
     white on it -- so Practice, My Decks and the collection name themselves
     the way the pack room already did, instead of each floating its title in
     a different place. p:Place(x, y, h, text) centres it on (x, y) (from the
     parent's top-left, y down), `h` tall, as wide as the title needs. ]]
--[[ Any horizontal 3-slice: caps keep their aspect, the middle stretches.
     u = {left, capEnd, midEnd, right} across the file, v = {top, bottom}.
     s:Layout(w, h) fills the host (or s:Layout(w, h, anchorRegion)). ]]
function W.ThreeSlice(host, file, u, v, capAspect, layer, sub)
  local s = { pieces = {} }
  for i = 1, 3 do
    local t = host:CreateTexture(nil, layer or "BACKGROUND", nil, sub)
    t:SetTexture(file)
    t:SetTexCoord(u[i], u[i + 1], v[1], v[2])
    s.pieces[i] = t
  end
  function s:Layout(w, h, at)
    at = at or host
    local cap = math.min(h * capAspect, w / 2)
    local l, m, r = self.pieces[1], self.pieces[2], self.pieces[3]
    l:ClearAllPoints(); l:SetPoint("TOPLEFT", at, "TOPLEFT"); l:SetSize(math.max(1, cap), math.max(1, h))
    r:ClearAllPoints(); r:SetPoint("TOPLEFT", at, "TOPLEFT", w - cap, 0); r:SetSize(math.max(1, cap), math.max(1, h))
    m:ClearAllPoints(); m:SetPoint("TOPLEFT", at, "TOPLEFT", cap, 0); m:SetSize(math.max(1, w - cap * 2), math.max(1, h))
  end
  function s:SetShown(shown) for _, t in ipairs(self.pieces) do t:SetShown(shown) end end
  function s:SetVertexColor(...) for _, t in ipairs(self.pieces) do t:SetVertexColor(...) end end
  return s
end

-- hs-nameplate.tga: the dark, gold-rimmed strip a hero's name sits on.
function W.NamePlate(host, layer, sub)
  return W.ThreeSlice(host, ART .. "hs-nameplate.tga", { 0, 20/256, 236/256, 1 }, { 0, 1 }, 20/64, layer, sub)
end

local PLAQUE_U = { 0, .296875, .453125, .75 }
local PLAQUE_V1 = .859375
local PLAQUE_CAP = 1.3818   -- cap width / plaque height

function W.TitlePlaque(parent)
  local p = CreateFrame("Frame", nil, parent)
  p.pieces = {}
  for i = 1, 3 do
    local t = p:CreateTexture(nil, "ARTWORK")
    t:SetTexture(ART .. "title-plaque.tga")
    t:SetTexCoord(PLAQUE_U[i], PLAQUE_U[i + 1], 0, PLAQUE_V1)
    p.pieces[i] = t
  end
  p.text = W.StyledText(p, "plaqueTitle")
  p.text:SetPoint("CENTER", p, "CENTER", 0, 1)
  p.text:SetWordWrap(false)
  function p:Place(x, y, h, text, frameH)
    if text then self.text:SetText(text) end
    W.ApplyStyle(self.text, "plaqueTitle", nil, math.floor(h * .46))
    local cap = h * PLAQUE_CAP
    local tw = unboundedWidth(self.text)
    local w = math.max(cap * 2 + h * 1.2, tw + cap * 1.3)
    self:ClearAllPoints(); self:SetSize(w, h)
    self:SetPoint("CENTER", parent, "TOPLEFT", x, -y)
    local l, m, r = self.pieces[1], self.pieces[2], self.pieces[3]
    l:ClearAllPoints(); l:SetPoint("TOPLEFT", self, "TOPLEFT"); l:SetSize(cap, h)
    r:ClearAllPoints(); r:SetPoint("TOPRIGHT", self, "TOPRIGHT"); r:SetSize(cap, h)
    m:ClearAllPoints(); m:SetPoint("TOPLEFT", self, "TOPLEFT", cap, 0)
    m:SetSize(math.max(1, w - cap * 2), h)
    self.text:SetSize(w - cap * 1.1, h * .8)
  end
  return p
end

--[[ The dark tray Hearthstone keeps its controls in: deep brown (darkened parchment) inside
     a gold rim. Used for the collection's bottom bar and the deck list. ]]
function W.TrayPanel(parent)
  local f=CreateFrame("Frame",nil,parent)
  f.bg=f:CreateTexture(nil,"BACKGROUND"); f.bg:SetAllPoints()
  f.bg:SetTexture(ART .. "menu-parchment.tga"); f.bg:SetVertexColor(.30,.19,.11,1)
  f.rim=W.GoldFrame(f,9,"BORDER")
  f:SetScript("OnSizeChanged",function(_,w,h) f.rim:Layout(w,h) end)
  return f
end

--[[ Hearthstone's big amber Play button: the same carved plaque as every
     other button, its stone face lit amber (tools/build_play_button.py). A
     MenuButton underneath, so it keeps the shared hover, press, sound and
     enabled behaviour, and its 3-slice. ]]
function W.StylePlayButton(b, size)
  b.bg:SetTexture(ART .. "play-button.tga")
  W.ApplyStyle(b.text, "playButton", nil, size)
  b.playStyle=true
  return b
end

--[[ A DECK BOX: the hero's portrait in a gold rim with the deck's name on a
     dark banner across the bottom -- how Hearthstone shows a saved deck on its
     Play and collection screens. Applied to an existing MenuButton so clicks,
     sounds and pooling are unchanged; W.ClearDeckBox undoes it when the button
     is recycled as something else.

     o = { portrait = texture, name = "", detail = "", detailColor = {r,g,b},
           selected = bool } ]]
--[[ A DECK'S FACE. Every deck box showed its class hero, so a shelf of one
     class's decks was a row of identical portraits (the in-client tour,
     docs/39). A deck shows its signature card instead -- the rarest, then the
     costliest, as a player would pick one to stand for it. A deck of only
     Basic cards, or an empty one, has nothing to tell it apart: its hero.
     Returns the card id to draw. ]]
local RARITY_RANK = { FREE = 0, COMMON = 1, RARE = 2, EPIC = 3, LEGENDARY = 4 }
--[[ The card a deck box shows when its owner has not chosen one. In order:
     a card of the deck's own class (what makes it THAT deck, not a pile of
     neutrals any class could run), then the rarest, then a minion -- its art
     is a character, a spell's is often an effect -- then the costliest. ]]
function W.DeckSignature(deck)
  local best, bestKey
  for _, id in ipairs(deck and deck.cards or {}) do
    local p = ns.PrintedCards[id]
    -- Basic (set CORE) never stands for a deck, whatever its rarity says:
    -- some Basic cards, Flamestrike among them, are printed COMMON
    local rank = p and p.set ~= "CORE" and RARITY_RANK[p.rarity or "FREE"] or 0
    if rank > 0 then
      local key = { p.class ~= "NEUTRAL" and 1 or 0, rank, p.type == "MINION" and 1 or 0, p.cost or 0 }
      local better = not best
      if not better then
        for i = 1, #key do
          if key[i] ~= bestKey[i] then better = key[i] > bestKey[i]; break end
          if i == #key then better = id < best end   -- a stable tie-break
        end
      end
      if better then best, bestKey = id, key end
    end
  end
  return best or ns.HERO_ID_BY_CLASS[deck and deck.class or "MAGE"] or ns.HERO_ID_BY_CLASS.MAGE
end

--- The card a deck box shows: the one its owner chose while it is still in
--- the deck, otherwise DeckSignature's pick.
function W.DeckArtCard(deck)
  local chosen = deck and deck.art
  if chosen then
    for _, id in ipairs(deck.cards or {}) do if id == chosen then return chosen end end
  end
  return W.DeckSignature(deck)
end

function W.StyleDeckBox(b, o)
  local d = rawget(b, "deckBox")
  if not d then
    d = {}
    b.deckBox = d
    d.glow = b:CreateTexture(nil, "BACKGROUND", nil, -2)
    d.glow:SetTexture(ART .. "crest-glow.tga"); d.glow:SetBlendMode("ADD")
    d.glow:SetVertexColor(1, .78, .3, .9)
    d.portrait = b:CreateTexture(nil, "BACKGROUND", nil, 2)
    d.plate = b:CreateTexture(nil, "BORDER")
    d.plate:SetColorTexture(.06, .035, .02, .86)
    d.rim = W.GoldFrame(b, 10, "ARTWORK")
    d.detail = W.StyledText(b, "body")
    d.detail:SetWordWrap(false)
  end
  local w, h = b:GetWidth(), b:GetHeight()
  b.bg:Hide()
  d.portrait:ClearAllPoints(); d.portrait:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -4)
  d.portrait:SetSize(math.max(1, w - 8), math.max(1, h - 8))
  d.portrait:SetTexture(o.portrait)
  -- Square art cropped to the box: keep the middle across, the top down,
  -- because that is where Hearthstone's hero faces are painted.
  local a = (w - 8) / math.max(1, h - 8)
  if a < 1 then d.portrait:SetTexCoord((1 - a) / 2, (1 + a) / 2, 0, 1)
  else d.portrait:SetTexCoord(0, 1, .08, math.min(1, .08 + 1 / a)) end
  local plateH = math.max(34, h * .30)
  d.plate:ClearAllPoints(); d.plate:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 4, 4)
  d.plate:SetSize(math.max(1, w - 8), plateH)
  d.glow:ClearAllPoints(); d.glow:SetPoint("TOPLEFT", b, "TOPLEFT", -w * .18, h * .14)
  d.glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", w * .18, -h * .14)
  d.rim:Layout(w, h)
  b.textColor = W.Colors.cream
  b.text:ClearAllPoints(); b.text:SetPoint("BOTTOM", b, "BOTTOM", 0, 4 + plateH * .40)
  -- Long deck names wrap to a second line and shrink, never spill or "...".
  local nameSize = math.max(12, math.min(16, w / 11))
  W.AutoFit(b.text, { w = math.max(1, w - 16), h = plateH * .58, font = FONT,
                      size = nameSize, min = 8, flags = "OUTLINE", lines = 2 })
  W.ApplyStyle(b.text, "label", nil, nameSize, W.Colors.cream)
  b.text:SetJustifyH("CENTER")
  b.text:SetText(o.name or "")
  d.detail:ClearAllPoints(); d.detail:SetPoint("BOTTOM", b, "BOTTOM", 0, 7)
  local c = o.detailColor or W.Colors.count
  W.ApplyStyle(d.detail, "body", nil, 12, c)
  W.FitText(d.detail, { text = o.detail or "", w = math.max(1, w - 16), h = plateH * .36,
                        font = BODY_FONT, size = 12, min = 7, flags = "" })
  for _, r in ipairs({ d.portrait, d.plate, d.detail }) do r:Show() end
  d.rim:SetShown(true)
  d.rim:SetVertexColor(1, o.selected and 1 or .9, o.selected and .75 or .8)
  d.glow:SetShown(o.selected == true)
end

function W.ClearDeckBox(b)
  local d = rawget(b, "deckBox")
  b.textColor = nil
  local fo = rawget(b.text, "fitOpts")
  if fo then fo.lines = 1; fo.flags = "" end
  W.ApplyStyle(b.text, "button")
  if not d then return end
  for _, r in ipairs({ d.glow, d.portrait, d.plate, d.detail }) do r:Hide() end
  d.rim:SetShown(false)
  b.bg:Show()
end

--[[ THE RESIZE GRIP, shared by every window (hub, collection, packs, board).

     Two things made it jump. The windows are anchored by their CENTRE, and
     sizing a centre-anchored frame from one corner moves the other corners
     too; so the frame is re-anchored by its top-left corner, at exactly where
     it already is, before sizing starts. And the old grip sat 3px in from a
     32px hit box, so the corner snapped to the cursor from up to 35px away;
     this one is flush in the corner and small. The art is one texture (three
     gilded ridges), not rotated lines that pivot about their own centres. ]]
--[[ THE SPEAKER: a round gilded button that mutes everything this addon
     plays, with the volume slider dropping from it on hover. The board, the
     main menu and the collection each carry one, top right, and they are one
     setting: toggling any refreshes them all. `onToggle` is Main:ToggleMute
     (which also stops the music); without it the flag is flipped directly. ]]
local speakers, musicButtons = {}, {}
local function musicOn()
  local db = rawget(_G, "ForeverHearthstoneDB")
  return not (type(db) == "table" and db.music == false)
end
function W.RefreshSpeakers()
  for _, b in ipairs(speakers) do
    b.icon:SetTexture(ART .. (ns.Sounds.Muted() and "mute-off.tga" or "mute-on.tga"))
  end
  for _, b in ipairs(musicButtons) do
    b.icon:SetTexture(ART .. (musicOn() and "music-on.tga" or "music-off.tga"))
  end
end

--[[ THE MUSIC BUTTON: the speaker's twin (a gilded round button, two beamed
     notes; a red cross when off) that turns ONLY the music off or on --
     effects, voices and the rope keep playing. The same setting as `/fh
     music` (Main:ToggleMusic, saved), shown the same on every screen. Off, the
     zone's own music comes back. ]]
function W.MusicButton(parent, onToggle)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(30, 30)
  b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
  b.bg:SetTexture(ART .. "hs-round.tga")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("CENTER"); b.icon:SetSize(18, 18)
  b:SetScript("OnClick", function()
    if ns.Sounds then ns.Sounds.Play("menu_click") end
    if onToggle then onToggle()
    elseif ns.Main and ns.Main.ToggleMusic then ns.Main:ToggleMusic()
    else
      local db = rawget(_G, "ForeverHearthstoneDB")
      if type(db) == "table" then db.music = not musicOn() end
    end
    W.RefreshSpeakers()
  end)
  b:SetScript("OnEnter", function()
    b.icon:SetVertexColor(1, .92, .7)
    -- the same parchment panel as every other hint, not WoW's GameTooltip
    if not rawget(b, "tip") then
      b.tip = W.HSPanel(b, 12)
      if b.tip.SetFrameStrata then b.tip:SetFrameStrata("TOOLTIP") end
    end
    b.tip:SetContent(musicOn() and "Music on" or "Music off",
      "Click to turn the music " .. (musicOn() and "off" or "on") .. ".", 190)
    b.tip:ClearAllPoints(); b.tip:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 0, -6)
    b.tip:Show()
  end)
  b:SetScript("OnLeave", function()
    b.icon:SetVertexColor(1, 1, 1)
    if rawget(b, "tip") then b.tip:Hide() end
  end)
  musicButtons[#musicButtons + 1] = b
  W.RefreshSpeakers()
  return b
end
function W.SpeakerButton(parent, onToggle)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(30, 30)
  b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
  b.bg:SetTexture(ART .. "hs-round.tga")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("CENTER"); b.icon:SetSize(18, 18)
  local function toggle()
    if onToggle then onToggle() else ns.Sounds.SetMuted(not ns.Sounds.Muted()) end
    W.RefreshSpeakers()
  end
  b:SetScript("OnClick", toggle)
  -- Raising the volume while muted unmutes: that is plainly what was meant.
  b.volume = W.VolumeSlider(parent, b, {
    get = function() return ns.Sounds.Volume() end,
    set = function(v)
      ns.Sounds.SetVolume(v)
      if v > 0 and ns.Sounds.Muted() then toggle() end
    end,
  })
  b:SetScript("OnEnter", function() b.icon:SetVertexColor(1, .92, .7); b.volume:Open() end)
  b:SetScript("OnLeave", function() b.icon:SetVertexColor(1, 1, 1) end)
  speakers[#speakers + 1] = b
  W.RefreshSpeakers()
  return b
end

--[[ THE WINDOW'S CORNER: the same controls in the same place on every screen
     (board, main menu, practice, collection, decks, packs) -- right to left
     from the top-right corner: the gilded close button, Main Menu, any extra
     buttons the screen has (My Decks), then the speaker with its volume
     slider. Main Menu hides itself where you already are.

       opts.onClose       close (default: hide the window)
       opts.onHome        Main Menu
       opts.onToggleMute  the speaker (default: Sounds.SetMuted)
       opts.onToggleMusic the music button, left of the speaker
                          (default: Main:ToggleMusic) ]]
W.CORNER = { inset = 6, gap = 6, round = 30, homeW = 112, homeH = 28 }
function W.WindowControls(f, opts)
  opts = opts or {}
  local K = W.CORNER
  local c = { extra = {} }
  local close = CreateFrame("Button", nil, f)
  close:SetSize(K.round, K.round)
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -K.inset, -K.inset)
  close:SetFrameLevel(500)
  -- a small gilded round button with a drawn cross (close-x.tga), centred by
  -- construction; a letter "X" is centred by its font's line box, off-centre
  close.bg = close:CreateTexture(nil, "BACKGROUND"); close.bg:SetAllPoints()
  close.bg:SetTexture(ART .. "hs-round.tga")
  close.icon = close:CreateTexture(nil, "ARTWORK")
  close.icon:SetPoint("CENTER"); close.icon:SetSize(K.round * .6, K.round * .6)
  close.icon:SetTexture(ART .. "close-x.tga")
  close:SetScript("OnEnter", function() close.bg:SetVertexColor(1, .85, .6) end)
  close:SetScript("OnLeave", function() close.bg:SetVertexColor(1, 1, 1) end)
  close:SetScript("OnClick", function()
    if ns.Sounds then ns.Sounds.Play("menu_click") end
    if opts.onClose then opts.onClose() else f:Hide() end
  end)
  c.close = close
  c.home = W.MenuButton(f, "Main Menu", function() if opts.onHome then opts.onHome() end end)
  c.home:SetSize(K.homeW, K.homeH)
  c.home:SetFrameLevel(500)
  c.speaker = W.SpeakerButton(f, opts.onToggleMute)
  c.speaker:SetSize(K.round, K.round)
  c.speaker:SetFrameLevel(500)
  c.music = W.MusicButton(f, opts.onToggleMusic)
  c.music:SetSize(K.round, K.round)
  c.music:SetFrameLevel(500)
  -- lay the row out again whenever one of its buttons comes or goes
  function c:Arrange()
    local left = close
    for _, b in ipairs({ c.home, unpack(c.extra) }) do
      if b:IsShown() then
        b:ClearAllPoints(); b:SetPoint("RIGHT", left, "LEFT", -K.gap, 0); left = b
      end
    end
    c.speaker:ClearAllPoints(); c.speaker:SetPoint("RIGHT", left, "LEFT", -K.gap, 0)
    c.music:ClearAllPoints(); c.music:SetPoint("RIGHT", c.speaker, "LEFT", -K.gap, 0)
  end
  --[[ How much of the corner the row takes: its width from the window's right
       edge and its height from the top. The board keeps the enemy's hand out
       of it (a tall window hung their cards over Concede and Main Menu). ]]
  function c:Extent()
    local wsum = K.inset + K.round
    for _, b in ipairs({ c.home, unpack(c.extra) }) do
      if b:IsShown() then wsum = wsum + K.gap + b:GetWidth() end
    end
    wsum = wsum + 2 * (K.gap + K.round)       -- speaker and music
    return wsum, K.inset + math.max(K.round, K.homeH)
  end
  function c:Add(b)
    c.extra[#c.extra + 1] = b
    b:SetFrameLevel(500)
    b:HookScript("OnShow", function() c:Arrange() end)
    b:HookScript("OnHide", function() c:Arrange() end)
    c:Arrange()
  end
  c.home:HookScript("OnShow", function() c:Arrange() end)
  c.home:HookScript("OnHide", function() c:Arrange() end)
  c:Arrange()
  return c
end

--[[ WHERE THE RARITY GEM'S SOCKET HANGS on each 256x512 frame, as fractions:
     centre x, top, width, height. Sunwell's placement (MinionCard etc.
     rarityGemCoords, in its 764-wide canvas) carried onto the Joust frames by
     the fit the painted cost/attack/health badges give -- x' = 0.4218x - 12.5,
     y' = 0.6046y - 25.2 -- then centred on each banner by eye. ]]
W.GEM_SOCKET = {
  minion = { cx = 125.5 / 256, top = 296.5 / 512, w = 62.4 / 256, h = 49.0 / 512 },
  spell  = { cx = 126.0 / 256, top = 300.0 / 512, w = 48.9 / 256, h = 46.9 / 512 },
  weapon = { cx = 127.0 / 256, top = 300.0 / 512, w = 40.5 / 256, h = 54.4 / 512 },
}
W.GEM_RARITIES = { COMMON = true, RARE = true, EPIC = true, LEGENDARY = true }

--[[ THE VOLUME SLIDER that drops from the board's speaker on hover.

     Built from plain frames -- a trough, a gold fill, a knob -- and driven by
     the cursor, like the board's own aiming, rather than WoW's Slider
     template. It stays open while the pointer is over the speaker or the
     slider, and folds away a moment after it leaves both. `o.get()` returns
     0..1; `o.set(v)` applies it. Returns the panel; panel:Open() shows it. ]]
function W.VolumeSlider(parent, anchor, o)
  local p = CreateFrame("Frame", nil, parent)
  p:SetSize(40, 150); p:SetFrameLevel(anchor:GetFrameLevel() + 10)
  p:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
  p:EnableMouse(true)
  p.bg = p:CreateTexture(nil, "BACKGROUND"); p.bg:SetAllPoints()
  p.bg:SetColorTexture(.09, .06, .04, .92)
  p.rim = W.GoldFrame(p, 6, "BORDER"); p.rim:Layout(40, 150)
  p.label = p:CreateFontString(nil, "OVERLAY")
  W.ApplyStyle(p.label, "count", nil, 11, W.Colors.bodyLight); p.label:SetPoint("BOTTOM", p, "BOTTOM", 0, 8)
  local TROUGH_H = 104
  p.trough = CreateFrame("Frame", nil, p)
  p.trough:SetSize(8, TROUGH_H); p.trough:SetPoint("TOP", p, "TOP", 0, -12)
  p.trough:EnableMouse(true)
  local tt = p.trough:CreateTexture(nil, "BACKGROUND"); tt:SetAllPoints(); tt:SetColorTexture(0, 0, 0, .75)
  p.fill = p.trough:CreateTexture(nil, "ARTWORK")
  p.fill:SetPoint("BOTTOM", p.trough, "BOTTOM", 0, 0); p.fill:SetWidth(8)
  p.fill:SetColorTexture(.95, .74, .30, 1)
  p.knob = p.trough:CreateTexture(nil, "OVERLAY")
  p.knob:SetTexture(ART .. "hs-round.tga"); p.knob:SetSize(18, 18)
  function p:Refresh()
    local v = o.get()
    self.fill:SetHeight(math.max(0.01, v * TROUGH_H))
    self.knob:ClearAllPoints(); self.knob:SetPoint("CENTER", self.trough, "BOTTOM", 0, v * TROUGH_H)
    self.label:SetText(("%d%%"):format(math.floor(v * 100 + 0.5)))
  end
  -- the value under the cursor, from the trough's own screen rect
  function p:ValueAtCursor()
    if not GetCursorPosition then return nil end
    local _, cy = GetCursorPosition()
    local scale = self.trough:GetEffectiveScale()
    local bottom = self.trough:GetBottom()
    if not (cy and bottom) then return nil end
    return math.max(0, math.min(1, (cy / scale - bottom) / TROUGH_H))
  end
  local function drag()
    local v = p:ValueAtCursor()
    if v then o.set(v); p:Refresh() end
  end
  --[[ The grab area is the whole panel's width over the trough's height, not
       the 8px trough itself, which was too narrow to hit reliably. ]]
  p.hit = CreateFrame("Frame", nil, p)
  p.hit:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -6)
  p.hit:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 22)
  p.hit:SetFrameLevel(p.trough:GetFrameLevel() + 2)
  p.hit:EnableMouse(true)
  local function press() p.dragging = true; drag() end
  local function release() drag(); p.dragging = false end
  for _, target in ipairs({ p.trough, p.hit }) do
    target:SetScript("OnMouseDown", press)
    target:SetScript("OnMouseUp", release)
  end
  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function(_, delta)
    o.set(math.max(0, math.min(1, o.get() + delta * 0.05))); p:Refresh()
  end)
  -- open while hovered; fold away shortly after the pointer leaves both
  local linger = 0
  p:SetScript("OnUpdate", function(_, dt)
    if p.dragging then
      if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then p.dragging = false else drag() end
    end
    local over = (p.IsMouseOver and p:IsMouseOver()) or (anchor.IsMouseOver and anchor:IsMouseOver())
    if over or p.dragging then linger = 0.35
    else
      linger = linger - dt
      if linger <= 0 then p:Hide() end
    end
  end)
  function p:Open() linger = 0.35; self:Refresh(); self:Show() end
  p:Hide()
  return p
end

--[[ A STEPPED SLIDER -- the practice bots' difficulty.

     The volume slider's parts laid on their side -- a dark trough, a gold
     fill, the round knob -- with a notch at every step, so five settings read
     as five places the knob can rest rather than a continuous dial. Click or
     drag anywhere along it and the knob snaps to the nearest notch; the wheel
     steps it one at a time. `o.steps` is the count, `o.get()` returns 1..steps
     and `o.set(i)` applies one. p:Layout(w) sizes it; the height is fixed. ]]
function W.StepSlider(parent, o)
  local steps = o.steps or 5
  local p = CreateFrame("Frame", nil, parent)
  p:EnableMouse(true)
  p.trough = p:CreateTexture(nil, "BACKGROUND")
  p.trough:SetColorTexture(0, 0, 0, .75)
  p.fill = p:CreateTexture(nil, "ARTWORK")
  p.fill:SetColorTexture(.95, .74, .30, 1)
  p.notches = {}
  for i = 1, steps do
    local n = p:CreateTexture(nil, "ARTWORK", nil, 1)
    n:SetTexture(ART .. "hs-round.tga")
    p.notches[i] = n
  end
  p.knob = p:CreateTexture(nil, "OVERLAY")
  p.knob:SetTexture(ART .. "hs-round.tga")
  p.width, p.dragging = 200, false
  local PAD, H = 12, 22
  local function x(i) return PAD + (i - 1) * (p.width - 2 * PAD) / math.max(1, steps - 1) end
  function p:Refresh()
    local v = math.max(1, math.min(steps, o.get() or 1))
    self.fill:ClearAllPoints()
    self.fill:SetPoint("LEFT", self, "LEFT", PAD, 0)
    self.fill:SetSize(math.max(1, x(v) - PAD), 4)
    for i, n in ipairs(self.notches) do
      n:ClearAllPoints(); n:SetPoint("CENTER", self, "LEFT", x(i), 0)
      n:SetSize(10, 10)
      if i <= v then n:SetVertexColor(1, .86, .45, 1) else n:SetVertexColor(.45, .40, .34, 1) end
    end
    self.knob:ClearAllPoints(); self.knob:SetPoint("CENTER", self, "LEFT", x(v), 0)
    self.knob:SetSize(20, 20)
  end
  function p:Layout(w)
    self.width = math.max(2 * PAD + steps * 12, w or self.width)
    self:SetSize(self.width, H)
    self.trough:ClearAllPoints()
    self.trough:SetPoint("LEFT", self, "LEFT", PAD, 0)
    self.trough:SetSize(self.width - 2 * PAD, 4)
    self:Refresh()
  end
  -- the notch nearest the cursor, from the slider's own screen rect
  function p:StepAtCursor()
    if not GetCursorPosition then return nil end
    local cx = GetCursorPosition()
    local left = self:GetLeft()
    if not (cx and left) then return nil end
    local local_ = cx / self:GetEffectiveScale() - left
    local span = (self.width - 2 * PAD) / math.max(1, steps - 1)
    return math.max(1, math.min(steps, math.floor((local_ - PAD) / span + 1.5)))
  end
  local function pick()
    local i = p:StepAtCursor()
    if i and i ~= o.get() then o.set(i) end
    p:Refresh()
  end
  p:SetScript("OnMouseDown", function() p.dragging = true; pick() end)
  p:SetScript("OnMouseUp", function() pick(); p.dragging = false end)
  p:SetScript("OnUpdate", function()
    if not p.dragging then return end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then p.dragging = false
    else pick() end
  end)
  p:EnableMouseWheel(true)
  p:SetScript("OnMouseWheel", function(_, delta)
    local v = math.max(1, math.min(steps, (o.get() or 1) + (delta > 0 and 1 or -1)))
    if v ~= o.get() then o.set(v) end
    p:Refresh()
  end)
  p:Layout(200)
  return p
end

-- Reuse five level columns while scrolling the guaranteed unlock schedule.
function W.RewardTrack(parent,resolver,ink)
  -- `ink`: drawn on parchment, so dark text rather than light (docs/39)
  local body=ink and "bodyInk" or "body"
  local t=CreateFrame("Frame",nil,parent)
  t:SetFrameLevel(parent:GetFrameLevel()+1)
  t:SetSize(800,500); t.first=1; t.current=1; t.rows={}; t.columns={}; t.onScroll=false; t.inspect=false
  local function scroll(delta) t:Scroll(delta) end
  local function inspect(cardId)
    if not t.inspect then
      t.inspect=W.NewInspect(parent)
      t.inspect.frame:SetFrameLevel(parent:GetFrameLevel()+50)
      t.inspect.card.frame:SetFrameLevel(parent:GetFrameLevel()+60)
      t.inspect.frame:SetScript("OnClick",function() t.inspect.frame:Hide() end)
    end
    local w,h=parent:GetWidth(),parent:GetHeight()
    local ch=math.min(480,h*.7)
    ns.CardWidget.SetDescriptor(t.inspect.card,resolver:Card(cardId))
    ns.CardWidget.ApplyRect(t.inspect.card,{x=(w-ch*.7)/2,y=(h-ch)/2,w=ch*.7,h=ch})
    W.InspectKeywords(t.inspect,cardId)
    t.inspect.frame:Show()
  end
  t:SetScript("OnHide",function() if t.inspect then t.inspect.frame:Hide() end end)
  t:EnableMouseWheel(true); t:SetScript("OnMouseWheel",function(_,delta) scroll(-delta) end)
  for i=1,5 do
    local col=CreateFrame("Frame",nil,t); t.columns[i]=col
    col:SetFrameLevel(t:GetFrameLevel()+1)
    col:SetSize(148,420); col:SetPoint("TOPLEFT",t,"TOPLEFT",(i-1)*160+6,0)
    col.rail=col:CreateTexture(nil,"BACKGROUND"); col.rail:SetSize(160,4); col.rail:SetPoint("TOPLEFT",col,"TOPLEFT",-6,-20)
    col.marker=col:CreateTexture(nil,"ARTWORK"); col.marker:SetTexture(ART.."hs-round.tga")
    col.marker:SetSize(40,40); col.marker:SetPoint("TOP",col,"TOP",0,0)
    -- the level sits in a dark node, so it stays light even on parchment
    col.levelText=W.StyledText(col,"body"); W.ApplyStyle(col.levelText,"body",nil,16)
    col.levelText:SetAllPoints(col.marker); col.levelText:SetJustifyH("CENTER"); col.levelText:SetJustifyV("MIDDLE")
    col.status=W.StyledText(col,body); col.status:SetSize(148,22)
    col.status:SetPoint("TOP",col,"TOP",0,-44); col.status:SetJustifyH("CENTER")
    col.slots={}
    for j=1,3 do
      local slot=CreateFrame("Frame",nil,col); col.slots[j]=slot
      slot:SetFrameLevel(col:GetFrameLevel()+1)
      slot:SetAllPoints(col); slot.reward=false
      slot.icon=slot:CreateTexture(nil,"ARTWORK")
      slot.count=W.StyledText(slot,"count"); slot.count:SetSize(148,22); slot.count:SetJustifyH("CENTER")
      slot.card=ns.CardWidget.New(slot)
      slot.card.frame:SetFrameLevel(slot:GetFrameLevel()+1)
      slot.card.frame:RegisterForClicks("LeftButtonUp","RightButtonUp")
      slot.card.frame:SetScript("OnClick",function(_,button)
        if button=="RightButton" and slot.reward and slot.reward.cardId then inspect(slot.reward.cardId) end
      end)
      slot.card.frame:EnableMouseWheel(true); slot.card.frame:SetScript("OnMouseWheel",function(_,delta) scroll(-delta) end)
    end
  end
  t.slider=W.StepSlider(t,{steps=56,get=function() return t.first end,set=function(v) t:Scroll(v-t.first) end})
  t.slider:SetFrameLevel(t:GetFrameLevel()+1)
  t.slider:Layout(690); t.slider:SetPoint("BOTTOM",t,"BOTTOM",0,0)
  t.slider:SetScript("OnMouseWheel",function(_,delta) scroll(-delta) end)
  t.range=W.StyledText(t,body); t.range:SetSize(700,22)
  t.range:SetPoint("BOTTOM",t.slider,"TOP",0,5); t.range:SetJustifyH("CENTER")
  function t:Refresh()
    for i,col in ipairs(self.columns) do
      local level=self.first+i-1; local row=self.rows[level]
      local reached=level<=self.current
      col.levelText:SetText(tostring(level))
      col.marker:SetVertexColor(reached and 1 or .38,reached and .79 or .35,reached and .35 or .31,1)
      col.rail:SetColorTexture(reached and .9 or .24,reached and .64 or .20,reached and .2 or .16,1)
      col.status:SetText(level==self.current and "YOUR LEVEL" or (level==1 and "Starting collection" or (row and #row.rewards>0 and (reached and "Unlocked" or "Upcoming") or "")))
      local nCards=0
      for _,r in ipairs(row and row.rewards or {}) do if r.kind=="CARD" then nCards=nCards+1 end end
      local cardIndex=0
      for j,slot in ipairs(col.slots) do
        local r=row and row.rewards[j]; slot.reward=r or false; slot:SetShown(r~=nil)
        slot.card.frame:Hide(); slot.icon:Hide(); slot.count:Hide()
        if r then
          if r.kind=="CARD" then
            cardIndex=cardIndex+1
            local ch=nCards>1 and 126 or 204; local cw=ch*.7
            local top=72+(cardIndex-1)*152
            ns.CardWidget.SetDescriptor(slot.card,resolver:Card(r.cardId))
            ns.CardWidget.ApplyRect(slot.card,{x=(148-cw)/2,y=420-top-ch,w=cw,h=ch})
            slot.card.frame:Show()
            slot.count:ClearAllPoints(); slot.count:SetPoint("TOP",col,"TOP",0,-top-ch-2)
            slot.count:SetText("x"..r.count); slot.count:Show()
          else
            local ph=nCards>1 and 44 or (nCards==1 and 58 or 188)
            local top=nCards>1 and 380 or (nCards==1 and 315 or 78)
            slot.icon:ClearAllPoints(); slot.icon:SetSize(ph*150/208,ph)
            slot.icon:SetPoint("TOP",col,"TOP",0,-top); slot.icon:SetTexture(ART.."menu-pack.tga"); slot.icon:Show()
            slot.count:ClearAllPoints(); slot.count:SetPoint("TOP",col,"TOP",0,-top-ph)
            slot.count:SetText("x"..r.count..(r.count==1 and " Pack" or " Packs")); slot.count:Show()
          end
        end
      end
    end
    self.range:SetText(("Levels %d-%d of 60  |  Scroll or drag to explore"):format(self.first,self.first+4))
    self.slider:Refresh(); if self.onScroll then self.onScroll() end
  end
  function t:Scroll(delta)
    self.first=math.max(1,math.min(56,self.first+delta))
    if self.inspect then self.inspect.frame:Hide() end
    self:Refresh()
  end
  function t:SetRewards(rows,current,first)
    self.rows=rows; self.current=current
    self.first=math.max(1,math.min(56,first or current-2)); self:Refresh()
  end
  return t
end

--[[ ONE WINDOW, THREE SCREENS.

     The hub, the collection and the board are separate frames, and each kept
     its own position and size -- so leaving the collection for a match put
     the table somewhere else, at another size, and the next resize seemed to
     jump. Every window with a grip now shares ONE rect: move or size any of
     them and the next one opens exactly there.

     It lasts for the session only. WoW saves a named, moved frame's anchor
     and size in its layout cache and restores them on /reload, which is how
     a badly sized window survived every reload; SetDontSavePosition stops
     that, so a reload always comes back at each window's default. ]]
local sharedRect
function W.RememberRect(frame)
  local left, top = frame:GetLeft(), frame:GetTop()
  if not (left and top) then return end
  sharedRect = { left = left, top = top, w = frame:GetWidth(), h = frame:GetHeight() }
end
function W.SharedRect() return sharedRect end
function W.ForgetRect() sharedRect = nil end
local function clampToBounds(frame, w, h)
  local a, b, c, d = frame:GetResizeBounds()
  if a then w = math.max(a, math.min(c or w, w)); h = math.max(b, math.min(d or h, h)) end
  return w, h
end
--[[ Until something has been moved or sized this session, every window opens
     at its OWN default, centred -- applied on every show rather than trusted
     to still be true. SetDontSavePosition stops WoW saving a window's rect, but
     not restoring one it saved before: a size cached by an older version came
     back when the collection was first built after a /reload, and opening packs
     jumped the window to it. ]]
--[[ THE DEFAULT FILLS THE SCREEN THE WAY HEARTHSTONE DOES. A fixed 1280x720
     took a third of a 3440x1440 screen (the first in-client screenshot tour,
     docs/39): Hearthstone is the whole screen. So the first open is 16:9 at
     DEFAULT_FILL of the screen's height, never wider than DEFAULT_FILL of its
     width, and never below the size the window was built at, which is its
     legibility floor. Once moved or sized, the player's rect wins as before. ]]
W.DEFAULT_FILL = 0.86

--[[ Where a digit sits on mana_crystal.tga, as a fraction of the crystal's
     size, from the run-4 in-client screenshots (docs/39). Positive x is right,
     positive y is up. ]]
W.CRYSTAL_DIGIT = { tileX = 0.09, tileY = 0, filterX = 0, filterY = 0.035 }
function W.DefaultSize(d)
  local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
  if not (sw and sh and sw > 0 and sh > 0) then return d.w, d.h end
  local h = sh * W.DEFAULT_FILL
  local w = h * d.w / d.h
  if w > sw * W.DEFAULT_FILL then w = sw * W.DEFAULT_FILL; h = w * d.h / d.w end
  if w < d.w then return d.w, d.h end
  return w, h
end

function W.ApplySharedRect(frame)
  local r = sharedRect
  if not r then
    local d = rawget(frame, "defaultRect")
    if d then
      frame:SetSize(clampToBounds(frame, W.DefaultSize(d)))
      frame:ClearAllPoints(); frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    return
  end
  frame:SetSize(clampToBounds(frame, r.w, r.h))
  frame:ClearAllPoints(); frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", r.left, r.top)
end
function W.SharedWindow(frame)
  if rawget(frame, "sharedWindow") then return end
  frame.sharedWindow = true
  -- the size the window was built at is its default (Board 1280x720, etc.)
  frame.defaultRect = { w = frame:GetWidth(), h = frame:GetHeight() }
  if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
  frame:SetUserPlaced(false)
  frame:HookScript("OnShow", function() W.ApplySharedRect(frame) end)
  frame:HookScript("OnDragStop", function() frame:SetUserPlaced(false); W.RememberRect(frame) end)
  --[[ A frame is created SHOWN, so its first opening raises no OnShow: the
       default above reached only the second opening, and run 2 of the tour
       (docs/39) still met every window at its built size. Applied now too. ]]
  W.ApplySharedRect(frame)
end

function W.ResizeGrip(frame, minW, minH, maxW, maxH, onDone)
  frame:SetResizable(true); frame:SetResizeBounds(minW, minH, maxW or 3840, maxH or 2160)
  frame:SetClampedToScreen(true)
  W.SharedWindow(frame)
  local grip = CreateFrame("Button",nil,frame)
  grip:EnableMouse(true)
  grip:SetSize(22,22); grip:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",0,0)
  grip:SetFrameLevel(frame:GetFrameLevel()+480)
  grip.tex=grip:CreateTexture(nil,"OVERLAY"); grip.tex:SetAllPoints()
  grip.tex:SetTexture(ART .. "resize-grip.tga")
  grip.hint=grip:CreateFontString(nil,"OVERLAY")
  W.ApplyStyle(grip.hint, "label", nil, 13); grip.hint:SetText("Drag to resize")
  grip.hint:SetPoint("BOTTOMRIGHT",grip,"TOPRIGHT",-4,6); grip.hint:Hide()
  grip:SetScript("OnEnter",function()
    grip.hint:Show(); grip.tex:SetVertexColor(1,.95,.7,1)
  end)
  grip:SetScript("OnLeave",function() grip.hint:Hide(); grip.tex:SetVertexColor(1,1,1,1) end)
  --[[ SIZED BY THE ADDON, NOT BY StartSizing. WoW's own sizing decides on
       its first frame where the dragged corner goes -- it can snap the corner
       to the pointer, and it applies the screen clamp and the resize bounds in
       its own order -- and each of those was a "the window jumped" report
       (the latest mid-duel). Here the drag is plain arithmetic: the size at
       the press plus how far the pointer has moved since, the top-left corner
       held still, capped at the screen's edge and the window's bounds. The
       first frame of a drag is always exactly the size it already was. ]]
  grip.drag=false
  local function stopSizing()
    if not grip.drag then return end
    grip.drag=false; grip:SetScript("OnUpdate",nil)
    frame:StopMovingOrSizing()
    frame:SetUserPlaced(false)
    W.RememberRect(frame)
    if onDone then onDone() end
  end
  local function pointer()
    if not GetCursorPosition then return nil end
    local x,y=GetCursorPosition(); if not x then return nil end
    local s=frame:GetEffectiveScale() or 1
    return x/s,y/s
  end
  function grip:Step()
    local d=self.drag; if not d then return end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then return stopSizing() end
    local x,y=pointer(); if not x then return end
    local w,h=d.w+(x-d.x),d.h+(d.y-y)
    -- never past the screen's right or bottom edge (in this frame's units)
    local ratio=(UIParent:GetEffectiveScale() or 1)/(frame:GetEffectiveScale() or 1)
    w=math.min(w,UIParent:GetWidth()*ratio-d.left); h=math.min(h,d.top)
    w,h=clampToBounds(frame,w,h)
    if math.abs(w-frame:GetWidth())>.5 or math.abs(h-frame:GetHeight())>.5 then frame:SetSize(w,h) end
  end
  grip:SetScript("OnMouseDown",function(_,button)
    if button and button~="LeftButton" then return end
    local left,top=frame:GetLeft(),frame:GetTop()
    if not (left and top) then return end
    -- hold the top-left corner still while the bottom-right one moves
    frame:ClearAllPoints(); frame:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",left,top)
    -- A window outside its own bounds (one shared rect, three minimums) is put
    -- inside them first, so the drag starts from a size it can keep.
    local w,h=frame:GetWidth(),frame:GetHeight()
    local cw,ch=clampToBounds(frame,w,h)
    if cw~=w or ch~=h then frame:SetSize(cw,ch) end
    local x,y=pointer(); if not x then return end
    grip.drag={x=x,y=y,w=cw,h=ch,left=left,top=top}
    grip:SetScript("OnUpdate",function() grip:Step() end)
  end)
  grip:SetScript("OnMouseUp",function() stopSizing() end)
  grip:SetScript("OnHide",function() stopSizing(); grip.hint:Hide() end)
  return grip
end
local function mask(parent, texture, name)
  local m = parent:CreateMaskTexture()
  m:SetTexture(ART .. name .. ".tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  m:SetAllPoints(texture)
  texture:AddMaskTexture(m)
  return m
end

W.Mask = mask

-- ============================================================= widget pools

local function newPool(factory)
  return { free = {}, used = {}, factory = factory, created = 0 }
end

--[[ `gen` is what makes a pooled widget safe to animate.

     WoW cannot destroy a frame, so every card on screen is a REUSED frame. An
     animation holds the widget and writes alpha, scale and position to it over
     a third of a second -- and in that time the widget can be released and
     handed out again as a completely different card. The death fade of a
     minion that died half a second ago then fades whatever card is now in that
     frame, which is why cards went invisible, flickered, or vanished "for a
     bit" during attacks and deaths.

     Every acquire bumps the counter. Client/UI/Board.lua captures it when it
     builds an animation handle and ignores every call once it has moved on, so
     a stale animation writes to nothing instead of to the wrong card. ]]
local function poolAcquire(pool, parent)
  local w = table.remove(pool.free)
  if not w then
    w = pool.factory(parent)
    pool.created = pool.created + 1
  end
  pool.used[#pool.used + 1] = w
  w.gen = (w.gen or 0) + 1
  w.frame:SetScale(1)
  w.frame:SetAlpha(1)
  if w.ownedCount then w.ownedCount:Hide() end
  w.frame:Show()
  return w
end

local function poolReleaseAll(pool, keepShown)
  for i = #pool.used, 1, -1 do
    local w = pool.used[i]
    --[[ Bumped on the way OUT as well as the way in, so an animation is
         invalidated the moment its widget stops being the card it animated --
         not merely when the frame is handed to someone else. A widget can sit
         in the free list for many frames, and a death fade running over that
         gap would otherwise still be pointed at it when it came back. ]]
    w.gen = (w.gen or 0) + 1
    if w.anim then w.anim:Stop() end
    if not keepShown then w.frame:Hide() end
    w.frame:SetAlpha(1)
    w.frame:SetScale(1)
    if w.art and w.art.SetRotation then w.art:SetRotation(0) end
    pool.used[i] = nil
    pool.free[#pool.free + 1] = w
  end
end

W.NewPool = newPool
W.Acquire = poolAcquire
W.ReleaseAll = poolReleaseAll

-- ============================================================== card widget

--[[ A card widget is a frame plus the pieces every card needs. Built once and
     re-pointed, never rebuilt. `SetCard` takes a descriptor from
     Assets/Resolver.lua, which is guaranteed complete even with zero art. ]]
--[[ Board-minion states that Hearthstone paints on the portrait, in draw order.
     `key` is the flag on the controller's live stats. Numbers stay on top
     (OVERLAY 6), so nothing here can hide an attack or health value. ]]
W.CARD_STATES = {
  { key = "enraged",     file = "inplay_minion_enraged",      layer = "ARTWORK", sub = 3 },
  { key = "stealth",     file = "inplay_minion_stealth",      layer = "OVERLAY", sub = 0 },
  { key = "immune",      file = "inplay_minion_immune",       layer = "OVERLAY", sub = 1 },
  { key = "elusive",     file = "inplay_minion_untargetable", layer = "OVERLAY", sub = 1 },
  { key = "silenced",    file = "inplay_minion_silenced",     layer = "OVERLAY", sub = 2 },
  { key = "frozen",      file = "inplay_minion_frozen",       layer = "OVERLAY", sub = 2 },
  { key = "sleeping",    file = "effect_sleep",               layer = "OVERLAY", sub = 4 },
  { key = "deathrattle", file = "icon_deathrattle",           layer = "OVERLAY", sub = 4 },
  { key = "trigger",     file = "icon_trigger",               layer = "OVERLAY", sub = 4 },
}

local cardSetLean   -- defined below; cardApplyRect applies a card's lean

--[[ A minion's glow (can attack, targetable, selected) follows its outline. A
     taunt shield stands out past the oval frame and is drawn over the glow, so
     it wears its own glow traced round the shield (tools/build_taunt_glow.py,
     a canvas 1.25x the frame's); otherwise the glow was hidden behind it. ]]
local function cardFitGlow(w, taunt)
  local sw, sh = w.skin:GetWidth(), w.skin:GetHeight()
  w.glowTaunt = taunt and true or false
  w.glow:ClearAllPoints(); w.glow:SetPoint("CENTER", w.frame, "CENTER", 0, 0)
  if taunt then
    w.glow:SetTexture(ART .. "inplay_minion_taunt-glow.tga")
    w.glow:SetSize(sw * 1.25, sh * 1.25)
  else
    w.glow:SetTexture(ART .. "inplay_minion-glow.tga")
    w.glow:SetSize(sw * 1.075, sh * 1.075)
  end
end
local cardSetFaceDown
local cardDrawRules
local cardApplyBaked

-- Each digit is a full-card overlay, with its ink positioned using UVs.
-- Small regions rotate differently from the card canvas in the live client.
-- Identical bounds and centers make the skin and every digit share a pivot,
-- regardless of whether the client transforms regions or the whole frame.
-- Separate transparent-edged glyph files prevent neighboring atlas cells from
-- leaking into the expanded UV range. This also supports arbitrary live values.
-- Ink width of each digit in card-digit-*.tga, as a fraction of the glyph's
-- height-scaled cell (tools/build_card_digits.py: 64px cells, 50px digits,
-- the 1 is 43px), and how much neighbouring outlines overlap.
-- One texture out of the pixel grid (see W.NoPixelSnap), for textures a
-- card gains after it was built.
function W.Unsnap(tex)
  if tex and tex.SetSnapToPixelGrid then
    tex:SetSnapToPixelGrid(false)
    tex:SetTexelSnappingBias(0)
  end
  return tex
end

local GLYPH_INK = { ["-"] = 17/64 }
for d = 0, 9 do GLYPH_INK[tostring(d)] = 50/64 end
GLYPH_INK["1"] = 43/64
local GLYPH_OVERLAP = 0.07
W.GLYPH_INK = GLYPH_INK

local function makeCardNumber(parent)
  local n = { glyphs = {}, text = "", size = 12, shown = true, alpha = 1,
              colour = {1, 1, 1, 1}, parent = parent }
  local function refresh()
    local count = #n.text
    local size = n.size * (count >= 2 and 0.84 or 1)
    --[[ Glyphs are placed by their INK, not by a fixed pitch: a fixed pitch
         left "10" lopsided (the 1 is narrower than its cell) and wider than
         the gem. Neighbours overlap by their outline, as Hearthstone's do. ]]
    local centres, total = {}, 0
    for i = 1, count do
      local ink = GLYPH_INK[n.text:sub(i, i)] or GLYPH_INK["0"]
      local width = ink * size
      centres[i] = total + width / 2
      total = total + width - (i < count and size * GLYPH_OVERLAP or 0)
    end
    for i = 1, math.max(count, #n.glyphs) do
      local tex = n.glyphs[i]
      if i <= count then
        if not tex then
          tex = parent:CreateTexture(nil, "OVERLAY", nil, 6)
          --[[ Made after the card's W.NoPixelSnap, so it must opt out itself:
               a snapped digit rounded differently from the card around it and
               the numbers jiggled on their gems while the window was resized. ]]
          W.Unsnap(tex)
          n.glyphs[i] = tex
        end
        local ch = n.text:sub(i, i)
        local cell = tonumber(ch) or 10
        tex:SetTexture(ART .. "card-digit-" .. cell .. ".tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        local p = n.point
        tex:ClearAllPoints()
        if p and n.canvasW and n.canvasH then
          local offset = centres[i] - total / 2
          local x, y = p[4] + offset, p[5]
          local gw, gh = size, size*2
          local left = 0.5 - (n.canvasW/2 + x)/gw
          local top = 0.5 - (n.canvasH/2 - y)/gh
          tex:SetSize(n.canvasW, n.canvasH)
          tex:SetPoint("CENTER", parent, "CENTER", 0, 0)
          tex:SetTexCoord(left, left+n.canvasW/gw, top, top+n.canvasH/gh)
        end
        tex:SetVertexColor(unpack(n.colour))
        tex:SetAlpha(n.alpha)
        if n.shown and p and n.canvasW then tex:Show() else tex:Hide() end
      elseif tex then tex:Hide() end
    end
  end
  function n:SetLean(rot) self.lean = rot; refresh() end
  function n:SetCanvas(width, height) self.canvasW, self.canvasH = width, height; refresh() end
  function n:SetText(text) self.text = tostring(text or ""); refresh() end
  function n:GetText() return self.text end
  function n:SetFont(font, size, flags) self.font = {font, size, flags}; self.size = size; refresh() end
  function n:GetFont() return unpack(self.font) end
  function n:SetTextColor(...) self.colour = {...}; refresh() end
  function n:ClearAllPoints() self.point = nil end
  function n:SetPoint(point, relative, relativePoint, x, y)
    -- All card badges use centered anchors, including the unskinned fallback.
    self.point = {point, relative, relativePoint, x or 0, y or 0}; refresh()
  end
  function n:Show() self.shown = true; refresh() end
  function n:Hide() self.shown = false; refresh() end
  function n:IsShown() return self.shown end
  function n:SetAlpha(a) self.alpha = a; refresh() end
  function n:GetAlpha() return self.alpha end
  return n
end

-- The mana gem's centre on each in-hand frame, in its 256x512 canvas.
W.COST_GEM = { MINION = { 30.5, 81 }, SPELL = { 36.5, 80.5 }, WEAPON = { 34, 85 },
  -- Hearthstone's hero-power card (Sunwell's hero-power-player.png): the gem
  -- crowns the stone ring, centred
  HERO_POWER = { 128.5, 27.6 } }
--[[ The hero-power card's own furniture, as fractions of its face (measured
     on the 564x841 source): the round art window, the name scroll, the text
     plate. ]]
W.HERO_POWER_CARD = { art = { .2785, .1305, .443, .297 }, nameY = .493, nameW = .74,
                      body = { top = .612, w = .70, h = .245 } }

--[[ A CARD'S PIECES MOVE AS ONE. Mainline snaps every texture to the pixel
     grid on its own, which is right for a static frame and wrong for a card:
     its frame, art, gem and badges sit at fractional positions (and a hand
     card is rotated), so as the window was resized each piece rounded a
     different way from frame to frame and the hand visibly jiggled. Turned
     off for every texture of the frame and its child frames. ]]
function W.NoPixelSnap(frame)
  if not (frame and frame.GetRegions) then return end
  for _, r in ipairs({ frame:GetRegions() }) do
    if r:GetObjectType() == "Texture" then W.Unsnap(r) end
  end
  for _, child in ipairs({ frame:GetChildren() }) do W.NoPixelSnap(child) end
end

local function makeCard(parent)
  local f = CreateFrame("Button", nil, parent)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  local w = { frame = f }

  w.bg = f:CreateTexture(nil, "BACKGROUND")
  w.bg:SetAllPoints()
  w.bg:SetColorTexture(0.10, 0.10, 0.12, 0.95)

  -- the class-coloured frame is drawn as four edges rather than a border
  -- texture, so the default tier needs no art at all
  w.edges = {}
  for i = 1, 4 do
    local e = f:CreateTexture(nil, "BORDER")
    e:SetColorTexture(1, 1, 1, 1)
    w.edges[i] = e
  end

  w.art = f:CreateTexture(nil, "ARTWORK")
  w.artMask = mask(f, w.art, "mask-oval")
  w.skin = f:CreateTexture(nil, "ARTWORK", nil, 1)
  w.skin:SetAllPoints()
  w.skin:Hide()
  w.model = CreateFrame("PlayerModel", nil, f)
  w.model:Hide()

  --[[ THE RARITY GEM. A diamond set into the frame, not a square.

       It was a plain ColorTexture, which is a square, and a square is not what
       a rarity gem looks like in any card game. Rotating it would not have
       helped: a solid colour has no orientation. So the shape is a generated
       texture with alpha (Art/gem.tga) and the rarity is a vertex tint on it,
       which also means one texture serves all five rarities. ]]
  w.gem = f:CreateTexture(nil, "OVERLAY")
  local gemArt = (ns.HearthstoneArt or {}).gem
  if gemArt then
    w.gem:SetTexture(gemArt)
    w.gemShaped = true
  end

  w.cost = makeCardNumber(f)
  w.name = f:CreateFontString(nil, "OVERLAY")
  w.body = f:CreateFontString(nil, "OVERLAY")
  --[[ What is drawn is the rich text (keywords bold), in runs placed over the
       body's box. The body FontString keeps the plain text and the fitted box
       and is never drawn; its Show / Hide / SetShown drive the runs, so every
       place that hides the rules text (face down, in play) still does. ]]
  w.bodyRich = W.RichText(f, w.body)
  --[[ THE BAKED TEXT (tools/build_card_text.py, docs/24): the name and the
       rules text as two images, drawn instead of the live labels whenever
       the card has them. A leaning FontString is drawn jagged by the client;
       an image turns smoothly. Both are card-sized regions like the skin, so
       they turn about the card's own pivot. ]]
  w.bakedName = f:CreateTexture(nil, "OVERLAY", nil, 4)
  w.bakedText = f:CreateTexture(nil, "OVERLAY", nil, 4)
  w.bakedName:Hide(); w.bakedText:Hide()
  --[[ A MINION'S RACE ("Beast", "Murloc") on its small banner under the text
       plate, as Hearthstone prints it. The banner is Sunwell's
       (tools/import_card_extras.py); the word is baked like the name, or a
       live label when the card is drawn live. It follows the name. ]]
  w.raceBanner = f:CreateTexture(nil, "OVERLAY", nil, 3)
  w.bakedRace = f:CreateTexture(nil, "OVERLAY", nil, 5)
  w.race = f:CreateFontString(nil, "OVERLAY", nil, 5)
  w.race:SetFont(FONT, 10, "OUTLINE"); w.race:SetText(""); w.race:SetWordWrap(false)
  w.raceBanner:Hide(); w.bakedRace:Hide(); w.race:Hide()
  do
    local body, rich = w.body, w.bodyRich
    local show, hide, setShown = body.Show, body.Hide, body.SetShown
    local function sync(v)
      local baked = rawget(w, "baked")
      rich:SetShown(v and not baked)
      w.bakedText:SetShown(v and baked and rawget(w, "bakedHasText") or false)
    end
    body.Show = function(self) show(self); sync(true) end
    body.Hide = function(self) hide(self); sync(false) end
    body.SetShown = function(self, v) setShown(self, v); sync(v) end
    local name = w.name
    local nshow, nhide, nsetShown = name.Show, name.Hide, name.SetShown
    local function raceSync(v)
      local race = v and rawget(w, "raceLabel") and true or false
      local baked = rawget(w, "baked") and true or false
      w.raceBanner:SetShown(race); w.bakedRace:SetShown(race and baked); w.race:SetShown(race and not baked)
    end
    name.Show = function(self) nshow(self); w.bakedName:SetShown(rawget(w, "baked") and true or false); raceSync(true) end
    name.Hide = function(self) nhide(self); w.bakedName:Hide(); raceSync(false) end
    name.SetShown = function(self, v) nsetShown(self, v); w.bakedName:SetShown(v and rawget(w, "baked") and true or false); raceSync(v) end
    w.raceSync = raceSync
  end
  w.atk  = makeCardNumber(f)
  w.hp   = makeCardNumber(f)
  for _, label in ipairs({w.cost, w.name, w.body, w.atk, w.hp}) do
    label:SetFont(FONT, 12, "OUTLINE")
  end
  w.status = f:CreateFontString(nil, "OVERLAY")
  w.status:SetFont(FONT, 14, "OUTLINE")
  w.status:SetText("")
  w.body:SetWordWrap(true)
  w.name:SetWordWrap(false)
  w.name:SetJustifyH("CENTER")
  w.name:SetJustifyV("MIDDLE")

  w.glow = f:CreateTexture(nil, "BACKGROUND", nil, -1)
  w.glow:SetBlendMode("ADD")
  w.glow:SetVertexColor(1, 1, 1, 0)
  w.glow:Hide()

  --[[ The face-down back. A card that is flipped shows this INSTEAD of
       everything else, which is what makes a pack reveal work: there must
       genuinely be nothing to read until it turns over. ]]
  w.taunt = f:CreateTexture(nil, "BACKGROUND", nil, 0)
  w.taunt:SetTexture(ART .. "inplay_minion_taunt.tga")
  w.taunt:SetAllPoints(w.skin)
  w.taunt:Hide()
  w.shield = f:CreateTexture(nil, "OVERLAY", nil, 3)
  w.shield:SetTexture(ART .. "inplay_minion_divine_shield.tga")
  w.shield:SetAllPoints(w.skin)
  w.shield:Hide()
  --[[ HEARTHSTONE'S OWN STATE ART, drawn over the frame rather than implied by
       a tint. Every one of these shares its base frame's canvas, so anchoring
       it to the skin registers it exactly -- no per-texture offsets to drift.
       The legendary dragon wraps the frame itself, so it sits just above it. ]]
  w.legend = f:CreateTexture(nil, "ARTWORK", nil, 2)
  w.legend:SetAllPoints(w.skin)
  w.legend:Hide()
  w.states = {}
  for _, spec in ipairs(W.CARD_STATES) do
    local t = f:CreateTexture(nil, spec.layer, nil, spec.sub)
    t:SetTexture(ART .. spec.file .. ".tga")
    t:SetAllPoints(w.skin)
    t:Hide()
    w.states[spec.key] = t
  end
  w.back = f:CreateTexture(nil, "OVERLAY")
  w.back:SetAllPoints()
  w.back:SetColorTexture(0.16, 0.13, 0.28, 1)
  if ns.HearthstoneArt and ns.HearthstoneArt.cardback then
    w.back:SetTexture(ns.HearthstoneArt.cardback)
  end
  w.back:Hide()

  w.anim = f:CreateAnimationGroup()
  w.rotation = w.anim:CreateAnimation("Rotation")
  w.rotation:SetDuration(0)
  w.rotation:SetEndDelay(86400)
  w.rotation:SetOrigin("CENTER", 0, 0)
  W.NoPixelSnap(f)
  return w
end

--[[ FITTING THE ART TO ITS WINDOW.

     Hearthstone's card art is a square with, on about a quarter of the cards,
     flat bands of grey, white or black down the sides or across the top: the
     original canvas was padded to square. Shown whole, those bands are the
     "grey sides" on a hand or collection card. tools/art_crop.py measures them
     into ns.HearthstoneArtCrop, and the art is cropped to what is left, then to
     the window's own shape, so it always COVERS the window (never stretched,
     never padded). `window` narrows the source first -- a board minion shows
     only the middle of the art, inside the oval. ]]
local BOARD_ART_WINDOW = { 0.14, 0.82, 0.06, 0.92 }
function W.ArtCoords(cardId, aw, ah, window)
  local crop = ns.HearthstoneArtCrop and cardId and ns.HearthstoneArtCrop[cardId]
  local u0, u1, v0, v1 = 0, 1, 0, 1
  if crop then u0, u1, v0, v1 = crop[1], crop[2], crop[3], crop[4] end
  if window then
    u0, u1 = math.max(u0, window[1]), math.min(u1, window[2])
    v0, v1 = math.max(v0, window[3]), math.min(v1, window[4])
  end
  if not aw or not ah or aw <= 0 or ah <= 0 then return u0, u1, v0, v1 end
  local want = aw / ah                    -- the textures are square
  local su, sv = u1 - u0, v1 - v0
  if su / sv > want then
    local nu, c = sv * want, (u0 + u1) / 2
    u0, u1 = c - nu / 2, c + nu / 2
  else
    -- Too tall: trim mostly from the bottom; faces are painted high.
    local nv = su / want
    local top = v0 + (sv - nv) * 0.3
    v0, v1 = top, top + nv
  end
  return u0, u1, v0, v1
end
function W.FitArt(w, window)
  local d = w.descriptor
  if not d or not w.art then return end
  w.art:SetTexCoord(W.ArtCoords(d.cardId or d.id, w.art:GetWidth(), w.art:GetHeight(), window))
end

-- Draw the rules text into the body's fitted box, keywords bold. The body
-- FontString itself carries the plain text and is kept invisible.
cardDrawRules = function(w)
  local box = rawget(w, "bodyBox")
  if not (box and w.bodyRich) then return end
  w.body:SetAlpha(0)
  --[[ The runs take their colour from w.bodyColor, never from the hidden body:
       in the client a FontString's alpha is part of its text colour, so after
       SetAlpha(0) GetTextColor reads back alpha 0 and every run was drawn
       invisible -- cards showed no rules text at all. ]]
  local c = rawget(w, "bodyColor") or { 1, 1, 1 }
  local at = rawget(w, "bodyAt")
  w.bodyRich:Set(rawget(w, "rulesText") or "", { w = box.w, h = box.h, size = box.size,
    min = math.max(4, math.floor(box.size * 0.6)), color = { c[1], c[2], c[3], 1 },
    at = at and { w.frame, at[1], at[2] } })
  w.bodyRich:SetShown(w.body:IsShown() and not rawget(w, "baked"))
end

--[[ BAKED OR LIVE. The baked images are used for a framed (skinned) card
     face whose name and text are the printed ones, up to BAKED_MAX_H tall --
     the size the images were made for (a hovered hand card at 1440p). Larger
     (the enlarged inspect card) and anything unusual keep the live labels,
     which are crisp when upright. ]]
local BAKED_MAX_H = 440
W.BAKED_MAX_H = BAKED_MAX_H
local function bakedEntry(w, r)
  local ct = ns.CardText
  local d = w.descriptor
  if rawget(w, "liveText") or rawget(w, "liveSpellText") then return nil end
  if not (ct and d and w.skinned and not w.inPlay and r and r.h <= BAKED_MAX_H) then return nil end
  local id = d.cardId or d.id
  local e = id and ct.cards[id]
  local p = id and ns.PrintedCards and ns.PrintedCards[id]
  if not (e and p) then return nil end
  if (d.name or "") ~= (p.name or "") or (d.text or "") ~= (p.text or "") then return nil end
  if e[1] ~= d.type then return nil end
  return e, id
end
W.BakedEntry = bakedEntry

function W.CardTextPaths(id)
  local e = ns.CardText and ns.CardText.cards[id]
  if not e then return nil end
  local base = ART .. "CardText\\" .. id
  return base .. "-n.tga", e[2] and (base .. "-t.tga") or nil
end

-- A band image covering `rect` of the face, drawn on a face-sized region.
local function placeBand(tex, w, r, path, rect)
  tex:SetTexture(path, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  tex:ClearAllPoints(); tex:SetPoint("CENTER", w.frame, "CENTER", 0, 0); tex:SetSize(r.w, r.h)
  local x0, x1, y0, y1 = rect[1], rect[2], rect[3], rect[4]
  tex:SetTexCoord(-x0 / (x1 - x0), (1 - x0) / (x1 - x0), -y0 / (y1 - y0), (1 - y0) / (y1 - y0))
end

W.RACE_LABELS = { BEAST = "Beast", MURLOC = "Murloc", DEMON = "Demon", MECHANICAL = "Mech",
                  DRAGON = "Dragon", PIRATE = "Pirate", TOTEM = "Totem" }
-- where the race banner and its word sit on a minion's face (the baker's
-- RACE_BANNER / RACE_BAND; used when CardText.lua is not loaded)
local RACE_CY = 0.893
local RACE_BANNER = { 0.18, 0.82, RACE_CY - 0.056, RACE_CY + 0.056 }

cardApplyBaked = function(w, r)
  local e, id = bakedEntry(w, r)
  w.baked = e and true or nil
  w.bakedHasText = e and e[2] or nil
  if e then
    local namePath, textPath = W.CardTextPaths(id)
    placeBand(w.bakedName, w, r, namePath, ns.CardText.name)
    if textPath then placeBand(w.bakedText, w, r, textPath, ns.CardText.text[e[1]]) end
    w.name:SetAlpha(0)
  else
    w.name:SetAlpha(1)
  end
  w.bakedName:SetShown(e and w.name:IsShown() or false)
  w.bakedText:SetShown(e and e[2] and w.body:IsShown() or false)
  -- the race line: a framed minion face with a race
  local d = w.descriptor or {}
  local label = w.skinned and not w.inPlay and d.type == "MINION" and W.RACE_LABELS[d.race or ""] or nil
  w.raceLabel = label
  if label then
    local ct = ns.CardText
    placeBand(w.raceBanner, w, r, ART .. "race-banner.tga", (ct and ct.raceBanner) or RACE_BANNER)
    if e then
      placeBand(w.bakedRace, w, r, ART .. "CardText\\" .. id .. "-r.tga", ct.race)
    else
      w.race:SetText(label)
      w.race:SetFont(FONT, math.max(6, math.floor(r.h * 0.052)), "OUTLINE")
      w.race:SetTextColor(1, 1, 1, 1)
      w.raceAt = { 0, r.h / 2 - r.h * RACE_CY }
      w.race:ClearAllPoints(); w.race:SetPoint("CENTER", w.frame, "CENTER", 0, w.raceAt[2])
    end
  end
  w.raceSync(w.name:IsShown())
end

local function cardApplyRect(w, r)
  local f = w.frame
  --[[ A card that may LEAN is drawn inside a larger frame, with its face inset
       by the room the turn needs (see W.SetLean). The frame grows rather than
       the face shrinking, so a leaning card is the same size as an upright
       one. `r.lean` is set by the binding for cards in a fan; everything else
       -- the board, the collection, the mulligan -- passes nothing and is
       unaffected. ]]
  --[[ A LEANING CARD IS ANCHORED BY ITS FACE, NOT BY ITS FRAME.

       The frame is bigger than the card -- that is the room the lean turns in
       -- so the frame's corner sits `pad` outside the card's. Anything that
       later re-anchors this widget has to apply the same offset or the card
       jumps sideways by that much.

       THE BUG THIS FIXES: the padding was dropped from the stored rect, so the
       tween that slides a hand into place, and the stage handle that nudges a
       card, both re-anchored WITHOUT it. Hovering a card re-applied its
       neighbours and they all shifted by a tenth of a card. `padX`/`padY` are
       kept on the widget so there is one answer to "where does this frame go",
       and `lean` survives the copy so a rect taken back off the widget still
       describes the same card. ]]
  local pad = r.lean and ((r.lean - 1) / 2) or 0
  w.padX, w.padY = r.w * pad, r.h * pad
  f:ClearAllPoints()
  f:SetSize(r.w * (1 + pad * 2), r.h * (1 + pad * 2))
  f:SetPoint("BOTTOMLEFT", w.frame:GetParent(), "BOTTOMLEFT",
             r.x - w.padX, r.y - w.padY)
  r = { x = r.x, y = r.y, w = r.w, h = r.h, rot = r.rot, lean = r.lean }

  local t = math.max(1, r.w * 0.035)   -- edge thickness scales with the card
  local e = w.edges
  e[1]:ClearAllPoints(); e[1]:SetPoint("BOTTOM", f, "CENTER", 0, -r.h / 2); e[1]:SetSize(r.w, t)
  e[2]:ClearAllPoints(); e[2]:SetPoint("TOP",    f, "CENTER", 0,  r.h / 2); e[2]:SetSize(r.w, t)
  e[3]:ClearAllPoints(); e[3]:SetPoint("LEFT",   f, "CENTER", -r.w / 2, 0); e[3]:SetSize(t, r.h)
  e[4]:ClearAllPoints(); e[4]:SetPoint("RIGHT",  f, "CENTER",  r.w / 2, 0); e[4]:SetSize(t, r.h)

  --[[ The card's face, centred in the frame. When the frame was grown to make
       room for a lean, this is what keeps the face the size it was meant to be
       and the lean turning about the middle of it. ]]
  w.skin:ClearAllPoints()
  w.skin:SetPoint("CENTER")
  w.skin:SetSize(r.w, r.h)
  w.bg:ClearAllPoints()
  w.bg:SetPoint("CENTER")
  w.bg:SetSize(r.w, r.h)
  w.back:ClearAllPoints()
  w.back:SetPoint("CENTER")
  w.back:SetSize(r.w, r.h)

  -- art occupies the upper portion; text the lower
  local faceX = -r.w / 2
  local faceY =  r.h / 2
  w.art:ClearAllPoints()
  w.art:SetPoint("TOPLEFT", f, "CENTER", faceX + t * 2, faceY - t * 2)
  w.art:SetSize(r.w - t * 4, r.h * 0.46)
  w.model:ClearAllPoints()
  w.model:SetPoint("TOPLEFT", f, "CENTER", faceX + t * 2, faceY - t * 2)
  w.model:SetSize(r.w - t * 4, r.h * 0.46)

  local fontH = math.max(6, math.floor(r.h * 0.085))
  w.cost:SetFont(FONT, math.floor(fontH * 1.5), "OUTLINE")
  w.name:SetFont(FONT, fontH, "OUTLINE")
  w.body:SetFont(BODY_FONT, math.max(5, math.floor(fontH * 0.82)), "")
  w.atk:SetFont(FONT, math.floor(fontH * 1.5), "OUTLINE")
  w.hp:SetFont(FONT, math.floor(fontH * 1.5), "OUTLINE")

  w.cost:ClearAllPoints(); w.cost:SetPoint("CENTER", f, "CENTER", faceX + t * 4, faceY - t * 4)
  w.name:ClearAllPoints(); w.name:SetPoint("TOP", f, "CENTER", 0, faceY - r.h * 0.50)
  w.nameAt = nil   -- set again below for a skinned card, whose name turns with a lean
  w.name:SetWidth(r.w - t * 4)
  w.body:ClearAllPoints(); w.body:SetPoint("TOP", f, "CENTER", 0, faceY - r.h * 0.62)
  w.body:SetWidth(r.w - t * 5)
  w.bodyAt = { 0, faceY - r.h * 0.62 }   -- the text box's top-centre (cardDrawRules)
  w.atk:ClearAllPoints(); w.atk:SetPoint("CENTER", f, "CENTER", faceX + t * 4, -faceY + t * 4)
  w.hp:ClearAllPoints();  w.hp:SetPoint("CENTER", f, "CENTER", -faceX - t * 4, -faceY + t * 4)

  w.gem:ClearAllPoints(); w.gem:SetPoint("TOP", f, "CENTER", 0, faceY - r.h * 0.455)
  w.gem:SetSize(r.w * 0.11, r.w * 0.11)

  w.glow:ClearAllPoints()
  w.glow:SetPoint("CENTER")
  w.glow:SetSize(r.w * 1.075, r.h * 1.075)
  if w.skinned then
    local minion = w.descriptor and w.descriptor.type == "MINION"
    w.art:ClearAllPoints()
    w.art:SetPoint("TOPLEFT", f, "CENTER",
                   faceX + r.w * (minion and 0.22 or 0.15),
                   faceY - r.h * (minion and 0.07 or 0.16))
    w.art:SetSize(r.w * (minion and 0.56 or 0.70), r.h * (minion and 0.46 or 0.37))
    --[[ Name banner and text plate, measured on the 256x512 frames: the
         ribbon's readable run is ~0.70 of the width at 0.57 down; the plate is
         0.665-0.845 across its full width -- below that the attack and health
         badges intrude (minions, weapons), so the text stops there. Spells
         have no badges and a taller plate. ]]
    local spell = w.descriptor and w.descriptor.type == "SPELL"
    local power = w.descriptor and w.descriptor.type == "HERO_POWER"
    local HP = W.HERO_POWER_CARD
    if power then
      w.art:ClearAllPoints()
      w.art:SetPoint("TOPLEFT", f, "CENTER", faceX + r.w * HP.art[1], faceY - r.h * HP.art[2])
      w.art:SetSize(r.w * HP.art[3], r.h * HP.art[4])
    end
    local nameY = power and HP.nameY or (292/512)
    w.name:ClearAllPoints()
    w.name:SetPoint("CENTER", f, "CENTER", 0, faceY - r.h * nameY)
    w.nameAt = { 0, faceY - r.h * nameY }   -- turned with a lean (cardSetLean)
    w.nameBox = { w = r.w * (power and HP.nameW or 0.70), h = r.h * 0.075, size = math.max(6, math.floor(r.h * 0.062)) }
    local bodyTop = power and HP.body.top or (spell and 0.675 or 0.665)
    w.body:ClearAllPoints()
    w.body:SetPoint("TOP", f, "CENTER", spell and r.w * 0.01 or 0, faceY - r.h * bodyTop)
    w.bodyAt = { spell and r.w * 0.01 or 0, faceY - r.h * bodyTop }
    w.bodyBox = { w = r.w * (power and HP.body.w or spell and 0.62 or 0.66),
                  h = r.h * (power and HP.body.h or spell and 0.215 or 0.18),
                  size = math.max(5, math.floor(r.h * (power and 0.058 or 0.052))) }
    -- dark ink on the minion and spell parchment; white on a weapon's dark slate
    if w.descriptor.type == "WEAPON" then
      w.body:SetTextColor(1, 1, 1, 1); w.bodyColor = { 1, 1, 1 }
    else
      w.body:SetTextColor(0.12, 0.08, 0.04, 1); w.bodyColor = { 0.12, 0.08, 0.04 }
    end
    local badgeSize = math.max(7, math.floor(r.h * 0.095))
    for _, label in ipairs({w.cost, w.atk, w.hp}) do label:SetFont(FONT, badgeSize, "OUTLINE") end
    -- Painted badge centers, measured in the 256x512 card canvas. The mana gem
    -- sits differently on each frame (tools: gem bbox per inhand_* texture).
    local kind = w.descriptor.type or "MINION"
    local gem = W.COST_GEM[kind] or W.COST_GEM.MINION
    local weapon = kind == "WEAPON"
    w.cost:ClearAllPoints(); w.cost:SetPoint("CENTER", f, "CENTER", faceX + r.w * (gem[1]/256), faceY - r.h * (gem[2]/512))
    w.atk:ClearAllPoints(); w.atk:SetPoint("CENTER", f, "CENTER", faceX + r.w * (38/256), faceY - r.h * ((weapon and 469 or 474)/512))
    -- Minion Attack and Health share a baseline; the droplet's pointed top
    -- should not push its number below the attack number.
    w.hp:ClearAllPoints(); w.hp:SetPoint("CENTER", f, "CENTER", faceX + r.w * ((weapon and 220 or 222)/256), faceY - r.h * ((weapon and 468 or 474)/512))
    -- the rarity gem, in its socket hanging from the name banner
    local sock = W.GEM_SOCKET[(w.descriptor.type or "MINION"):lower()] or W.GEM_SOCKET.minion
    w.gem:ClearAllPoints()
    w.gem:SetPoint("TOP", f, "CENTER", faceX + r.w * sock.cx, faceY - r.h * sock.top)
    w.gem:SetSize(r.w * sock.w, r.h * sock.h)
  else
    w.body:SetTextColor(1, 1, 1, 1); w.bodyColor = { 1, 1, 1 }
  end
  if not w.skinned then
    w.nameBox = { w = r.w * 0.86, h = r.h * 0.075, size = fontH }
    w.bodyBox = { w = r.w - t * 5, h = r.h * 0.28, size = math.max(5, math.floor(fontH * 0.82)) }
  end
  W.FitText(w.name, { w = w.nameBox.w, h = w.nameBox.h, font = FONT, size = w.nameBox.size,
                      min = math.max(5, math.floor(w.nameBox.size * 0.55)), flags = "OUTLINE" })
  w.name:SetJustifyH("CENTER")
  W.FitText(w.body, { w = w.bodyBox.w, h = w.bodyBox.h, font = BODY_FONT, size = w.bodyBox.size,
                      min = math.max(4, math.floor(w.bodyBox.size * 0.6)), lines = 6 })
  w.body:SetJustifyH("CENTER"); w.body:SetJustifyV("MIDDLE")
  cardApplyBaked(w, r)
  cardDrawRules(w)
  if w.inPlay then
    w.cost:Hide(); w.name:Hide(); w.body:Hide(); w.gem:Hide()
    w.bakedName:Hide(); w.bakedText:Hide(); w.raceBanner:Hide(); w.bakedRace:Hide(); w.race:Hide()
    w.bg:Hide()
    -- The native square contains generous transparent margins. Enlarge the
    -- canvas within the slot so the visible oval, rather than padding, fills it.
    local r = {w=r.w*1.25, h=r.h*1.25}
    local golden = w.descriptor and w.descriptor.golden
    local art = ns.HearthstoneArt or {}
    w.skin:SetTexture(golden and art.inplay_minion_premium or art.inplay_minion)
    w.taunt:SetTexture(ART .. (golden and "inplay_minion_taunt_premium" or "inplay_minion_taunt") .. ".tga")
    w.skin:Show()
    w.skin:ClearAllPoints(); w.skin:SetPoint("CENTER"); w.skin:SetSize(r.w,r.h)
    -- the taunt shield, if this minion has one, was settled by its live stats
    cardFitGlow(w, w.taunt:IsShown())
    w.art:ClearAllPoints()
    w.art:SetPoint("CENTER", f, "CENTER", 0, r.h * (8/256))
    w.art:SetSize(r.w * (142/256), r.h * (170/256))
    w.atk:ClearAllPoints(); w.atk:SetPoint("CENTER", f, "CENTER", r.w * (75/256-0.5), r.h * (0.5-177/256))
    w.hp:ClearAllPoints(); w.hp:SetPoint("CENTER", f, "CENTER", r.w * (179/256-0.5), r.h * (0.5-177/256))
    --[[ Hearthstone's board digits are as tall as their gems and spill past
         them, under a heavy black outline. At .085 with a thin outline they
         read as 8px scratches in the first in-client tour (docs/39). ]]
    for _, badge in ipairs({w.atk,w.hp}) do badge:SetFont(FONT, math.max(10,r.h*0.13), "THICKOUTLINE") end
    w.taunt:ClearAllPoints(); w.taunt:SetPoint("CENTER", f, "CENTER", 0, 0)
    w.taunt:SetSize(r.w, r.h)
    w.shield:ClearAllPoints(); w.shield:SetAllPoints(w.skin)
    w.status:ClearAllPoints(); w.status:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    w.status:SetFont(FONT, math.max(10, r.h * 0.14), "OUTLINE")
  end
  --[[ THE LEGENDARY DRAGON. Hand and board frames each have their own, and a
       golden card has a gold one. There is no weapon dragon in the source, so a
       legendary weapon keeps its plain frame rather than borrowing a minion's. ]]
  local d = w.descriptor
  local legend
  if d and d.rarity == "LEGENDARY" and (w.skinned or w.inPlay) then
    local art = ns.HearthstoneArt or {}
    local base = w.inPlay and "inplay_minion_legendary"
      or ("inhand_" .. (d.type or "MINION"):lower() .. "_legendary")
    legend = (d.golden and art[base .. "_premium"]) or art[base]
  end
  if legend then w.legend:SetTexture(legend); w.legend:Show() else w.legend:Hide() end
  w.rect = r
  for _, number in ipairs({w.cost,w.atk,w.hp}) do
    number:SetCanvas(w.skin:GetWidth(), w.skin:GetHeight())
  end
  cardSetLean(w, r.rot or 0)
  W.FitArt(w, w.inPlay and BOARD_ART_WINDOW or nil)
  if w.faceDown then cardSetFaceDown(w,true) end
end

--[[ Apply a resolver descriptor. Everything here degrades: if `icon` is a bad
     path the art simply does not draw, and the card is still fully readable
     because name, cost and stats are text. That is the guarantee from
     docs/06 §6.1, expressed in the one place it has to hold. ]]
local function cardSetDescriptor(w, d)
  if w.faceDown then cardSetFaceDown(w,false) end
  for _, label in ipairs({w.cost, w.name, w.body, w.atk, w.hp}) do label:Show() end
  w.back:Hide()
  w.taunt:Hide(); w.shield:Hide()
  for _, t in pairs(w.states) do t:Hide() end
  w.faceDown = false
  w.art:SetRotation(0)
  w.art:SetTexCoord(0, 1, 0, 1)
  --[[ Reset what SetLiveStats may have left on a pooled widget. A card that
       was a frozen minion last frame must not arrive in the next hand still
       tinted blue -- the pool reuses frames, so anything set per-state has to
       be cleared per-state. ]]
  w.art:SetVertexColor(1, 1, 1, 1)
  w.atk:SetTextColor(1, 1, 1, 1)
  w.hp:SetTextColor(1, 1, 1, 1)
  local art = ns.HearthstoneArt or {}
  local kind = (d.type or "MINION"):lower()
  local cls = (d.class or "NEUTRAL"):lower()
  -- A golden card has one gold frame whatever its class, as in Hearthstone.
  local skin = (d.golden and art["inhand_" .. kind .. "_premium"])
    or art["inhand_" .. kind .. "_" .. cls] or art["inhand_" .. kind .. "_neutral"]
  if kind == "hero_power" then
    -- Hearthstone's hero-power card (tools/import_card_extras.py), one frame
    -- for every class; hovering a hero power showed a bare black box before
    skin = ART .. (d.golden and "inhand_hero_power_premium.tga" or "inhand_hero_power.tga")
  end
  w.skinned = skin ~= nil and not d.model
  w.artMask:SetTexture(ART .. ((kind == "minion" or kind == "hero_power") and "mask-oval" or "mask-rect") .. ".tga")
  if w.skinned then
    -- the hero-power frame has no glow sheet of its own
    w.skin:SetTexture(skin); w.glow:SetTexture(kind ~= "hero_power" and skin:gsub("%.tga$", "-glow.tga") or nil)
    w.skin:Show(); w.bg:Hide()
    for _, edge in ipairs(w.edges) do edge:Hide() end
  else
    w.skin:Hide(); w.bg:Show()
    for _, edge in ipairs(w.edges) do edge:Show() end
  end
  local fc = d.frameColor or { 0.5, 0.5, 0.5 }
  for _, e in ipairs(w.edges) do e:SetVertexColor(fc[1], fc[2], fc[3], 1) end
  local gc = d.gemColor or { 0.6, 0.6, 0.6 }
  local socketed = w.skinned and W.GEM_SOCKET[kind] and W.GEM_RARITIES[d.rarity or ""]
  if w.skinned then
    --[[ Hearthstone's own gem, set in its socket (import_rarity_gems.py).
         Basic ("FREE") cards have none, exactly as in Hearthstone. ]]
    if socketed then
      w.gem:SetTexture(ART .. "rarity-" .. kind .. "-" .. d.rarity:lower() .. ".tga")
      w.gem:SetVertexColor(1, 1, 1, 1)
    end
    w.gem:SetShown(socketed and true or false)
  elseif w.gemShaped then
    w.gem:SetTexture((ns.HearthstoneArt or {}).gem); w.gem:Show()
    w.gem:SetVertexColor(gc[1], gc[2], gc[3], 1)
  else
    -- No gem texture installed: a coloured pip is still legible, just square.
    w.gem:SetColorTexture(gc[1], gc[2], gc[3], 1)
  end

  if d.model then
    w.art:Hide()
    w.model:Show()
    w.model:SetDisplayInfo(d.model)
  else
    w.model:Hide()
    w.art:Show()
    if d.icon then w.art:SetTexture(d.icon) else w.art:SetTexture(nil) end
  end

  w.cost:SetText(d.cost and tostring(d.cost) or "")
  w.name:SetText(d.name or "")
  w.liveSpellText = nil
  w.rulesText = d.text or ""
  -- the data prefixes a hero power's text with its type; the card does not
  if d.type == "HERO_POWER" then w.rulesText = w.rulesText:gsub("^<b>Hero Power</b>%s*", "") end
  w.body:SetText(W.PlainText(w.rulesText))
  cardDrawRules(w)
  if d.type == "MINION" then
    w.atk:SetText(tostring(d.atk or 0))
    w.hp:SetText(tostring(d.hp or 0))
  elseif d.type == "WEAPON" then
    w.atk:SetText(tostring(d.atk or 0))
    w.hp:SetText(tostring(d.dur or 0))
  else
    w.atk:SetText("")
    w.hp:SetText("")
  end
  w.descriptor = d
  if w.rect then cardApplyRect(w, w.rect) end
end

--[[ THE LIVE STATE OF A MINION, over the top of its printed card.

     A descriptor is what the card was PRINTED as, and a minion on the board is
     not its card: it has taken damage, been buffed, been frozen, been silenced.
     Nothing applied any of that, so the board drew the printed 3/2 of something
     that was currently a 5/1 -- you hit a minion and the number under it did
     not move, which reads as the damage not having happened.

     `st` comes from the controller's snapshot and is numbers only, never an
     entity. Absent `st` leaves the printed values alone, which is what the
     collection screen wants. ]]
local function cardSetLiveStats(w, st)
  if not st then return end
  local d = w.descriptor or {}
  local text = st.rulesText or d.text or ""
  if text ~= w.rulesText then
    w.rulesText = text
    w.liveSpellText = text ~= (d.text or "") or nil
    w.body:SetText(W.PlainText(text))
    cardDrawRules(w)
    if w.rect then cardApplyRect(w, w.rect) end
  end
  w.status:SetText("")
  if st.taunt then w.taunt:Show() else w.taunt:Hide() end
  if w.inPlay and (st.taunt and true or false) ~= w.glowTaunt then cardFitGlow(w, st.taunt) end
  if st.divineShield then w.shield:Show() else w.shield:Hide() end
  --[[ Portrait states are board art; a hand card carries the same live stats
       for its cost and numbers but must not sprout a Zzz. Hearthstone shows one
       icon under the portrait, and a Deathrattle takes precedence. ]]
  for key, t in pairs(w.states) do
    local on = w.inPlay and st[key]
    if key == "trigger" and st.deathrattle then on = false end
    if on then t:Show() else t:Hide() end
  end
  -- a spell has no stats: writing them put "0" and "1" on an enlarged Fireball
  local hasStats = d.type == "MINION" or d.type == "WEAPON"
  if hasStats then
  w.atk:SetText(tostring(st.atk or 0))
  w.hp:SetText(tostring(st.health or 0))

  --[[ COLOUR CARRIES THE DIFFERENCE FROM PRINTED. Red health means damaged,
       green means buffed above the card. Without it a 2/1 Yeti and a damaged
       4/5 Yeti are the same two glyphs and you have to remember which is
       which -- and remembering is the thing the board exists to spare you. ]]
  if st.damaged then
    w.hp:SetTextColor(1, 0.35, 0.30, 1)
  elseif d.hp and (st.maxHealth or 0) > d.hp then
    w.hp:SetTextColor(0.40, 1, 0.45, 1)
  else
    w.hp:SetTextColor(1, 1, 1, 1)
  end
  if d.atk and (st.atk or 0) > d.atk then
    w.atk:SetTextColor(0.40, 1, 0.45, 1)
  elseif d.atk and (st.atk or 0) < d.atk then
    w.atk:SetTextColor(1, 0.55, 0.35, 1)
  else
    w.atk:SetTextColor(1, 1, 1, 1)
  end
  end -- hasStats

  --[[ Frozen is a blue wash over the art and stealth is transparency: both are
       states you must be able to see without reading, because both change what
       you are allowed to do to the minion. ]]
  if st.frozen then
    w.art:SetVertexColor(0.70, 0.85, 1.0, 1)
  else
    w.art:SetVertexColor(1, 1, 1, 1)
  end
  -- The native stealth shroud carries the state now; fading the whole frame
  -- as well would also fade the numbers you still need to read.
  w.frame:SetAlpha((st.stealth and not w.states.stealth) and 0.55 or 1)
end

--[[ Turn a card face down, or back up. The back covers everything rather than
     the text being blanked, because a reveal only works if there is genuinely
     nothing to read beforehand. ]]
cardSetFaceDown = function(w, down)
  if down then
    -- The back has transparent corners. Hide the entire front, including art
    -- and stat ornaments, rather than relying on an opaque rectangular cover.
    local regions={w.cost,w.name,w.body,w.atk,w.hp,w.art,w.skin,w.bg,w.gem,
      w.model,w.status,w.taunt,w.shield,w.legend}
    -- (the baked name and rules bands follow w.name and w.body, see makeCard)
    for _,edge in ipairs(w.edges) do regions[#regions+1]=edge end
    for _,state in pairs(w.states) do regions[#regions+1]=state end
    if w.ownedCount then regions[#regions+1]=w.ownedCount end
    w.faceVisibility=w.faceVisibility or {}
    for _,region in ipairs(regions) do
      if w.faceVisibility[region]==nil then w.faceVisibility[region]=region:IsShown() end
      region:Hide()
    end
    w.back:Show(); w.back:SetDrawLayer("OVERLAY",7)
  else
    for region,shown in pairs(w.faceVisibility or {}) do
      if shown then region:Show() else region:Hide() end
    end
    w.faceVisibility=nil
    w.back:Hide()
  end
  w.faceDown=down and true or false
end

--[[ AN INVISIBLE HIT AREA.

     THE BUG THIS EXISTS FOR: the hand card frame was both the picture and the
     mouse target. Hovering one made it grow and lift, which moved it out from
     under the pointer, which fired OnLeave, which shrank it back under the
     pointer, which fired OnEnter -- a card that flickered, jumped, or vanished
     as you tried to look at it. Every hover also ran a full relayout, so the
     whole hand was released back to the pool and re-acquired mid-gesture.

     Splitting them fixes it by construction: this frame sits at the card's
     RESTING rect and never moves, so the pointer's relationship to it does not
     change while the picture animates. The picture stops taking the mouse
     entirely and is free to move however it likes. ]]
local function makeHitArea(parent)
  local f = CreateFrame("Button", nil, parent)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  return { frame = f }
end

local function hitAreaApply(w, r, parent, level)
  local f = w.frame
  f:ClearAllPoints()
  f:SetSize(r.w, r.h)
  f:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", r.x, r.y)
  if level then f:SetFrameLevel(level) end
  w.rect = r
end

--[[ CAN YOU PLAY IT -- THE GREEN BORDER, AND NOTHING ELSE.

     Hearthstone never fades a card you cannot play and never recolours its
     cost: a playable card gets the green glow (Board draws it) and a card you
     cannot play simply does not. Earlier passes dimmed unplayable cards to 62%
     and turned the cost red; both read as "broken" rather than "not now", and
     neither is something Hearthstone does. So this only resets what a pooled
     widget may have carried in. `playable`/`affordable` are kept in the
     signature because Board passes them and the glow logic keys on them. ]]
local function cardSetPlayable(w, playable, affordable)
  w.cost:SetTextColor(1, 1, 1, 1)
  w.frame:SetAlpha(1)
  w.playable = playable
end

W.SetPlayable = cardSetPlayable

--[[ A CARD YOU DO NOT OWN, as Hearthstone's crafting view shows one: drained
     of colour and a little dark, but solid. Fading the whole card to 45%, as
     the collection used to, let the parchment show through the art and the
     rules text, which read as a rendering fault rather than "not yours". ]]
function W.SetGhost(w, ghost)
  local v = ghost and .62 or 1
  for _, t in ipairs({ w.art, w.skin, w.gem, w.legend, w.bg }) do
    if t then
      if t.SetDesaturated then t:SetDesaturated(ghost and true or false) end
      t:SetVertexColor(v, v, v, 1)
    end
  end
  w.frame:SetAlpha(ghost and .88 or 1)
  w.ghost = ghost or nil
end
W.NewHitArea = makeHitArea
W.ApplyHitArea = hitAreaApply

-- Rotate the frame as one object so artwork, masks, and text share a pivot.
local MAX_LEAN = 0.14      -- radians; the outermost card of a full hand

local function leanInset(aspect)
  return math.cos(MAX_LEAN) + aspect * math.sin(MAX_LEAN)
end

function cardSetLean(w, rot)
  rot = math.max(-MAX_LEAN, math.min(MAX_LEAN, rot or 0))
  w.lean = rot
  for _, number in ipairs({w.cost,w.atk,w.hp}) do number:SetLean(rot) end
  w.anim:Stop()
  w.rotation:SetDegrees(rot * 180 / math.pi)
  if math.abs(rot) > 0.0001 then w.anim:Play() end
  --[[ Text regions turn about their own centres in the client, so their
       centres are moved to where they fall on the turned card (see
       W.RichText): the rules text word by word, and the name. ]]
  if w.bodyRich then w.bodyRich:SetRotation(rot) end
  local na = rawget(w, "nameAt")
  if na then
    local c, s = math.cos(rot), math.sin(rot)
    w.name:ClearAllPoints()
    w.name:SetPoint("CENTER", w.frame, "CENTER", na[1] * c - na[2] * s, na[1] * s + na[2] * c)
  end
  local ra = rawget(w, "raceAt")
  if ra and rawget(w, "raceLabel") and not rawget(w, "baked") then
    local c, s = math.cos(rot), math.sin(rot)
    w.race:ClearAllPoints()
    w.race:SetPoint("CENTER", w.frame, "CENTER", ra[1] * c - ra[2] * s, ra[1] * s + ra[2] * c)
  end

end

W.New = makeCard
W.SetLean = cardSetLean
W.LeanInset = leanInset
W.MAX_LEAN = MAX_LEAN
W.ApplyRect = cardApplyRect
W.SetDescriptor = cardSetDescriptor
W.SetLiveStats = cardSetLiveStats
W.SetFaceDown = cardSetFaceDown

--[[ The old export name. Client/UI/Collection.lua captured `ns.CardWidget` from
     Board back when the card code lived there; keeping the alias means the two
     screens cannot drift onto different card code by accident. ]]
ns.CardWidget = {
  New = makeCard, ApplyRect = cardApplyRect, SetDescriptor = cardSetDescriptor,
  SetLiveStats = cardSetLiveStats, SetFaceDown = cardSetFaceDown,
  SetPlayable = cardSetPlayable,
  NewPool = newPool, Acquire = poolAcquire, ReleaseAll = poolReleaseAll,
}

-- =============================================================== portraits

--[[ A HERO: portrait, health, armour and attack.

     The board had none of these until now -- Layout computed rects for both
     heroes, both hero powers and both weapons, and Board drew none of them, so
     a "board" was a row of minions with nothing to attack. This is most of what
     makes the screen read as Hearthstone rather than as a list. ]]
local function makePortrait(parent, skinKey)
  local f = CreateFrame("Button", nil, parent)
  f:EnableMouse(true)
  f:RegisterForClicks("LeftButtonUp")
  --[[ A hero power is AIMED, and aiming in Hearthstone is a drag. Registering
       here rather than only on the hero power keeps every portrait the same
       kind of thing; the ones nothing listens on simply never fire. ]]
  f:RegisterForDrag("LeftButton")
  local w = { frame = f }

  w.bg = f:CreateTexture(nil, "BACKGROUND")
  w.bg:SetAllPoints()
  w.bg:SetColorTexture(0.12, 0.11, 0.14, 1)

  w.art = f:CreateTexture(nil, "ARTWORK")
  w.artMask = mask(f, w.art, "mask-oval")
  w.skinKey = skinKey or "hero_frame"
  local skin = skinKey ~= false and (ns.HearthstoneArt or {})[skinKey or "hero_frame"]
  if skinKey == "inplay_weapon" then skin=ART .. "inplay_weapon.tga" end
  if skin then
    w.skin = f:CreateTexture(nil, "ARTWORK", nil, 1)
    w.skin:SetAllPoints()
    w.skin:SetTexture(skin)
    w.bg:Hide()
  end

  --[[ The ring is four edges, like a card's, so a hero needs no border art.
       It turns red when the hero is a legal target, which is the single most
       useful piece of feedback on the whole board. ]]
  w.edges = {}
  for i = 1, 4 do
    local e = f:CreateTexture(nil, "BORDER")
    e:SetColorTexture(0.8, 0.75, 0.5, 1)
    w.edges[i] = e
    if w.skin then e:Hide() end
  end

  w.health = f:CreateFontString(nil, "OVERLAY")
  w.armor  = f:CreateFontString(nil, "OVERLAY")
  w.armorBadge = f:CreateTexture(nil, "ARTWORK", nil, 2)
  w.armorBadge:SetTexture(ART .. "hero_armor.tga")
  w.armorBadge:Hide()
  w.attackBadge = f:CreateTexture(nil, "ARTWORK", nil, 2)
  w.attackBadge:SetTexture(ART .. "hero_attack.tga")
  w.attackBadge:SetAllPoints(f); w.attackBadge:Hide()
  w.atk    = f:CreateFontString(nil, "OVERLAY")
  for _, label in ipairs({w.health, w.armor, w.atk}) do
    label:SetFont(NUMBER_FONT, 12, "OUTLINE")
  end
  --[[ Hearthstone's hero states share the hero frame's canvas, and the spent
       hero power is the token's own reverse face on the power's canvas, so
       all three cover the whole portrait with no offsets. ]]
  local function cover(file, sub)
    local t = f:CreateTexture(nil, "OVERLAY", nil, sub)
    t:SetTexture(ART .. file .. ".tga"); t:SetAllPoints(f); t:Hide()
    return t
  end
  if w.skinKey == "hero_frame" then
    w.frozenFx = cover("inplay_hero_frozen", 1)
    w.immuneFx = cover("inplay_hero_immune", 1)
  elseif w.skinKey == "hero_power" then
    w.spentFx = cover("hero_power_exhausted", 2)
  end
  w.glow   = f:CreateTexture(nil, "BACKGROUND", nil, -1)
  w.glow:SetTexture(skin or ART .. "status-shield.tga")
  w.glow:SetBlendMode("ADD")
  w.glow:SetVertexColor(1, 1, 1, 0)
  w.glow:Hide()
  return w
end

local function portraitApply(w, r, parent)
  local f = w.frame
  w.gen = (w.gen or 0) + 1
  f:SetAlpha(1)
  f:SetScale(1)
  f:ClearAllPoints()
  f:SetSize(r.w, r.h)
  f:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", r.x, r.y)
  local t = math.max(1, r.w * 0.04)
  local e = w.edges
  e[1]:ClearAllPoints(); e[1]:SetPoint("BOTTOMLEFT"); e[1]:SetSize(r.w, t)
  e[2]:ClearAllPoints(); e[2]:SetPoint("TOPLEFT");    e[2]:SetSize(r.w, t)
  e[3]:ClearAllPoints(); e[3]:SetPoint("BOTTOMLEFT"); e[3]:SetSize(t, r.h)
  e[4]:ClearAllPoints(); e[4]:SetPoint("BOTTOMRIGHT");e[4]:SetSize(t, r.h)

  --[[ THE PORTRAIT SITS INSIDE THE FRAME'S WINDOW, not across the whole frame.

       The hero frame art is an ornate surround with a window cut in the middle
       of it. Filling the frame's full rect with the portrait painted the
       illustration over the ornament -- the background ran past the border on
       every side, which is precisely what it looked like. The window is a
       little above centre, as the art draws it, so the inset is not
       symmetrical. ]]
  local inset = w.skin and 0.30 or 0.08
  w.artMask:SetTexture(ART .. (w.skinKey == "inplay_weapon" and "mask-oval" or (w.skin and ("mask-" .. w.skinKey) or "mask-rect")) .. ".tga")
  local aw = math.max(1, r.w * (1 - inset))
  local ah = math.max(1, r.h * (1 - inset))
  w.art:ClearAllPoints()
  w.art:SetPoint("CENTER", f, "CENTER", 0, w.skin and r.h * 0.06 or 0)
  w.art:SetSize(aw, ah)
  if w.skin then
    w.art:ClearAllPoints()
    w.art:SetPoint("CENTER", f, "CENTER", 0, 0)
    w.art:SetSize(r.w, r.h)
  end

  local fh = math.max(8, math.floor(r.h * 0.20))
  w.health:SetFont(NUMBER_FONT, fh, "OUTLINE")
  w.armorSize = math.floor(fh * 0.8)
  w.armor:SetFont(NUMBER_FONT, w.armorSize, "OUTLINE")
  w.atk:SetFont(NUMBER_FONT, fh, "OUTLINE")
  w.health:ClearAllPoints(); w.health:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -t, t)
  w.armor:ClearAllPoints();  w.armor:SetPoint("TOPRIGHT", f, "TOPRIGHT", -t, -t)
  if w.skinKey == "hero_frame" then
    w.health:ClearAllPoints()
    --[[ Between the red drop's round bulb and the middle of its box
         (hero_frame.tga: the drop runs .031 to .172 up, its bulb centred near
         .09), lowered by the digit rise. At the box's middle (.109) the number
         read as too high; on the bulb (.092) as too low. Across, .838 puts the
         ink on the drop's axis -- at .83 in game it sat two pixels left. ]]
    local healthSize = math.max(16,math.floor(r.h*.16+.5))
    w.health:SetPoint("CENTER", f, "BOTTOMLEFT", r.w*.838, r.h*.101 - healthSize*W.DIGIT_RISE)
    w.health:SetWidth(math.max(44,r.w*.32)); w.health:SetHeight(math.max(28,r.h*.24)); w.health:SetWordWrap(false); w.health:SetJustifyH("CENTER")
    w.health:SetFont(NUMBER_FONT,healthSize,"OUTLINE")
    w.armorBadge:ClearAllPoints()
    w.armorBadge:SetAllPoints(f)
    --[[ On the shield's face: hero_armor.tga's shield is centred at .84 across
         and .356 up; its point below lifts the face's middle a little. At .85,
         .35 a lone digit sat visibly right of and below the middle, which two
         digits filling the shield hid. ]]
    w.armorSize = math.max(12, math.floor(r.h*.16+.5))
    w.armor:ClearAllPoints(); w.armor:SetPoint("CENTER",f,"BOTTOMLEFT",r.w*.84,r.h*.362 - w.armorSize*W.DIGIT_RISE)
    w.armor:SetWidth(math.max(40,r.w*.30)); w.armor:SetHeight(math.max(26,r.h*.22)); w.armor:SetWordWrap(false); w.armor:SetJustifyH("CENTER")
  end
  w.atk:ClearAllPoints();    w.atk:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", t, t)
  if w.skinKey == "hero_frame" then
    w.atk:ClearAllPoints(); w.atk:SetPoint("CENTER",f,"BOTTOMLEFT",r.w*.15,r.h*.095 - fh*W.DIGIT_RISE)
  elseif w.skinKey == "inplay_weapon" then
    w.art:ClearAllPoints(); w.art:SetPoint("CENTER",f,"CENTER",0,r.h*.035); w.art:SetSize(r.w*.7,r.h*.7)
    w.atk:ClearAllPoints(); w.atk:SetPoint("CENTER",f,"BOTTOMLEFT",r.w*.20,r.h*.27)
    w.health:ClearAllPoints(); w.health:SetPoint("CENTER",f,"BOTTOMLEFT",r.w*.80,r.h*.27)
    w.health:SetWidth(math.max(44,r.w*.32)); w.health:SetHeight(math.max(28,r.h*.24)); w.health:SetWordWrap(false)
  end
  w.glow:ClearAllPoints()
  w.glow:SetPoint("CENTER", f, "CENTER", 0, 0)
  w.glow:SetSize(r.w * 1.075, r.h * 1.075)
  w.rect = r
end

--[[ `c` is the character table from the controller's snapshot -- numbers, never
     an entity. Armour is HIDDEN at zero rather than shown as "0", because a
     permanent 0 next to every hero is noise that trains the eye to ignore the
     one place the number matters. ]]
local function portraitSet(w, c, icon, color)
  w.armorBadge:Hide()
  w.attackBadge:Hide()
  if w.frozenFx then
    if c and c.frozen then w.frozenFx:Show() else w.frozenFx:Hide() end
    if c and c.immune then w.immuneFx:Show() else w.immuneFx:Hide() end
  end
  if icon then w.art:SetTexture(icon) else w.art:SetTexture(nil) end
  local col = color or { 0.8, 0.75, 0.5 }
  for _, e in ipairs(w.edges) do e:SetVertexColor(col[1], col[2], col[3], 1) end
  if not c then
    w.health:SetText(""); w.armor:SetText(""); w.atk:SetText("")
    return
  end
  w.health:SetText(tostring(c.health or 0))
  -- red when damaged, as Hearthstone draws a hero's Health (and a minion's)
  if c.maxHealth and (c.health or 0) < c.maxHealth then w.health:SetTextColor(1, 0.35, 0.30)
  else w.health:SetTextColor(1, 1, 1) end
  w.armor:SetText((c.armor or 0) > 0 and tostring(c.armor) or "")
  -- two digits shrink to stay on the shield, as the cards' numbers do
  if w.armorSize then
    w.armor:SetFont(NUMBER_FONT, math.floor(w.armorSize * ((c.armor or 0) >= 10 and 0.84 or 1)), "OUTLINE")
  end
  if w.skinKey == "hero_frame" and (c.armor or 0)>0 then w.armorBadge:Show() end
  w.atk:SetText((c.atk or 0) > 0 and tostring(c.atk) or "")
  if w.skinKey == "hero_frame" and (c.atk or 0)>0 then w.attackBadge:Show() end
end

--[[ THE HERO POWER'S ART FITS THE RING'S WINDOW. The art texture spans the
     whole token and mask-hero_power cuts out the window, which is only the
     middle half of hero_power.tga (measured: .230-.773 across, .293-.813 down).
     Drawn 0..1 over the token, the board showed the middle half of the
     picture -- visibly zoomed beside the hover card. Map the same crop the
     hover card uses (W.ArtCoords) onto the window instead; what spills outside
     it is under the ring and masked away. ]]
W.POWER_WINDOW = { .230, .773, .293, .813 }
function W.FitPowerArt(w, cardId)
  local r = w.rect
  if not (r and cardId and w.skinKey == "hero_power") then w.art:SetTexCoord(0, 1, 0, 1); return end
  local x0, x1, y0, y1 = unpack(W.POWER_WINDOW)
  local u0, u1, v0, v1 = W.ArtCoords(cardId, r.w * (x1 - x0), r.h * (y1 - y0))
  local su, sv = (u1 - u0) / (x1 - x0), (v1 - v0) / (y1 - y0)
  w.art:SetTexCoord(u0 - x0 * su, u0 + (1 - x0) * su, v0 - y0 * sv, v0 + (1 - y0) * sv)
end

--[[ A DECK, as Hearthstone draws it: a stack lying in its slot on the rail --
     the top card's back facing you, the gilded edges of the rest beside it.
     The edges thin as you draw and the slot is empty when the deck is. There
     is no number on it; the count is for hovering (Board shows it).

     Proportions are the painted decks the board art shipped with, measured in
     the slot: back in the left 39%, edges up to half the slot's width beyond
     it at a full thirty cards, overhanging the rail as Hearthstone's do. ]]
local DECK_FULL = 30
local function makeDeckStack(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:EnableMouse(true)
  local w = { frame = f }
  w.shadow = f:CreateTexture(nil, "BACKGROUND")
  w.shadow:SetColorTexture(0, 0, 0, 0.35)
  w.pages = f:CreateTexture(nil, "ARTWORK")
  w.pages:SetTexture(ART .. "deck-pages.tga")
  w.back = f:CreateTexture(nil, "ARTWORK", nil, 1)
  local art = ns.HearthstoneArt or {}
  if art.cardback then w.back:SetTexture(art.cardback) else w.back:SetColorTexture(0.16, 0.13, 0.28, 1) end
  w.back:SetVertexColor(0.92, 0.92, 0.92, 1)
  return w
end

local function deckStackApply(w, r, parent, count)
  local f = w.frame
  f:ClearAllPoints()
  f:SetSize(r.w, r.h)
  f:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", r.x, r.y)
  count = math.max(0, count or 0)
  w.count = count
  if count == 0 then
    w.back:Hide(); w.pages:Hide(); w.shadow:Hide()
    return
  end
  local h = r.h * 0.96
  local backW = r.w * 0.39
  w.back:ClearAllPoints()
  w.back:SetPoint("LEFT", f, "LEFT", r.w * 0.05, 0)
  w.back:SetSize(backW, h)
  -- one card is still a sliver of edge; a full deck is half the slot wide
  local frac = math.min(1, count / DECK_FULL)
  local pagesW = math.max(r.w * 0.035, r.w * 0.5 * frac)
  w.pages:ClearAllPoints()
  w.pages:SetPoint("LEFT", w.back, "RIGHT", 0, 0)
  w.pages:SetSize(pagesW, h)
  w.pages:SetTexCoord(0, math.min(1, pagesW / (r.w * 0.5)), 0, 1)
  w.shadow:ClearAllPoints()
  w.shadow:SetPoint("LEFT", w.pages, "RIGHT", 0, -r.h * 0.01)
  w.shadow:SetSize(math.max(1, r.w * 0.035), h * 0.97)
  w.back:Show(); w.pages:Show(); w.shadow:Show()
end

W.NewDeckStack = makeDeckStack
W.ApplyDeckStack = deckStackApply

--[[ A spent hero power turns over to its reverse face, as in Hearthstone,
     instead of fading: the art and cost vanish and the token's back shows. ]]
local function portraitSetSpent(w, spent)
  if not w.spentFx then return end
  if spent then
    w.spentFx:Show(); w.art:Hide(); w.armor:Hide()
    if w.skin then w.skin:Hide() end
  else
    w.spentFx:Hide(); w.art:Show(); w.armor:Show()
    if w.skin then w.skin:Show() end
  end
end

W.NewPortrait = makePortrait
W.SetPowerSpent = portraitSetSpent
W.ApplyPortrait = portraitApply

--[[ A hero power's cost, on the gem crowning its ring. hero_power.tga's gem
     runs 10..70 down and 93..159 across (the pale facet reaches 162), so its
     middle is .156 down and on the axis. The old -.15 with no digit rise put
     the ink a pixel and a half above the middle, and at .16 of the height the
     digit left a wide blue margin that made the offset read as off-centre. ]]
function W.PlacePowerCost(w, r)
  local size = math.max(10, math.floor(r.h * 0.19 + 0.5))
  w.armor:SetFont(NUMBER_FONT, size, "OUTLINE")
  w.armor:ClearAllPoints()
  w.armor:SetPoint("CENTER", w.frame, "TOP", 0, -r.h * 0.156 - size * W.DIGIT_RISE)
end
W.SetPortrait = portraitSet

-- =========================================================== mana crystals

--[[ Mana. Ten slots, filled / spent / locked by Overload, and a "7/10" readout
     for when the crystals are too small to count at a glance.

     Overload is drawn as its own colour rather than as a missing crystal
     because "why do I have less mana than last turn" is exactly the question
     the board should answer without being asked. ]]
local function makeCrystal(parent)
  local f = CreateFrame("Frame", nil, parent)
  local w = { frame = f }
  w.tex = f:CreateTexture(nil, "ARTWORK")
  w.tex:SetAllPoints()
  w.tex:SetColorTexture(0.2, 0.45, 0.95, 1)
  return w
end

local CRYSTAL = {
  full   = { 0.25, 0.55, 1.00 },
  spent  = { 0.12, 0.16, 0.28 },
  locked = { 0.55, 0.20, 0.20 },
}

local function crystalApply(w, r, parent, state)
  local f = w.frame
  f:ClearAllPoints()
  f:SetSize(r.w, r.h)
  f:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", r.x, r.y)
  local c = CRYSTAL[state or "full"] or CRYSTAL.full
  w.tex:SetColorTexture(c[1], c[2], c[3], 1)
  if ns.HearthstoneArt and ns.HearthstoneArt.mana_crystal then
    w.tex:SetTexture(ns.HearthstoneArt.mana_crystal)
    if state == "full" then w.tex:SetVertexColor(1, 1, 1, 1)
    else w.tex:SetVertexColor(c[1], c[2], c[3], 1) end
  end
end

W.NewCrystal = makeCrystal
W.ApplyCrystal = crystalApply

-- ================================================================ the arrow

--[[ THE TARGETING ARROW.

     Aiming with no arrow is aiming blind: you pick up Fireball, the board
     lights up, and nothing on screen connects the spell to the thing under
     your cursor. Hearthstone draws a curving chain of glowing segments from
     the source to the pointer, and that line is most of what makes targeting
     feel like pointing at something rather than like a two-click form.

     It is a CHAIN OF DOTS rather than a drawn line on purpose. A line needs
     Frame:CreateLine, which is one more API surface to model and to be wrong
     about; a row of textures needs nothing that is not already used on every
     other widget here, and the segmented look is closer to the original
     anyway. The dots grow toward the head so the arrow has a direction. ]]
--[[ HEARTHSTONE'S TARGETING ARROW: a chain of glowing red-gold chevrons that
     arcs from what you are aiming to the pointer and FLOWS toward it, a broad
     barbed head that points along the curve, and -- only while the pointer is
     over something you can legally target -- a crosshair ring locked onto it.
     Over an enemy the arrow burns red; over a friendly target (a heal, a buff)
     it turns green. Segments are placed along a quadratic Bezier at a fixed
     spacing, each rotated to the curve's tangent (plain textures, rotation
     only, so SetRotation is safe here). ]]
local ARROW_SEGMENTS = 32

local function makeArrow(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints()
  f:SetFrameLevel(400)
  local w = { frame = f, dots = {} }
  for i = 1, ARROW_SEGMENTS do
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetTexture(ART .. "arrow-seg.tga")
    w.dots[i] = t
  end
  w.head = f:CreateTexture(nil, "OVERLAY", nil, 2)
  w.head:SetTexture(ART .. "arrow-head.tga")
  w.ring = f:CreateTexture(nil, "OVERLAY", nil, 1)
  w.ring:SetTexture(ART .. "target-ring.tga")
  w.ring:Hide()
  f:Hide()
  return w
end

local ARROW_TINT = {
  none     = { 1, 1, 1 },
  enemy    = { 1, 0.45, 0.35 },
  friendly = { 0.45, 1, 0.5 },
}

--[[ Lay the arrow from (x1,y1) to (x2,y2), in the parent's coordinate space.
     `target`, when given, is the legal target under the pointer:
     { x, y, w, h, friendly = bool }. ]]
local function arrowApply(w, x1, y1, x2, y2, parent, scale, target)
  local f = w.frame
  f:Show()
  local dx, dy = x2 - x1, y2 - y1
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 1 then f:Hide() return end
  local base = scale or 1
  -- The control point bows the curve upward, the way Hearthstone's arcs.
  local nx, ny = -dy / len, dx / len
  if ny < 0 then nx, ny = -nx, -ny end
  local bow = math.min(len * 0.22, 110 * base)
  local cx, cy = (x1 + x2) / 2 + nx * bow, (y1 + y2) / 2 + ny * bow
  local function at(t)
    local u = 1 - t
    return u * u * x1 + 2 * u * t * cx + t * t * x2,
           u * u * y1 + 2 * u * t * cy + t * t * y2,
           2 * u * (cx - x1) + 2 * t * (x2 - cx),
           2 * u * (cy - y1) + 2 * t * (y2 - cy)
  end
  local tint = ARROW_TINT[target and (target.friendly and "friendly" or "enemy") or "none"]
  local headSize = 62 * base
  local spacing = 24 * base
  local count = math.min(ARROW_SEGMENTS, math.max(1, math.floor((len - headSize * 0.4) / spacing)))
  -- The chevrons flow toward the head: a phase that advances with time.
  local phase = ((GetTime and GetTime() or 0) * 1.8) % 1
  local stop = math.max(0, 1 - headSize * 0.45 / len)
  for i, t in ipairs(w.dots) do
    if i > count then t:Hide() else
      local v = ((i - 1) + phase) / count * stop
      local px, py, tx, ty = at(v)
      local size = (18 + 12 * v) * base
      t:ClearAllPoints()
      t:SetSize(size, size)
      t:SetRotation(math.atan2(ty, tx) - math.pi / 2)
      t:SetPoint("CENTER", parent, "BOTTOMLEFT", px, py)
      t:SetVertexColor(tint[1], tint[2], tint[3], 1)
      -- Fade in from the source and out as a chevron flows into the head.
      t:SetAlpha(math.min(1, v * 4) * (0.55 + 0.45 * v))
      t:Show()
    end
  end
  local _, _, tx, ty = at(1)
  w.head:ClearAllPoints()
  w.head:SetSize(headSize, headSize)
  w.head:SetRotation(math.atan2(ty, tx) - math.pi / 2)
  w.head:SetPoint("CENTER", parent, "BOTTOMLEFT", x2, y2)
  w.head:SetVertexColor(tint[1], tint[2], tint[3], 1)
  w.head:Show()
  if target then
    local pulse = 1 + 0.06 * math.sin((GetTime and GetTime() or 0) * 8)
    local size = math.min(target.w, target.h) * 0.95 * pulse
    w.ring:ClearAllPoints(); w.ring:SetSize(size, size)
    w.ring:SetPoint("CENTER", parent, "BOTTOMLEFT", target.x + target.w / 2, target.y + target.h / 2)
    w.ring:SetVertexColor(tint[1], tint[2], tint[3], 1)
    w.ring:Show()
  else
    w.ring:Hide()
  end
end

local function arrowHide(w) w.frame:Hide() end

W.NewArrow = makeArrow
W.ApplyArrow = arrowApply
W.HideArrow = arrowHide

-- ============================================================== the inspect

--[[ RIGHT-CLICK TO READ A CARD.

     Cards on the board are minion-sized, and a minion is small enough that its
     rules text is unreadable at any sane window size -- so "what does that
     actually do" had no answer without remembering the card. Hearthstone
     answers it by enlarging the card under the cursor.

     One widget, reused: this is a reader, never more than one card at a time,
     and it is pure presentation -- it asks the engine nothing and changes
     nothing, which is why it lives entirely in the binding. ]]
--[[ HEARTHSTONE'S KEYWORD REMINDERS: what Taunt, Battlecry, Overload... do,
     for any card whose text uses the word. Entry: { name, reminder, also },
     `also` being other words that call for it (Ice Lance's "Frozen"). ]]
W.KEYWORDS = {
  { "Taunt", "Enemies must attack this minion." },
  { "Charge", "Can attack immediately." },
  { "Divine Shield", "The first time a Shield minion takes damage, ignore it." },
  -- `unless`: a longer keyword containing this one (V-07-TR-0N's Mega-Windfury)
  { "Windfury", "Can attack twice each turn.", unless = "Mega%-Windfury" },
  { "Mega-Windfury", "Can attack four times each turn." },
  { "Stealth", "Can't be attacked or targeted until it attacks." },
  { "Battlecry", "Does something when you play it from your hand." },
  { "Deathrattle", "Does something when it dies." },
  { "Spell Damage", "Your spell cards deal extra damage." },
  { "Freeze", "Frozen characters lose their next attack.", { "Frozen" } },
  { "Silence", "Removes all card text and enchantments." },
  { "Enrage", "While damaged, this minion has a new power." },
  { "Combo", "A bonus if you already played a card this turn." },
  { "Overload", "Overloaded Mana Crystals are locked next turn." },
  { "Secret", "Hidden until a specific action occurs on your opponent's turn." },
  { "Choose One", "Choose one of two effects." },
  { "Immune", "Can't be damaged." },
  { "Spare Part", "Spare Parts are 1-Cost spells with minor effects." },
  { "Counter", "A card that is Countered has no effect." },
}

function W.KeywordsOf(card)
  local text = ((card and card.text) or ""):gsub("<[^>]+>", "")
  local found = {}
  for _, kw in ipairs(W.KEYWORDS) do
    local own = kw.unless and text:gsub(kw.unless, "") or text
    local hit = own:find(kw[1], 1, true)
    for _, word in ipairs(kw[3] or {}) do hit = hit or own:find(word, 1, true) end
    if hit then found[#found + 1] = kw end
  end
  return found
end

--[[ THE KEYWORDS OF AN ENLARGED CARD, in parchment boxes down its left side:
     right-clicking a Sen'jin says what Taunt does, as Hearthstone does. `w` is
     an inspect widget (W.NewInspect); nil or a card with no keywords clears
     them. ]]
function W.InspectKeywords(w, cardId)
  w.keywordPanels = w.keywordPanels or {}
  for _, p in ipairs(w.keywordPanels) do p:Hide() end
  local list = W.KeywordsOf(cardId and ns.PrintedCards[cardId])
  local y = 20
  for i, kw in ipairs(list) do
    local p = w.keywordPanels[i]
    if not p then
      p = W.HSPanel(w.frame); p:EnableMouse(false)
      w.keywordPanels[i] = p
    end
    p:SetFrameLevel(w.card.frame:GetFrameLevel() + 2)
    p:SetContent(kw[1], kw[2], 220)
    p:ClearAllPoints()
    p:SetPoint("TOPRIGHT", w.card.frame, "TOPLEFT", -14, -y)
    y = y + p:GetHeight() + 6
    p:Show()
  end
  return #list
end

local function makeInspect(parent)
  local f = CreateFrame("Button", nil, parent)
  f:SetAllPoints()
  f:SetFrameLevel(450)
  f:EnableMouse(true)
  f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  local w = { frame = f }
  w.dim = f:CreateTexture(nil, "BACKGROUND")
  w.dim:SetAllPoints()
  w.dim:SetColorTexture(0, 0, 0, 0.55)
  w.card = makeCard(f)
  w.card.frame:SetFrameLevel(460)
  --[[ The enlarged card must not be a second thing you can click: it is being
       read, not played, and a click anywhere dismisses it. ]]
  w.card.frame:EnableMouse(false)
  w.effects = f:CreateFontString(nil, "OVERLAY")
  w.effects:SetFont(BODY_FONT, 14, "OUTLINE")
  w.effects:SetJustifyH("LEFT"); w.effects:SetJustifyV("TOP")
  f:Hide()
  return w
end

W.NewInspect = makeInspect

--[[ THE ROPE. It burns from full to nothing over the turn's last seconds and
     changes colour in three stages, so the deadline is felt rather than read.

     Choreography.Rope has driven a `Burn`/`Urgency` handle since long before
     anything drew one; this is the frame that finally listens. ]]
local function makeRope(parent)
  local f = CreateFrame("Frame", nil, parent)
  --[[ Over the board art, under the cards. It crosses the middle of the table
       now, so without this it would either hide behind the background or draw
       on top of the minions it runs between. ]]
  f:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 0) + 4)
  local w = { frame = f }
  w.fill = f:CreateTexture(nil, "ARTWORK")
  w.fill:SetTexture(ART.."turn-rope.tga")
  w.spark = f:CreateTexture(nil, "OVERLAY")
  w.spark:SetTexture(ART.."rope-ember.tga"); w.spark:SetBlendMode("ADD"); w.spark:SetAlpha(0)
  f:Hide()
  return w
end

--[[ URGENCY IS IN THE FLAME, NOT THE ROPE. Hearthstone's rope stays hemp
     brown to the end; the flame at its burning end is what grows. It was
     tinted orange then red here, which turned the old stripe texture into a
     candy cane (docs/24). The flame's size, as a multiple of the rope's
     thickness, per stage: burning, hurry, now. ]]
local URGENCY = { 3.2, 4.0, 5.0 }
local ROPE_V0, ROPE_V1 = 9 / 32, 23 / 32   -- the rope's own rows in turn-rope.tga

--[[ `burn` is 0..1 of the turn consumed.

     THE ROPE RUNS ACROSS THE BOARD, so it burns left to right, toward the End
     Turn button -- the flame travels the way your turn is going and the rope
     still to come lies ahead of it on the right. The remaining length is
     therefore anchored to the RIGHT and the spark sits on its left edge, which
     is the burning end.

     The old version was a vertical strip whose fill shrank from the top. Both
     orientations are still handled, decided by the rect's own shape, so this
     stays correct if the rope is ever moved back to a rail. ]]
local function ropeApply(w, r, parent, burn, urgency)
  local f = w.frame
  f:ClearAllPoints()
  f:SetSize(r.w, r.h)
  f:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", r.x, r.y)
  local consumed=math.max(0,math.min(1,burn or 0))
  local left = 1-consumed
  if left>0 then w.fill:Show() else w.fill:Hide() end
  local flame = URGENCY[math.max(1, math.min(3, urgency or 1))]
  w.fill:ClearAllPoints()
  w.spark:ClearAllPoints()
  if r.w >= r.h then
    -- horizontal: burns left to right, toward the End Turn button
    w.fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    w.fill:SetSize(math.max(1, r.w * left), r.h)
    w.spark:SetPoint("CENTER", w.fill, "LEFT", 0, 0)
    w.spark:SetSize(r.h * flame, r.h * flame)
  else
    -- vertical: shrinks from the top, the way a rope hanging down burns
    w.fill:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    w.fill:SetSize(r.w, math.max(1, r.h * left))
    w.spark:SetPoint("BOTTOM", w.fill, "TOP", 0, 0)
    w.spark:SetSize(r.w * flame, r.w * flame)
  end
  w.fill:SetVertexColor(1, 1, 1, 1)
  --[[ turn-rope.tga is 32px tall but the rope in it is only rows 10..22, so the
       rect's height drew a rope less than half as thick. The texture is
       cropped to the rope (and the rect sized for it, Layout L.rope). ]]
  if r.w>=r.h then w.fill:SetTexCoord(consumed,1,ROPE_V0,ROPE_V1)
  else w.fill:SetTexCoord(ROPE_V0,ROPE_V1,consumed,1) end
  w.spark:SetAlpha(left > 0 and 1 or 0)
end

W.NewRope = makeRope
W.ApplyRope = ropeApply

-- ================================================================== toasts

--[[ A corner toast: the pack that just dropped, the card that just completed a
     set. It fires in the OPEN WORLD, mid-fight, so it is small, it never takes
     focus, and it leaves on its own.

     Choreography drives Pos/Alpha/Shimmer/Count on it. ]]
--[[ THE DROP TOAST: what you see in the world when a kill pays. A dark leather
     plaque in a gold rim, the pack (or the card's art) on its left, what it is
     in gold, and what to do about it underneath -- "3 packs waiting - click to
     open". It was a 220px grey rectangle with an empty icon, gone in two
     seconds, which in a fight nobody saw. ]]
W.TOAST_W, W.TOAST_H = 300, 84
local function makeToast(parent)
  local f = CreateFrame("Button", nil, parent or UIParent)
  f:SetSize(W.TOAST_W, W.TOAST_H)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:RegisterForClicks("LeftButtonUp")
  local w = { frame = f, baseX = 0, baseY = 0 }
  w.bg = f:CreateTexture(nil, "BACKGROUND")
  w.bg:SetAllPoints()
  w.bg:SetTexture(ART .. "menu-leather.tga")
  w.bg:SetVertexColor(.36, .22, .14, .97)
  w.rim = W.GoldFrame(f, 8, "BORDER")
  w.rim:Layout(W.TOAST_W, W.TOAST_H)
  w.glow = f:CreateTexture(nil, "BACKGROUND", nil, -1)
  w.glow:SetTexture(ART .. "fx-aura.tga"); w.glow:SetBlendMode("ADD")
  w.glow:SetPoint("CENTER", f, "LEFT", 40, 0); w.glow:SetSize(150, 150)
  w.glow:SetVertexColor(1, .78, .3, .55)
  w.icon = f:CreateTexture(nil, "ARTWORK")
  w.icon:SetPoint("LEFT", f, "LEFT", 14, 0)
  w.icon:SetSize(48, 66)
  w.title = f:CreateFontString(nil, "OVERLAY")
  w.title:SetFont(FONT, 16, "OUTLINE")
  w.title:SetTextColor(1, .82, .3)
  w.title:SetPoint("TOPLEFT", f, "TOPLEFT", 74, -14)
  w.title:SetSize(W.TOAST_W - 86, 20); w.title:SetJustifyH("LEFT"); w.title:SetWordWrap(false)
  w.sub = f:CreateFontString(nil, "OVERLAY")
  w.sub:SetFont(BODY_FONT, 12, "")
  w.sub:SetTextColor(1, .96, .86)
  w.sub:SetPoint("TOPLEFT", w.title, "BOTTOMLEFT", 0, -4)
  w.sub:SetSize(W.TOAST_W - 86, 16); w.sub:SetJustifyH("LEFT"); w.sub:SetWordWrap(false)
  w.hint = f:CreateFontString(nil, "OVERLAY")
  w.hint:SetFont(BODY_FONT, 11, "")
  w.hint:SetTextColor(.8, .72, .58)
  w.hint:SetPoint("TOPLEFT", w.sub, "BOTTOMLEFT", 0, -3)
  w.hint:SetSize(W.TOAST_W - 86, 14); w.hint:SetJustifyH("LEFT"); w.hint:SetWordWrap(false)
  w.shine = f:CreateTexture(nil, "OVERLAY")
  w.shine:SetTexture(ART .. "fx-aura.tga"); w.shine:SetBlendMode("ADD")
  w.shine:SetPoint("CENTER", w.icon, "CENTER"); w.shine:SetSize(90, 90)
  w.shine:SetAlpha(0)
  f:Hide()
  return w
end

--[[ Fill the toast for a drop. `data` is the reward: a pack ({total}) or a
     card ({cardId, golden}). `resolver` finds the card's art. ]]
function W.FillToast(t, kind, data, resolver)
  data = data or {}
  if kind == "pack" then
    t.icon:SetTexture(ART .. "menu-pack.tga"); t.icon:SetTexCoord(0, 1, 0, 1)
    t.title:SetText(data.fromLevel and ((data.count or 1)>1
      and ("Level reward: "..data.count.." packs!") or "Level reward: card pack!") or "Card pack!")
    local n = data.total or 1
    t.sub:SetText(("%d pack%s waiting"):format(n, n == 1 and "" or "s"))
    t.hint:SetText(data.preview and "Preview - no pack added" or "Added automatically")
    t.glow:SetVertexColor(1, .78, .3, .55)
  else
    local d = data.cardId and resolver and resolver:Card(data.cardId)
    t.icon:SetTexture(d and d.icon or (ART .. "menu-pack.tga"))
    t.icon:SetTexCoord(.18, .82, .1, .9)
    t.title:SetText(d and d.name or "New card!")
    local rarity = tostring(data.rarity or (d and d.rarity) or ""):lower()
    t.sub:SetText((data.golden and "Golden " or "") .. (rarity ~= "" and (rarity:sub(1, 1):upper() .. rarity:sub(2)) or "New") .. " card"
      .. (data.set == "NAXX" and " from Naxxramas" or ""))
    t.hint:SetText(data.extra and "An extra copy - worth dust" or "Added to your collection")
    local c = ({ LEGENDARY = { 1, .6, .1 }, EPIC = { .75, .35, 1 }, RARE = { .3, .6, 1 } })[data.rarity or ""]
      or { 1, .9, .7 }
    if data.golden then c = { 1, .82, .2 } end
    t.glow:SetVertexColor(c[1], c[2], c[3], .6)
  end
end

W.NewToast = makeToast

-- =============================================================== particles

--[[ PARTICLES, the cheapest way to make an impact feel like one.

     A pool of small textures with a velocity and a lifetime, updated by
     whatever owns the frame. Deliberately tiny and deliberately not a real
     particle system: twenty squares thrown outward and faded is most of the
     perceived effect of a burst, at a cost that will never matter.

     Colour is per-burst, so the same code does gold for a legendary, blue for
     dust and red for damage. ]]
local BURST_COLOR = {
  burst_gold     = { 1.00, 0.80, 0.25 },
  burst_purple   = { 0.70, 0.35, 1.00 },
  burst_blue     = { 0.35, 0.65, 1.00 },
  pack_burst     = { 1.00, 0.85, 0.45 },
  golden_sparkle = { 1.00, 0.90, 0.40 },
  card_motes     = { 0.85, 0.85, 1.00 },
  dust_inflow    = { 0.45, 0.80, 1.00 },
  dust_outflow   = { 0.45, 0.80, 1.00 },
  shatter        = { 0.75, 0.80, 0.90 },
  impact         = { 1.00, 0.95, 0.80 },
  -- Kinds the match asked for that used to render plain white.
  arcane         = { 0.80, 0.45, 1.00 },
  summon_dust    = { 0.90, 0.78, 0.55 },
  hit_spark      = { 1.00, 0.80, 0.40 },
  -- Spell schools (Client/FX/SpellFX.lua).
  fire           = { 1.00, 0.55, 0.15 },
  frost          = { 0.55, 0.85, 1.00 },
  holy           = { 1.00, 0.90, 0.50 },
  shadow         = { 0.60, 0.25, 0.90 },
  nature         = { 0.45, 0.95, 0.35 },
  lightning      = { 0.65, 0.80, 1.00 },
  orb            = { 1.00, 0.95, 0.80 },
}

local function newParticles(parent, opts)
  opts = opts or {}
  local p = {
    parent = parent, pool = {}, live = {},
    max = opts.max or 120,
    created = 0,
  }
  return p
end

local function particleAcquire(p)
  local t = table.remove(p.pool)
  if not t then
    if p.created >= p.max then return nil end   -- hard ceiling; never unbounded
    t = p.parent:CreateTexture(nil, "OVERLAY")
    t:SetSize(4, 4)
    p.created = p.created + 1
  end
  t:Show()
  return t
end

--[[ Throw `n` particles outward from (x, y), in the parent's coordinate space.

     `rand` is injected so a test can make a burst deterministic. It defaults to
     math.random, which is correct here and nowhere near the engine: particles
     are decoration and never touch game state, so they cannot desync anything. ]]
--[[ A spell school's burst moves the way its element does (SpellFX.MOTION:
     embers rise, frost falls, smoke swells); every other kind keeps the one
     gravity and glow it always had. ]]
local function particleBurst(p, kind, x, y, n, rand)
  rand = rand or math.random
  local c = BURST_COLOR[kind] or { 1, 1, 1 }
  local m = ns.SpellFX and ns.SpellFX.MOTION and ns.SpellFX.MOTION[kind]
  for _ = 1, math.min(n or 12, p.max) do
    local t = particleAcquire(p)
    if not t then break end
    local angle = rand() * math.pi * 2
    local speed = m and (m.speed[1] + rand() * (m.speed[2] - m.speed[1])) or (40 + rand() * 120)
    --[[ A soft glowing mote, not inplay_minion-glow: that is the HOLLOW oval
         drawn round a minion, and shrunk to a particle every burst, trail and
         shatter shed little gold rings (the in-client tour, docs/39). ]]
    t:SetTexture(ART .. (m and m.spark and "fx-spark.tga" or "fx-orb.tga"))
    t:SetBlendMode("ADD")
    t:SetVertexColor(c[1], c[2], c[3], 1)
    t:SetAlpha(1)
    local size = 8 + rand() * 10
    t:SetSize(size, size)
    t:ClearAllPoints()
    t:SetPoint("BOTTOMLEFT", p.parent, "BOTTOMLEFT", x, y)
    p.live[#p.live + 1] = {
      tex = t, x = x, y = y, size = size,
      vx = math.cos(angle) * speed, vy = math.sin(angle) * speed,
      life = m and (m.life[1] + rand() * (m.life[2] - m.life[1])) or (0.45 + rand() * 0.45), age = 0,
      gravity = m and m.gravity, grow = m and m.grow,
    }
  end
end

--[[ Advance every live particle. Returns how many are still alive, so the
     owner can stop its OnUpdate when nothing is left -- an OnUpdate that runs
     forever for nothing is the most common way an addon costs frames. ]]
local function particleTick(p, dt)
  local keep = {}
  for _, q in ipairs(p.live) do
    q.age = q.age + dt
    if q.age >= q.life then
      q.tex:Hide()
      p.pool[#p.pool + 1] = q.tex
    else
      q.vy = q.vy - (q.gravity or 260) * dt  -- gravity: a burst that falls reads as weight
      q.x = q.x + q.vx * dt
      q.y = q.y + q.vy * dt
      if q.grow then
        local k = 1 + (q.grow - 1) * (q.age / q.life)
        q.tex:SetSize(q.size * k, q.size * k)
      end
      q.tex:ClearAllPoints()
      q.tex:SetPoint("BOTTOMLEFT", p.parent, "BOTTOMLEFT", q.x, q.y)
      q.tex:SetAlpha(1 - (q.age / q.life))
      keep[#keep + 1] = q
    end
  end
  p.live = keep
  return #keep
end

local function particleClear(p)
  for _, q in ipairs(p.live) do
    q.tex:Hide()
    p.pool[#p.pool + 1] = q.tex
  end
  p.live = {}
end

W.NewParticles = newParticles
W.Burst = particleBurst
W.TickParticles = particleTick
W.ClearParticles = particleClear
W.BURST_COLOR = BURST_COLOR

-- ============================================================ screen effects

--[[ SHAKE and VIGNETTE.

     Both were stored by the board's stage and read by nothing, so an impact set
     a number and the screen sat still. They are real here, and they share one
     rule: THE BOARD MUST RETURN TO WHERE THE PLAYER PUT IT. A shake that
     applies an absolute position would walk the window across the screen over a
     match, which is the worst kind of slow bug. So the offset is always applied
     relative to a remembered anchor, and clearing it restores exactly. ]]
local function newShake(frame)
  return { frame = frame, amount = 0, age = 0, anchor = nil }
end

local function shakeStart(s, amount)
  if not s.anchor then
    local point, rel, relPoint, x, y = s.frame:GetPoint(1)
    s.anchor = { point = point, rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 }
  end
  --[[ A new shake during a shake takes the LARGER amplitude rather than adding.
       Two impacts in the same frame should not double the violence. ]]
  s.amount = math.max(s.amount, amount or 0)
  s.age = 0
end

local function shakeTick(s, dt, rand)
  if s.amount <= 0 or not s.anchor then return false end
  rand = rand or math.random
  s.age = s.age + dt
  local decay = math.max(0, 1 - s.age / 0.28)
  local a = s.amount * decay
  local ax, ay = (rand() - 0.5) * 2 * a, (rand() - 0.5) * 2 * a
  local anc = s.anchor
  s.frame:ClearAllPoints()
  s.frame:SetPoint(anc.point, anc.rel, anc.relPoint, anc.x + ax, anc.y + ay)
  if decay <= 0 then
    --[[ The final tick already applied a ZERO amplitude, so the frame is
         standing exactly on its anchor -- an explicit restore here was
         unobservable and has been removed (a mutation that deleted it changed
         nothing, which is the definition of dead code). What remains is the
         part that matters: forget the anchor, so the player may move the window
         and the next shake re-reads where they put it. ]]
    s.amount, s.anchor = 0, nil
    return false
  end
  return true
end

--[[ End a shake NOW, standing the frame back on its anchor. For a board hidden
     or reset mid-shake: TickShake never runs on a hidden frame, so without this
     the window stayed a few pixels off where the player had put it. ]]
local function shakeStop(s)
  if not (s and s.anchor) then if s then s.amount = 0 end; return end
  local anc = s.anchor
  s.frame:ClearAllPoints()
  s.frame:SetPoint(anc.point, anc.rel, anc.relPoint, anc.x, anc.y)
  s.amount, s.anchor = 0, nil
end

W.NewShake = newShake
W.StopShake = shakeStop
W.Shake = shakeStart
W.TickShake = shakeTick

local function makeVignette(parent)
  local t = parent:CreateTexture(nil, "OVERLAY")
  t:SetAllPoints()
  t:SetColorTexture(0, 0, 0, 0)
  t:Hide()
  return t
end

local function vignetteSet(t, a)
  if not t then return end
  if (a or 0) <= 0.01 then t:Hide(); return end
  t:Show()
  t:SetColorTexture(0, 0, 0, math.min(0.85, a))
end

W.NewVignette = makeVignette
W.SetVignette = vignetteSet

--[[ A STAGE WITH NO BOARD.

     A pack drops while you are fighting something, with no card game on screen
     at all -- that is the NORMAL case for a drop, not an edge case. The board's
     stage is useless there because there is no board, so the toast would have
     been driven into a null object and nothing would ever have appeared.

     This is the minimum stage that can still show a corner toast: it owns its
     own frame and particle pool on UIParent, and every other method is a
     harmless no-op. ]]
local function newToastStage(owner)
  local t = makeToast(UIParent)
  t.frame:SetPoint("TOP", UIParent, "TOP", 0, -100)
  local parts = newParticles(UIParent, { max = 40 })
  local stage = { toastWidget = t, particles = parts }

  local function chain(h) return setmetatable(h, { __index = function() return function() return h end end }) end

  function stage:Toast(kind, data)
    local h = {}
    t.frame:ClearAllPoints()
    t.frame:SetPoint("TOP", UIParent, "TOP", 0, -100)
    t.frame:Show()
    W.FillToast(t, kind, data, owner and owner.resolver)
    function h:Pos(x, y)
      t.frame:ClearAllPoints()
      t.frame:SetPoint("TOP", UIParent, "TOP", x or 0, -100 + (y or 0))
      return h
    end
    function h:Alpha(a)
      a = a or 1
      t.frame:SetAlpha(a)
      --[[ Hidden when faded out, SHOWN when faded in. Hiding only was a real
           bug: every slide-in starts at alpha 0, so the toast hid itself on the
           first frame of its own arrival and never came back. An invisible
           frame also still eats the mouse where it sits, which is why this is
           not simply left at alpha 0. ]]
      if a <= 0.02 then t.frame:Hide() else t.frame:Show() end
      return h
    end
    function h:Shimmer(v) t.shine:SetAlpha((v or 0) * 0.5); return h end
    function h:Count(n)
      if kind == "pack" then t.sub:SetText(("%d pack%s waiting"):format(n or 1, (n or 1) == 1 and "" or "s")) end
      return h
    end
    return chain(h)
  end

  function stage:Sound(key, step) ns.Sounds.Play(key, step) end
  function stage:Particles(kind, x, y, n)
    --[[ Around the toast itself, which is the only thing on screen that the
         burst could possibly belong to. ]]
    local f = t.frame
    W.Burst(parts, kind, (f:GetLeft() or 0) + 40 + (x or 0), (f:GetBottom() or 0) + (y or 0), n or 8)
  end
  function stage:Card() return chain({}) end
  function stage:Screen() return chain({}) end
  function stage:Board() return chain({}) end
  function stage:Hero() return chain({}) end

  function stage:Tick(dt) return particleTick(parts, dt) end
  return stage
end

-- =================================================================== tweens

--[[ SMOOTH MOVEMENT.

     Hearthstone's hand never teleports: draw a card and the whole fan slides
     apart to make room. Until now every relayout snapped every widget to its
     new rect, which is the single most obvious way this looked like a spreadsheet
     rather than a card game.

     A tween is a from-rect, a to-rect and a clock. Cheap enough to run on every
     card in the hand, and it degrades correctly -- a widget with no previous
     rect simply appears, which is right for a card that was just drawn. ]]
local function newTween(w, from, to, dur)
  return { w = w, from = from, to = to, dur = dur or 0.18, age = 0 }
end

local function easeOut(v) return 1 - (1 - v) * (1 - v) end

--[[ A TWEEN CARRIES EVERY FIELD OF THE RECT, not just the four numbers that
     happen to be geometry.

     THE BUG THIS FIXES: this built a rect with x, y, w and h and nothing else,
     so a sliding card lost its `lean` -- the padding that makes room for its
     tilt -- and its `rot`. Losing the padding moves the frame's anchor by a
     tenth of a card, so every card that slid ALSO shifted sideways, and
     finished the slide shifted, because the last tick is what the frame keeps.
     Hovering redraws the hand, so pointing at a card was enough to set it off.

     `rot` is interpolated, because a card turning as it moves is the point.
     `lean` is taken from the destination and not blended: it is the ROOM the
     turn needs, it is the same for every card in a hand by construction, and
     blending it would animate the padding rather than the card. ]]
local function tweenTick(t, dt, apply)
  t.age = t.age + dt
  local v = math.min(1, t.age / t.dur)
  local e = easeOut(v)
  local fromRot, toRot = t.from.rot or 0, t.to.rot or 0
  local r = {
    x = t.from.x + (t.to.x - t.from.x) * e,
    y = t.from.y + (t.to.y - t.from.y) * e,
    w = t.from.w + (t.to.w - t.from.w) * e,
    h = t.from.h + (t.to.h - t.from.h) * e,
    rot = fromRot + (toRot - fromRot) * e,
    lean = t.to.lean or t.from.lean,
  }
  apply(t.w, r)
  return v < 1
end

W.NewToastStage = newToastStage
W.NewTween = newTween
W.TickTween = tweenTick

return W
