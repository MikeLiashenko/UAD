# The chosen icon (u1, the flag letters) into the project's art folder (then run
# tools_scripts/make_icons.ps1), and the menu's wordmark logo.png: the full icon and the two
# Android adaptive layers; plus a preview of the layers under a round launcher mask.
from PIL import Image, ImageDraw
from draw import rounded
from draw_uad import u1

ART = "C:/Work/UAD/art"
full = rounded(u1("full")).resize((1024, 1024), Image.LANCZOS)
full.save(f"{ART}/icon_source.png")
u1("bg").resize((1024, 1024), Image.LANCZOS).save(f"{ART}/icon_bg.png")
u1("fg").resize((1024, 1024), Image.LANCZOS).save(f"{ART}/icon_fg.png")
# what a round launcher shows: bg full size, fg inset 19%, the middle 2/3 of the 108 dp square visible
S = 432
bg = Image.open(f"{ART}/icon_bg.png").resize((S, S), Image.LANCZOS)
fg = Image.open(f"{ART}/icon_fg.png")
k = int(S * 0.62)
fg = fg.resize((k, k), Image.LANCZOS)
comp = bg.copy()
comp.alpha_composite(fg, ((S - k) // 2, (S - k) // 2))
vis = int(S * 72 / 108)
crop = comp.crop(((S - vis) // 2, (S - vis) // 2, (S + vis) // 2, (S + vis) // 2))
m = Image.new("L", crop.size, 0)
ImageDraw.Draw(m).ellipse([0, 0, crop.size[0] - 1, crop.size[1] - 1], fill=255)
out = Image.new("RGBA", crop.size, (0, 0, 0, 0))
out.paste(crop, (0, 0), m)
sheet = Image.new("RGB", (1100, 560), (225, 228, 232))
sheet.paste(full.resize((512, 512), Image.LANCZOS), (20, 24), full.resize((512, 512), Image.LANCZOS))
big = out.resize((480, 480), Image.LANCZOS)
sheet.paste(big, (580, 40), big)
sheet.save("C:/Work/UAD/build/icon_variants/final_preview.png")
from draw_uad import logo
lg = logo()
lg.resize((1200, int(lg.size[1] * 1200 / lg.size[0])), Image.LANCZOS).save("C:/Work/UAD/logo.png")
print("ok")
