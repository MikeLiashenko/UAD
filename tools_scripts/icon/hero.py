# The picture across the top of the Windows installer: the icon's night sky and a low, distant
# city, wide, with the game's wordmark. -> art/installer_hero.png (1440x500: a 720x250 area at 200 %)
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, H = 1440, 500
rng = np.random.default_rng(21)
y = np.linspace(0, 1, H)[:, None, None]
top, bot = np.array((3, 8, 24), float), np.array((26, 50, 92), float)
sky = np.repeat(top + (bot - top) * y ** 1.3, W, axis=1)
# the warm glow of the city on the low clouds
yy, xx = np.mgrid[0:H, 0:W]
sky += np.array((70, 52, 30), float) * np.exp(-(((xx - W / 2) / (W * 0.6)) ** 2 + ((yy - H) / (H * 0.45)) ** 2))[..., None]
img = Image.fromarray(np.clip(sky, 0, 255).astype(np.uint8)).convert("RGBA")
d = ImageDraw.Draw(img)
for _ in range(170):
    x, yv, r = rng.random() * W, rng.random() * H * 0.62, rng.random() * 1.5 + 0.5
    d.ellipse([x - r, yv - r, x + r, yv + r], fill=(220, 230, 255, int(rng.integers(70, 220))))
# two rows of buildings: a hazy far row, then the near one with lit windows
for row, (base, hmin, hmax, col, lit) in enumerate(((H - 70, 30, 90, (14, 24, 46), 0.05), (H, 40, 150, (4, 8, 20), 0.17))):
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dl = ImageDraw.Draw(lay)
    x = -10
    while x < W:
        w = int(rng.integers(26, 70))
        h = int(rng.integers(hmin, hmax))
        dl.rectangle([x, base - h - 60, x + w, H], fill=col + (255,))
        for wy in range(base - h - 50, H - 4, 13):
            for wx in range(x + 6, x + w - 8, 10):
                if rng.random() < lit:
                    c = (255, 196, 110) if rng.random() < 0.8 else (190, 215, 255)
                    dl.rectangle([wx, wy, wx + 4, wy + 6], fill=c + (int(rng.integers(130, 235)),))
        x += w - int(rng.integers(0, 8))
    if row == 0:
        lay = lay.filter(ImageFilter.GaussianBlur(1.2))
    img.alpha_composite(lay)
logo = Image.open("C:/Work/UAD/logo.png").convert("RGBA")
h = 300
logo = logo.resize((int(logo.size[0] * h / logo.size[1]), h), Image.LANCZOS)
img.alpha_composite(logo, ((W - logo.size[0]) // 2, 40))
img.convert("RGB").save("C:/Work/UAD/art/installer_hero.png")
print("hero", img.size)
