# Icons built around the letters UAD: three treatments of the same idea — the name, an interceptor's
# trail rising from the city, and its burst on the apex of the A.
#   py draw_uad.py   -> u1_flag.png, u2_silver.png, u3_gold.png (1024 px) and compare_uad.png
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from draw import N, OUT, FONT, sky, add, glow, bezier, trail, flash, skyline, rounded, stars


def text_mask(text, var, size):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(var)
    m = Image.new("L", (N, N), 0)
    d = ImageDraw.Draw(m)
    bb = d.textbbox((0, 0), text, font=f)
    w, h = bb[2] - bb[0], bb[3] - bb[1]
    return f, w, h, bb


def letters(text, var, size, cx, cy, fill, rim=(255, 255, 255), rim_w=0, dark_rim=(2, 8, 24), dark_w=22, bevel=1.0):
    """The name as a layer: a gradient fill, a bevel (lit from above), a rim and a dark outline.
    fill(u) gives the colour at u = 0 (top of the letters) … 1 (bottom). Returns the layer, the
    letters' box and the apex of the A."""
    f, w, h, bb = text_mask(text, var, size)
    x0, y0 = cx - w / 2 - bb[0], cy - h / 2 - bb[1]
    m = Image.new("L", (N, N), 0)
    ImageDraw.Draw(m).text((x0, y0), text, font=f, fill=255)
    M = np.asarray(m).astype(np.float32) / 255.0
    ys = np.where(M.max(1) > 0.5)[0]
    top, bot = ys[0], ys[-1]
    u = np.clip((np.arange(N) - top) / max(1, bot - top), 0, 1)
    col = np.array([fill(v) for v in u], np.float32)  # one colour per row
    rgb = np.repeat(col[:, None, :], N, axis=1)
    # bevel: the blurred mask's slope, light from above, shade below
    e = np.asarray(m.filter(ImageFilter.GaussianBlur(14))).astype(np.float32) / 255.0
    k = 10
    hl = np.clip(e - np.roll(e, k, axis=0), 0, 1) * M
    sh = np.clip(e - np.roll(e, -k, axis=0), 0, 1) * M
    rgb = rgb * (1 - 0.55 * bevel * sh[..., None]) + 255 * 0.85 * bevel * hl[..., None]
    # a gloss over the upper half
    gl = (u < 0.45)[:, None].astype(np.float32) * 0.10
    rgb = rgb + (255 - rgb) * gl[..., None] * M[..., None]
    out = np.zeros((N, N, 4), np.float32)
    # the dark outline, then the light rim, then the letters
    if dark_w:
        dm = np.asarray(m.filter(ImageFilter.GaussianBlur(dark_w))).astype(np.float32) / 255.0
        dm = np.clip(dm * 3.0, 0, 1)
        out[..., :3] = np.array(dark_rim, np.float32)
        out[..., 3] = dm * 255
    if rim_w:
        rm = np.asarray(m.filter(ImageFilter.MaxFilter(rim_w))).astype(np.float32) / 255.0
        a = rm
        out[..., :3] = out[..., :3] * (1 - a[..., None]) + np.array(rim, np.float32) * a[..., None]
        out[..., 3] = np.maximum(out[..., 3], a * 255)
    out[..., :3] = out[..., :3] * (1 - M[..., None]) + np.clip(rgb, 0, 255) * M[..., None]
    out[..., 3] = np.maximum(out[..., 3], M * 255)
    lay = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))
    # the apex of the A: the topmost lit pixel between the U and the D
    d = ImageDraw.Draw(Image.new("L", (1, 1)))
    xa0 = x0 + d.textlength(text[0], font=f)
    xa1 = xa0 + d.textlength(text[1], font=f)
    cols = M[:, int(xa0):int(xa1)]
    ay = int(np.where(cols.max(1) > 0.5)[0][0])
    ax = int(xa0 + np.where(cols[ay] > 0.5)[0].mean())
    xs = np.where(M.max(0) > 0.5)[0]
    return lay, (xs[0], top, xs[-1], bot), (ax, ay)


HIT = (1560, 470)


