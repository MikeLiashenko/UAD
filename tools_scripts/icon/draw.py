# Four candidate icons for UAD, drawn in code at 2048 px and scaled down (clean edges at every size).
#   py draw.py      -> v1_intercept.png … v4_letters.png (1024 px) and compare.png
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = "C:/Work/UAD/build/icon_variants"
N = 2048
BLUE = (0, 87, 183)
YELLOW = (255, 213, 0)
FONT = "C:/Windows/Fonts/bahnschrift.ttf"


def sky(top=(4, 10, 28), bottom=(18, 42, 84), glow=None):
    """Night sky: a vertical gradient, optionally warmed near the horizon."""
    y = np.linspace(0, 1, N)[:, None, None]
    a, b = np.array(top, float), np.array(bottom, float)
    img = a + (b - a) * (y ** 1.4)
    img = np.repeat(img, N, axis=1)
    if glow is not None:
        cx, cy, r, col, k = glow
        yy, xx = np.mgrid[0:N, 0:N]
        d = np.sqrt(((xx - cx) / r) ** 2 + ((yy - cy) / (r * 0.55)) ** 2)
        img += np.array(col, float)[None, None, :] * (np.exp(-d * d) * k)[..., None]
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).convert("RGBA")


def add(base, layer):
    """Additive light (glows, flashes)."""
    a = np.asarray(base).astype(np.int32)
    b = np.asarray(layer).astype(np.int32)
    al = b[..., 3:4] / 255.0
    out = a.copy()
    out[..., :3] = np.clip(a[..., :3] + b[..., :3] * al, 0, 255)
    return Image.fromarray(out.astype(np.uint8))


def glow(layer, radius, strength=1.0):
    g = layer.filter(ImageFilter.GaussianBlur(radius))
    if strength != 1.0:
        arr = np.asarray(g).astype(np.float32)
        arr[..., 3] = np.clip(arr[..., 3] * strength, 0, 255)
        g = Image.fromarray(arr.astype(np.uint8))
    return g


def bezier(p0, p1, p2, n=400):
    t = np.linspace(0, 1, n)[:, None]
    return (1 - t) ** 2 * np.array(p0) + 2 * (1 - t) * t * np.array(p1) + t ** 2 * np.array(p2)


def trail(img, pts, w0, w1, c0, c1, glow_r=40, glow_k=1.6):
    """A missile trail: thin and dim at its tail, thick and hot at its head, with a glow."""
    lay = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    n = len(pts)
    for i, (x, y) in enumerate(pts):
        u = i / (n - 1)
        r = w0 + (w1 - w0) * u ** 1.5
        c = tuple(int(c0[k] + (c1[k] - c0[k]) * u) for k in range(3))
        a = int(255 * min(1.0, 0.15 + u * 1.2))
        d.ellipse([x - r, y - r, x + r, y + r], fill=c + (a,))
    img = add(img, glow(lay, glow_r, glow_k))
    return Image.alpha_composite(img, lay)


def flash(img, x, y, r, col=(255, 236, 160), spikes=4, spike_len=3.2, rot=0.0):
    lay = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    for k in range(spikes * 2):
        a = rot + k * math.pi / spikes
        L = r * (spike_len if k % 2 == 0 else spike_len * 0.55)
        wdt = r * 0.16
        p = [(x + math.cos(a) * L, y + math.sin(a) * L),
             (x + math.cos(a + math.pi / 2) * wdt, y + math.sin(a + math.pi / 2) * wdt),
             (x - math.cos(a + math.pi / 2) * wdt, y - math.sin(a + math.pi / 2) * wdt)]
        d.polygon(p, fill=col + (230,))
    d.ellipse([x - r, y - r, x + r, y + r], fill=col + (255,))
    d.ellipse([x - r * 0.55, y - r * 0.55, x + r * 0.55, y + r * 0.55], fill=(255, 255, 255, 255))
    img = add(img, glow(lay, r * 2.2, 2.2))
    img = add(img, glow(lay, r * 0.6, 1.0))
    return Image.alpha_composite(img, lay)


def skyline(img, base_y, color=(3, 7, 18), lights=True, seed=3, tower=True):
    """A low city silhouette with a few lit windows (a TV-tower spike for Kyiv)."""
    rng = np.random.default_rng(seed)
    lay = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    x = -20
    blocks = []
    while x < N + 20:
        w = int(rng.integers(70, 170))
        h = int(rng.integers(90, 300))
        if 820 < x < 1000:
            h = int(rng.integers(260, 360))
        blocks.append((x, base_y - h, x + w, N))
        x += w - int(rng.integers(0, 25))
    for b in blocks:
        d.rectangle(b, fill=color + (255,))
    # the TV tower
    tx = 1460
    if tower:
        d.rectangle([tx - 14, base_y - 560, tx + 14, N], fill=color + (255,))
        d.polygon([(tx - 50, base_y - 330), (tx + 50, base_y - 330), (tx + 16, base_y - 380), (tx - 16, base_y - 380)], fill=color + (255,))
        d.rectangle([tx - 4, base_y - 700, tx + 4, base_y - 560], fill=color + (255,))
    img = Image.alpha_composite(img, lay)
    if lights:
        wl = Image.new("RGBA", (N, N), (0, 0, 0, 0))
        dw = ImageDraw.Draw(wl)
        for b in blocks:
            for yy in range(b[1] + 30, base_y + 200, 46):
                for xx in range(b[0] + 18, b[2] - 22, 34):
                    if rng.random() < 0.16:
                        c = (255, 196, 110) if rng.random() < 0.8 else (190, 215, 255)
                        dw.rectangle([xx, yy, xx + 14, yy + 18], fill=c + (int(rng.integers(120, 230)),))
        img = add(img, glow(wl, 6, 1.2))
        img = Image.alpha_composite(img, wl)
        if tower:
            ImageDraw.Draw(img).ellipse([tx - 9, base_y - 712, tx + 9, base_y - 694], fill=(255, 60, 50, 255))
    return img


