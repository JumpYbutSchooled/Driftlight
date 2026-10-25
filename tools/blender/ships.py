"""Builds every Driftlight ship as a GLB.

Run:  blender --background --python ships.py [-- ship_id ...]

Every ship has its own design (see DESIGNS): darts, twin-boom interceptors, container haulers, a mining
barge with claw arms, a flying-wing stealth ship, a ring-waisted explorer, destroyers, a carrier, a
dreadnought... all built from one kit of armour-plated parts (Kit). Each carries empties named Gun_N:
turret mounts, which the game puts a moving turret (turret.glb) on. A mount's rotation says which way the
turret faces (up off the deck, down under the keel, or out to a side) and its scale how big the turret is.
Engine_N empties mark the nozzle exits, scaled by each nozzle's radius. Pirates are built the same way.
"""
import json
import math
import os
import random
import sys

from mathutils import Euler, Vector

sys.path.append(os.path.dirname(__file__))
from common import *  # noqa: E402,F401,F403


def shade(h, k):
    """A hex colour darkened (k < 1) or lightened (k > 1)."""
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) for i in (0, 2, 4)]
    if k < 1:
        c = [int(v * k) for v in c]
    else:
        c = [int(v + (255 - v) * (k - 1)) for v in c]
    return "%02x%02x%02x" % tuple(max(0, min(255, v)) for v in c)


# id: (hull, accent, glass colours) - mirrors Game.SHIPS
SHIPS = {
    "wren": ("b8c4d6", "4a7fd0", "7ff0ff"),
    "sparrow": ("e6e0c8", "e07a3c", "9dfcff"),
    "mule": ("c9a46a", "8a5a2e", "7ff0ff"),
    "prospector": ("d9b23c", "3a3a3a", "ffe066"),
    "kestrel": ("e8f0ea", "3fc46a", "9dfcff"),
    "corsair": ("2e3440", "e04848", "ffd24a"),
    "lancer": ("cfd6e6", "7a5cff", "b9a6ff"),
    "aegis": ("dfe9ff", "4fd6ff", "4fd6ff"),
    "bastion": ("8a8f9c", "b8433a", "ffd27a"),
    "specter": ("2a2f3a", "4a5468", "6fffd8"),
    "nyx": ("3c2c55", "b366ff", "f0b0ff"),
    "leviathan": ("6b7080", "d9b23c", "7ff0ff"),
    "seraph": ("fff0f6", "ff5fa2", "ffe066"),
    "halberd": ("9aa4b4", "2fb8a8", "bff4ff"),
    "monarch": ("2c3e66", "e8b84a", "ffe7a3"),
    "behemoth": ("6a3a40", "d8433a", "ffb36b"),
    "ark": ("8a8170", "4a7fd0", "7ff0ff"),
    "titan": ("4a4462", "9b4dff", "e0a0ff"),
}

# capital ships carry heavier turrets than their mount sizes below say
TURRET_K = {"leviathan": 1.25, "halberd": 1.3, "monarch": 1.32, "behemoth": 1.38, "ark": 1.35, "titan": 1.45}

UP = Vector((0, 0, 1))
TOP = (Vector((1, 0, 0)), Vector((0, 1, 0)), UP)
BOTTOM = (Vector((1, 0, 0)), Vector((0, -1, 0)), -UP)
# which way a turret mount can face: its outward normal, and the mount's rotation (turning the turret's
# up, +Z, onto that normal while its front stays the ship's front, +Y)
FACES = {
    "top": (Vector((0, 0, 1)), (0.0, 0.0, 0.0)),
    "bottom": (Vector((0, 0, -1)), (0.0, math.pi, 0.0)),
    "right": (Vector((1, 0, 0)), (0.0, math.pi / 2, 0.0)),
    "left": (Vector((-1, 0, 0)), (0.0, -math.pi / 2, 0.0)),
}


def side(sx):
    return "right" if sx > 0 else "left"


class Part:
    """A (tapered) box: taper narrows the +Y end in x and z. For placing things on its surfaces."""

    def __init__(self, w, l, h, x=0.0, y=0.0, z=0.0, taper=(1.0, 1.0)):
        self.w, self.l, self.h, self.x, self.y, self.z, self.taper = w, l, h, x, y, z, taper
        self.slope = w / 2 * (taper[0] - 1) / l

    def t(self, y):
        return min(1.0, max(0.0, (y - self.y) / self.l + 0.5))

    def hw(self, y):
        return self.w / 2 * (1 + (self.taper[0] - 1) * self.t(y))

    def hh(self, y):
        return self.h / 2 * (1 + (self.taper[1] - 1) * self.t(y))

    def top(self, y):
        return self.z + self.hh(y)

    def bottom(self, y):
        return self.z - self.hh(y)

    def side_x(self, sx, y):
        return self.x + sx * self.hw(y)

    def front(self):
        return self.y + self.l / 2

    def back(self):
        return self.y - self.l / 2

    def side_frame(self, sx, yc, zc):
        """Surface frame on the left (sx=-1) or right flank: local x runs along the hull, y up, z out."""
        T = Vector((sx * self.slope, 1, 0)).normalized()
        u, v = (T if sx > 0 else -T), Vector((0, 0, 1))
        return frame((self.side_x(sx, yc), yc, zc), u, v, u.cross(v))


