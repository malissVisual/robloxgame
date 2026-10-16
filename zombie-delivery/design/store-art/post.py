"""The finishing step for the store art: grade, bloom, the titles, the rarity tags, the money chips and the DELIVEROS
logo (its outline, shadow, glints and tagline ribbon).

python post.py <logo|logo-tagline> <logo_raw.png> <out.png>       the logo (make these first: the rest put it on)
python post.py <t0|t1|t2|t3|icon|icon-box> <raw.png> <out.png>   (the raw render's .json next to it holds the tags'
                                                                 places; the logo comes from art/store/)
"""
import json
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT_TITLE = os.path.join(HERE, "fonts", "LuckiestGuy-Regular.ttf")
FONT_UI = os.path.join(HERE, "fonts", "LilitaOne-Regular.ttf")
STORE = os.path.abspath(os.path.join(HERE, "..", "..", "art", "store"))
LOGO = os.environ.get("DELIVEROS_LOGO", os.path.join(STORE, "deliveros-logo.png"))
LOGO_TAGLINE = os.environ.get("DELIVEROS_LOGO_TAGLINE", os.path.join(STORE, "deliveros-logo-tagline.png"))


def logo_image(tagline=False):
    return Image.open(LOGO_TAGLINE if tagline else LOGO).convert("RGBA")
INK = (22, 24, 30)
ZDC_RED = (214, 34, 40)
WHITE = (255, 255, 255)
GREEN = (74, 206, 96)
RARITY = {"common": (178, 182, 188), "uncommon": (92, 196, 104), "rare": (70, 144, 240), "epic": (178, 96, 236),
          "legendary": (255, 178, 36)}  # (Config.Collection.Tiers' colours)


def font(path, size):
    return ImageFont.truetype(path, size)


# ── the picture ──────────────────────────────────────────────────────────────

def grade(im, sat=1.14, contrast=1.06, bright=1.02):
    im = ImageEnhance.Color(im).enhance(sat)
    im = ImageEnhance.Contrast(im).enhance(contrast)
    return ImageEnhance.Brightness(im).enhance(bright)


def bloom(im, threshold=200, strength=0.55, radii=(14, 46)):
    """What is bright glows: its light blurred and added back (screen)."""
    lum = im.convert("L").point(lambda v: 0 if v < threshold else int((v - threshold) * 255 / (255 - threshold)))
    bright = Image.composite(im, Image.new("RGB", im.size), lum)
    out = im
    for r in radii:
        glow = bright.filter(ImageFilter.GaussianBlur(r * im.width / 1920))
        glow = ImageEnhance.Brightness(glow).enhance(strength)
        out = ImageChops.screen(out, glow)
    return out


def vignette(im, amount=0.28):
    w, h = im.size
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse((-w * 0.25, -h * 0.35, w * 1.25, h * 1.35), fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(w * 0.12))
    dark = ImageEnhance.Brightness(im).enhance(1 - amount)
    return Image.composite(im, dark, mask)


def rays(im, at, color, count=14, length=0.6, alpha=70, spin=0.0):
    """Soft light rays from a point (a legendary find's burst)."""
    w, h = im.size
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = at[0] * w, at[1] * h
    r = length * w
    for i in range(count):
        a = spin + i * 2 * math.pi / count
        da = math.pi / count * 0.45
        d.polygon([(cx, cy), (cx + r * math.cos(a - da), cy + r * math.sin(a - da)),
                   (cx + r * math.cos(a + da), cy + r * math.sin(a + da))], fill=color + (alpha,))
    fade = Image.new("L", (w, h), 0)
    ImageDraw.Draw(fade).ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    fade = fade.filter(ImageFilter.GaussianBlur(r * 0.35))
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), fade))
    layer = layer.filter(ImageFilter.GaussianBlur(w * 0.004))
    base = im.convert("RGBA")
    return Image.alpha_composite(base, layer).convert("RGB")


def sparkle(d, x, y, r, color=(255, 255, 255, 255)):
    pts = []
    for i in range(8):
        a = i * math.pi / 4
        rr = r if i % 2 == 0 else r * 0.22
        pts.append((x + rr * math.cos(a), y + rr * math.sin(a)))
    d.polygon(pts, fill=color)