def rounded(img, radius=0.2):
    m = Image.new("L", (N, N), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, N - 1, N - 1], int(N * radius), fill=255)
    out = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    out.paste(img, (0, 0), m)
    return out


def stars(img, n=140, seed=1, max_y=1.0):
    rng = np.random.default_rng(seed)
    lay = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    for _ in range(n):
        x, y = rng.random() * N, rng.random() * N * max_y
        r = rng.random() * 3.5 + 1.2
        d.ellipse([x - r, y - r, x + r, y + r], fill=(220, 230, 255, int(rng.integers(60, 200))))
    return add(img, lay)


# ---------------------------------------------------------------- 1: the intercept
def v1():
    img = sky((3, 8, 24), (20, 46, 92), glow=(N * 0.5, N * 1.02, N * 0.7, (60, 50, 30), 1.0))
    img = stars(img, 120, max_y=0.6)
    # the threat, coming in from the upper right
    img = trail(img, bezier((2150, 260), (1700, 360), (1330, 640)), 6, 24, (120, 40, 20), (255, 110, 50), 30, 1.3)
    # the interceptor, rising from the battery at the lower left
    img = trail(img, bezier((300, 1700), (520, 820), (1300, 660)), 8, 44, (90, 120, 200), (255, 230, 140), 46, 1.8)
    img = flash(img, 1320, 650, 100, spikes=4, rot=0.35)
    img = skyline(img, 1820)
    return img


# ---------------------------------------------------------------- 2: the radar
def v2():
    img = sky((4, 12, 26), (8, 26, 52))
    cx, cy, R = N / 2, N / 2, N * 0.40
    lay = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    for k, rr in enumerate((1.0, 0.72, 0.44, 0.16)):
        r = R * rr
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(70, 140, 230, 255 if k == 0 else 150), width=16 if k == 0 else 9)
    d.line([cx - R, cy, cx + R, cy], fill=(70, 140, 230, 110), width=7)
    d.line([cx, cy - R, cx, cy + R], fill=(70, 140, 230, 110), width=7)
    img = add(img, glow(lay, 18, 1.2))
    img = Image.alpha_composite(img, lay)
    # the sweep: a yellow wedge that fades behind the beam
    yy, xx = np.mgrid[0:N, 0:N]
    ang = (np.degrees(np.arctan2(yy - cy, xx - cx)) + 360) % 360
    head = 312.0
    behind = (head - ang) % 360
    dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    a = np.where((dist < R) & (behind < 80), np.clip(1 - behind / 80, 0, 1) ** 2.2, 0)
    sw = np.zeros((N, N, 4), np.uint8)
    sw[..., 0], sw[..., 1], sw[..., 2] = 255, 200, 0
    sw[..., 3] = (a * 170).astype(np.uint8)
    img = add(img, Image.fromarray(sw))
    beam = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    bx, by = cx + math.cos(math.radians(head)) * R, cy + math.sin(math.radians(head)) * R
    ImageDraw.Draw(beam).line([cx, cy, bx, by], fill=YELLOW + (255,), width=20)
    img = add(img, glow(beam, 22, 1.6))
    img = Image.alpha_composite(img, beam)
    # the contact, just swept
    img = flash(img, cx + math.cos(math.radians(head - 14)) * R * 0.62, cy + math.sin(math.radians(head - 14)) * R * 0.62, 42,
                col=(255, 240, 180), spikes=4, spike_len=2.2, rot=0.2)
    d = ImageDraw.Draw(img)
    d.ellipse([cx - 26, cy - 26, cx + 26, cy + 26], fill=(200, 225, 255, 255))
    return img


# ---------------------------------------------------------------- 3: the shield
def shield_path(cx, top, w, h):
    pts = []
    for i in range(60):  # the curved bottom to a point
        t = i / 59
        x = cx - w / 2 + w * t
        y = top + h * 0.55 + (h * 0.45) * (1 - abs(2 * t - 1) ** 1.6)
        pts.append((x, y))
    return [(cx - w / 2, top + h * 0.06), (cx - w * 0.18, top), (cx, top + h * 0.035), (cx + w * 0.18, top),
            (cx + w / 2, top + h * 0.06)] + pts[::-1]