class Kit:
    """One ship under construction: its materials, the parts root, the turret mounts and engines on it,
    and its overall bounds. Plates are big and seams light, so a hull reads as armour, not a grid."""

    def __init__(self, sid, c_hull, c_acc, c_glass, pirate=False):
        self.sid = sid
        self.rng = random.Random(sid)
        pre = sid + "_"
        self.hull = mat(pre + "hull", c_hull, 0.55, 0.36)
        self.hull2 = mat(pre + "hull2", shade(c_hull, 0.78), 0.55, 0.44)
        self.seam = mat(pre + "seam", shade(c_hull, 0.5), 0.6, 0.6)
        self.acc = mat(pre + "accent", c_acc, 0.4, 0.4)
        self.acc2 = mat(pre + "accent2", shade(c_acc, 0.7), 0.45, 0.45)
        self.glass = mat(pre + "glass", shade(c_glass, 0.3), 0.3, 0.06, emit=0.25)
        self.win = mat(pre + "window", shade(c_glass, 1.2), 0.0, 0.3, emit=1.6)
        self.dark = mat("dark_metal", "1c2230", 0.65, 0.55)
        self.gunm = mat("gun_metal", "3a4050", 0.8, 0.32)
        self.bell = mat("engine_bell", "2a2f3a", 0.85, 0.3)  # open tubes: the game draws these two-sided
        self.greeb = mat(pre + "greeble", shade(c_hull, 0.55), 0.6, 0.5)
        self.deckm = mat(pre + "deck", shade(c_hull, 0.6), 0.5, 0.6)
        self.eng = mat("engine_glow", "c8602a", 0.0, 0.4, emit=0.3)  # the nozzle's hot throat, idling (the game adds the burn)
        self.eng_core = mat("engine_core", "e09060", 0.0, 0.4, emit=0.45)
        self.navr = mat("nav_red", "ff3030", 0.0, 0.3, emit=3.5)
        self.navg = mat("nav_green", "30ff70", 0.0, 0.3, emit=3.5)
        self.strobe = mat("strobe", "ffffff", 0.0, 0.3, emit=6.0)
        self.amber = mat("running_light", "ffc060", 0.0, 0.3, emit=2.5)
        self.P = [self.hull, self.seam, self.hull2]
        self.A = [self.acc, self.seam, self.acc2]
        self.D = [self.deckm, self.seam, self.hull2]
        self.G = [self.gunm, self.dark, self.greeb]
        self.r = root(sid)
        self.body = root(pre + "parts")
        self.body.parent = self.r
        self.g = Greebler(self.body, self.rng, self.greeb, self.dark, self.acc2, self.amber)
        self.mounts = []  # (position, rotation, scale)
        self.engines = []  # (position, nozzle radius)
        self.lo = Vector((1e9, 1e9, 1e9))
        self.hi = Vector((-1e9, -1e9, -1e9))
        self.main = None  # the main hull: the game's "can't shoot through your own hull" box
        self.turret_k = TURRET_K.get(sid, 1.0)

    # ---------------------------------------------------------------- building blocks

    def grow(self, c, half, rot=(0, 0, 0)):
        m = Euler(rot).to_matrix()
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    p = Vector(c) + m @ Vector((sx * half[0], sy * half[1], sz * half[2]))
                    self.lo = Vector(tuple(min(a, b) for a, b in zip(self.lo, p)))
                    self.hi = Vector(tuple(max(a, b) for a, b in zip(self.hi, p)))

    def part(self, name, w, l, h, x=0.0, y=0.0, z=0.0, taper=(1.0, 1.0), mats=None, cell=None, chamfer=None, faces=None,
             rot=(0, 0, 0), depth=None):
        big = max(w, l)
        plated(name, (w, l, h), (x, y, z), mats or self.P, self.body, rot=rot, taper=taper,
               cell=cell or min(4.0, 0.9 + big * 0.06), rng=self.rng, depth=depth or (0.02 + big * 0.0015),
               seam=0.025 + big * 0.0012, chamfer=min(w, h) * 0.08 if chamfer is None else chamfer, faces=faces)
        self.grow((x, y, z), (w / 2, l / 2, h / 2), rot)
        return Part(w, l, h, x, y, z, taper)

    def hull_part(self, name, w, l, h, **kw):
        p = self.part(name, w, l, h, **kw)
        self.main = self.main or p
        return p

    def plate(self, name, pts, t, offset=0.0, plane="xy", mat_=None, x=0.0, rot=(0, 0, 0)):
        """A wing, fin or blade cut to an outline (see common.slab)."""
        o = slab(name, pts, t, offset, plane, mat_ or self.hull, self.body, rot=rot, loc=(x, 0, 0), bevel=min(0.04, t * 0.3))
        for u, v in pts:
            p = (u + x, v, offset) if plane == "xy" else (offset + x, u, v)
            self.grow(p, (t, t, t), rot)
        return o

    def mount(self, x, y, z, face="top", s=1.0):
        """A turret mount on the surface at (x, y, z), facing `face`: an armoured barbette sunk into the hull
        with a lip round it; the turret sits on top. s scales the turret (1 is about a metre across)."""
        n, rot = FACES[face]
        s *= self.turret_k
        surf = Vector((x, y, z))
        top = surf + n * 0.19 * s
        cyl("barbette", 0.64 * s, 0.6 * s, tuple(surf - n * 0.11 * s), self.hull2, rot=rot, parent=self.body, segs=20)
        cyl("barbette_lip", 0.71 * s, 0.07 * s, tuple(top - n * 0.09 * s), self.acc2, rot=rot, parent=self.body, segs=20)
        self.mounts.append((top, rot, s))
        self.grow(top + n * 0.5 * s, (1.1 * s, 1.5 * s, 1.1 * s))

    def engine(self, x, y, z, r, nlen=None, fins=True):
        """A nozzle whose housing meets the hull at y, pointing back (-Y): ribbed bell, heat fins, a glowing
        throat and a hot core."""
        nlen = nlen or r * 2.2
        along_y(r * 1.4, nlen * 0.45, (x, y - nlen * 0.2 + 0.1, z), self.dark, parent=self.body, segs=16)
        along_y(r * 1.25, nlen, (x, y - nlen / 2 + 0.1, z), self.bell, parent=self.body, segs=20, r2=r, caps=False)
        along_y(r * 1.02, 0.1, (x, y - nlen * 0.3, z), self.dark, parent=self.body, segs=20)
        for c in range(3):
            f = 0.35 + c * 0.25
            torus("rib", r * (1.0 + 0.25 * f) + 0.02, 0.04 + r * 0.03, (x, y - nlen * f + 0.1, z), self.dark,
                  rot=(math.radians(90), 0, 0), parent=self.body, seg=20, ring=6)
        if fins:
            for k in range(4):
                a = k * math.pi / 2 + math.pi / 4
                box("heat_fin", (0.05 + r * 0.03, nlen * 0.4, r * 0.5),
                    (x + math.cos(a) * r * 1.45, y - nlen * 0.15, z + math.sin(a) * r * 1.45), self.greeb, 0.0,
                    rot=(0, -a + math.pi / 2, 0), parent=self.body)
        along_y(r * 1.0, 0.08, (x, y - nlen * 0.34, z), self.eng, parent=self.body, segs=20)
        along_y(r * 0.42, nlen * 0.5, (x, y - nlen * 0.6, z), self.eng_core, parent=self.body, segs=12, r2=r * 0.12)
        self.engines.append((Vector((x, y - nlen + 0.1, z)), r))
        self.grow((x, y - nlen / 2, z), (r * 1.4, nlen / 2, r * 1.4))

    def cockpit(self, on, y, w, l, h, x=0.0):
        """A raised cockpit on top of part `on`: plated, with a raked windscreen and a glass roof panel."""
        base = on.top(y)
        cb = self.part("cockpit", w, l, h, x=x, y=y, z=base + h / 2 - 0.05, taper=(0.8, 0.78), chamfer=h * 0.2)
        box("windscreen", (w * 0.62, 0.07, h * 0.62), (x, y + l / 2 - h * 0.12, base + h * 0.5), self.glass, 0.0,
            rot=(math.radians(-40), 0, 0), parent=self.body)
        box("canopy_roof", (w * 0.5, l * 0.42, 0.05), (x, y + l * 0.08, cb.top(y + l * 0.08) + 0.02), self.glass, 0.0,
            parent=self.body)
        box("canopy_bar", (w * 0.04 + 0.03, l * 0.44, 0.06), (x, y + l * 0.08, cb.top(y + l * 0.08) + 0.04), self.dark, 0.0,
            parent=self.body)
        return cb

    def glass_band(self, on, y, z, w, h):
        """A bridge window band across the front face of part `on` at y."""
        box("bridge_glass", (w, 0.08, h), (on.x, y, z), self.glass, 0.0, parent=self.body)
        box("bridge_brow", (w * 1.06, 0.25, h * 0.35), (on.x, y + 0.08, z + h * 0.62), self.dark, 0.0, parent=self.body)

    def lights(self, x, y, z, size):
        """Navigation lights: red to port, green to starboard, white strobes just behind them."""
        ico("nav", size, (-x, y, z), self.navr, 1, parent=self.body)
        ico("nav", size, (x, y, z), self.navg, 1, parent=self.body)
        for sx, ph in ((-1, 0), (1, 6)):
            light("strobe", (sx * x, y - size * 3, z), size * 0.7, self.strobe, self.r, period=48, on=2, phase=ph)

    def beacon(self, x, y, z, size, phase=30):
        light("beacon", (x, y, z), size, self.navr, self.r, period=60, on=6, phase=phase)

    def mast(self, x, y, z, h, size):
        cyl("mast", 0.05 + size * 0.4, h, (x, y, z + h / 2), self.dark, parent=self.body, segs=8)
        for k in range(3):
            box("mast_bar", (size * 6 - k * size * 1.2, 0.05, 0.05), (x, y, z + h * (0.45 + k * 0.18)), self.gunm, 0.0,
                parent=self.body)
        light("mast_light", (x, y, z + h + size), size, self.navr, self.r, period=60, on=10)

    def radar(self, x, y, z, size, period=240):
        dish = root("radar")
        dish.parent = self.r
        dish.location = (x, y, z)
        cyl("dish_post", 0.08 * size, 0.5 * size, (0, 0, 0.25 * size), self.dark, parent=dish, segs=8)
        d = cyl("dish", 0.08 * size, 0.25 * size, (0, 0.05 * size, 0.65 * size), self.gunm, parent=dish, segs=16, r2=0.75 * size)
        d.rotation_euler = (math.radians(-60), 0, 0)
        cyl("dish_feed", 0.025 * size, 0.5 * size, (0, 0.25 * size, 0.85 * size), self.dark, parent=dish,
            segs=6).rotation_euler = (math.radians(-60), 0, 0)
        merge(dish, "radar_mesh").parent = dish
        spin(dish, "Z", period)

    def deck(self, part, y0, y1, count, scale, inset=0.85, kinds=None):
        """Greebles over the top of `part` between y0 and y1."""
        if y1 - y0 < 0.4 or count <= 0:
            return
        yc = (y0 + y1) / 2
        self.g.patch(frame((part.x, yc, 0), *TOP), part.hw(yc) * 2 * inset, y1 - y0, count, scale,
                     lift=lambda x, y: part.top(yc + y), kinds=kinds)

    def belly(self, part, y0, y1, count, scale, inset=0.75):
        if y1 - y0 < 0.4 or count <= 0:
            return
        yc = (y0 + y1) / 2
        self.g.patch(frame((part.x, yc, 0), *BOTTOM), part.hw(yc) * 2 * inset, y1 - y0, count, scale,
                     lift=lambda x, y: -part.bottom(yc - y), kinds=["tank", "pipes", "block", "hatch", "dome"])

    def flanks(self, part, count, scale, z=None):
        for sx in (-1, 1):
            self.g.patch(part.side_frame(sx, part.y, part.z if z is None else z), part.l * 0.8, part.h * 0.45, count, scale,
                         kinds=["pipes", "pipes", "vent", "hatch", "block"])

    def portholes(self, part, y, z, length, rows, gap):
        for sx in (-1, 1):
            windows(part.side_frame(sx, y, z), length, rows * gap * 0.8, rows, self.win, self.rng, self.body, gap=gap,
                    cell=(gap * 0.55, gap * 0.35))

    def container(self, x, y, z, w, l, h):
        c = self.rng.choice([self.A, self.P, self.D, [self.acc2, self.seam, self.acc]])
        self.part("container", w, l, h, x=x, y=y, z=z, mats=c, cell=0.32, chamfer=0.05, depth=0.03)

    # ---------------------------------------------------------------- finishing

    def finish(self, folder):
        merge(self.body, self.sid + "_mesh")
        # merge() made the joined mesh the child of `body`; reparent it under the root and drop `body`
        mesh_obj = next(o for o in self.body.children if o.type == "MESH")
        mesh_obj.parent = self.r
        bpy.data.objects.remove(self.body)
        for i, (p, rot, s) in enumerate(self.mounts):
            e = empty("Gun_%d" % i, tuple(p), self.r)
            e.rotation_euler = rot
            e.scale = (s, s, s)
        for i, (p, rr) in enumerate(self.engines):
            e = empty("Engine_%d" % i, tuple(p), self.r)
            e.scale = (rr, rr, rr)
        export(self.r, os.path.join(OUT, folder, self.sid + ".glb"))
        m = self.main
        size = self.hi - self.lo
        return {"hull": [m.w, m.l, m.h], "size": [size.x, size.y, size.z], "guns": len(self.mounts)}