def sparkles(im, spots, color=(255, 246, 210)):
    """Four-pointed glints (with their own small glow)."""
    w, h = im.size
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for (x, y, r) in spots:
        sparkle(d, x * w, y * h, r * w, color + (255,))
    glow = layer.filter(ImageFilter.GaussianBlur(w * 0.006))
    base = im.convert("RGBA")
    base = Image.alpha_composite(base, glow)
    base = Image.alpha_composite(base, layer)
    return base.convert("RGB")


# ── words ────────────────────────────────────────────────────────────────────

def gradient(size, top, bottom):
    w, h = size
    g = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        g.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return g.resize((w, h))


def title(im, text, at, size, fill=((255, 255, 255), (255, 226, 120)), stroke=INK, stroke_w=None, rot=-4.0,
          anchor="la", shadow=True):
    """A chunky outlined title (a gradient inside, a thick dark outline, a drop shadow), a little tilted."""
    w, h = im.size
    f = font(FONT_TITLE, size)
    sw = stroke_w if stroke_w is not None else max(4, size // 7)
    pad = sw * 3 + size // 2
    box = ImageDraw.Draw(Image.new("L", (1, 1))).textbbox((0, 0), text, font=f, stroke_width=sw)
    tw, th = box[2] - box[0] + pad * 2, box[3] - box[1] + pad * 2
    layer = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    ox, oy = pad - box[0], pad - box[1]
    if shadow:
        sh = Image.new("L", (tw, th), 0)
        ImageDraw.Draw(sh).text((ox + sw * 0.5, oy + sw * 1.1), text, font=f, fill=200, stroke_width=sw, stroke_fill=200)
        sh = sh.filter(ImageFilter.GaussianBlur(sw * 0.6))
        layer.paste(Image.new("RGBA", (tw, th), (0, 0, 0, 255)), (0, 0), sh)
    out = Image.new("L", (tw, th), 0)
    ImageDraw.Draw(out).text((ox, oy), text, font=f, fill=255, stroke_width=sw, stroke_fill=255)
    layer.paste(Image.new("RGBA", (tw, th), stroke + (255,)), (0, 0), out)
    inner = Image.new("L", (tw, th), 0)
    ImageDraw.Draw(inner).text((ox, oy), text, font=f, fill=255)
    top, bottom = fill
    g = gradient((tw, box[3] - box[1]), top, bottom)
    gfull = Image.new("RGB", (tw, th), bottom)
    gfull.paste(g, (0, oy + box[1]))
    layer.paste(gfull, (0, 0), inner)
    layer = layer.rotate(rot, resample=Image.BICUBIC, expand=True)
    layer = layer.crop(layer.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox())
    x, y = at[0] * w, at[1] * h
    if anchor[0] == "m":
        x -= layer.width / 2
    elif anchor[0] == "r":
        x -= layer.width
    if anchor[1] == "m":
        y -= layer.height / 2
    elif anchor[1] == "b":
        y -= layer.height
    base = im.convert("RGBA")
    base.alpha_composite(layer, (int(x), int(y)))
    return base.convert("RGB"), layer.size


def pill(im, at, text, color, size, sub=None, text_color=None, back=(20, 22, 28, 230), pointer=True, side="down"):
    """A game-UI tag: a dark rounded pill with a coloured rim, its word in the colour, a pointer down to the piece."""
    w, h = im.size
    f = font(FONT_UI, size)
    fs = font(FONT_UI, int(size * 0.62)) if sub else None
    d0 = ImageDraw.Draw(Image.new("L", (1, 1)))
    tb = d0.textbbox((0, 0), text, font=f)
    tw = tb[2] - tb[0]
    sb = d0.textbbox((0, 0), sub, font=fs) if sub else (0, 0, 0, 0)
    sw_ = sb[2] - sb[0]
    padx, pady = size * 0.6, size * 0.32
    bw = max(tw, sw_) + padx * 2
    bh = (tb[3] - tb[1]) + pady * 2 + ((sb[3] - sb[1]) + size * 0.22 if sub else 0)
    rim = max(3, size // 9)
    layer = Image.new("RGBA", (int(bw + size * 0.6 + rim * 4), int(bh + size * 0.6 + rim * 4)), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x0, y0 = rim * 2, rim * 2
    r = bh * 0.32
    d.rounded_rectangle((x0, y0, x0 + bw, y0 + bh), r, fill=back, outline=color + (255,), width=rim)
    p = size * 0.42
    if pointer and side == "down":
        cx = x0 + bw / 2
        d.polygon([(cx - p, y0 + bh - rim), (cx + p, y0 + bh - rim), (cx, y0 + bh + p)], fill=color + (255,))
    elif pointer and side == "right":
        cy = y0 + bh / 2
        d.polygon([(x0 + bw - rim, cy - p), (x0 + bw - rim, cy + p), (x0 + bw + p, cy)], fill=color + (255,))
    d.text((x0 + (bw - tw) / 2 - tb[0], y0 + pady - tb[1]), text, font=f, fill=(text_color or color) + (255,))
    if sub:
        d.text((x0 + (bw - sw_) / 2 - sb[0], y0 + pady + (tb[3] - tb[1]) + size * 0.22 - sb[1]), sub, font=fs, fill=WHITE + (255,))
    glow = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.rounded_rectangle((x0, y0, x0 + bw, y0 + bh), r, fill=color + (120,))
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.35))
    if side == "right":  # (at: the pointer's tip)
        x = at[0] * w - (x0 + bw + p)
        y = at[1] * h - (y0 + bh / 2)
    else:  # (at: under the pointer)
        x = at[0] * w - layer.width / 2
        y = at[1] * h - (y0 + bh + (p if pointer else 0))
    base = im.convert("RGBA")
    base.alpha_composite(glow, (int(x), int(y)))
    base.alpha_composite(layer, (int(x), int(y)))
    return base.convert("RGB")


def money_chip(im, at, text, size):
    """"+$105/min": a green chip with a coin (the stands' income)."""
    w, h = im.size
    f = font(FONT_UI, size)
    tb = ImageDraw.Draw(Image.new("L", (1, 1))).textbbox((0, 0), text, font=f)
    tw, th = tb[2] - tb[0], tb[3] - tb[1]
    coin = size * 1.05
    padx, pady = size * 0.45, size * 0.28
    bw, bh = coin + size * 0.3 + tw + padx * 2, max(th, coin) + pady * 2
    rim = max(3, size // 10)
    layer = Image.new("RGBA", (int(bw + rim * 4), int(bh + rim * 4)), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x0, y0 = rim * 2, rim * 2
    d.rounded_rectangle((x0, y0, x0 + bw, y0 + bh), bh / 2, fill=(26, 70, 36, 235), outline=GREEN + (255,), width=rim)
    cx, cy = x0 + padx + coin / 2, y0 + bh / 2
    d.ellipse((cx - coin / 2, cy - coin / 2, cx + coin / 2, cy + coin / 2), fill=(255, 204, 60, 255), outline=(176, 120, 20, 255),
              width=max(2, rim - 1))
    fc = font(FONT_UI, int(size * 0.8))
    cb = d.textbbox((0, 0), "$", font=fc)
    d.text((cx - (cb[2] - cb[0]) / 2 - cb[0], cy - (cb[3] - cb[1]) / 2 - cb[1]), "$", font=fc, fill=(150, 96, 10, 255))
    d.text((x0 + padx + coin + size * 0.3 - tb[0], y0 + (bh - th) / 2 - tb[1]), text, font=f, fill=(196, 255, 190, 255))
    x = at[0] * w - layer.width / 2
    y = at[1] * h - layer.height / 2
    base = im.convert("RGBA")
    base.alpha_composite(layer, (int(x), int(y)))
    return base.convert("RGB")


# ── the DELIVEROS logo ───────────────────────────────────────────────────────

def dilate(alpha, r):
    """The alpha grown by about r pixels (a blur, then a threshold: fast at any size), its edge smoothed."""
    grown = alpha.filter(ImageFilter.GaussianBlur(r * 0.5)).point(lambda v: 255 if v > 6 else 0)
    return grown.filter(ImageFilter.GaussianBlur(max(1, r * 0.06)))


def logo_finish(raw, ribbon=False):
    """The rendered wordmark (transparent) → the logo: a thick dark outline, a soft drop shadow, a glint; with
    ribbon, a red MOVE · FIND · GROW ribbon under it. Cropped to itself (a small margin)."""
    word = raw.convert("RGBA")
    a = word.getchannel("A").point(lambda v: 255 if v > 40 else int(v * 255 / 40))
    w, h = word.size
    r = int(w * 0.016)
    pad = r * 4
    canvas = Image.new("RGBA", (w + pad * 2, h + pad * 2 + (int(h * 0.36) if ribbon else 0)), (0, 0, 0, 0))
    full_a = Image.new("L", canvas.size, 0)
    full_a.paste(a, (pad, pad))
    outline = dilate(full_a, r)
    shadow = outline.filter(ImageFilter.GaussianBlur(r * 0.8)).point(lambda v: int(v * 0.6))
    canvas.paste(Image.new("RGBA", canvas.size, (0, 0, 0, 255)), (int(r * 0.4), int(r * 1.1)), shadow)
    canvas.paste(Image.new("RGBA", canvas.size, INK + (255,)), (0, 0), outline)
    canvas.alpha_composite(word, (pad, pad))
    if ribbon:
        d = ImageDraw.Draw(canvas)
        bb = full_a.getbbox()
        rh = h * 0.24
        f = font(FONT_UI, int(rh * 0.56))
        words = ["MOVE", "FIND", "GROW"]
        widths = [d.textbbox((0, 0), t, font=f)[2] for t in words]
        gap = rh * 0.62
        total = sum(widths) + gap * 2
        rw = total + rh * 1.5
        cx = (bb[0] + bb[2]) / 2
        top = bb[3] - h * 0.04
        ribbon_poly = [(cx - rw / 2, top), (cx + rw / 2, top), (cx + rw / 2 - rh * 0.25, top + rh), (cx - rw / 2 + rh * 0.25, top + rh)]
        rib = Image.new("L", canvas.size, 0)
        ImageDraw.Draw(rib).polygon(ribbon_poly, fill=255)
        canvas.paste(Image.new("RGBA", canvas.size, INK + (255,)), (0, 0), dilate(rib, r * 0.8))
        d.polygon(ribbon_poly, fill=ZDC_RED + (255,))
        x = cx - total / 2
        tb = d.textbbox((0, 0), "MOVE", font=f)
        y = top + (rh - (tb[3] - tb[1])) / 2 - tb[1]
        for i, t in enumerate(words):
            d.text((x, y), t, font=f, fill=WHITE + (255,))
            x += widths[i]
            if i < 2:
                dot = rh * 0.09
                d.ellipse((x + gap / 2 - dot, top + rh / 2 - dot, x + gap / 2 + dot, top + rh / 2 + dot), fill=(255, 214, 90, 255))
                x += gap
    # a glint on the last letter's top (only there: one over a letter reads as an accent)
    bb = full_a.getbbox()
    glints = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glints)
    sparkle(gd, bb[2] - (bb[2] - bb[0]) * 0.07, bb[1] + h * 0.09, w * 0.03, (255, 255, 255, 255))
    canvas.alpha_composite(glints.filter(ImageFilter.GaussianBlur(w * 0.004)))
    canvas.alpha_composite(glints)
    return canvas.crop(canvas.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox())


def place_logo(im, logo, at, width, anchor="ma"):
    """The logo, `width` (share of the picture's width) wide, its anchor point at `at` (0…1)."""
    w, h = im.size
    lw = int(w * width)
    lg = logo.resize((lw, int(logo.height * lw / logo.width)), Image.LANCZOS)
    x, y = at[0] * w, at[1] * h
    if anchor[0] == "m":
        x -= lg.width / 2
    elif anchor[0] == "r":
        x -= lg.width
    if anchor[1] == "m":
        y -= lg.height / 2
    elif anchor[1] == "b":
        y -= lg.height
    base = im.convert("RGBA")
    base.alpha_composite(lg, (int(x), int(y)))
    return base.convert("RGB")


# ── the pictures ─────────────────────────────────────────────────────────────

def marks_of(raw):
    p = os.path.splitext(raw)[0] + ".json"
    return json.load(open(p)) if os.path.exists(p) else {}


def t1(im, m):
    im = grade(im, sat=1.16, contrast=1.07)
    im = bloom(im, threshold=225, strength=0.35)
    im = vignette(im, 0.22)
    im, size = title(im, "MOVE HOUSES", (0.02, 0.025), 168, rot=-3)
    im, _ = title(im, "WITH YOUR CREW!", (0.045, 0.025 + size[1] / 1080 - 0.045), 84, fill=((255, 92, 92), (214, 34, 40)),
                  stroke=WHITE, rot=-3)
    im = place_logo(im, logo_image(), (0.985, 0.025), 0.27, anchor="ra")
    return im


def t2(im, m):
    im = grade(im, sat=1.12, contrast=1.08)
    tx, ty = m.get("trophy", (0.39, 0.17))
    im = rays(im, (tx, ty + 0.2), (255, 214, 120), count=16, length=0.4, alpha=36, spin=0.1)
    im = bloom(im, threshold=190, strength=0.6)
    im = vignette(im, 0.3)
    im = sparkles(im, [(tx - 0.07, ty + 0.05, 0.016), (tx + 0.08, ty + 0.12, 0.012), (tx + 0.03, ty - 0.03, 0.01),
                       (tx - 0.04, ty + 0.3, 0.012), (tx + 0.1, ty + 0.33, 0.009)])
    im = pill(im, (tx - 0.075, ty + 0.17), "LEGENDARY!", RARITY["legendary"], 60, sub="$5,800", side="right")
    if "guitar" in m:
        im = pill(im, (m["guitar"][0], m["guitar"][1]), "EPIC", RARITY["epic"], 44)
    if "gramophone" in m:
        im = pill(im, (m["gramophone"][0], m["gramophone"][1]), "RARE", RARITY["rare"], 40)
    im, _ = title(im, "FIND RARE", (0.975, 0.02), 150, anchor="ra", rot=3)
    im, _ = title(im, "TREASURES!", (0.975, 0.19), 150, anchor="ra", rot=3, fill=((255, 240, 160), (255, 178, 36)))
    im = place_logo(im, logo_image(), (0.015, 0.025), 0.25, anchor="la")
    return im


INCOME = {"legendary": "+$105/min", "epic": "+$32/min", "rare": "+$14/min", "uncommon": "+$6/min"}
CHIPS = ("F_zombie_safe", "F_trex_skull", "F_ski_trophy", "F_alphorn", "F_golden_horseshoe")  # (the chips that do not overlap)


def t3(im, m):
    im = grade(im, sat=1.14, contrast=1.08)
    im = bloom(im, threshold=200, strength=0.5)
    im = vignette(im, 0.25)
    for key, (x, y) in m.items():
        name, rarity = key.split("|")
        if name in CHIPS and 0.06 < x < 0.94:
            im = money_chip(im, (x, y - 0.03), INCOME[rarity], 40 if rarity == "legendary" else 32)
    im, _ = title(im, "BUILD YOUR", (0.5, 0.015), 120, anchor="ma", rot=0)
    im, _ = title(im, "WAREHOUSE EMPIRE", (0.5, 0.135), 150, anchor="ma", rot=0, fill=((255, 240, 160), (255, 178, 36)))
    im = pill(im, (0.155, 0.965), "UPGRADE TO LEVEL 5", ZDC_RED, 44, text_color=WHITE, back=(214, 34, 40, 235), pointer=False)
    im = place_logo(im, logo_image(), (0.985, 0.025), 0.2, anchor="ra")
    return im


def t0(im, m):
    """The title card: the big logo (its tagline) over the key art, the legendary find tagged."""
    im = grade(im, sat=1.16, contrast=1.07)
    im = bloom(im, threshold=215, strength=0.45)
    im = vignette(im, 0.22)
    if "skull" in m:
        sx, sy = m["skull"]
        im = sparkles(im, [(sx - 0.015, sy + 0.075, 0.011), (sx + 0.045, sy + 0.06, 0.008)])
        im = pill(im, (sx, sy), "LEGENDARY!", RARITY["legendary"], 40)
    im = place_logo(im, logo_image(tagline=True), (0.5, 0.02), 0.6, anchor="ma")
    return im


def sunburst(w, h, at=(0.5, 0.42)):
    bg = Image.new("RGB", (w, h), (214, 34, 40))
    g = ImageDraw.Draw(bg)
    for i in range(w // 2, 0, -2):
        t = i / (w / 2)
        c = tuple(int(a + (b - a) * t) for a, b in zip((255, 214, 92), (214, 34, 40)))
        g.ellipse((w * at[0] - i * 1.5, h * at[1] - i * 1.5, w * at[0] + i * 1.5, h * at[1] + i * 1.5), fill=c)
    return rays(bg, at, (255, 244, 200), count=18, length=0.9, alpha=55, spin=0.15)


def subject(sub, w, h, top, bottom, dx=0.0):
    """The transparent render's subject as big as fits between `top` and `bottom` (shares of the height), centred."""
    bb = sub.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    cut = sub.crop(bb)
    k = min(h * (bottom - top) / cut.height, w * 0.98 / cut.width)
    cut = cut.resize((int(cut.width * k), int(cut.height * k)), Image.LANCZOS)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.alpha_composite(cut, (int((w - cut.width) / 2 + w * dx), int(h * bottom - cut.height)))
    return out


def icon_from(im, top, bottom, dx, logo_at, logo_anchor, burst_at, glints):
    w, h = im.size
    bg = sunburst(w, h, burst_at)
    sub = subject(im.convert("RGBA"), w, h, top, bottom, dx)
    shadow = Image.new("RGBA", sub.size, (0, 0, 0, 0))
    shadow.putalpha(sub.getchannel("A").filter(ImageFilter.GaussianBlur(w * 0.012)).point(lambda v: v * 0.55))
    out = bg.convert("RGBA")
    out.alpha_composite(shadow, (int(w * 0.008), int(h * 0.012)))
    out.alpha_composite(sub)
    out = out.convert("RGB")
    out = grade(out, sat=1.1, contrast=1.05)
    out = bloom(out, threshold=215, strength=0.45)
    out = sparkles(out, glints)
    return place_logo(out, logo_image(), logo_at, 0.94, anchor=logo_anchor)


def icon(im, m):
    """Icon A: the courier holds the legendary find up, DELIVEROS across the bottom."""
    return icon_from(im, 0.02, 0.86, 0.03, (0.5, 0.985), "mb", (0.45, 0.36), [(0.64, 0.1, 0.03), (0.88, 0.28, 0.022), (0.14, 0.3, 0.02)])


def icon_box(im, m):
    """Icon B: the open box glowing, the find rising out of it, DELIVEROS across the top."""
    return icon_from(im, 0.22, 1.03, 0.0, (0.5, 0.025), "ma", (0.5, 0.55), [(0.2, 0.5, 0.026), (0.82, 0.46, 0.022), (0.7, 0.86, 0.016)])


if __name__ == "__main__":
    kind, raw, out = sys.argv[1], sys.argv[2], sys.argv[3]
    im = Image.open(raw)
    if kind in ("logo", "logo-tagline"):
        logo_finish(im, ribbon=kind == "logo-tagline").save(out, optimize=True)
        print("saved", out)
        sys.exit(0)
    if kind not in ("icon", "icon-box"):
        im = im.convert("RGB")
    result = {"t0": t0, "t1": t1, "t2": t2, "t3": t3, "icon": icon, "icon-box": icon_box}[kind](im, marks_of(raw))
    if kind.startswith("icon"):
        result = result.resize((512, 512), Image.LANCZOS)
    result.save(out, optimize=True)
    print("saved", out, result.size)
