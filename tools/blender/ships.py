"""Builds every Driftlight ship as a GLB.

Run:  blender --background --python ships.py [-- ship_id ...]

Player ships are built from the same shape numbers the game uses (Game.SHIPS: body size, gap to the gun
pods, pod size, gun count, stripe style, colours), so a ship keeps its identity from the 2D version:
a boxy hull with gun pods spaced down both sides. Each player ship carries empties named Gun_N (turret
mounts, in gun-slot order: front-left, front-right, second-left, ...) and Engine_N; pirates carry fixed
Muzzle_N guns instead. turret.glb is the moving gun turret the game sets on every Gun_N mount.
"""
import json
import math
import os
import random
import sys

from mathutils import Vector

sys.path.append(os.path.dirname(__file__))
from common import *  # noqa: E402,F401,F403

U = 0.55  # metres per old pixel-art pixel


def shade(h, k):
    """A hex colour darkened (k < 1) or lightened (k > 1)."""
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) for i in (0, 2, 4)]
    if k < 1:
        c = [int(v * k) for v in c]
    else:
        c = [int(v + (255 - v) * (k - 1)) for v in c]
    return "%02x%02x%02x" % tuple(max(0, min(255, v)) for v in c)

# id: (body w, body h, gap, pod, guns, style, hull, accent, glass)  - mirrors Game.SHIPS
SHIPS = {
    "wren": (9, 11, 2, 4, 2, "h", "b8c4d6", "4a7fd0", "7ff0ff"),
    "sparrow": (5, 9, 2, 4, 2, "v", "e6e0c8", "e07a3c", "9dfcff"),
    "mule": (11, 13, 3, 4, 2, "x", "c9a46a", "8a5a2e", "7ff0ff"),
    "prospector": (13, 13, 2, 6, 2, "h", "d9b23c", "3a3a3a", "ffe066"),
    "kestrel": (5, 10, 4, 4, 2, "v", "e8f0ea", "3fc46a", "9dfcff"),
    "corsair": (7, 11, 4, 6, 2, "x", "2e3440", "e04848", "ffd24a"),
    "lancer": (5, 15, 3, 4, 2, "v", "cfd6e6", "7a5cff", "b9a6ff"),
    "aegis": (11, 11, 3, 4, 2, "h", "dfe9ff", "4fd6ff", "4fd6ff"),
    "bastion": (11, 15, 3, 4, 4, "x", "8a8f9c", "b8433a", "ffd27a"),
    "specter": (7, 12, 2, 4, 2, "n", "2a2f3a", "4a5468", "6fffd8"),
    "nyx": (7, 11, 4, 4, 2, "v", "3c2c55", "b366ff", "f0b0ff"),
    "leviathan": (17, 19, 3, 4, 4, "x", "6b7080", "d9b23c", "7ff0ff"),
    "seraph": (9, 15, 4, 4, 4, "h", "fff0f6", "ff5fa2", "ffe066"),
    "halberd": (13, 21, 3, 4, 4, "x", "9aa4b4", "2fb8a8", "bff4ff"),
    "monarch": (17, 27, 3, 4, 6, "h", "2c3e66", "e8b84a", "ffe7a3"),
    "behemoth": (21, 33, 4, 4, 8, "x", "6a3a40", "d8433a", "ffb36b"),
    "ark": (27, 37, 3, 4, 6, "v", "8a8170", "4a7fd0", "7ff0ff"),
    "titan": (25, 43, 4, 4, 10, "n", "4a4462", "9b4dff", "e0a0ff"),
}


class Block:
    """The surfaces of a (tapered) box, for placing details on it. taper narrows the +Y end like box()."""

    def __init__(self, w, l, h, y=0.0, z=0.0, taper=(1.0, 1.0)):
        self.w, self.l, self.h, self.y, self.z, self.taper = w, l, h, y, z, taper
        self.slope = w / 2 * (taper[0] - 1) / l

    def t(self, y):
        return (y - self.y) / self.l + 0.5

    def hw(self, y):
        return self.w / 2 * (1 + (self.taper[0] - 1) * self.t(y))

    def hh(self, y):
        return self.h / 2 * (1 + (self.taper[1] - 1) * self.t(y))

    def top(self, y):
        return self.z + self.hh(y)

    def bottom(self, y):
        return self.z - self.hh(y)

    def covers(self, x, y):
        return abs(y - self.y) <= self.l / 2 and abs(x) <= self.hw(y)

    def side(self, sx, yc, zc, along=True):
        """Frame on the left (sx=-1) or right side. along: local x runs down the hull, else local y does."""
        T = Vector((sx * self.slope, 1, 0)).normalized()
        if along:
            u, v = (T if sx > 0 else -T), Vector((0, 0, 1))
        else:
            u, v = Vector((0, 0, -sx)), T
        return frame((sx * self.hw(yc), yc, zc), u, v, u.cross(v))

    def build(self, name, mats, parent, rng, cell, chamfer=0.0, depth=0.04, seam=0.035):
        return plated(name, (self.w, self.l, self.h), (0, self.y, self.z), mats, parent, taper=self.taper, cell=cell,
                      rng=rng, chamfer=chamfer, depth=depth, seam=seam)


UP = Vector((0, 0, 1))
TOP = (Vector((1, 0, 0)), Vector((0, 1, 0)), UP)
BOTTOM = (Vector((1, 0, 0)), Vector((0, -1, 0)), -UP)