# ---------------------------------------------------------------- player ships

def d_wren(k):
    """Skiff, the starter: a plain plated box with a gun pod on a strut each side, a turret on each pod."""
    W, L, H = 4.6, 6.2, 1.7
    hb = k.hull_part("hull", W, L, H, taper=(0.9, 0.86))
    cb = k.cockpit(hb, 1.9, 2.2, 1.5, 0.75)
    sup = k.part("cargo_deck", 3.0, 2.4, 0.55, y=-0.7, z=hb.top(-0.7) + 0.22, taper=(0.9, 0.9))
    k.part("engine_block", 3.8, 1.0, 1.35, y=-L / 2 + 0.35, z=-0.08, mats=k.D)
    for x in (-1.0, 1.0):
        k.engine(x, -L / 2 - 0.15, -0.08, 0.42)
    for sx in (-1, 1):
        k.part("strut", 1.3, 0.55, 0.45, x=sx * (W / 2 + 0.5), y=0.3, mats=k.G)
        pod = k.part("pod", 1.15, 2.5, 0.95, x=sx * (W / 2 + 1.55), y=0.4, mats=k.G, chamfer=0.1)
        box("pod_band", (1.27, 0.22, 1.07), (pod.x, pod.y - 0.6, 0), k.acc, 0.0, parent=k.body)
        box("pod_nose", (0.9, 0.24, 0.7), (pod.x, pod.front() + 0.1, 0), k.dark, 0.03, parent=k.body)
        k.mount(pod.x, 0.7, pod.top(0.7), "top", 0.85)
    k.lights(W / 2 + 2.2, 0.9, 0.3, 0.1)
    k.beacon(0, sup.y, sup.top(sup.y) + 0.12, 0.1)
    k.deck(hb, sup.front() + 0.1, cb.back() - 0.1, 8, 0.5)
    k.deck(sup, sup.back() + 0.2, sup.front() - 0.2, 10, 0.4)
    k.flanks(hb, 12, 0.4, z=-0.2)
    k.belly(hb, -2.4, 2.4, 14, 0.45)


def d_sparrow(k):
    """Scout: a tiny dart. A needle fuselage with a bubble canopy, swept wings, canards, a tail fin, one big
    engine and two small ones. One turret on the spine, one under the tail."""
    fus = k.hull_part("fuselage", 1.7, 7.0, 1.15, y=0.4, taper=(0.3, 0.5), chamfer=0.22)
    rear = k.part("rear", 2.5, 2.0, 1.35, y=-2.4, chamfer=0.25)
    box("canopy", (0.75, 1.7, 0.4), (0, 1.6, fus.top(1.6) + 0.08), k.glass, 0.04, taper=(0.45, 0.5), parent=k.body)
    for sx in (-1, 1):
        k.plate("wing", [(sx * 0.7, -0.9), (sx * 4.1, -2.9), (sx * 4.1, -3.5), (sx * 0.7, -3.3)], 0.16, -0.2)
        k.plate("wing_edge", [(sx * 2.0, -1.66), (sx * 4.1, -2.9), (sx * 4.1, -3.05), (sx * 2.0, -1.85)], 0.2, -0.2, mat_=k.acc)
        k.plate("canard", [(sx * 0.55, 2.3), (sx * 1.8, 1.6), (sx * 1.8, 1.3), (sx * 0.55, 1.6)], 0.08, -0.05)
        k.engine(sx * 1.15, -3.3, -0.25, 0.22, fins=False)
    k.plate("fin", [(-1.7, 0.5), (-3.3, 0.5), (-3.6, 2.0), (-2.9, 2.0)], 0.1, plane="yz")
    k.engine(0, -3.4, 0.0, 0.55)
    k.mount(0, -0.8, fus.top(-0.8), "top", 0.7)
    k.mount(0, -2.4, rear.bottom(-2.4), "bottom", 0.7)
    k.lights(4.1, -3.1, -0.2, 0.08)
    k.belly(fus, -1.5, 1.5, 6, 0.3)


def d_mule(k):
    """Hauler: a tug cab up front, a frame of cargo containers stacked two high behind it, and a heavy
    engine block. A turret on the cab roof and one under the engine block."""
    k.main = Part(5.4, 13.0, 3.0)
    cab = k.part("cab", 4.4, 3.0, 2.8, y=4.7, z=0.3, taper=(0.86, 0.8), chamfer=0.35)
    k.glass_band(cab, cab.front() + 0.02, 0.9, 3.0, 0.45)
    k.part("spine", 1.2, 8.6, 1.0, y=-0.6, mats=k.G)
    for y in (2.0, -0.6, -3.2):
        for x in (-1.45, 1.45):
            for z in (0.74, -0.74):
                if k.rng.random() < 0.9:
                    k.container(x, y, z, 2.6, 2.4, 1.42)
        for sx in (-1, 1):
            box("frame_post", (0.14, 0.14, 3.2), (sx * 2.8, y + 1.25, 0), k.dark, 0.0, parent=k.body)
    for sx in (-1, 1):
        for sz in (-1, 1):
            box("frame_rail", (0.16, 8.4, 0.16), (sx * 2.8, -0.6, sz * 1.55), k.gunm, 0.0, parent=k.body)
    eb = k.part("engine_block", 4.6, 2.2, 3.2, y=-5.9, mats=k.D, chamfer=0.3)
    for x in (-1.2, 1.2):
        k.engine(x, eb.back() - 0.05, 0, 0.75)
    k.mount(0, 4.4, cab.top(4.4), "top", 0.95)
    k.mount(0, eb.y, eb.bottom(eb.y), "bottom", 0.95)
    k.lights(2.3, 4.6, 0.6, 0.11)
    k.beacon(0, eb.y, eb.top(eb.y) + 0.12, 0.12)
    k.deck(eb, eb.back() + 0.2, eb.front() - 0.3, 8, 0.5)


def d_prospector(k):
    """Mining barge: a wide, low hull carrying an open ore hopper; two big mining arms reach forward with
    claws, a drill head between them. Turrets ride on top of the arms."""
    hb = k.hull_part("hull", 7.4, 6.8, 2.1, taper=(0.86, 0.9))
    top = hb.top(-0.6)
    for sx in (-1, 1):
        k.part("hopper_wall", 0.35, 3.6, 1.1, x=sx * 2.2, y=-0.6, z=top + 0.5, mats=k.A)
        k.part("hopper_wall", 4.75, 0.35, 1.1, y=-0.6 + sx * 1.8, z=top + 0.5, mats=k.A)
    rock = mat("ore_rock", "4a4038", 0.1, 0.9)
    for i in range(9):
        ico("ore", k.rng.uniform(0.35, 0.6), (k.rng.uniform(-1.6, 1.6), -0.6 + k.rng.uniform(-1.3, 1.3), top + 0.35), rock, 1,
            parent=k.body)
    for sx in (-1, 1):
        k.part("shoulder", 1.7, 1.7, 1.7, x=sx * 2.9, y=2.6, z=0.1, mats=k.A)
        arm = k.part("arm", 1.1, 4.6, 1.1, x=sx * 2.9, y=4.9, z=0.1, mats=k.G, taper=(0.8, 0.8))
        for c in (-1, 0, 1):
            box("claw", (0.28, 1.7, 0.45), (arm.x + c * 0.36, arm.front() + 0.75, 0.1 + abs(c) * 0.1), k.dark, 0.02,
                taper=(0.3, 0.5), rot=(0, 0, -sx * 0.25 + c * 0.2), parent=k.body)
        k.mount(arm.x, 4.0, arm.top(4.0), "top", 0.9)
    k.part("drill_housing", 2.0, 1.4, 1.5, y=hb.front() + 0.6, z=-0.25, mats=k.G)
    along_y(0.75, 2.6, (0, hb.front() + 2.6, -0.25), k.gunm, parent=k.body, segs=16, r2=0.05)
    for c in range(4):
        torus("drill_thread", 0.62 - c * 0.14, 0.05, (0, hb.front() + 1.7 + c * 0.55, -0.25), k.dark, rot=(math.radians(90), 0, 0),
              parent=k.body, seg=16, ring=4)
    br = k.part("bridge", 1.8, 1.7, 1.3, x=-2.5, y=-2.6, z=hb.top(-2.6) + 0.6, taper=(0.9, 0.85))
    k.glass_band(br, br.front() + 0.02, br.z + 0.2, 1.4, 0.35)
    k.radar(2.5, -2.6, hb.top(-2.6), 1.0)
    for x in (-2.2, 0.0, 2.2):
        k.engine(x, hb.back() - 0.05, -0.1, 0.6)
    k.lights(3.75, 1.5, 0.4, 0.11)
    k.flanks(hb, 14, 0.5)
    k.belly(hb, -2.8, 2.8, 16, 0.5)