def intercept(img, hot=(255, 232, 150)):
    """The threat comes down from the upper right, the interceptor climbs from the city on the left;
    they meet in the sky above the letters."""
    img = trail(img, bezier((2200, 40), (1900, 200), HIT), 6, 26, (110, 30, 20), (255, 100, 40), 30, 1.4)
    img = trail(img, bezier((110, 2000), (300, 640), HIT), 10, 52, (90, 120, 210), hot, 50, 2.0)
    return img


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def ramp(*stops):
    """fill(u) through colour stops [(u, colour), …]."""
    def f(u):
        for (u0, c0), (u1, c1) in zip(stops, stops[1:]):
            if u <= u1:
                return lerp(c0, c1, (u - u0) / max(1e-6, u1 - u0))
        return stops[-1][1]
    return f


def radar_rings(img, cx, cy, radii, col, width, alpha):
    lay = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    for r in radii:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col + (alpha,), width=width)
    return add(img, glow(lay, 10, 1.0)) if alpha else img


# ---------------------------------------------------------------- u1: the flag in the letters
def u1_bg():
    img = sky((3, 8, 24), (18, 42, 86), glow=(N * 0.5, N * 1.0, N * 0.75, (70, 55, 30), 1.0))
    img = stars(img, 130, seed=2, max_y=0.55)
    return skyline(img, 1880, seed=5, tower=False)


def from_black(img):
    """Light drawn on black as a layer with alpha (glows and trails for the Android foreground)."""
    a = np.asarray(img).astype(np.float32)
    al = a[..., :3].max(2)
    rgb = np.clip(a[..., :3] / np.maximum(al, 1)[..., None] * 255, 0, 255)
    return Image.fromarray(np.dstack([rgb, al]).astype(np.uint8))


def u1(layer="full"):
    """layer: "full" (the icon), "bg" (sky and city only), "fg" (trails, letters, burst on clear)."""
    if layer == "bg":
        return u1_bg()
    img = u1_bg() if layer == "full" else Image.new("RGBA", (N, N), (0, 0, 0, 255))
    flagfill = ramp((0, (90, 160, 255)), (0.5, (0, 92, 200)), (0.5001, (255, 222, 40)), (1, (255, 190, 0)))
    lay, box, (ax, ay) = letters("UAD", "Bold", 780, N / 2, N * 0.585, flagfill, rim=(250, 252, 255), rim_w=29, dark_w=34)
    img = intercept(img)
    img = add(img, glow(lay, 40, 0.35))
    if layer == "fg":
        img = Image.alpha_composite(from_black(img), lay)
        burst = from_black(flash(Image.new("RGBA", (N, N), (0, 0, 0, 255)), *HIT, 118, spikes=4, rot=0.32))
        return Image.alpha_composite(img, burst)
    img = Image.alpha_composite(img, lay)
    img = flash(img, *HIT, 118, spikes=4, rot=0.32)
    return img


# ---------------------------------------------------------------- u2: silver letters, the flag beneath
def u2():
    img = sky((2, 6, 18), (10, 26, 58), glow=(N * 0.5, N * 0.5, N * 0.55, (20, 50, 110), 1.0))
    img = radar_rings(img, N / 2, N * 0.52, (N * 0.44, N * 0.33, N * 0.22), (60, 130, 230), 8, 90)
    img = stars(img, 80, seed=9, max_y=0.4)
    silver = ramp((0, (255, 255, 255)), (0.48, (214, 224, 240)), (0.52, (150, 166, 190)), (1, (236, 242, 252)))
    lay, box, (ax, ay) = letters("UAD", "Bold", 760, N / 2, N * 0.57, silver, rim_w=0, dark_w=30)
    img = intercept(img)
    img = add(img, glow(lay, 46, 0.45))
    img = Image.alpha_composite(img, lay)
    d = ImageDraw.Draw(img)
    y = box[3] + 90
    d.rounded_rectangle([box[0], y, box[2], y + 52], 26, fill=(0, 87, 183, 255))
    d.rounded_rectangle([box[0], y + 52, box[2], y + 104], 26, fill=(255, 213, 0, 255))
    d.rectangle([box[0], y + 30, box[2], y + 74], fill=(0, 87, 183, 255))
    d.rectangle([box[0], y + 52, box[2], y + 74], fill=(255, 213, 0, 255))
    img = flash(img, *HIT, 118, spikes=4, rot=0.32)
    return img