def player_ship(sid):
    bw, bh, gap, pod, guns, style, c_hull, c_acc, c_glass = SHIPS[sid]
    rng = random.Random(sid)
    W, L = bw * U, bh * U
    H = max(1.4, W * 0.32)
    big = bw >= 13
    cell = 0.6 + W * 0.03
    gs = 0.45 + W * 0.035  # greeble scale

    hull = mat(sid + "_hull", c_hull, 0.45, 0.42)
    hull2 = mat(sid + "_hull2", shade(c_hull, 0.8), 0.5, 0.5)
    seam = mat(sid + "_seam", shade(c_hull, 0.25), 0.6, 0.75)
    acc = mat(sid + "_accent", c_acc, 0.35, 0.4)
    acc2 = mat(sid + "_accent2", shade(c_acc, 0.7), 0.4, 0.45)
    glass = mat(sid + "_glass", shade(c_glass, 0.7), 0.1, 0.1, emit=0.7)
    win = mat(sid + "_window", shade(c_glass, 1.25), 0.0, 0.3, emit=4.0)
    dark = mat("dark_metal", "1c2230", 0.6, 0.6)
    gunm = mat("gun_metal", "3a4050", 0.8, 0.35)
    deck = mat(sid + "_deck", shade(c_hull, 0.62), 0.45, 0.6)
    greeb = mat(sid + "_greeble", shade(c_hull, 0.5), 0.6, 0.5)
    eng = mat("engine_glow", "ff9a3d", 0.0, 0.3, emit=1.1)
    eng_core = mat("engine_core", "ffd9a0", 0.0, 0.3, emit=1.8)
    navr = mat("nav_red", "ff3030", 0.0, 0.3, emit=8.0)
    navg = mat("nav_green", "30ff70", 0.0, 0.3, emit=8.0)
    strobe = mat("strobe", "ffffff", 0.0, 0.3, emit=16.0)
    amber = mat("running_light", "ffc060", 0.0, 0.3, emit=6.0)
    P = [hull, seam, hull2]
    D = [deck, seam, hull2]
    A = [acc, seam, acc2]
    G = [gunm, dark, greeb]

    r = root(sid)
    body = root(sid + "_parts")
    body.parent = r
    g = Greebler(body, rng, greeb, dark, acc2, amber)

    hb = Block(W, L, H, taper=(0.9, 0.86))
    hb.build("hull", P, body, rng, cell, chamfer=min(W, H) * 0.07, depth=0.03 + W * 0.003, seam=0.03 + W * 0.002)
    blocks = [hb]

    def deck_z(x, y):
        return max([b.top(y) for b in blocks if b.covers(x, y)] or [hb.top(y)])

    def top_patch(x0, x1, y0, y1, count, kinds=None, scale=gs):
        if x1 - x0 < 0.3 or y1 - y0 < 0.3 or count <= 0:
            return
        xc, yc = (x0 + x1) / 2, (y0 + y1) / 2
        g.patch(frame((xc, yc, 0), *TOP), x1 - x0, y1 - y0, count, scale,
                lift=lambda x, y: deck_z(xc + x, yc + y), kinds=kinds)

    # layered superstructure on mid-size and bigger hulls
    sups = []
    if bw >= 9:
        s1 = Block(W * 0.6, L * 0.46, H * 0.3 + 0.25, y=-L * 0.12, taper=(0.8, 0.9))
        s1.z = hb.top(s1.y) + s1.h / 2 - 0.06
        s1.build("super1", P, body, rng, cell * 0.8, chamfer=s1.h * 0.18)
        sups.append(s1)
        if big:
            s2 = Block(W * 0.34, L * 0.26, H * 0.28 + 0.25, y=s1.y - L * 0.05, taper=(0.82, 0.9))
            s2.z = s1.top(s2.y) + s2.h / 2 - 0.06
            s2.build("super2", P, body, rng, cell * 0.7, chamfer=s2.h * 0.2)
            sups.append(s2)
    blocks += sups

    # side armour, intakes and the engine block
    sa = Block(0.24 + W * 0.012, L * 0.55, H * 0.5)
    for sx in (-1, 1):
        y = -L * 0.08
        plated("side_armor", (sa.w, sa.l, sa.h), (sx * (hb.hw(y) + sa.w / 2 - 0.04), y, -H * 0.1), A, body,
               rot=(0, 0, -sx * math.atan(hb.slope)), cell=cell * 0.8, rng=rng, faces=["+X", "-X", "+Z"])
        iy = L * 0.3
        ix = sx * (hb.hw(iy) + 0.06)
        box("intake", (0.26, L * 0.12, H * 0.32), (ix, iy, -H * 0.12), dark, 0.03, parent=body)
        for k in range(3):
            box("intake_fin", (0.3, L * 0.11, 0.04), (ix, iy, -H * 0.12 - H * 0.1 + k * H * 0.1), gunm, 0.0, parent=body)
    eb = Block(W * 0.86, L * 0.14, H * 0.82, y=-L / 2 + L * 0.05, z=-H * 0.06)
    eb.build("engine_block", D, body, rng, cell * 0.7, chamfer=0.08)

    # cockpit and canopy at the front
    cw, cl, ch = W * 0.5, L * 0.22, H * 0.42
    cy = L / 2 - cl / 2 - L * 0.04
    base = hb.top(cy)
    cb = Block(cw, cl, ch, y=cy, z=base + ch / 2 - 0.05, taper=(0.85, 0.9))
    cb.build("cockpit", P, body, rng, cell * 0.6, chamfer=ch * 0.15)
    blocks.append(cb)
    box("canopy", (cw * 0.72, 0.12, ch * 0.62), (0, cy + cl / 2 + 0.0, base + ch * 0.42), glass, 0.0,
        rot=(math.radians(-28), 0, 0), parent=body)
    ctw, ctl = (cw * 0.62, cl * 0.6) if not big else (cw * 0.34, cl * 0.3)
    box("canopy_top", (ctw, ctl, 0.08), (0, cy + cl * 0.1, cb.top(cy) + 0.02), glass, 0.0, parent=body)
    for k in (-1, 0, 1):
        box("canopy_bar", (0.06, ctl * 1.04, 0.06), (k * ctw * 0.26, cy + cl * 0.1, cb.top(cy) + 0.06), dark, 0.0, parent=body)
    box("canopy_bar", (ctw * 1.06, 0.08, 0.08), (0, cy + cl * 0.1, cb.top(cy) + 0.07), dark, 0.0, parent=body)
    if big:
        g.patch(frame((0, cy - cl * 0.2, 0), *TOP), cw * 0.7, cl * 0.4, 5, gs * 0.4, lift=lambda x, y: cb.top(cy - cl * 0.2 + y))

    # greebles: front deck, beside and behind the superstructure, along the sides and underneath
    hw0 = hb.hw(0) * 0.9
    front_end = cy - cl / 2 - 0.1
    sup_front = sups[0].y + sups[0].l / 2 if sups else -L * 0.42
    top_patch(-hw0, hw0, sup_front + 0.1, front_end, int(W * (front_end - sup_front) * 0.6))
    # pipe runs down both edges of the deck, clamped by brackets
    pr = 0.07 + W * 0.004
    for sx in (-1, 1):
        x = sx * hb.hw(0) * 0.8
        y0, y1 = eb.y + eb.l / 2 + 0.2, front_end - 0.2
        if y1 - y0 < 1.0:
            continue
        for k in range(3):
            along_y(pr, y1 - y0, (x + (k - 1) * pr * 2.4, (y0 + y1) / 2, hb.top((y0 + y1) / 2) + pr), [gunm, acc2, greeb][k],
                    parent=body, segs=8)
        yy = y0 + 0.3
        while yy < y1:
            box("bracket", (pr * 8.5, 0.12, pr * 2.6), (x, yy, hb.top(yy) + pr * 1.1), dark, 0.0, parent=body)
            yy += 1.4
    if sups:
        s1 = sups[0]
        sw = s1.hw(s1.y) + 0.1
        for sx in (-1, 1):
            x0, x1 = sorted((sx * sw, sx * hw0))
            top_patch(x0, x1, s1.y - s1.l / 2, s1.y + s1.l / 2, int((x1 - x0) * s1.l * 0.5), scale=gs * 0.8)
        # on top of the superstructure, beside the upper tier
        top_patch(-s1.hw(s1.y) * 0.85, s1.hw(s1.y) * 0.85, s1.y - s1.l * 0.45, s1.y + s1.l * 0.45,
                  int(s1.w * s1.l * 0.3), scale=gs * 0.65)
    aft_end = eb.y + eb.l / 2 + 0.1
    sup_back = sups[0].y - sups[0].l / 2 - 0.1 if sups else -L * 0.42
    top_patch(-hw0, hw0, aft_end, sup_back, int(W * (sup_back - aft_end) * 0.6))
    for sx in (-1, 1):
        g.patch(hb.side(sx, -L * 0.1, -H * 0.15, along=False), H * 0.45, L * 0.7, int(L * 0.5), gs * 0.6,
                kinds=["pipes", "pipes", "vent", "hatch", "block", "tank"])
    box("keel", (W * 0.55, L * 0.8, 0.22), (0, 0, hb.bottom(0) - 0.08), dark, 0.04, parent=body)
    for sx in (-1, 1):
        xc = sx * W * 0.35
        g.patch(frame((xc, 0, 0), *BOTTOM), W * 0.18, L * 0.7, int(L * 0.35), gs * 0.6,
                lift=lambda x, y: -hb.bottom(-y), kinds=["tank", "pipes", "block", "hatch", "dome"])

    # lit windows: rows down both sides of the hull and the superstructure
    if bw >= 7:
        rows = 1 if bw < 13 else (2 if bw < 21 else 3)
        for sx in (-1, 1):
            windows(hb.side(sx, -L * 0.05, H * 0.3), L * 0.62, H * 0.06 * rows, rows, win, rng, body, gap=0.42)
            for sb in sups:
                windows(sb.side(sx, sb.y, sb.z), sb.l * 0.8, sb.h * 0.4, max(1, rows - 1), win, rng, body, gap=0.38)

    # stripe style
    if style == "h":
        n = max(1, int(L / 2.2))
        for i in range(n):
            y = L / 2 - L * 0.3 - i * 2.2
            if y < -L / 2 + 0.6:
                break
            box("stripe", (hb.hw(y) * 2 + 0.08, 0.35, hb.hh(y) * 2 + 0.08), (0, y, 0), acc, 0.03, parent=body)
    elif style == "v":
        for sx in (-1, 1):
            y = -L * 0.04
            box("stripe", (0.1, L * 0.82, H * 0.3), (sx * (hb.hw(y) + 0.05), y, -H * 0.02), acc, 0.0,
                rot=(0, 0, -sx * math.atan(hb.slope)), parent=body)
            box("stripe_lo", (0.08, L * 0.6, H * 0.08), (sx * (hb.hw(y) + 0.05), y - L * 0.08, -H * 0.24), acc2, 0.0,
                rot=(0, 0, -sx * math.atan(hb.slope)), parent=body)
    elif style == "x":
        n = max(1, int(L / 3.0))
        for i in range(n):
            y = L * 0.25 - i * 3.0
            if y < -L / 2 + 0.8:
                break
            for sx in (-1, 1):
                x = sx * W * 0.2
                box("chevron", (W * 0.42, 0.32, 0.1), (x, y, hb.top(y) + 0.06), acc, 0.0,
                    rot=(0, 0, math.radians(sx * 28)), parent=body)
    else:
        xs = (0.0,) if not sups else (-hw0 * 0.8, hw0 * 0.8)
        for x in xs:
            for i in range(int(L * 0.85 / 0.6)):
                y = L * 0.38 - i * 0.6
                z = deck_z(x, y)
                box("spine", (0.4, 0.5, 0.2), (x, y, z + 0.1), acc, 0.0, parent=body)
                if i % 4 == 0:
                    box("spine_light", (0.2, 0.2, 0.08), (x, y, z + 0.24), win, 0.0, parent=body)

    # big ships: a bridge tower with windows, antennas and a turning radar dish
    animated = []
    if big:
        top_b = sups[-1]
        tw, tl, th = W * 0.24, L * 0.12, H * 0.7
        ty = top_b.y - top_b.l * 0.25
        tz = top_b.top(ty) + th / 2 - 0.05
        tb = Block(tw, tl, th, y=ty, z=tz, taper=(0.85, 0.95))
        tb.build("bridge", P, body, rng, cell * 0.5, chamfer=th * 0.15)
        box("bridge_win", (tw * 0.8, 0.1, th * 0.2), (0, ty + tl / 2 + 0.02, tz + th * 0.22), glass, 0.0, parent=body)
        for sx in (-1, 1):
            windows(tb.side(sx, ty, tz + th * 0.2), tl * 0.8, th * 0.15, 1, win, rng, body, gap=0.3)
        mast_h = th * 1.6
        cyl("mast", 0.09, mast_h, (tw * 0.25, ty - tl * 0.2, tb.top(ty) + mast_h / 2), dark, parent=body, segs=8)
        for k in range(3):
            box("mast_bar", (0.7 - k * 0.15, 0.05, 0.05), (tw * 0.25, ty - tl * 0.2, tb.top(ty) + mast_h * (0.45 + k * 0.18)),
                gunm, 0.0, parent=body)
        animated.append(light("mast_light", (tw * 0.25, ty - tl * 0.2, tb.top(ty) + mast_h + 0.08), 0.12, navr, r,
                              period=60, on=10))
        # radar dish on its own turning mount
        dish = root("radar")
        dish.parent = r
        dish.location = (-tw * 0.22, ty, tb.top(ty))
        cyl("dish_post", 0.08, 0.5, (0, 0, 0.25), dark, parent=dish, segs=8)
        d = cyl("dish", 0.08, 0.25, (0, 0.05, 0.65), gunm, parent=dish, segs=16, r2=0.75)
        d.rotation_euler = (math.radians(-60), 0, 0)
        cyl("dish_feed", 0.025, 0.5, (0, 0.25, 0.85), dark, parent=dish, segs=6).rotation_euler = (math.radians(-60), 0, 0)
        dm = merge(dish, "radar_mesh")
        dm.parent = dish
        spin(dish, "Z", 240)


    # gun pods: half the gun slots on each side, evenly spaced from the front. Each carries a turret mount
    # (Gun_N): the game puts a moving turret there (turret.glb)
    per_side = max(1, guns // 2)
    pw, pl, ph = max(1.1, H * 0.42), pod * U, H * 0.55
    px = W / 2 + gap * U + pw / 2
    blen = 0.0
    muzzles = []
    for k in range(per_side):
        y = L / 2 - (k + 0.5) * L / per_side
        for sx in (-1, 1):
            x = sx * px
            plated("pod", (pw, pl, ph), (x, y, 0), G, body, cell=0.45, rng=rng, chamfer=0.08, depth=0.025, seam=0.025)
            box("pod_band", (pw * 1.06, 0.2, ph * 1.06), (x, y - pl * 0.2, 0), acc, 0.0, parent=body)
            box("pod_band", (pw * 1.04, 0.08, ph * 1.04), (x, y - pl * 0.32, 0), acc2, 0.0, parent=body)
            sl = gap * U + 0.3
            plated("strut", (sl, 0.55, ph * 0.38), (sx * (W / 2 + gap * U / 2 - 0.05), y, 0), [dark, seam, greeb], body,
                   cell=0.3, rng=rng, depth=0.02, seam=0.02)
            box("strut_pipe", (sl, 0.1, 0.1), (sx * (W / 2 + gap * U / 2 - 0.05), y - 0.38, ph * 0.12), gunm, 0.0, parent=body)
            box("ammo", (pw * 0.4, pl * 0.22, 0.16), (x - sx * pw * 0.1, y - pl * 0.34, ph / 2 + 0.08), dark, 0.02, parent=body)
            cyl("mount", pw * 0.42, 0.1, (x, y + pl * 0.08, ph / 2 + 0.05), dark, parent=body, segs=16)
            box("pod_nose", (pw * 0.8, 0.2, ph * 0.7), (x, y + pl / 2 + 0.08, 0), dark, 0.03, parent=body)
            muzzles.append((x, y + pl * 0.08, ph / 2 + 0.1))
        if k == 0:
            ico("nav", 0.16, (-px - pw / 2 - 0.05, y, ph / 2), navr, 1, parent=body)
            ico("nav", 0.16, (px + pw / 2 + 0.05, y, ph / 2), navg, 1, parent=body)
            for sx, ph_ in ((-1, 0), (1, 6)):
                animated.append(light("strobe", (sx * (px + pw / 2 + 0.05), y - pl * 0.4, ph / 2), 0.11, strobe, r,
                                      period=48, on=2, phase=ph_))
    # running lights down the sides
    for i in range(max(2, int(sa.l / 2.0))):
        y = -L * 0.08 + sa.l * 0.45 - i * 2.0
        if y < -L * 0.08 - sa.l * 0.45:
            break
        for sx in (-1, 1):
            ico("running", 0.09, (sx * (hb.hw(y) + sa.w - 0.02), y, -H * 0.1), amber, 1, parent=body)
    animated.append(light("beacon", (0, eb.y, deck_z(0, eb.y) + 0.15), 0.14, navr, r, period=60, on=6, phase=30))

    # engines across the back: housings, ribbed bells, a hot core and a glowing throat
    n_eng = 4 if bw >= 17 else (3 if bw >= 13 else 2)
    nr = min(H * 0.32, W / (n_eng * 2.6))
    nlen = nr * 2.2
    ez = -H * 0.05
    engines = []
    for i in range(n_eng):
        x = (i - (n_eng - 1) / 2) * (W * 0.7 / max(1, n_eng - 1)) if n_eng > 1 else 0.0
        yb = -L / 2
        along_y(nr * 1.4, nlen * 0.45, (x, yb - nlen * 0.2 + 0.1, ez), dark, parent=body, segs=16)
        along_y(nr * 1.25, nlen, (x, yb - nlen / 2 + 0.1, ez), gunm, parent=body, segs=20, r2=nr, caps=False)
        along_y(nr * 1.02, 0.1, (x, yb - nlen * 0.3, ez), dark, parent=body, segs=20)
        for c in range(3):
            f = 0.35 + c * 0.25
            torus("rib", nr * (1.0 + 0.25 * f) + 0.02, 0.05 + nr * 0.03, (x, yb - nlen * f + 0.1, ez), dark,
                  rot=(math.radians(90), 0, 0), parent=body, seg=20, ring=6)
        for k in range(4):
            a = k * math.pi / 2 + math.pi / 4
            box("heat_fin", (0.06, nlen * 0.4, nr * 0.5), (x + math.cos(a) * nr * 1.45, yb - nlen * 0.15, ez + math.sin(a) * nr * 1.45),
                greeb, 0.0, rot=(0, -a + math.pi / 2, 0), parent=body)
        along_y(nr * 1.0, 0.08, (x, yb - nlen * 0.34, ez), eng, parent=body, segs=20)
        along_y(nr * 0.42, nlen * 0.5, (x, yb - nlen * 0.6, ez), eng_core, parent=body, segs=12, r2=nr * 0.12)
        engines.append((x, yb - nlen, ez))

    merge(body, sid + "_mesh")
    # merge() made the joined mesh the child of `body`; reparent it under the root and drop `body`
    mesh_obj = next(o for o in body.children if o.type == "MESH")
    mesh_obj.parent = r
    bpy.data.objects.remove(body)
    for i, m in enumerate(muzzles):
        empty("Gun_%d" % i, m, r)  # turret mounts, in gun-slot order
    for i, e in enumerate(engines):
        empty("Engine_%d" % i, e, r)
    export(r, os.path.join(OUT, "ships", sid + ".glb"))
    return {"hull": [W, L, H], "size": [2 * (px + pw / 2), L + nlen + blen, H + 1.0], "guns": len(muzzles)}

# ---------------------------------------------------------------- pirates

ENEMIES = {
    # id: (width, length, height, hull, trim, light, guns, scale-ish features)
    "raider": (5.0, 6.5, 1.6, "a52a1f", "1a0d0d", "ffd24a", 2),
    "gunner": (7.5, 6.5, 2.4, "8a3a24", "200a06", "ff9a3d", 2),
    "sniper": (2.8, 9.5, 1.3, "c25012", "1a0d06", "ffe066", 1),
    "swarmer": (2.4, 3.0, 0.9, "d43c2c", "200808", "ffd24a", 2),
    "captain": (11.0, 15.0, 3.4, "6e1010", "120404", "ffd700", 2),
}


def pirate(eid):
    if eid == "sentinel":
        return sentinel()
    W, L, H, c_hull, c_trim, c_light, guns = ENEMIES[eid]
    rng = random.Random(eid)
    boss = eid == "captain"
    hull = mat(eid + "_hull", c_hull, 0.45, 0.45)
    hull2 = mat(eid + "_hull2", shade(c_hull, 0.7), 0.5, 0.5)
    seam = mat("pirate_seam", "a01a0a", 0.0, 0.5, emit=0.45)  # pirate hulls glow along their panel lines
    trim = mat(eid + "_trim", c_trim, 0.6, 0.55)
    trim2 = mat(eid + "_trim2", shade(c_trim, 1.18), 0.6, 0.5)
    dseam = mat("pirate_dark_seam", "080404", 0.5, 0.8)
    lamp = mat(eid + "_light", c_light, 0.0, 0.3, emit=6.0)
    gunm = mat("gun_metal", "3a4050", 0.8, 0.35)
    eng = mat("pirate_engine", "ff4a1f", 0.0, 0.3, emit=1.1)
    core = mat("pirate_core", "ffb080", 0.0, 0.3, emit=1.8)
    red = mat("nav_red", "ff3030", 0.0, 0.3, emit=8.0)
    P = [hull, seam, hull2]
    T = [trim, dseam, trim2]
    cell = 0.7 + W * 0.05
    r = root(eid)
    body = root(eid + "_parts")
    body.parent = r
    g = Greebler(body, rng, trim2, trim, hull2, lamp)

    # wedge hull: wide at the back, narrow nose
    hb = Block(W * 0.6, L, H, taper=(0.35, 0.6))
    hb.build("hull", P, body, rng, cell, chamfer=min(W * 0.6, H) * 0.08, depth=0.03, seam=0.018)
    ab = Block(W * 0.66, L * 0.5, H * 0.5, y=-L * 0.15, z=H * 0.35, taper=(0.6, 0.8))
    ab.build("armor", T, body, rng, cell * 0.8, chamfer=ab.h * 0.15, depth=0.03, seam=0.03)
    box("eye", (W * 0.18, 0.1, H * 0.16), (0, L * 0.3, hb.top(L * 0.3) - H * 0.02), lamp, 0.0, parent=body)
    box("eye_brow", (W * 0.26, 0.3, H * 0.08), (0, L * 0.27, hb.top(L * 0.27) + H * 0.04), trim, 0.0, parent=body)
    g.patch(frame((0, ab.y, 0), *TOP), ab.w * 0.7, ab.l * 0.8, int(W * L * 0.12) + 2, 0.25 + W * 0.05,
            lift=lambda x, y: ab.top(ab.y + y))
    # glowing ribs across the back of the hull
    for k in range(3 if L > 5 else 1):
        y = -L * 0.32 - k * L * 0.05
        box("rib", (hb.hw(y) * 2 + 0.1, 0.12, hb.hh(y) * 2 + 0.1), (0, y, 0), seam, 0.0, parent=body)
    # swept "claw" wings with armoured edges, spikes and blinking tips
    for sx in (-1, 1):
        rot = (0, 0, math.radians(-sx * 14))
        plated("wing", (W * 0.42, L * 0.55, H * 0.22), (sx * W * 0.38, -L * 0.12, 0), P, body, rot=rot,
               taper=(0.4, 1.0), cell=cell * 0.8, rng=rng, depth=0.02, seam=0.016)
        box("wing_trim", (W * 0.06, L * 0.5, H * 0.3), (sx * W * 0.58, -L * 0.15, 0), trim, 0.02, rot=rot, parent=body)
        box("wing_vane", (W * 0.3, L * 0.08, H * 0.05), (sx * W * 0.4, -L * 0.3, H * 0.14), trim2, 0.0, rot=rot, parent=body)
        cyl("spike", 0.18 + W * 0.01, H * 0.9, (sx * W * 0.2, -L * 0.25, H * 0.6), trim, parent=body, segs=6, r2=0.0)
        cyl("spike", 0.12 + W * 0.008, H * 0.7, (sx * W * 0.62, -L * 0.33, H * 0.1), trim, rot=(0, math.radians(sx * 60), 0),
            parent=body, segs=6, r2=0.0)
        light("tip", (sx * W * 0.62, -L * 0.36, H * 0.16), 0.08 + W * 0.006, red, r, period=40, on=4, phase=0 if sx < 0 else 20)
    if eid in ("raider", "captain", "sniper"):
        fin = box("fin", (0.1 + W * 0.01, L * 0.2, H * 0.55), (0, -L * 0.3, hb.top(-L * 0.3) + H * 0.22), trim2, 0.02,
                  parent=body, taper=(1.0, 0.2))
        fin.rotation_euler = (math.radians(-12), 0, 0)
    if boss:
        tb = Block(W * 0.22, L * 0.22, H * 0.9, y=-L * 0.22, z=ab.top(-L * 0.22) + H * 0.4, taper=(0.8, 0.9))
        tb.build("tower", T, body, rng, cell * 0.6, chamfer=0.1)
        box("tower_win", (W * 0.2, 0.1, H * 0.18), (0, tb.y + tb.l / 2 + 0.02, tb.z + H * 0.15), lamp, 0.0, parent=body)
        for sx in (-1, 1):
            windows(tb.side(sx, tb.y, tb.z + H * 0.1), tb.l * 0.8, H * 0.2, 2, lamp, rng, body, gap=0.32)
            windows(hb.side(sx, -L * 0.1, 0), L * 0.4, H * 0.2, 2, lamp, rng, body, gap=0.4)
        for i in range(8):
            a = i * 2 * math.pi / 8
            cyl("crown", 0.22, H * 0.7, (math.cos(a) * W * 0.12, tb.y + math.sin(a) * L * 0.1, tb.top(tb.y) + H * 0.25), trim,
                rot=(math.sin(a) * -0.5, math.cos(a) * 0.5, 0), parent=body, segs=6, r2=0.0)
        for i in range(6):
            cyl("spike", 0.3, H * 0.9, (rng.uniform(-W * 0.3, W * 0.3), rng.uniform(-L * 0.4, L * 0.1), H * 0.7),
                trim, parent=body, segs=6, r2=0.0)
        mast = light("mast", (0, tb.y, tb.top(tb.y) + H * 1.1), 0.18, red, r, period=60, on=8)
        cyl("mast_pole", 0.06, H * 1.1, (0, tb.y, tb.top(tb.y) + H * 0.55), gunm, parent=body, segs=6)
    muzzles = []
    blen = L * (0.5 if eid == "sniper" else 0.22)
    br = 0.3 if eid == "gunner" else (0.25 if boss else 0.14)
    xs = [0.0] if guns == 1 else [-W * 0.42, W * 0.42]
    for x in xs:
        y0 = L * (0.25 if guns == 1 else 0.0)
        z0 = 0.0 if guns == 2 else hb.top(y0) * 0.3
        plated("gun_mount", (br * 4, br * 5, br * 3), (x, y0, z0), T, body, cell=0.25, rng=rng, depth=0.015, seam=0.015)
        along_y(br * 1.35, br * 2, (x, y0 + br * 2.5 + br, z0), trim, parent=body, segs=10)
        along_y(br, blen, (x, y0 + blen / 2, z0), gunm, parent=body, segs=10)
        for c in range(2 if blen < 3 else 4):
            along_y(br * 1.25, br * 0.4, (x, y0 + blen * (0.45 + c * 0.12), z0), trim2, parent=body, segs=10)
        along_y(br * 1.3, br * 1.2, (x, y0 + blen - br * 0.6, z0), trim, parent=body, segs=6)
        muzzles.append((x, y0 + blen, z0))
    engines = []
    for sx in ((-1, 1) if W > 3 else (0,)):
        x = sx * W * 0.16
        er = H * 0.28
        along_y(er * 1.2, H * 0.3, (x, -L / 2 + H * 0.05, 0), trim, parent=body, segs=12)
        along_y(er, H * 0.6, (x, -L / 2 - H * 0.2, 0), trim2, parent=body, segs=14, r2=er * 0.72, caps=False)
        along_y(er * 0.7, 0.06, (x, -L / 2 - H * 0.02, 0), eng, parent=body, segs=12)
        along_y(er * 0.3, H * 0.35, (x, -L / 2 - H * 0.18, 0), core, parent=body, segs=8, r2=er * 0.1)
        engines.append((x, -L / 2 - H * 0.5, 0))
    merge(body, eid + "_mesh")
    mesh_obj = next(o for o in body.children if o.type == "MESH")
    mesh_obj.parent = r
    bpy.data.objects.remove(body)
    for i, m in enumerate(muzzles):
        empty("Muzzle_%d" % i, m, r)
    for i, e in enumerate(engines):
        empty("Engine_%d" % i, e, r)
    export(r, os.path.join(OUT, "enemies", eid + ".glb"))
    return {"hull": [W * 0.6, L, H], "size": [W, L, H], "guns": len(muzzles)}


def sentinel():
    """Anomaly guardian: a glowing crystal core in two counter-turning rings, inside four slowly orbiting
    armour plates, with a loose swarm of shards circling the other way."""
    rng = random.Random("sentinel")
    core = mat("sentinel_core", "d080ff", 0.0, 0.2, emit=7.0)
    hot = mat("sentinel_hot", "ffe0ff", 0.0, 0.2, emit=14.0)
    plate = mat("sentinel_plate", "2a1040", 0.6, 0.4)
    plate2 = mat("sentinel_plate2", "3d1a5c", 0.6, 0.4)
    seam = mat("sentinel_seam", "9040e0", 0.0, 0.4, emit=1.2)
    trim = mat("sentinel_trim", "8e44ad", 0.3, 0.4, emit=1.5)
    metal = mat("sentinel_metal", "4a3a5c", 0.8, 0.3)
    r = root("sentinel")
    octa("core", 1.4, 2.6, (0, 0, 0), core, rot=(math.radians(90), 0, 0), parent=r)
    octa("core_hot", 0.7, 1.4, (0, 0, 0), hot, rot=(math.radians(90), math.radians(45), 0), parent=r)
    # two gimbal rings turning on different axes
    for i, (axis, period) in enumerate((("X", 300), ("Z", 200))):
        ring = root("gimbal%d" % i)
        ring.parent = r
        torus("ring", 2.3 - i * 0.35, 0.12, (0, 0, 0), metal, rot=(0, math.radians(90) if i == 0 else 0, 0), parent=ring, seg=40, ring=8)
        for k in range(4):
            a = k * math.pi / 2
            p = (0, math.cos(a) * (2.3 - i * 0.35), math.sin(a) * (2.3 - i * 0.35)) if i == 0 else \
                (math.cos(a) * 1.95, math.sin(a) * 1.95, 0)
            ico("node", 0.18, p, trim, 1, parent=ring)
        rm = merge(ring, "gimbal%d_mesh" % i)
        rm.parent = ring
        spin(ring, axis, period, turns=1 if i == 0 else -1)
    ring = root("plates")
    ring.parent = r
    for i in range(4):
        a = i * math.pi / 2 + math.pi / 4
        rot = (0, 0, a + math.pi / 2)
        plated("plate", (2.4, 0.5, 3.6), (math.cos(a) * 3.2, math.sin(a) * 3.2, 0), [plate, seam, plate2], ring, rot=rot,
               cell=0.85, rng=rng, depth=0.04, seam=0.025, chamfer=0.12)
        box("plate_trim", (2.0, 0.55, 0.3), (math.cos(a) * 3.25, math.sin(a) * 3.25, 1.2), trim, 0.0, rot=rot, parent=ring)
        box("plate_trim", (1.4, 0.55, 0.2), (math.cos(a) * 3.25, math.sin(a) * 3.25, -1.3), trim, 0.0, rot=rot, parent=ring)
        for z in (2.0, -2.0):
            octa("plate_spike", 0.25, 0.6, (math.cos(a) * 3.2, math.sin(a) * 3.2, z * 1.05), metal, parent=ring)
    plates = merge(ring, "plates_mesh")
    plates.parent = ring
    spin(ring, "Z", 240)
    swarm = root("shards")
    swarm.parent = r
    for i in range(9):
        a = i * 2 * math.pi / 9
        rad = rng.uniform(4.6, 5.4)
        octa("shard", 0.22, 0.55, (math.cos(a) * rad, math.sin(a) * rad, rng.uniform(-1.6, 1.6)), core,
             rot=(rng.uniform(0, 3), rng.uniform(0, 3), 0), parent=swarm)
    sm = merge(swarm, "shards_mesh")
    sm.parent = swarm
    spin(swarm, "Z", 400, turns=-1)
    for i, x in enumerate((-2.2, 2.2)):
        empty("Muzzle_%d" % i, (x, 2.4, 0), r)
    export(r, os.path.join(OUT, "enemies", "sentinel.glb"))
    return {"hull": [3.2, 3.2, 6.0], "size": [7.4, 7.4, 6.0], "guns": 2}


def turret():
    """A twin-barrel turret about a metre across, in the parts the game moves: Base (fixed to the gun pod),
    Yaw (the housing, turning left and right on the base) and Pitch (the barrels, raised and lowered), with a
    Muzzle empty between the barrel tips. Nose +Y like the ships."""
    rng = random.Random("turret")
    metal = mat("turret_metal", "4a5262", 0.75, 0.35)
    metal2 = mat("turret_metal2", "394050", 0.75, 0.4)
    seam = mat("turret_seam", "14181f", 0.6, 0.7)
    dark = mat("dark_metal", "1c2230", 0.6, 0.6)
    lens = mat("turret_lens", "7fd8ff", 0.0, 0.3, emit=3.0)
    r = root("turret")
    base = root("Base")
    base.parent = r
    cyl("ring", 0.55, 0.16, (0, 0, 0.08), dark, parent=base, segs=28)
    cyl("ring_top", 0.5, 0.06, (0, 0, 0.19), metal2, parent=base, segs=28)
    for k in range(8):
        a = k * math.pi / 4
        box("bolt", (0.06, 0.06, 0.05), (math.cos(a) * 0.5, math.sin(a) * 0.5, 0.18), metal, 0.0, parent=base)
    m = merge(base, "Base_mesh")
    m.parent = base
    yaw = root("Yaw")
    yaw.parent = r
    yaw.location = (0, 0, 0.22)
    plated("housing", (0.78, 0.82, 0.36), (0, -0.06, 0.18), [metal, seam, metal2], yaw, cell=0.22, rng=rng, chamfer=0.07,
           depth=0.012, seam=0.01, taper=(0.85, 0.9))
    for sx in (-1, 1):
        box("cheek", (0.1, 0.62, 0.5), (sx * 0.44, 0.02, 0.32), metal2, 0.02, parent=yaw, taper=(1.0, 0.7))
        box("vent", (0.02, 0.3, 0.16), (sx * 0.5, -0.12, 0.3), dark, 0.0, parent=yaw)
    box("back", (0.6, 0.18, 0.28), (0, -0.5, 0.16), dark, 0.02, parent=yaw)
    box("sensor", (0.14, 0.14, 0.12), (0.26, -0.28, 0.42), dark, 0.01, parent=yaw)
    ico("lens", 0.035, (0.26, -0.2, 0.43), lens, 1, parent=yaw)
    m = merge(yaw, "Yaw_mesh")
    m.parent = yaw
    pitch = root("Pitch")
    pitch.parent = yaw
    pitch.location = (0, 0.06, 0.34)
    box("mantlet", (0.6, 0.32, 0.3), (0, 0.06, 0), metal2, 0.04, parent=pitch)
    for sx in (-1, 1):
        x = sx * 0.16
        along_y(0.1, 0.3, (x, 0.32, 0), dark, parent=pitch, segs=14)
        along_y(0.052, 1.15, (x, 0.85, 0), metal, parent=pitch, segs=12)
        for c in range(3):
            along_y(0.075, 0.045, (x, 0.55 + c * 0.12, 0), dark, parent=pitch, segs=12)
        along_y(0.078, 0.16, (x, 1.36, 0), dark, parent=pitch, segs=8)
    m = merge(pitch, "Pitch_mesh")
    m.parent = pitch
    empty("Muzzle", (0, 1.45, 0), pitch)
    export(r, os.path.join(OUT, "props", "turret.glb"))


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    meta_path = os.path.join(OUT, "ship_meta.json")
    meta = {}
    if os.path.exists(meta_path):
        with open(meta_path) as f:
            meta = json.load(f)
    for sid in (argv or list(SHIPS) + list(ENEMIES) + ["sentinel", "turret"]):
        reset()
        if sid == "turret":
            turret()
            continue
        meta[sid] = player_ship(sid) if sid in SHIPS else pirate(sid)
    os.makedirs(OUT, exist_ok=True)
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=1)
    print("DONE", len(meta))