def d_kestrel(k):
    """Interceptor: twin booms joined by a thin wing and a high tailplane, a needle cockpit pod between them.
    The turrets sit on sponsons on the booms' outer flanks, each with its whole side to shoot into."""
    pod = k.hull_part("pod", 1.5, 5.4, 1.2, y=1.0, taper=(0.45, 0.6), chamfer=0.25)
    box("canopy", (0.7, 1.8, 0.36), (0, 2.0, pod.top(2.0) + 0.08), k.glass, 0.04, taper=(0.5, 0.6), parent=k.body)
    k.plate("wing", [(-3.0, 0.4), (3.0, 0.4), (3.0, -1.5), (-3.0, -1.5)], 0.2, 0.0)
    k.plate("tailplane", [(-3.1, -3.1), (3.1, -3.1), (3.1, -3.75), (-3.1, -3.75)], 0.1, 1.45)
    for sx in (-1, 1):
        boom = k.part("boom", 0.95, 7.2, 0.95, x=sx * 3.1, y=-0.4, taper=(0.55, 0.55), chamfer=0.15)
        box("boom_stripe", (0.99, 0.5, 0.99), (boom.x, -2.2, 0), k.acc, 0.0, parent=k.body)
        k.engine(boom.x, boom.back() - 0.05, 0, 0.42)
        k.plate("fin", [(-2.6, 0.4), (-3.8, 0.4), (-4.0, 1.55), (-3.4, 1.55)], 0.08, sx * 3.1, plane="yz")
        sp = k.part("sponson", 0.55, 1.5, 0.9, x=sx * (boom.hw(1.3) + 3.1 + 0.2), y=1.3, mats=k.A)
        k.mount(sp.side_x(sx, 1.3), 1.3, 0, side(sx), 0.72)
    k.lights(3.1, 2.9, 0.0, 0.08)


def d_corsair(k):
    """Fighter: an armoured arrowhead. A broad delta hull with a raised spine, big side intakes, delta wing
    extensions and canted twin tail fins. One turret on the spine, one under the belly."""
    hb = k.hull_part("hull", 5.6, 7.4, 1.5, taper=(0.18, 0.55), chamfer=0.25)
    spine = k.part("spine", 1.2, 5.4, 0.62, y=-0.4, z=hb.top(-0.4) + 0.2, taper=(0.5, 0.6), mats=k.A)
    box("canopy", (0.6, 1.4, 0.32), (0, 2.0, spine.top(2.0) + 0.06), k.glass, 0.03, taper=(0.5, 0.6), parent=k.body)
    for sx in (-1, 1):
        k.plate("wing", [(sx * 1.8, -0.8), (sx * 4.3, -3.3), (sx * 4.3, -3.9), (sx * 1.8, -3.7)], 0.18, -0.25)
        k.plate("wing_stripe", [(sx * 3.0, -2.0), (sx * 4.3, -3.3), (sx * 4.3, -3.5), (sx * 3.0, -2.25)], 0.22, -0.25, mat_=k.acc)
        intake = k.part("intake", 0.8, 2.2, 0.9, x=sx * 1.65, y=-1.4, z=-0.35, mats=k.G)
        box("intake_mouth", (0.62, 0.1, 0.7), (intake.x, intake.front() + 0.02, intake.z), k.dark, 0.0, parent=k.body)
        k.plate("fin", [(-2.2, 0.0), (-3.6, 0.0), (-3.9, 1.5), (-3.2, 1.5)], 0.09, 0.0, plane="yz", x=sx * 1.4,
                rot=(0, sx * 0.4, 0))
        k.engine(sx * 0.85, hb.back() - 0.05, -0.1, 0.5)
    k.mount(0, -1.0, spine.top(-1.0), "top", 0.85)
    k.mount(0, 0.2, hb.bottom(0.2), "bottom", 0.85)
    k.lights(4.3, -3.6, -0.25, 0.08)
    k.belly(hb, -2.5, 1.5, 8, 0.35)


def d_lancer(k):
    """Marksman: a spear. A long armoured spine ending in a rail-gun prow wound with coils, a collar of
    emitters, a mid-ship block bristling with radiator fins, three engines. Turrets above and below."""
    sp = k.hull_part("spine", 1.4, 11.0, 1.4, chamfer=0.22)
    along_y(0.3, 4.6, (0, sp.front() + 2.2, 0), k.gunm, parent=k.body, segs=12)
    for c in range(6):
        torus("coil", 0.42, 0.09, (0, sp.front() + 0.6 + c * 0.62, 0), k.acc2, rot=(math.radians(90), 0, 0), parent=k.body,
              seg=16, ring=6)
    box("muzzle_brake", (0.9, 0.5, 0.9), (0, sp.front() + 4.6, 0), k.dark, 0.05, parent=k.body)
    torus("collar", 1.35, 0.17, (0, 3.6, 0), k.gunm, rot=(math.radians(90), 0, 0), parent=k.body, seg=32, ring=8)
    for a in range(4):
        ang = a * math.pi / 2 + math.pi / 4
        box("emitter", (0.3, 0.5, 0.3), (math.cos(ang) * 1.35, 3.6, math.sin(ang) * 1.35), k.acc, 0.03, parent=k.body)
    mid = k.part("mid", 2.8, 3.2, 2.0, y=-1.4, chamfer=0.3)
    for sx in (-1, 1):
        for sz in (-1, 1):
            box("radiator", (1.8, 2.6, 0.06), (sx * 2.2, -1.4, sz * 0.9), k.acc2, 0.0, rot=(0, sx * sz * -0.5, 0),
                parent=k.body)
            k.grow((sx * 2.2, -1.4, sz * 0.9), (0.9, 1.3, 0.6))
    k.cockpit(sp, 2.2, 1.0, 1.4, 0.5)
    for x, z in ((0.0, 0.42), (-0.42, -0.3), (0.42, -0.3)):
        k.engine(x, sp.back() - 0.05, z, 0.36, fins=False)
    k.mount(0, -1.4, mid.top(-1.4), "top", 0.85)
    k.mount(0, 1.6, sp.bottom(1.6), "bottom", 0.8)
    k.lights(1.45, -1.4, 0.0, 0.08)