# ---------------------------------------------------------------- u3: golden letters on the blue
def u3():
    img = sky((6, 40, 118), (2, 14, 48))
    yy, xx = np.mgrid[0:N, 0:N]
    d = np.sqrt((xx - N * 0.5) ** 2 + (yy - N * 0.42) ** 2) / N
    light = np.zeros((N, N, 4), np.uint8)
    light[..., 0], light[..., 1], light[..., 2] = 40, 110, 220
    light[..., 3] = (np.exp(-(d / 0.33) ** 2) * 150).astype(np.uint8)
    img = add(img, Image.fromarray(light))
    img = radar_rings(img, N / 2, N * 0.52, (N * 0.46, N * 0.35), (120, 180, 255), 6, 60)
    img = stars(img, 90, seed=11, max_y=0.5)
    img = skyline(img, 1900, color=(2, 10, 34), seed=8)
    gold = ramp((0, (255, 246, 190)), (0.35, (255, 220, 60)), (0.62, (240, 180, 0)), (0.66, (255, 214, 40)), (1, (205, 140, 0)))
    lay, box, (ax, ay) = letters("UAD", "Bold", 780, N / 2, N * 0.585, gold, rim=(255, 250, 225), rim_w=13, dark_rim=(1, 10, 40), dark_w=36)
    img = intercept(img)
    img = add(img, glow(lay, 50, 0.4))
    img = Image.alpha_composite(img, lay)
    img = flash(img, *HIT, 118, col=(255, 250, 220), spikes=4, rot=0.32)
    return img


def sheet(rows, path):
    W, H = 1500, 560 * len(rows)
    sh = Image.new("RGB", (W, H), (24, 26, 30))
    d = ImageDraw.Draw(sh)
    lab = ImageFont.truetype(FONT, 34)
    for r, (name, im) in enumerate(rows):
        y = r * 560 + 24
        d.rectangle([0, y - 24, W, y + 536], fill=(24, 26, 30) if r % 2 == 0 else (30, 33, 38))
        big = im.resize((480, 480), Image.LANCZOS)
        sh.paste(big, (20, y + 40), big)
        d.text((560, y + 20), name, font=lab, fill=(230, 230, 230))
        x = 560
        for s in (192, 96, 48):
            sm = im.resize((s, s), Image.LANCZOS)
            sh.paste(sm, (x, y + 160), sm)
            x += s + 40
        d.rectangle([x, y + 120, W - 20, y + 420], fill=(225, 228, 232))
        xx = x + 30
        for s in (96, 48):
            sm = im.resize((s, s), Image.LANCZOS)
            sh.paste(sm, (xx, y + 200), sm)
            xx += s + 40
    sh.save(path)


def main():
    rows = []
    for name, fn in (("u1_flag", u1), ("u2_silver", u2), ("u3_gold", u3)):
        im = rounded(fn()).resize((1024, 1024), Image.LANCZOS)
        im.save(f"{OUT}/{name}.png")
        rows.append((name, im))
        print("made", name)
    sheet(rows, f"{OUT}/compare_uad.png")


if __name__ == "__main__":
    main()


HIT_L = (1600, 740)  # the logo's burst sits closer to the letters than the icon's


def logo():
    """The menu's wordmark: u1's letters and intercept on a clear background, cropped to them."""
    flagfill = ramp((0, (90, 160, 255)), (0.5, (0, 92, 200)), (0.5001, (255, 222, 40)), (1, (255, 190, 0)))
    lay, box, _ = letters("UAD", "Bold", 780, N / 2, N * 0.585, flagfill, rim=(250, 252, 255), rim_w=29, dark_w=34)
    img = Image.new("RGBA", (N, N), (0, 0, 0, 255))
    img = trail(img, bezier((2010, 470), (1860, 560), HIT_L), 6, 26, (110, 30, 20), (255, 100, 40), 30, 1.4)
    img = trail(img, bezier((300, 1180), (430, 640), HIT_L), 10, 52, (90, 120, 210), (255, 232, 150), 50, 2.0)
    img = add(img, glow(lay, 40, 0.35))
    img = Image.alpha_composite(from_black(img), lay)
    burst = from_black(flash(Image.new("RGBA", (N, N), (0, 0, 0, 255)), *HIT_L, 92, spikes=4, rot=0.32))
    img = Image.alpha_composite(img, burst)
    a = np.asarray(img)[..., 3]
    ys, xs = np.where(a > 60)  # the faint outer halo may be cut: it fades to nothing anyway
    pad = 30
    return img.crop((max(0, xs.min() - pad), max(0, ys.min() - pad), min(N, xs.max() + pad), min(N, ys.max() + pad)))
