-- Export actual widget geometry for the independent raster preview.
local H = require("tests.harness")
H.LoadEngine()
local ns = H.ns
require("tests.wowstub").Install(_G)
assert(loadfile("ForeverHearthstone/Client/UI/Widgets.lua"))("ForeverHearthstone",ns)
local resolver=ns.Resolver.New({printed=ns.PrintedCards,palette={}})
print("sample\tcard\tangle\tlayer\ttexture\twidth\theight\tleft\tright\ttop\tbottom")
local sample=0
for _,rot in ipairs({-.14,0,.14}) do
  for _,id in ipairs({"CS2_074","NEW1_004","CS2_080","CS2_121"}) do
    sample=sample+1
    local w=ns.Widgets.New(UIParent)
    ns.Widgets.SetDescriptor(w,resolver:Card(id))
    ns.Widgets.ApplyRect(w,{x=0,y=0,w=224,h=320,rot=rot})
    local function emit(layer,tex)
      local uv=rawget(tex,"texcoord") or {0,1,0,1}
      print(table.concat({sample,id,rot,layer,tex:GetTexture(),tex:GetWidth(),tex:GetHeight(),unpack(uv)},"\t"))
    end
    emit("skin",w.skin)
    for _,n in ipairs({w.cost,w.atk,w.hp}) do
      for _,g in ipairs(n.glyphs) do if g:IsShown() then emit("digit",g) end end
    end
  end
end