def d_aegis(k):
    """Guardian: a squat octagonal fortress inside a shield-emitter ring, with a domed command deck. Its two
    turrets sit on armoured sponsons out on the flanks."""
    k.main = hb = Part(6.4, 6.4, 2.0)
    cyl("hull_core", 3.45, 2.0, (0, 0, 0), k.hull, rot=(0, 0, math.pi / 8), parent=k.body, segs=8)
    k.grow((0, 0, 0), (3.45, 3.45, 1.0))
    k.part("deck_plate", 4.8, 4.8, 0.5, z=1.1, chamfer=0.35)
    k.part("belly_plate", 4.2, 4.2, 0.4, z=-1.05, chamfer=0.3)
    for i in range(8):
        a = i * math.pi / 4 + math.pi / 8
        k.part("rim_armor", 2.4, 0.4, 1.6, x=math.cos(a) * 3.3, y=math.sin(a) * 3.3, rot=(0, 0, a + math.pi / 2), mats=k.A)
    cyl("dome", 1.7, 0.8, (0, -0.3, hb.top(0) + 0.35), k.hull2, parent=k.body, segs=8, r2=1.05)
    cyl("dome_glass", 1.3, 0.2, (0, -0.3, hb.top(0) + 0.55), k.glass, parent=k.body, segs=8, r2=1.1)
    torus("emitter_ring", 4.5, 0.16, (0, 0, -0.65), k.gunm, parent=k.body, seg=64, ring=8)
    for i in range(8):
        a = i * math.pi / 4 + math.pi / 8
        box("emitter", (0.4, 0.4, 0.5), (math.cos(a) * 4.5, math.sin(a) * 4.5, -0.65), k.acc, 0.04, rot=(0, 0, a),
            parent=k.body)
        ico("emitter_lamp", 0.1, (math.cos(a) * 4.5, math.sin(a) * 4.5, -0.32), k.win, 1, parent=k.body)
    for i in range(4):
        a = i * math.pi / 2 + math.pi / 4
        box("ring_strut", (1.6, 0.25, 0.25), (math.cos(a) * 3.7, math.sin(a) * 3.7, -0.65), k.dark, 0.0, rot=(0, 0, a),
            parent=k.body)
    k.grow((0, 0, -0.65), (4.7, 4.7, 0.3))
    for sx in (-1, 1):
        sp = k.part("sponson", 1.0, 2.2, 1.3, x=sx * 3.4, y=0.3, z=0.2, mats=k.A, chamfer=0.25)
        k.mount(sp.side_x(sx, 0.3), 0.3, 0.2, side(sx), 0.95)
    for x in (-1.4, 1.4):
        k.engine(x, hb.back() - 0.05, 0, 0.55)
    k.lights(3.9, -1.2, 0.4, 0.1)
    k.beacon(0, -0.3, hb.top(0) + 0.8, 0.1)
    k.belly(hb, -2.0, 2.0, 12, 0.5)


def d_bastion(k):
    """Gunship: a flying fortress. A heavy plated hull with sloped armour skirts, a raised citadel, gun pods
    on both flanks, a turret on the citadel roof and one under the keel."""
    hb = k.hull_part("hull", 6.2, 8.6, 2.6, taper=(0.9, 0.88), chamfer=0.45)
    for sx in (-1, 1):
        k.part("skirt", 0.5, 7.2, 1.8, x=sx * 3.15, y=-0.2, z=-0.35, rot=(0, sx * 0.35, 0), mats=k.A)
    cit = k.part("citadel", 3.4, 3.4, 1.3, y=-0.9, z=hb.top(-0.9) + 0.55, taper=(0.85, 0.9), chamfer=0.3)
    k.glass_band(cit, cit.front() + 0.02, cit.z + 0.2, 2.4, 0.35)
    for sx in (-1, 1):
        k.part("strut", 1.5, 0.7, 0.6, x=sx * 3.85, y=1.6, mats=k.G)
        pod = k.part("pod", 1.4, 3.0, 1.2, x=sx * 5.1, y=1.6, mats=k.G, chamfer=0.12)
        box("pod_band", (1.52, 0.3, 1.32), (pod.x, pod.y - 0.7, 0), k.acc, 0.0, parent=k.body)
        k.mount(pod.x, pod.y + 0.3, pod.top(pod.y), "top", 1.0)
    k.mount(0, -1.3, cit.top(-1.3), "top", 1.15)
    k.mount(0, 0.8, hb.bottom(0.8), "bottom", 1.15)
    for x in (-1.6, 0.0, 1.6):
        k.engine(x, hb.back() - 0.05, -0.1, 0.62)
    k.lights(5.8, 1.6, 0.4, 0.11)
    k.beacon(0, cit.y + 0.9, cit.top(cit.y) + 0.12, 0.11)
    k.deck(hb, cit.front() + 0.2, hb.front() - 0.4, 14, 0.55)
    k.belly(hb, -3.4, 3.4, 18, 0.55)


def d_specter(k):
    """Stealth: a faceted flying wing in dark plating, almost flat, with a serrated trailing edge and slot
    exhausts buried under it. Low turrets above and below the centre body."""
    body = k.hull_part("body", 2.2, 6.0, 1.0, y=0.2, taper=(0.25, 0.45), chamfer=0.2)
    k.plate("wing", [(0, 4.0), (4.3, -1.5), (3.5, -2.3), (2.4, -1.75), (1.3, -2.55), (0, -1.95), (-1.3, -2.55), (-2.4, -1.75),
                     (-3.5, -2.3), (-4.3, -1.5)], 0.28, -0.1)
    k.plate("wing_trim", [(0, 3.2), (3.6, -1.3), (3.45, -1.45), (0, 2.95), (-3.45, -1.45), (-3.6, -1.3)], 0.32, -0.1, mat_=k.acc)
    hump = k.part("hump", 1.6, 2.6, 0.5, y=-0.4, z=body.top(-0.4) + 0.12, taper=(0.5, 0.4))
    box("canopy", (0.8, 1.2, 0.2), (0, 1.4, body.top(1.4) + 0.05), k.glass, 0.02, taper=(0.4, 0.5), parent=k.body)
    for x in (-0.65, 0.65):
        k.engine(x, -1.7, -0.1, 0.26, fins=False)
    k.mount(0, -1.25, hump.top(-1.25) - 0.05, "top", 0.68)
    k.mount(0, -0.4, body.bottom(-0.4), "bottom", 0.68)
    k.lights(4.2, -1.6, -0.1, 0.06)


def d_nyx(k):
    """Explorer: a long hull with a slowly turning ring round its waist, a sensor prow of dishes and
    antennas, a turret above the bow and one under the stern."""
    hb = k.hull_part("hull", 2.2, 8.4, 2.0, taper=(0.62, 0.68), chamfer=0.32)
    along_y(0.6, 1.5, (0, hb.front() + 0.65, 0), k.gunm, parent=k.body, segs=12, r2=0.14)
    for sx in (-1, 1):
        cyl("antenna", 0.03, 2.6, (sx * 0.45, hb.front() + 1.0, 0.5), k.dark, rot=(math.radians(-80), 0, sx * 0.3), parent=k.body,
            segs=6)
        d = cyl("sensor_dish", 0.05, 0.12, (sx * 0.9, hb.front() - 1.2, hb.top(hb.front() - 1.2) + 0.3), k.gunm, parent=k.body,
                segs=14, r2=0.45)
        d.rotation_euler = (math.radians(-50), 0, sx * 0.4)
    k.cockpit(hb, 2.3, 1.2, 1.5, 0.55)
    ring = root("ring")
    ring.parent = k.r
    ring.location = (0, -0.9, 0)
    torus("ring", 3.4, 0.32, (0, 0, 0), k.hull2, rot=(math.radians(90), 0, 0), parent=ring, seg=48, ring=10)
    for i in range(4):
        a = i * math.pi / 2 + math.pi / 4
        box("spoke", (2.4, 0.3, 0.3), (math.cos(a) * 2.2, 0, math.sin(a) * 2.2), k.dark, 0.0, rot=(0, -a, 0), parent=ring)
        box("ring_pod", (0.9, 0.9, 0.7), (math.cos(a) * 3.4, 0, math.sin(a) * 3.4), k.acc, 0.05, rot=(0, -a, 0), parent=ring)
    merge(ring, "ring_mesh").parent = ring
    spin(ring, "Y", 600)
    k.grow((0, -0.9, 0), (3.8, 0.5, 3.8))
    for x in (-0.6, 0.6):
        k.engine(x, hb.back() - 0.05, 0, 0.45)
    k.mount(0, 0.6, hb.top(0.6), "top", 0.75)
    k.mount(0, -3.0, hb.bottom(-3.0), "bottom", 0.75)
    k.lights(1.15, 0.8, 0.0, 0.08)
    k.flanks(hb, 10, 0.35)


def d_leviathan(k):
    """Freighter: a command section up front, a long open spine stacked with containers all the way round,
    and a big engine section. Turrets on top of and under both ends."""
    k.main = Part(8.0, 24.0, 5.6)
    bow = k.part("bow", 7.0, 4.6, 5.0, y=9.3, taper=(0.8, 0.75), chamfer=0.6)
    k.part("spine", 1.6, 14.4, 1.6, y=0.0, mats=k.G)
    stern = k.part("stern", 8.0, 4.4, 5.6, y=-9.4, mats=k.D, chamfer=0.5)
    for y in (5.4, 2.7, 0.0, -2.7, -5.4):
        for x in (-1.9, 0.0, 1.9):
            for z in (-1.9, 0.0, 1.9):
                if (x, z) != (0.0, 0.0) and k.rng.random() < 0.88:
                    k.container(x, y, z, 1.85, 2.5, 1.85)
    br = k.part("bridge", 3.0, 1.8, 1.4, y=8.4, z=bow.top(8.4) + 0.6, taper=(0.9, 0.9))
    k.glass_band(br, br.front() + 0.02, br.z + 0.2, 2.6, 0.4)
    k.mast(-1.0, 8.0, br.top(8.0), 2.4, 0.12)
    k.radar(1.0, 8.0, br.top(8.0), 1.2)
    k.portholes(bow, 9.3, 0.6, 3.6, 2, 0.5)
    for x in (-1.8, 1.8):
        for z in (-1.4, 1.4):
            k.engine(x, stern.back() - 0.05, z, 0.95)
    k.mount(0, 10.6, bow.top(10.6), "top", 1.3)
    k.mount(0, -9.4, stern.top(-9.4), "top", 1.3)
    k.mount(0, 9.3, bow.bottom(9.3), "bottom", 1.3)
    k.mount(0, -9.4, stern.bottom(-9.4), "bottom", 1.3)
    k.lights(4.05, -9.4, 1.5, 0.14)
    k.beacon(0, -9.4 - 1.5, stern.top(-9.4) + 0.15, 0.14)
    k.deck(stern, stern.back() + 0.3, stern.y - 0.8, 10, 0.7)
    k.belly(bow, 7.5, 11.0, 8, 0.6)