def v3():
    img = sky((5, 12, 30), (14, 32, 66))
    cx, top, w, h = N / 2, N * 0.15, N * 0.62, N * 0.72
    poly = shield_path(cx, top, w, h)
    m = Image.new("L", (N, N), 0)
    ImageDraw.Draw(m).polygon(poly, fill=255)
    # inside: the night sky above, the yellow field below (the flag, seen as sky over ground)
    inner = sky((6, 40, 120), (0, 87, 183))
    ground = Image.new("RGBA", (N, N), YELLOW + (255,))
    gm = Image.new("L", (N, N), 0)
    ImageDraw.Draw(gm).rectangle([0, top + h * 0.62, N, N], fill=255)
    inner.paste(ground, (0, 0), gm)
    inner = stars(inner, 60, seed=4, max_y=0.5)
    # the interceptor rising from the field
    inner = trail(inner, bezier((cx - 120, top + h * 0.66), (cx - 160, top + h * 0.35), (cx + 70, top + h * 0.2)), 12, 46,
                  (255, 255, 255), (255, 255, 255), 30, 1.4)
    inner = flash(inner, cx + 80, top + h * 0.19, 88, col=(255, 240, 170), spikes=4, rot=0.4)
    sh = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    sh.paste(inner, (0, 0), m)
    rim = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(rim).line(poly + [poly[0]], fill=(235, 240, 255, 255), width=34, joint="curve")
    img = add(img, glow(m.convert("RGBA").point(lambda v: v) if False else rim, 40, 1.0))
    img = Image.alpha_composite(img, sh)
    img = Image.alpha_composite(img, rim)
    return img


# ---------------------------------------------------------------- 4: the letters
def v4():
    img = sky((3, 8, 24), (16, 38, 80))
    img = stars(img, 90, seed=6, max_y=0.45)
    f = ImageFont.truetype(FONT, 760)
    f.set_variation_by_name("Bold")
    lay = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    text = "UAD"
    tw = d.textlength(text, font=f)
    x0, y0 = (N - tw) / 2, N * 0.43
    d.text((x0, y0), text, font=f, fill=(245, 248, 255, 255))
    bb = d.textbbox((x0, y0), text, font=f)
    # the A's apex: where the trail meets the letters
    ax = x0 + d.textlength("U", font=f) + d.textlength("A", font=f) / 2
    ay = bb[1]
    # the yellow-blue rule under the letters
    d.rectangle([bb[0], bb[3] + 70, bb[2], bb[3] + 110], fill=BLUE + (255,))
    d.rectangle([bb[0], bb[3] + 110, bb[2], bb[3] + 150], fill=YELLOW + (255,))
    img = add(img, glow(lay, 30, 0.5))
    img = Image.alpha_composite(img, lay)
    img = trail(img, bezier((120, 1500), (300, 300), (ax, ay - 40)), 8, 42, (90, 120, 200), (255, 225, 120), 40, 1.8)
    img = flash(img, ax, ay - 40, 88, spikes=4, rot=0.3)
    return img


def main():
    vs = [("v1_intercept", v1), ("v2_radar", v2), ("v3_shield", v3), ("v4_letters", v4)]
    made = []
    for name, fn in vs:
        im = rounded(fn())
        small = im.resize((1024, 1024), Image.LANCZOS)
        small.save(f"{OUT}/{name}.png")
        made.append((name, small))
        print("made", name)
    # the comparison: each row is a variant at 512, 192, 96, 48 px, on dark and on light
    old = Image.open("C:/Work/UAD/icon.png").convert("RGBA").resize((1024, 1024), Image.LANCZOS)
    rows = [("old", old)] + made
    W, H = 1500, 560 * len(rows)
    sheet = Image.new("RGB", (W, H), (24, 26, 30))
    d = ImageDraw.Draw(sheet)
    lab = ImageFont.truetype(FONT, 34)
    for r, (name, im) in enumerate(rows):
        y = r * 560 + 24
        d.rectangle([0, y - 24, W, y + 536], fill=(24, 26, 30) if r % 2 == 0 else (30, 33, 38))
        big = im.resize((480, 480), Image.LANCZOS)
        sheet.paste(big, (20, y + 40), big)
        d.text((560, y + 20), name, font=lab, fill=(230, 230, 230))
        x = 560
        for s in (192, 96, 48):
            sm = im.resize((s, s), Image.LANCZOS)
            sheet.paste(sm, (x, y + 160), sm)
            x += s + 40
        # on a light wallpaper too
        d.rectangle([x, y + 120, W - 20, y + 420], fill=(225, 228, 232))
        xx = x + 30
        for s in (96, 48):
            sm = im.resize((s, s), Image.LANCZOS)
            sheet.paste(sm, (xx, y + 200), sm)
            xx += s + 40
    sheet.save(f"{OUT}/compare.png")
    print("compare.png")


if __name__ == "__main__":
    main()