def d_seraph(k):
    """Flagship: long, sleek and swept. A blade of a hull, swept wings with engine nacelles at their roots,
    tall dorsal and ventral fins. Turrets on both wings, on the spine and under the keel."""
    hb = k.hull_part("hull", 2.8, 10.0, 1.5, y=0.3, taper=(0.3, 0.5), chamfer=0.4)
    k.cockpit(hb, 2.4, 1.2, 1.8, 0.5)
    for sx in (-1, 1):
        k.plate("wing", [(sx * 1.2, 0.2), (sx * 5.3, -3.3), (sx * 5.3, -4.0), (sx * 1.2, -2.8)], 0.22, -0.1)
        k.plate("wing_stripe", [(sx * 3.0, -1.35), (sx * 5.3, -3.3), (sx * 5.3, -3.55), (sx * 3.0, -1.62)], 0.26, -0.1,
                mat_=k.acc)
        nac = k.part("nacelle", 1.0, 3.8, 1.0, x=sx * 1.95, y=-2.6, z=-0.1, taper=(0.7, 0.7), mats=k.A)
        k.engine(nac.x, nac.back() - 0.05, -0.1, 0.42)
        k.mount(sx * 3.5, -2.6, 0.02, "top", 0.75)
    k.engine(0, hb.back() - 0.05, 0, 0.5)
    k.plate("fin", [(-1.3, 0.6), (-4.2, 0.6), (-4.8, 2.7), (-3.6, 2.7)], 0.1, plane="yz")
    k.plate("fin_lo", [(-1.6, -0.6), (-3.8, -0.6), (-4.4, -1.9), (-3.4, -1.9)], 0.1, plane="yz")
    k.mount(0, 0.6, hb.top(0.6), "top", 0.8)
    k.mount(0, -0.6, hb.bottom(-0.6), "bottom", 0.8)
    k.lights(5.3, -3.6, -0.1, 0.09)
    k.portholes(hb, 0.0, 0.1, 4.0, 1, 0.42)


def d_halberd(k):
    """Destroyer: long, narrow and sharp, with a knife-edged prow, armour belts down both flanks and the
    bridge set well aft under a mast and radar. Two turrets in a line on the deck, two under the keel."""
    hb = k.hull_part("hull", 6.4, 24.0, 3.2, taper=(0.35, 0.7), chamfer=0.6)
    k.part("prow", 1.0, 5.0, 2.4, y=hb.front() + 1.6, taper=(0.15, 0.4), mats=k.A)
    for sx in (-1, 1):
        k.part("belt", 0.5, 14.0, 1.4, x=sx * (hb.hw(-2.0) + 0.1), y=-2.0, z=-0.4, mats=k.A,
               rot=(0, 0, -sx * math.atan(hb.slope)))
    sup = k.part("superstructure", 3.8, 6.0, 1.6, y=-4.5, z=hb.top(-4.5) + 0.7, taper=(0.85, 0.9))
    br = k.part("bridge", 2.4, 2.2, 1.6, y=-3.6, z=sup.top(-3.6) + 0.7, taper=(0.85, 0.85))
    k.glass_band(br, br.front() + 0.02, br.z + 0.25, 2.0, 0.4)
    k.mast(0.5, -4.4, br.top(-4.4), 3.2, 0.14)
    k.radar(-0.6, -4.3, br.top(-4.3), 1.2)
    k.portholes(hb, -1.0, 0.2, 14.0, 2, 0.5)
    for x in (-1.9, 0.0, 1.9):
        k.engine(x, hb.back() - 0.05, 0, 1.0)
    k.mount(0, 5.5, hb.top(5.5), "top", 1.4)
    k.mount(0, -9.6, hb.top(-9.6), "top", 1.35)
    k.mount(0, 3.0, hb.bottom(3.0), "bottom", 1.3)
    k.mount(0, -7.0, hb.bottom(-7.0), "bottom", 1.3)
    k.lights(3.2, -8.0, 0.8, 0.14)
    k.deck(hb, sup.front() + 0.3, 3.9, 16, 0.8)
    k.deck(hb, -11.5, -10.8 + 0.0, 3, 0.6)
    k.belly(hb, -10.0, 10.0, 30, 0.7)


def d_monarch(k):
    """Cruiser: a broad hull stepped up in tiers to a tall bridge with radar, armoured sponsons on the flanks.
    Two turrets on the deck (one firing over the other), two under the keel, one out on each flank."""
    hb = k.hull_part("hull", 9.0, 30.0, 3.8, taper=(0.55, 0.75), chamfer=0.7)
    t1 = k.part("tier1", 6.0, 14.0, 1.8, y=-3.0, z=hb.top(-3.0) + 0.8, taper=(0.8, 0.9))
    t2 = k.part("tier2", 3.6, 7.0, 1.6, y=-4.5, z=t1.top(-4.5) + 0.7, taper=(0.8, 0.9))
    br = k.part("bridge", 2.6, 2.4, 1.8, y=-3.4, z=t2.top(-3.4) + 0.8, taper=(0.85, 0.85))
    k.glass_band(br, br.front() + 0.02, br.z + 0.3, 2.2, 0.45)
    k.mast(-0.6, -4.2, br.top(-4.2), 3.6, 0.15)
    k.radar(0.7, -4.0, br.top(-4.0), 1.4)
    for sx in (-1, 1):
        sp = k.part("sponson", 1.8, 5.0, 1.9, x=sx * (hb.hw(2.0) + 0.6), y=2.0, mats=k.A, chamfer=0.3)
        k.mount(sp.side_x(sx, 2.0), 2.0, 0, side(sx), 1.45)
    k.portholes(hb, -2.0, 0.4, 20.0, 3, 0.55)
    k.portholes(t1, -3.0, t1.z, 10.0, 2, 0.5)
    for x in (-3.0, -1.0, 1.0, 3.0):
        k.engine(x, hb.back() - 0.05, 0, 1.05)
    k.mount(0, 9.0, hb.top(9.0), "top", 1.6)
    k.mount(0, 3.0, t1.top(3.0), "top", 1.55)
    k.mount(0, 7.0, hb.bottom(7.0), "bottom", 1.5)
    k.mount(0, -8.0, hb.bottom(-8.0), "bottom", 1.5)
    k.lights(4.6, -9.0, 1.0, 0.16)
    k.deck(hb, -14.0, -10.5, 10, 0.8)
    k.deck(t1, -9.5, -8.4, 4, 0.6)
    k.belly(hb, -13.0, 13.0, 34, 0.8)


def d_behemoth(k):
    """Battlecruiser: a slab-sided brute, wide and heavy, with angled armour flanks, a ram prow and a tall
    twin-stacked superstructure. Turrets everywhere: three on the deck, three under the keel, one on each
    flank."""
    hb = k.hull_part("hull", 13.0, 38.0, 5.0, taper=(0.62, 0.8), chamfer=0.9)
    for sx in (-1, 1):
        k.part("flank_armor", 1.4, 26.0, 4.0, x=sx * (hb.hw(-2.0) + 0.3), y=-2.0, mats=k.A,
               rot=(0, sx * 0.3, -sx * math.atan(hb.slope)))
    k.part("ram", 3.0, 5.0, 3.0, y=hb.front() + 1.8, taper=(0.3, 0.4), mats=k.A)
    t1 = k.part("tier1", 8.0, 16.0, 2.0, y=-6.0, z=hb.top(-6.0) + 0.9, taper=(0.85, 0.9))
    t2 = k.part("tier2", 5.0, 8.0, 2.0, y=-7.0, z=t1.top(-7.0) + 0.9, taper=(0.85, 0.9))
    for sx in (-1, 1):
        tw = k.part("tower", 2.0, 2.4, 2.6, x=sx * 1.4, y=-6.4, z=t2.top(-6.4) + 1.2, taper=(0.85, 0.85))
        k.glass_band(tw, tw.front() + 0.02, tw.z + 0.5, 1.6, 0.4)
    k.mast(0, -7.6, t2.top(-7.6), 4.4, 0.18)
    k.radar(0, -9.6, t2.top(-9.6), 1.6)
    k.portholes(hb, -2.0, 0.6, 26.0, 3, 0.6)
    for sx in (-1, 1):
        k.mount(sx * (hb.hw(-2.0) + 1.15), -2.0, 0, side(sx), 1.7)
    for x in (-4.0, -2.0, 0.0, 2.0, 4.0):
        k.engine(x, hb.back() - 0.05, 0, 1.2)
    k.mount(0, 12.0, hb.top(12.0), "top", 2.0)
    k.mount(0, 1.0, t1.top(1.0), "top", 1.9)
    k.mount(0, -15.5, hb.top(-15.5), "top", 1.9)
    k.mount(0, 11.0, hb.bottom(11.0), "bottom", 1.9)
    k.mount(0, 0.0, hb.bottom(0.0), "bottom", 1.9)
    k.mount(0, -11.0, hb.bottom(-11.0), "bottom", 1.9)
    k.lights(6.6, -12.0, 1.6, 0.2)
    k.deck(hb, 3.0, 9.5, 14, 1.0)
    k.deck(hb, 14.5, 17.0, 6, 0.8)
    k.belly(hb, -17.0, 17.0, 36, 1.0)


def d_ark(k):
    """Mothership: a flying city of a carrier. A huge flat hull topped by a flight deck with runway lights,
    a hangar mouth in the bow, an island tower to one side, and a mining bay slung underneath. Turrets on
    sponsons along both deck edges and under the hull."""
    hb = k.hull_part("hull", 16.0, 36.0, 4.4, taper=(0.82, 0.9), chamfer=0.8)
    fd = k.part("flight_deck", 13.0, 32.0, 0.4, y=0.5, z=hb.top(0.5) + 0.15, mats=[k.deckm, k.seam, k.hull2], chamfer=0.1)
    dz = fd.top(0.5)
    for i in range(10):
        y = 14.0 - i * 3.0
        box("runway_stripe", (0.3, 1.6, 0.05), (0, y, dz + 0.02), k.acc, 0.0, parent=k.body)
        for sx in (-1, 1):
            ico("runway_light", 0.09, (sx * 4.2, y, dz + 0.06), k.amber, 1, parent=k.body)
    box("hangar_mouth", (9.0, 0.4, 2.4), (0, hb.front() + 0.05, 0.3), k.dark, 0.0, parent=k.body)
    box("hangar_glow", (8.4, 0.2, 0.18), (0, hb.front() + 0.18, 1.3), k.win, 0.0, parent=k.body)
    isl = k.part("island", 2.6, 7.0, 4.0, x=5.2, y=-3.0, z=dz + 2.0, taper=(0.9, 0.9))
    up = k.part("island_bridge", 2.2, 3.0, 1.6, x=5.2, y=-2.2, z=isl.top(-2.2) + 0.75)
    k.glass_band(up, up.front() + 0.02, up.z + 0.2, 1.8, 0.4)
    k.portholes(isl, -3.0, isl.z + 0.4, 5.0, 3, 0.45)
    k.mast(5.6, -3.4, up.top(-3.4), 4.0, 0.16)
    k.radar(4.6, -3.2, up.top(-3.2), 1.6)
    mb = k.part("mining_bay", 6.0, 10.0, 2.4, y=2.0, z=hb.bottom(2.0) - 1.0, mats=k.G)
    for y in (-2.0, 2.0, 6.0):
        box("bay_band", (6.15, 0.4, 2.55), (0, y, mb.z), k.acc, 0.0, parent=k.body)
    cyl("mining_emitter", 0.9, 1.2, (0, 2.0, mb.bottom(2.0) - 0.5), k.gunm, parent=k.body, segs=16, r2=0.5)
    for y in (9.0, -9.0):
        for sx in (-1, 1):
            sp = k.part("sponson", 1.8, 4.0, 1.8, x=sx * (hb.hw(y) + 0.6), y=y, mats=k.A, chamfer=0.3)
            k.mount(sp.side_x(sx, y), y, 0, side(sx), 1.8)
    k.mount(0, 12.0, hb.bottom(12.0), "bottom", 1.8)
    k.mount(0, -10.0, hb.bottom(-10.0), "bottom", 1.8)
    for x in (-6.0, -2.2, 2.2, 6.0):
        k.engine(x, hb.back() - 0.05, -0.3, 1.45)

    k.lights(8.0, -12.0, 1.6, 0.2)
    k.portholes(hb, 0.0, 0.0, 28.0, 3, 0.6)
    k.belly(hb, 8.0, 16.0, 16, 1.0)
    k.belly(hb, -16.0, -4.0, 20, 1.0)


def d_titan(k):
    """Dreadnought, the size of a station: a long dagger hull with a raised spinal ridge, a stepped citadel
    and bridge tower, and two armoured outer hulls riding its flanks. Ten turrets: four along the deck, four
    under the keel and one out on each outer hull."""
    hb = k.hull_part("hull", 15.0, 48.0, 6.0, taper=(0.42, 0.7), chamfer=1.0)
    ridge = k.part("ridge", 3.0, 30.0, 2.0, y=2.0, z=hb.top(2.0) + 0.8, taper=(0.6, 0.7), mats=k.A)
    cit = k.part("citadel", 7.0, 12.0, 3.0, y=-8.0, z=hb.top(-8.0) + 1.3, taper=(0.85, 0.9))
    tw = k.part("tower", 3.0, 3.6, 3.4, y=-9.6, z=cit.top(-9.6) + 1.5, taper=(0.85, 0.85))
    k.glass_band(tw, tw.front() + 0.02, tw.z + 0.7, 2.4, 0.5)
    k.mast(0.8, -10.6, tw.top(-10.6), 5.0, 0.2)
    k.radar(-0.8, -10.4, tw.top(-10.4), 1.8)
    for sx in (-1, 1):
        oh = k.part("outer_hull", 3.6, 22.0, 4.2, x=sx * (hb.hw(-8.0) + 2.4), y=-8.0, taper=(0.7, 0.8), chamfer=0.5, mats=k.D)
        for y in (-3.0, -13.0):
            k.part("pylon", 2.6, 3.0, 1.2, x=sx * (hb.hw(y) + 0.9), y=y, mats=k.G)
        k.mount(oh.side_x(sx, -4.0), -4.0, 0, side(sx), 2.0)
        k.engine(oh.x, oh.back() - 0.05, 0, 1.2)
        k.portholes(oh, -8.0, 0.6, 14.0, 2, 0.6)
    k.portholes(hb, -4.0, 0.8, 30.0, 3, 0.65)
    k.portholes(cit, -8.0, cit.z, 9.0, 2, 0.55)
    for x in (-3.6, -1.2, 1.2, 3.6):
        k.engine(x, hb.back() - 0.05, 0, 1.4)
    k.mount(0, 14.0, ridge.top(14.0), "top", 2.2)
    k.mount(0, 6.0, ridge.top(6.0), "top", 2.2)
    k.mount(0, -4.0, cit.top(-4.0), "top", 2.1)
    k.mount(0, -17.5, hb.top(-17.5), "top", 2.1)
    for y in (14.0, 4.0, -6.0, -16.0):
        k.mount(0, y, hb.bottom(y), "bottom", 2.1)
    k.lights(hb.hw(10.0) + 0.3, 10.0, 0.8, 0.22)
    k.beacon(0, -18.0, hb.top(-18.0) + 2.0, 0.2)
    k.deck(hb, 18.0, 22.0, 8, 1.0)
    k.deck(hb, -22.0, -19.5, 8, 1.0)
    k.belly(hb, -20.0, 20.0, 40, 1.1)


DESIGNS = {"wren": d_wren, "sparrow": d_sparrow, "mule": d_mule, "prospector": d_prospector, "kestrel": d_kestrel,
           "corsair": d_corsair, "lancer": d_lancer, "aegis": d_aegis, "bastion": d_bastion, "specter": d_specter,
           "nyx": d_nyx, "leviathan": d_leviathan, "seraph": d_seraph, "halberd": d_halberd, "monarch": d_monarch,
           "behemoth": d_behemoth, "ark": d_ark, "titan": d_titan}


def player_ship(sid):
    k = Kit(sid, *SHIPS[sid])
    DESIGNS[sid](k)
    return k.finish("ships")


# ---------------------------------------------------------------- pirates

# id: (hull, trim, lamp colours)
ENEMIES = {
    "raider": ("8f2a1f", "1f1412", "ffb84a"),
    "gunner": ("7a3a26", "1e120c", "ff9a3d"),
    "sniper": ("a5481c", "1a120c", "ffd060"),
    "swarmer": ("b03a2c", "1e0f0d", "ffb84a"),
    "captain": ("5e1414", "140808", "ffc040"),
}


def pirate(eid):
    """Pirates: scrap-built and spiky, rust-red over black, with a lamp 'eye'. Each has turrets like the
    player's ships (the sentinel is its own thing)."""
    if eid == "sentinel":
        return sentinel()
    c_hull, c_trim, c_lamp = ENEMIES[eid]
    k = Kit(eid, c_hull, c_trim, c_lamp)
    trim = k.acc  # the "accent" of a pirate is its dark trim
    lamp = mat(eid + "_lamp", c_lamp, 0.0, 0.3, emit=3.0)
    if eid == "raider":
        hb = k.hull_part("hull", 3.0, 6.5, 1.5, taper=(0.35, 0.6), chamfer=0.2)
        k.part("armor", 3.3, 3.2, 0.7, y=-1.0, z=hb.top(-1.0) + 0.2, mats=k.A, taper=(0.6, 0.8))
        for sx in (-1, 1):
            k.plate("claw_wing", [(sx * 1.2, 0.6), (sx * 3.4, -1.6), (sx * 3.0, -3.2), (sx * 1.3, -2.4)], 0.22, 0.0)
            k.plate("claw_edge", [(sx * 3.0, -1.2), (sx * 3.5, -1.6), (sx * 3.1, -3.3), (sx * 2.7, -2.8)], 0.3, 0.0, mat_=trim)
            cyl("spike", 0.14, 1.2, (sx * 1.0, -1.6, hb.top(-1.6) + 0.5), trim, parent=k.body, segs=6, r2=0.0)
            k.mount(sx * 2.6, -1.6, 0.11, "top", 0.6)
            k.engine(sx * 0.6, hb.back() - 0.05, 0, 0.36, fins=False)
        box("eye", (0.6, 0.1, 0.2), (0, 2.0, hb.top(2.0) - 0.05), lamp, 0.0, parent=k.body)
    elif eid == "gunner":
        hb = k.hull_part("hull", 4.6, 6.4, 2.4, taper=(0.8, 0.75), chamfer=0.35)
        hump = k.part("hump", 3.2, 3.6, 1.0, y=-0.6, z=hb.top(-0.6) + 0.4, mats=k.A, taper=(0.8, 0.8))
        for sx in (-1, 1):
            k.part("armor_slab", 0.6, 5.0, 2.0, x=sx * 2.5, y=-0.2, rot=(0, sx * 0.25, 0), mats=k.A)
            for i in range(3):
                cyl("spike", 0.16, 1.0, (sx * 2.7, 1.5 - i * 1.4, 0.9), trim, rot=(0, sx * 0.9, 0), parent=k.body, segs=6, r2=0.0)
            k.engine(sx * 1.2, hb.back() - 0.05, 0, 0.55)
        box("eye", (1.4, 0.1, 0.24), (0, hb.front() + 0.02, 0.5), lamp, 0.0, parent=k.body)
        k.mount(0, 1.6, hb.top(1.6), "top", 0.9)
        k.mount(0, -1.4, hump.top(-1.4), "top", 0.9)
    elif eid == "sniper":
        hb = k.hull_part("hull", 1.6, 9.0, 1.2, taper=(0.4, 0.6), chamfer=0.18)
        along_y(0.18, 5.0, (0, hb.front() + 2.2, -0.2), k.gunm, parent=k.body, segs=10)
        for c in range(4):
            along_y(0.24, 0.2, (0, hb.front() + 0.6 + c * 1.0, -0.2), trim, parent=k.body, segs=10)
        k.grow((0, hb.front() + 2.2, 0), (0.3, 2.6, 0.3))
        for sx in (-1, 1):
            k.plate("vane", [(sx * 0.6, -1.0), (sx * 2.2, -2.8), (sx * 2.0, -3.6), (sx * 0.6, -3.2)], 0.14, 0.0)
        k.plate("fin", [(-2.0, 0.4), (-3.6, 0.4), (-4.1, 1.5), (-3.3, 1.5)], 0.08, plane="yz", mat_=trim)
        k.engine(0, hb.back() - 0.05, 0, 0.42)
        box("eye", (0.4, 0.1, 0.16), (0, 1.5, hb.top(1.5) - 0.02), lamp, 0.0, parent=k.body)
        k.mount(0, -1.0, hb.top(-1.0), "top", 0.6)
    elif eid == "swarmer":
        hb = k.hull_part("hull", 1.4, 2.8, 0.9, taper=(0.4, 0.6), chamfer=0.15)
        for sx in (-1, 1):
            k.plate("blade", [(sx * 0.5, 0.6), (sx * 1.6, -0.6), (sx * 1.4, -1.3), (sx * 0.5, -0.9)], 0.1, 0.0, mat_=trim)
            pod = k.part("gun_pod", 0.5, 1.0, 0.5, x=sx * 1.25, y=-0.3, mats=k.A)
            k.mount(pod.side_x(sx, -0.3), -0.3, 0, side(sx), 0.42)
        k.engine(0, hb.back() - 0.05, 0, 0.3, fins=False)
        box("eye", (0.3, 0.08, 0.12), (0, 0.9, hb.top(0.9) - 0.02), lamp, 0.0, parent=k.body)
    else:  # captain: a pirate cruiser, crowned in spikes
        hb = k.hull_part("hull", 6.6, 15.0, 3.4, taper=(0.4, 0.65), chamfer=0.5)
        for sx in (-1, 1):
            k.plate("claw_wing", [(sx * 2.4, 1.0), (sx * 5.6, -3.4), (sx * 5.0, -6.4), (sx * 2.6, -4.6)], 0.35, -0.2)
            k.plate("claw_edge", [(sx * 5.0, -2.6), (sx * 5.7, -3.4), (sx * 5.1, -6.5), (sx * 4.5, -5.8)], 0.45, -0.2, mat_=trim)
            k.part("armor_slab", 0.8, 9.0, 2.6, x=sx * (hb.hw(-1.0) + 0.2), y=-1.0, mats=k.A, rot=(0, sx * 0.3, 0))

        for x in (-1.8, 0.0, 1.8):
            k.engine(x, hb.back() - 0.05, 0, 0.75)
        tw = k.part("tower", 2.4, 3.2, 3.0, y=-2.8, z=hb.top(-2.8) + 1.3, mats=k.A, taper=(0.8, 0.9))
        windows(tw.side_frame(1, tw.y, tw.z + 0.4), 2.6, 0.6, 2, lamp, k.rng, k.body, gap=0.35)
        windows(tw.side_frame(-1, tw.y, tw.z + 0.4), 2.6, 0.6, 2, lamp, k.rng, k.body, gap=0.35)
        for i in range(8):
            a = i * 2 * math.pi / 8
            cyl("crown", 0.22, 1.8, (math.cos(a) * 1.0, tw.y + math.sin(a) * 1.0, tw.top(tw.y) + 0.7), trim,
                rot=(math.sin(a) * -0.5, math.cos(a) * 0.5, 0), parent=k.body, segs=6, r2=0.0)
        for i in range(8):
            cyl("spike", 0.3, 1.6, (k.rng.uniform(-2.0, 2.0), k.rng.uniform(-5.0, 4.0), hb.top(0) + 0.5), trim, parent=k.body,
                segs=6, r2=0.0)
        box("eye", (2.0, 0.1, 0.3), (0, 4.5, hb.top(4.5) - 0.05), lamp, 0.0, parent=k.body)
        k.mount(0, 2.8, hb.top(2.8), "top", 1.2)
        k.mount(0, -1.0, hb.bottom(-1.0), "bottom", 1.2)
    k.beacon(0, k.main.back() + 0.5, k.main.top(k.main.back() + 0.5) + 0.12, 0.08 + k.main.w * 0.01)
    return k.finish("enemies")


def sentinel():
    """Anomaly guardian: a glowing crystal core in two counter-turning rings, inside four slowly orbiting
    armour plates, with a loose swarm of shards circling the other way."""
    rng = random.Random("sentinel")
    core = mat("sentinel_core", "d080ff", 0.0, 0.2, emit=3.5)
    hot = mat("sentinel_hot", "ffe0ff", 0.0, 0.2, emit=6.0)
    plate = mat("sentinel_plate", "2a1040", 0.6, 0.4)
    plate2 = mat("sentinel_plate2", "3d1a5c", 0.6, 0.4)
    seam = mat("sentinel_seam", "5a2a8a", 0.4, 0.5, emit=0.25)
    trim = mat("sentinel_trim", "8e44ad", 0.4, 0.4, emit=0.5)
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
    # two turrets ride on opposite armour plates, swinging round the core with them
    for i, a in enumerate((math.pi / 4, math.pi * 5 / 4)):
        e = empty("Gun_%d" % i, (math.cos(a) * 3.5, math.sin(a) * 3.5, 0), ring)
        e.rotation_euler = (0, math.pi / 2, a)
        e.scale = (0.7, 0.7, 0.7)
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
