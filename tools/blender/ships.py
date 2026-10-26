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
from mathutils.bvhtree import BVHTree

sys.path.append(os.path.dirname(__file__))
from common import *  # noqa: E402,F401,F403

# Ships are sleek and smooth (the user disliked the old plated boxes: "they look like legos"): every hull piece
# is a rounded, smooth-shaded loft (common.sleek), and every small block has its edges rounded right off.
_block = box


def box(name, size, loc=(0, 0, 0), material=None, bevel=0.0, rot=(0, 0, 0), parent=None, taper=None):
    o = _block(name, size, loc, material, 0.0, rot, parent, taper)
    m = o.modifiers.new("Round", "BEVEL")
    m.width = min(size) * 0.16
    m.segments = 2
    m.limit_method = "NONE"
    for poly in o.data.polygons:
        poly.use_smooth = True
    return o


def plated(name, size, loc=(0, 0, 0), mats=None, parent=None, rot=(0, 0, 0), taper=None, p=3.2, **_kw):
    """(No armour plating on ships: a smooth piece, squarer than a hull part.)"""
    return sleek(name, size, loc, mats, parent, rot, taper, p=p, nose=min(size) * 0.3, tail=min(size) * 0.2)


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


def turret_blocked(bvh, pa, n, s):
    """Would a turret on a mount at pa (facing n, size s) have its housing inside (or touching) the hull? Its
    housing and barrels fill a column above the mount and a ring round it."""
    u = n.orthogonal().normalized()
    v = n.cross(u)
    for h in (0.3, 0.55):
        pts = [pa + n * h * s]
        for a in range(8):
            ang = a * math.pi / 4
            pts.append(pa + n * h * s + (u * math.cos(ang) + v * math.sin(ang)) * 0.45 * s)
        for p in pts:
            loc, normal, _i, dist = bvh.find_nearest(p)
            if loc is not None and (dist < 0.03 * s or enclosed(bvh, p, s * 40.0)):
                if DEBUG_MOUNTS:
                    print("  blocked at h %.2f: point %s nearest %s normal %s dist %.3f" % (h, tuple(round(c, 2) for c in p),
                                                                                        tuple(round(c, 2) for c in loc), tuple(round(c, 2) for c in normal), dist))
                return True
    return False


DEBUG_MOUNTS = os.environ.get("DL_DEBUG_MOUNTS", "") != ""
AXES = [Vector(d) for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))]


def enclosed(bvh, p, reach):
    """Is p inside the hull? Only if a ray out of it hits the hull whichever way it goes (the nearest face's
    normal can't tell inside from out near an edge)."""
    return all(bvh.ray_cast(p, d, reach)[0] is not None for d in AXES)


def audit(k, mesh_obj):
    """Print AUDIT lines for anything that clashes on a finished ship: engine housings touching, an engine's
    exhaust running into the hull, turrets on top of each other or of an engine. Returns the turrets whose
    housings would sit inside other parts of the hull (see Kit.raise_mount)."""
    me = mesh_obj.data
    mw = mesh_obj.matrix_world
    bvh = BVHTree.FromPolygons([mw @ v.co for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
    eng = k.engines
    for i in range(len(eng)):
        for j in range(i + 1, len(eng)):
            (pa, ra), (pb, rb) = eng[i], eng[j]
            if (pa - pb).length < (ra + rb) * 1.4:
                print("AUDIT %s: engines %d and %d overlap" % (k.sid, i, j))
        p, r = eng[i]
        hit = bvh.ray_cast(p + Vector((0, -r * 0.3, 0)), Vector((0, -1, 0)), r * 5.0)
        if hit[0] is not None:
            print("AUDIT %s: engine %d exhaust runs into the hull" % (k.sid, i))
    buried = []
    for i, (pa, rot, sa) in enumerate(k.mounts):
        n = Euler(rot).to_matrix() @ Vector((0, 0, 1))
        for j in range(i + 1, len(k.mounts)):
            pb, _r, sb = k.mounts[j]
            if (pa - pb).length < (sa + sb) * 0.72:
                print("AUDIT %s: turrets %d and %d overlap" % (k.sid, i, j))
        for (pe, re) in eng:
            if (pa - pe).length < sa * 0.6 + re * 1.5:
                print("AUDIT %s: turret %d sits on engine" % (k.sid, i))
        if turret_blocked(bvh, pa, n, sa):
            buried.append(i)
    return buried


def side(sx):
    return "right" if sx > 0 else "left"


class Part:
    """A smooth hull piece (see common.sleek): taper narrows the +Y end in x and z, and the ends round off. For
    placing things on its surfaces."""

    def __init__(self, w, l, h, x=0.0, y=0.0, z=0.0, taper=(1.0, 1.0)):
        self.w, self.l, self.h, self.x, self.y, self.z, self.taper = w, l, h, x, y, z, taper
        self.slope = w / 2 * (taper[0] - 1) / l
        self.nose, self.tail = sleek_ends((w, l, h))

    def t(self, y):
        return min(1.0, max(0.0, (y - self.y) / self.l + 0.5))

    def k(self, y):
        return sleek_k(y - self.y, self.l, self.nose, self.tail)

    def hw(self, y):
        return self.w / 2 * (1 + (self.taper[0] - 1) * self.t(y)) * self.k(y)

    def hh(self, y):
        return self.h / 2 * (1 + (self.taper[1] - 1) * self.t(y)) * self.k(y)

    def dip(self, y):
        """How far the nose has dipped at y (see common.sleek's droop)."""
        if y <= self.y:
            return 0.0
        return -self.h / 2 * (1 + (self.taper[1] - 1) * self.t(y)) * (1 - self.k(y)) * 0.45

    def top(self, y):
        return self.z + self.dip(y) + self.hh(y)

    def bottom(self, y):
        return self.z + self.dip(y) - self.hh(y)

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
    and its overall bounds. Hull pieces are smooth and rounded, two-tone, with no plating or greebles."""

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

    def part(self, name, w, l, h, x=0.0, y=0.0, z=0.0, taper=(1.0, 1.0), mats=None, rot=(0, 0, 0), p=3.4, **_old):
        """A smooth hull piece (common.sleek). (_old: the plating options the old kit took, ignored.)"""
        sleek(name, (w, l, h), (x, y, z), mats or self.P, self.body, rot=rot, taper=taper, p=p)
        self.grow((x, y, z), (w / 2, l / 2, h / 2), rot)
        return Part(w, l, h, x, y, z, taper)

    def hull_part(self, name, w, l, h, **kw):
        p = self.part(name, w, l, h, **kw)
        self.main = self.main or p
        return p

    def plate(self, name, pts, t, offset=0.0, plane="xy", mat_=None, x=0.0, rot=(0, 0, 0)):
        """A wing, fin or blade cut to an outline (see common.slab)."""
        o = slab(name, pts, t, offset, plane, mat_ or self.hull, self.body, rot=rot, loc=(x, 0, 0))
        b = o.modifiers.new("Round", "BEVEL")  # soft, rounded edges all round the outline
        b.width = t * 0.45
        b.segments = 3
        b.limit_method = "ANGLE"
        for poly in o.data.polygons:
            poly.use_smooth = True
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
        # a smooth nacelle round the nozzle, flaring into a clean bell (no ribs or fins: ships are sleek)
        sleek("nacelle", (r * 2.8, nlen * 0.7, r * 2.8), (x, y - nlen * 0.2 + 0.1, z), [self.hull2], self.body, p=2.0,
              nose=nlen * 0.25, tail=r * 0.3, segs=24)
        along_y(r * 1.25, nlen, (x, y - nlen / 2 + 0.1, z), self.bell, parent=self.body, segs=32, r2=r, caps=False)
        torus("bell_lip", r * 1.25, 0.03 + r * 0.04, (x, y - nlen + 0.1, z), self.acc2, rot=(math.radians(90), 0, 0),
              parent=self.body, seg=32, ring=8)
        along_y(r * 1.0, 0.08, (x, y - nlen * 0.34, z), self.eng, parent=self.body, segs=20)
        along_y(r * 0.42, nlen * 0.5, (x, y - nlen * 0.6, z), self.eng_core, parent=self.body, segs=12, r2=r * 0.12)
        self.engines.append((Vector((x, y - nlen + 0.1, z)), r))
        self.grow((x, y - nlen / 2, z), (r * 1.4, nlen / 2, r * 1.4))

    def near_mount(self, p, r):
        """Is a part of radius r at p in the way of a turret mount (where the turret sits and swings)?"""
        return any((Vector(p) - m).length < r + s * 0.75 for m, _rot, s in self.mounts)

    def raise_mount(self, i, mesh_obj):
        """A turret whose housing would sit inside other parts of the hull goes up on a pedestal, out along its
        mount's normal, until it's clear."""
        p, rot, s = self.mounts[i]
        n = Euler(rot).to_matrix() @ Vector((0, 0, 1))
        me = mesh_obj.data
        mw = mesh_obj.matrix_world
        bvh = BVHTree.FromPolygons([mw @ v.co for v in me.vertices], [tuple(q.vertices) for q in me.polygons])
        lift = 0.0
        for step in range(1, 7):
            lift = step * 0.25 * s
            if not turret_blocked(bvh, p + n * lift, n, s):
                break
        else:
            print("AUDIT %s: turret %d is boxed in - left where it is" % (self.sid, i))
            return
        top = p + n * lift
        cyl("pedestal", 0.42 * s, lift + 0.2 * s, tuple(p + n * (lift / 2 - 0.1 * s)), self.hull2, rot=rot, parent=self.r, segs=16)
        cyl("pedestal_collar", 0.5 * s, 0.08 * s, tuple(top - n * 0.06 * s), self.acc2, rot=rot, parent=self.r, segs=16)
        self.mounts[i] = (top, rot, s)
        self.grow(top + n * 0.5 * s, (1.1 * s, 1.5 * s, 1.1 * s))
        print("AUDIT %s: turret %d raised %.2f m onto a pedestal" % (self.sid, i, lift))

    def cockpit(self, on, y, w, l, h, x=0.0):
        """A raised cockpit on top of part `on`: plated, with a raked windscreen and a glass roof panel."""
        base = on.top(y)
        cb = self.part("cockpit", w, l, h, x=x, y=y, z=base + h / 2 - 0.05, taper=(0.8, 0.78))
        # a smooth glass bubble set into its top, swept back
        sleek("canopy", (w * 0.62, l * 0.75, h * 0.9), (x, y + l * 0.08, base + h * 0.62), [self.glass], self.body, p=2.0,
              nose=l * 0.4, tail=l * 0.3, taper=(0.75, 0.7))
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

    # The old kit scattered greebles (pipes, vents, blocks...) over decks, bellies and flanks. Sleek ships keep
    # their surfaces clean, so these do nothing now (the designs still say where they'd go).
    def deck(self, part, y0, y1, count, scale, inset=0.85, kinds=None):
        pass

    def belly(self, part, y0, y1, count, scale, inset=0.75):
        pass

    def flanks(self, part, count, scale, z=None):
        pass

    def portholes(self, part, y, z, length, rows, gap):
        for sx in (-1, 1):
            windows(part.side_frame(sx, y, z), length, rows * gap * 0.8, rows, self.win, self.rng, self.body, gap=gap,
                    cell=(gap * 0.55, gap * 0.35))

    def container(self, x, y, z, w, l, h):
        c = self.rng.choice([self.A, self.P, self.D, [self.acc2, self.seam, self.acc]])
        # (cargo rides in smooth capsule tanks: a rack of boxes read as building blocks)
        # round tanks filling the container's slot: side by side (or stacked) as its proportions allow, since one
        # rounded piece the shape of a flat box reads as a pillow
        n = max(1, round(max(w, h) / min(w, h)))
        d = min(min(w, h), max(w, h) / n)
        for i in range(n):
            off = -max(w, h) / 2 + max(w, h) / n * (i + 0.5)
            at = (x + off, y, z) if w >= h else (x, y, z + off)
            sleek("container", (d * 0.96, l, d * 0.96), at, c, self.body, p=2.0, nose=min(l * 0.3, d * 0.5), tail=min(l * 0.2, d * 0.3),
                  droop=0.0)
        self.grow((x, y, z), (w / 2, l / 2, h / 2))

    # ---------------------------------------------------------------- finishing

    def finish(self, folder):
        merge(self.body, self.sid + "_mesh")
        # merge() made the joined mesh the child of `body`; reparent it under the root and drop `body`
        mesh_obj = next(o for o in self.body.children if o.type == "MESH")
        mesh_obj.parent = self.r
        bpy.data.objects.remove(self.body)
        for i in audit(self, mesh_obj):
            self.raise_mount(i, mesh_obj)
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
        k.part("hopper_wall", 4.75, 0.35, 1.04, y=-0.6 + sx * 1.8, z=top + 0.47, mats=k.A)
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
    for x, z in ((0.0, 0.4), (-0.44, -0.35), (0.44, -0.35)):
        k.engine(x, sp.back() - 0.05, z, 0.3, fins=False)
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
    for x in (-1.85, 0.0, 1.85):
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
        k.engine(x, body.back(), -0.1, 0.26, fins=False)  # out behind the wing's trailing edge
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
        k.engine(x, hb.back() - 0.05, 0, 0.4)
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
    for x in (-2.35, 0.0, 2.35):
        k.engine(x, hb.back() - 0.05, 0, 0.8)
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
    for x in (-3.7, -1.23, 1.23, 3.7):
        k.engine(x, hb.back() - 0.05, 0, 0.85)
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
    for x in (-5.3, -2.65, 0.0, 2.65, 5.3):
        k.engine(x, hb.back() - 0.05, 0, 0.9)
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
    for x in (-6.3, -2.1, 2.1, 6.3):
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
    for x in (-5.2, -1.74, 1.74, 5.2):
        k.engine(x, hb.back() - 0.05, 0, 1.2)
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


# ---------------------------------------------------------------- the generated fleet

# The rest of the fleet is built from a handful of archetypes (dart, wedge, block hauler, twin boom, spine
# explorer, mining barge, cruiser, carrier, saucer), each sized and varied by its spec. Capital ships are
# built at a modest size and shown `scale` times bigger by the game (its meta carries the scale).
# id: (archetype, length, width, height, engines, engine radius, turrets, turret size, hull, accent, glass, extras)
FLEET = {
    "gnat": ("dart", 5.5, 6.0, 1.2, 1, 0.42, 2, 0.6, "d8dde6", "39a0d8", "9dfcff", {}),
    "wisp": ("twin", 6.0, 7.0, 1.1, 2, 0.32, 2, 0.6, "eef2f6", "8a7cff", "c8c0ff", {}),
    "pike": ("wedge", 7.0, 6.0, 1.4, 2, 0.42, 2, 0.75, "b9bcc4", "d84a3a", "ffd27a", {}),
    "bumble": ("block", 8.0, 4.4, 2.6, 2, 0.55, 2, 0.8, "e0b84a", "3a3a3a", "7ff0ff", {"v": 1}),
    "drifter": ("spine", 9.0, 3.0, 2.0, 2, 0.4, 2, 0.7, "c8ccd8", "4ab0a0", "aaf8ee", {"ring": True}),
    "hornet": ("wedge", 8.0, 7.5, 1.6, 2, 0.5, 2, 0.8, "e8c02a", "222428", "ffe7a3", {"v": 1}),
    "digger": ("miner", 8.0, 6.5, 2.0, 2, 0.55, 2, 0.8, "c86a2a", "3a3330", "ffd27a", {}),
    "porter": ("block", 11.0, 5.0, 3.0, 2, 0.7, 2, 0.9, "7c8a9a", "e07a3c", "7ff0ff", {}),
    "falcon": ("dart", 9.0, 9.0, 1.4, 3, 0.4, 2, 0.8, "f0f0ea", "2f6fd8", "9dfcff", {"v": 1}),
    "vanguard": ("cruiser", 11.0, 6.0, 2.4, 3, 0.55, 4, 0.9, "8a96a8", "e8b84a", "ffe7a3", {}),
    "quarry": ("miner", 10.0, 8.0, 2.4, 3, 0.6, 2, 0.95, "a0a4ac", "e0b030", "ffe066", {"v": 1}),
    "wayfarer": ("spine", 12.0, 3.4, 2.2, 2, 0.5, 2, 0.8, "e6dcc8", "c0603a", "ffc890", {"v": 1}),
    "brick": ("saucer", 7.0, 7.0, 2.6, 2, 0.6, 2, 1.0, "9aa0a8", "5a7090", "8fd8ff", {}),
    "raptor": ("wedge", 10.0, 9.0, 1.8, 3, 0.55, 4, 0.85, "3a404c", "3fc46a", "9dffc0", {"v": 2}),
    "bulwark": ("saucer", 9.0, 9.0, 3.0, 3, 0.7, 4, 1.05, "c8ccd4", "3a62b0", "8fd8ff", {"v": 1}),
    "trawler": ("block", 16.0, 7.0, 4.0, 4, 0.8, 2, 1.0, "6a7a5a", "d8a040", "ffe066", {"v": 2}),
    "phantom": ("wedge", 9.0, 10.0, 1.0, 2, 0.35, 2, 0.7, "23272e", "3a4458", "70ffe0", {"stealth": True}),
    "warden": ("saucer", 12.0, 12.0, 3.6, 4, 0.8, 4, 1.2, "e6ecf6", "2fa8c8", "8ff4ff", {"v": 2}),
    "tempest": ("dart", 13.0, 11.0, 2.0, 3, 0.6, 4, 0.95, "dfe3ea", "7a3ad8", "d8b0ff", {"v": 2}),
    "excavator": ("miner", 14.0, 11.0, 3.2, 4, 0.75, 4, 1.1, "d8a020", "303030", "ffe066", {"v": 2}),
    "pathfinder": ("spine", 16.0, 4.0, 3.0, 3, 0.6, 4, 0.95, "d0d8e8", "3a7ad8", "a0d0ff", {"ring": True}),
    "mantis": ("twin", 12.0, 11.0, 2.0, 2, 0.7, 4, 0.9, "6aa040", "2a3a22", "c8ff8a", {}),
    "dominator": ("cruiser", 26.0, 9.0, 4.0, 4, 1.0, 6, 1.4, "5a6070", "c83a3a", "ffb08a", {"v": 1}),
    "atlas": ("block", 30.0, 9.0, 6.0, 4, 1.1, 4, 1.4, "8a8070", "3a8ad0", "7ff0ff", {"v": 3}),
    "valkyrie": ("dart", 18.0, 15.0, 2.6, 3, 0.8, 4, 1.1, "f4f0f8", "d84a8a", "ffc0e0", {"v": 3}),
    "obsidian": ("wedge", 16.0, 14.0, 1.8, 3, 0.5, 4, 1.0, "1a1c22", "50306a", "c070ff", {"stealth": True, "v": 4}),
    "juggernaut": ("cruiser", 55.0, 16.0, 7.0, 6, 1.5, 10, 2.2, "707884", "d8433a", "ffb36b", {"v": 2}),
    "harbinger": ("cruiser", 42.0, 12.0, 5.0, 4, 1.3, 8, 1.9, "30364a", "3ad0c0", "9ffff0", {"v": 3}),
    "starminer": ("miner", 40.0, 22.0, 7.0, 4, 1.5, 6, 1.8, "c8a03a", "3a3a3a", "ffe066", {"v": 3}),
    "paragon": ("dart", 45.0, 30.0, 5.0, 5, 1.4, 8, 1.9, "fff6ea", "e8b84a", "ffe7a3", {"v": 4}),
    "oracle": ("spine", 50.0, 10.0, 7.0, 4, 1.3, 6, 1.8, "e0e4f0", "8a5ad8", "d8c0ff", {"ring": True, "v": 2}),
    "colossus": ("carrier", 60.0, 26.0, 8.0, 6, 2.2, 12, 2.4, "7a808c", "d8a83a", "ffe7a3", {"scale": 6.0}),
    "starforge": ("miner", 60.0, 34.0, 10.0, 6, 2.4, 10, 2.4, "b88a2a", "2a2a2a", "ffd060", {"scale": 6.0, "v": 4}),
    "sovereign": ("cruiser", 80.0, 24.0, 10.0, 8, 2.4, 14, 2.6, "2a3450", "e8c060", "fff0b0", {"scale": 8.0}),
    "eclipse": ("spine", 90.0, 30.0, 12.0, 8, 2.8, 16, 2.8, "1e1a2a", "ff7a3a", "ffd0a0", {"scale": 11.0, "ring": True}),
    "aeon": ("cruiser", 100.0, 34.0, 14.0, 10, 3.0, 18, 3.0, "e8eaf0", "5a9aff", "c0e0ff", {"scale": 14.0, "v": 1}),
}


def engines(k, part, n, r, z=None, y=None):
    """n nozzles across the back of `part`, in as many rows as fit, never touching: each housing (with its heat
    fins) is about 3 nozzle radii across, so they sit at least that far apart - smaller, if that's what fits."""
    y = part.back() - 0.05 if y is None else y
    z = part.z if z is None else z
    avail_w = part.hw(part.back()) * 2.0 * 0.95
    avail_h = part.hh(part.back()) * 2.0 * 0.95
    pitch = r * 3.15
    rows = 1
    while rows < n and math.ceil(n / rows) * pitch > avail_w + pitch * 0.4 and (rows + 1) * pitch <= avail_h + pitch * 0.6:
        rows += 1
    per = math.ceil(n / rows)
    if per * pitch > avail_w + pitch * 0.4:  # still too wide: smaller nozzles
        r *= (avail_w + pitch * 0.4) / (per * pitch)
        pitch = r * 3.15
    for row in range(rows):
        m = per if row < rows - 1 else n - per * (rows - 1)
        zz = z + (row - (rows - 1) / 2) * pitch
        for i in range(m):
            x = (i - (m - 1) / 2) * pitch
            k.engine(x, y, zz, r)


def spread(k, part, n, s, y0, y1, face):
    """n turret mounts in a line along `part` between y0 and y1 on one face (top, bottom, left, right)."""
    for j in range(n):
        y = y0 + (y1 - y0) * ((j + 0.5) / n)
        if face == "top":
            k.mount(part.x, y, part.top(y), "top", s)
        elif face == "bottom":
            k.mount(part.x, y, part.bottom(y), "bottom", s)
        else:
            sx = 1 if face == "right" else -1
            k.mount(part.side_x(sx, y), y, part.z, face, s)


def g_dart(k, L, W, H, ne, er, guns, s, ex):
    """A fighter dart: a needle fuselage, swept wings with an accent edge, a tail fin, turrets on the spine
    and keel and (with more than two) out on the wings."""
    fw = max(1.2, W * 0.22)
    fus = k.hull_part("fuselage", fw, L, H, taper=(0.3, 0.55), chamfer=H * 0.18)
    k.cockpit(fus, L * 0.2, fw * 0.55, L * 0.18, H * 0.45)
    span = W / 2
    t = max(0.12, H * 0.14)
    v = ex.get("v", 0)
    for sx in (-1, 1):
        if v == 1:  # a pure delta from mid-body to the tail
            k.plate("delta", [(sx * fw * 0.4, L * 0.14), (sx * span, -L * 0.42), (sx * span * 0.9, -L * 0.47), (sx * fw * 0.4, -L * 0.47)],
                    t, -H * 0.1)
            k.plate("delta_edge", [(sx * span * 0.62, -L * 0.2), (sx * span, -L * 0.42), (sx * span * 0.96, -L * 0.44),
                                   (sx * span * 0.58, -L * 0.23)], t * 1.2, -H * 0.1, mat_=k.acc)
        elif v == 2:  # cranked: a broad glove near the body, a thin swept outer panel
            k.plate("glove", [(sx * fw * 0.4, L * 0.1), (sx * span * 0.5, -L * 0.22), (sx * span * 0.5, -L * 0.4), (sx * fw * 0.4, -L * 0.42)],
                    t * 1.2, -H * 0.1)
            k.plate("outer_wing", [(sx * span * 0.48, -L * 0.2), (sx * span, -L * 0.44), (sx * span, -L * 0.5), (sx * span * 0.48, -L * 0.4)],
                    t, -H * 0.1, mat_=k.acc)
        elif v == 3:  # swept far back, with a twin tail
            k.plate("wing", [(sx * fw * 0.4, -L * 0.08), (sx * span, -L * 0.46), (sx * span, -L * 0.52), (sx * fw * 0.4, -L * 0.38)], t,
                    -H * 0.1)
            k.plate("wing_edge", [(sx * span * 0.7, -L * 0.33), (sx * span, -L * 0.46), (sx * span, -L * 0.49), (sx * span * 0.7, -L * 0.36)],
                    t * 1.2, -H * 0.1, mat_=k.acc)
            k.plate("tail_fin", [(-L * 0.24, H * 0.3), (-L * 0.44, H * 0.3), (-L * 0.5, H * 0.3 + L * 0.14), (-L * 0.4, H * 0.3 + L * 0.14)],
                    max(0.08, H * 0.07), 0.0, plane="yz", x=sx * fw * 0.45, rot=(0, sx * 0.35, 0), mat_=k.acc)
        elif v == 4:  # a blended flying wing: the body flares out into it
            k.plate("blend", [(sx * fw * 0.3, L * 0.3), (sx * span * 0.55, -L * 0.05), (sx * span, -L * 0.36), (sx * span * 0.85, -L * 0.46),
                              (sx * fw * 0.3, -L * 0.42)], t * 1.4, -H * 0.05)
            k.plate("blend_edge", [(sx * span * 0.55, -L * 0.05), (sx * span, -L * 0.36), (sx * span * 0.97, -L * 0.38),
                                   (sx * span * 0.52, -L * 0.08)], t * 1.6, -H * 0.05, mat_=k.acc)
        else:
            k.plate("wing", [(sx * fw * 0.4, -L * 0.02), (sx * span, -L * 0.36), (sx * span, -L * 0.45), (sx * fw * 0.4, -L * 0.42)], t,
                    -H * 0.1)
            k.plate("wing_edge", [(sx * span * 0.55, -L * 0.22), (sx * span, -L * 0.36), (sx * span, -L * 0.39),
                                  (sx * span * 0.55, -L * 0.25)], t * 1.2, -H * 0.1, mat_=k.acc)
        if v in (0, 2):
            k.plate("canard", [(sx * fw * 0.35, L * 0.32), (sx * fw * 1.3, L * 0.24), (sx * fw * 1.3, L * 0.2), (sx * fw * 0.35, L * 0.24)],
                    t * 0.6, 0.0)
    if v != 3:
        k.plate("fin", [(-L * 0.2, H * 0.35), (-L * 0.42, H * 0.35), (-L * 0.47, H * 0.35 + L * 0.16), (-L * 0.36, H * 0.35 + L * 0.16)],
                max(0.08, H * 0.08), plane="yz")
    engines(k, fus, ne, er)
    wing = 0 if guns <= 2 else (4 if guns >= 8 else 2)
    top = (guns - wing + 1) // 2
    bottom = guns - wing - top
    spread(k, fus, top, s, -L * 0.3, L * 0.05, "top")
    spread(k, fus, bottom, s, -L * 0.25, L * 0.2, "bottom")
    wz = -H * (0.05 if v == 4 else 0.1)  # the wing's middle and half-thickness, for turrets on it
    wt = t * (1.4 if v == 4 else (1.2 if v == 2 else 1.0)) * 0.6
    for i in range(wing):
        sx = 1 if i % 2 == 0 else -1
        y = -L * (0.3 if i < 2 else 0.24) - (L * 0.08 if v == 3 else 0.0)
        if i < 2:
            k.mount(sx * span * 0.66, y, wz + wt, "top", s)
        else:
            k.mount(sx * span * 0.66, y, wz - wt, "bottom", s)
    k.lights(span, -L * 0.42, -H * 0.1, 0.06 + L * 0.004)
    k.belly(fus, -L * 0.2, L * 0.2, int(4 + L * 0.6), 0.1 + L * 0.03)


def g_wedge(k, L, W, H, ne, er, guns, s, ex):
    """An armoured arrowhead: a broad delta hull, a raised spine, wing extensions and (unless it's a stealth
    ship) canted twin fins."""
    hb = k.hull_part("hull", W * 0.62, L, H, taper=(0.2, 0.55), chamfer=H * 0.16)
    spine = k.part("spine", max(0.8, W * 0.15), L * 0.72, H * 0.4, y=-L * 0.06, z=hb.top(-L * 0.06) + H * 0.12, taper=(0.5, 0.6),
                   mats=k.A)
    box("canopy", (W * 0.08 + 0.3, L * 0.18, H * 0.25), (0, L * 0.24, spine.top(L * 0.24) + H * 0.05), k.glass, 0.03,
        taper=(0.5, 0.6), parent=k.body)
    t = max(0.14, H * 0.13)
    v = ex.get("v", 0)
    for sx in (-1, 1):
        k.plate("wing", [(sx * W * 0.24, -L * 0.1), (sx * W / 2, -L * 0.42), (sx * W / 2, -L * 0.5), (sx * W * 0.24, -L * 0.48)], t,
                -H * 0.18)
        k.plate("wing_stripe", [(sx * W * 0.38, -L * 0.27), (sx * W / 2, -L * 0.42), (sx * W / 2, -L * 0.45),
                                (sx * W * 0.38, -L * 0.3)], t * 1.2, -H * 0.18, mat_=k.acc)
        if v == 1:  # canards up front and a high T-tail instead of the canted fins
            k.plate("canard", [(sx * W * 0.08, L * 0.3), (sx * W * 0.3, L * 0.18), (sx * W * 0.3, L * 0.12), (sx * W * 0.08, L * 0.18)],
                    t * 0.7, H * 0.1, mat_=k.acc)
        elif v == 2:  # twin outer hulls riding along the wing
            side = k.part("side_hull", W * 0.12, L * 0.62, H * 0.75, x=sx * W * 0.4, y=-L * 0.16, taper=(0.4, 0.6), mats=k.A,
                          chamfer=H * 0.1)
            k.engine(side.x, side.back() - 0.05, 0, er * 0.8)
        elif v == 4:  # a sawtooth trailing edge, all angles
            k.plate("sawtooth", [(sx * W * 0.24, -L * 0.48), (sx * W * 0.32, -L * 0.58), (sx * W * 0.38, -L * 0.48), (sx * W * 0.44, -L * 0.57),
                                 (sx * W * 0.5, -L * 0.5)], t, -H * 0.18)
        if not ex.get("stealth") and v != 1:
            k.plate("fin", [(-L * 0.28, 0.0), (-L * 0.46, 0.0), (-L * 0.5, L * 0.18), (-L * 0.42, L * 0.18)], max(0.08, H * 0.07), 0.0,
                    plane="yz", x=sx * W * 0.18, rot=(0, sx * 0.4, 0))
    if v == 1:
        k.plate("t_fin", [(-L * 0.26, H * 0.3), (-L * 0.46, H * 0.3), (-L * 0.5, H * 0.3 + L * 0.2), (-L * 0.4, H * 0.3 + L * 0.2)],
                max(0.08, H * 0.07), plane="yz")
        k.plate("t_plane", [(-W * 0.25, -L * 0.37), (W * 0.25, -L * 0.37), (W * 0.25, -L * 0.45), (-W * 0.25, -L * 0.45)], t * 0.7,
                H * 0.3 + L * 0.2, mat_=k.acc)
    engines(k, hb, ne, er, z=-H * 0.05)
    top = min(2, max(1, guns // 2))
    bottom = min(2, guns - top)
    spread(k, spine, top, s, -L * 0.3, L * 0.06, "top")
    spread(k, hb, bottom, s, -L * 0.25, L * 0.15, "bottom")
    rest = guns - top - bottom
    for i in range(rest):
        sx = 1 if i % 2 == 0 else -1
        k.mount(sx * W * 0.38, -L * 0.36, -H * 0.18 + t * 0.6, "top", s * 0.9)
    k.lights(W / 2, -L * 0.48, -H * 0.18, 0.06 + L * 0.004)
    k.belly(hb, -L * 0.3, L * 0.2, int(6 + L * 0.6), 0.1 + L * 0.03)


def g_block(k, L, W, H, ne, er, guns, s, ex):
    """A hauler: a cab up front, a spine stacked with cargo containers, a heavy engine block. Turrets on the
    cab and the engine block."""
    k.main = Part(W, L, H)
    cab = k.part("cab", W * 0.85, L * 0.22, H * 0.92, y=L * 0.39, z=H * 0.04, taper=(0.86, 0.8), chamfer=H * 0.12)
    k.glass_band(cab, cab.front() + 0.02, H * 0.3, W * 0.6, H * 0.16)
    k.part("spine", W * 0.22, L * 0.62, H * 0.3, y=-L * 0.03, mats=k.G)
    rows = 3 if L < 14 else 4
    cl = L * 0.6 / rows
    v = ex.get("v", 0)
    if v == 1:  # a tanker: rows of pressure tanks instead of containers
        for i in range(rows):
            y = L * 0.24 - cl * (i + 0.5)
            for x in (-W * 0.24, W * 0.24):
                c = (x, y, 0.0)
                along_y(min(W * 0.22, H * 0.45), cl * 0.9, c, k.hull2 if i % 2 else k.acc2, parent=k.body, segs=18)
                along_y(min(W * 0.23, H * 0.47), cl * 0.08, c, k.dark, parent=k.body, segs=18)
                k.grow(c, (W * 0.23, cl * 0.45, H * 0.47))
            box("tank_walk", (W * 0.1, cl * 0.8, 0.06), (0, y, H * 0.3), k.gunm, 0.0, parent=k.body)
    elif v == 2:  # an enclosed freighter hull, cargo doors down its flanks and a raised bridge
        hold = k.part("hold", W * 0.9, L * 0.6, H * 0.9, y=-L * 0.03, mats=k.D, chamfer=H * 0.1)
        for i in range(rows):
            y = L * 0.24 - cl * (i + 0.5)
            for sx in (-1, 1):
                box("cargo_door", (0.08, cl * 0.75, H * 0.6), (hold.side_x(sx, y) + sx * 0.03, y, 0), k.acc, 0.0, parent=k.body)
        br = k.part("bridge_tower", W * 0.35, L * 0.08, H * 0.5, y=-L * 0.28, z=hold.top(-L * 0.28) + H * 0.22, taper=(0.9, 0.9))
        k.glass_band(br, br.front() + 0.02, br.z + H * 0.08, br.w * 0.8, H * 0.12)
    else:  # containers: two wide and two high, or (v 3) three by three round the spine
        cols = (-W * 0.3, 0.0, W * 0.3) if v == 3 else (-W * 0.26, W * 0.26)
        layers = (H * 0.32, 0.0, -H * 0.32) if v == 3 else (H * 0.25, -H * 0.25)
        cw = W * (0.29 if v == 3 else 0.46)
        ch = H * (0.3 if v == 3 else 0.46)
        for i in range(rows):
            y = L * 0.24 - cl * (i + 0.5)
            for x in cols:
                for z in layers:
                    if (x, z) != (0.0, 0.0) and k.rng.random() < 0.88:
                        k.container(x, y, z, cw, cl * 0.92, ch)
    eb = k.part("engine_block", W * 0.92, L * 0.17, H, y=-L * 0.42, mats=k.D, chamfer=H * 0.1)
    engines(k, eb, ne, er)
    faces = [(cab, "top"), (eb, "bottom"), (eb, "top"), (cab, "bottom")]
    for i in range(guns):
        part, face = faces[i % 4]
        y = part.y + (0.0 if i < 4 else part.l * 0.3)
        k.mount(0, y, part.top(y) if face == "top" else part.bottom(y), face, s)
    k.lights(W * 0.45, cab.y, H * 0.2, 0.08 + L * 0.004)
    k.beacon(0, eb.y - eb.l * 0.3, eb.top(eb.y) + 0.12, 0.1)
    k.deck(eb, eb.back() + 0.2, eb.y - 0.2, int(6 + L * 0.3), 0.15 + L * 0.02)


def g_twin(k, L, W, H, ne, er, guns, s, ex):
    """Twin booms joined by a wing, a cockpit pod between them and a high tailplane. Turrets on sponsons out
    on the booms and on the pod."""
    pod = k.hull_part("pod", max(1.2, W * 0.2), L * 0.75, H, y=L * 0.1, taper=(0.45, 0.6), chamfer=H * 0.2)
    box("canopy", (W * 0.1 + 0.3, L * 0.22, H * 0.3), (0, L * 0.25, pod.top(L * 0.25) + H * 0.05), k.glass, 0.04, taper=(0.5, 0.6),
        parent=k.body)
    bx = W * 0.4
    k.plate("wing", [(-bx, L * 0.06), (bx, L * 0.06), (bx, -L * 0.18), (-bx, -L * 0.18)], max(0.14, H * 0.16), 0.0)
    k.plate("tailplane", [(-bx * 1.03, -L * 0.42), (bx * 1.03, -L * 0.42), (bx * 1.03, -L * 0.5), (-bx * 1.03, -L * 0.5)],
            max(0.08, H * 0.09), H * 1.2)
    for sx in (-1, 1):
        boom = k.part("boom", max(0.7, W * 0.13), L, H * 0.8, x=sx * bx, taper=(0.55, 0.55), chamfer=H * 0.12)
        box("boom_stripe", (boom.w * 1.04, L * 0.07, H * 0.84), (boom.x, -L * 0.28, 0), k.acc, 0.0, parent=k.body)
        for e in range(max(1, ne // 2)):
            k.engine(boom.x + (0 if ne < 4 else (e - 0.5) * er * 2.4), boom.back() - 0.05, 0, er)
        k.plate("fin", [(-L * 0.35, H * 0.4), (-L * 0.5, H * 0.4), (-L * 0.52, H * 1.25), (-L * 0.44, H * 1.25)], 0.08, sx * bx,
                plane="yz")
        sp = k.part("sponson", max(0.5, W * 0.06), L * 0.18, H * 0.7, x=sx * (bx + boom.hw(L * 0.15) + W * 0.03), y=L * 0.15, mats=k.A)
        k.mount(sp.side_x(sx, L * 0.15), L * 0.15, 0, side(sx), s)
    rest = guns - 2
    spread(k, pod, (rest + 1) // 2, s, -L * 0.2, L * 0.1, "top")
    spread(k, pod, rest // 2, s, -L * 0.15, L * 0.25, "bottom")
    k.lights(bx, L * 0.4, 0.0, 0.06 + L * 0.004)


def g_spine(k, L, W, H, ne, er, guns, s, ex):
    """An explorer: a long spine with a sensor prow, pods along it and (often) a slowly turning ring round
    its waist. Turrets alternate above and below the spine."""
    hb = k.hull_part("spine", max(1.4, W * 0.36), L, H * 0.62, taper=(0.62, 0.68), chamfer=H * 0.12)
    v = ex.get("v", 0)
    if v == 1:  # a big sensor bulb on the bow
        ico("sensor_bulb", hb.w * 0.7, (0, hb.front() + hb.w * 0.4, 0), k.glass, 2, parent=k.body, smooth=True)
        torus("bulb_ring", hb.w * 0.66, hb.w * 0.06, (0, hb.front() + hb.w * 0.4, 0), k.acc, rot=(math.radians(90), 0, 0), parent=k.body,
              seg=32, ring=6)
        k.grow((0, hb.front() + hb.w * 0.4, 0), (hb.w * 0.7, hb.w * 0.7, hb.w * 0.7))
    else:
        along_y(hb.w * 0.28, L * 0.18, (0, hb.front() + L * 0.08, 0), k.gunm, parent=k.body, segs=12, r2=hb.w * 0.06)
        k.grow((0, hb.front() + L * 0.08, 0), (hb.w * 0.3, L * 0.09, hb.w * 0.3))
    k.cockpit(hb, L * 0.3, hb.w * 0.55, L * 0.14, H * 0.3)
    for c in range(3):
        y = L * (0.12 - c * 0.17)
        for sx in (-1, 1):
            if v == 2:  # boxy instrument pods on struts
                k.part("pod", hb.w * 0.5, L * 0.1, hb.w * 0.4, x=sx * (hb.hw(y) + hb.w * 0.45), y=y, mats=k.D if c % 2 else k.A, chamfer=0.05)
                k.part("pod_strut", hb.w * 0.4, L * 0.03, hb.w * 0.1, x=sx * (hb.hw(y) + hb.w * 0.12), y=y, mats=k.G)
            else:
                along_y(hb.w * 0.32, L * 0.12, (sx * (hb.hw(y) + hb.w * 0.3), y, 0), k.hull2 if c % 2 else k.acc, parent=k.body, segs=10)
                k.grow((sx * (hb.hw(y) + hb.w * 0.3), y, 0), (hb.w * 0.32, L * 0.06, hb.w * 0.32))
    if ex.get("ring"):
        rr = max(W * 0.5, hb.w * 1.6)
        ring = root("ring")
        ring.parent = k.r
        ring.location = (0, -L * 0.18, 0)
        torus("ring", rr, rr * 0.08, (0, 0, 0), k.hull2, rot=(math.radians(90), 0, 0), parent=ring, seg=48, ring=10)
        for i in range(4):
            a = i * math.pi / 2 + math.pi / 4
            box("spoke", (rr * 0.7, rr * 0.08, rr * 0.08), (math.cos(a) * rr * 0.62, 0, math.sin(a) * rr * 0.62), k.dark, 0.0,
                rot=(0, -a, 0), parent=ring)
            box("ring_pod", (rr * 0.25, rr * 0.25, rr * 0.2), (math.cos(a) * rr, 0, math.sin(a) * rr), k.acc, 0.05, rot=(0, -a, 0),
                parent=ring)
        merge(ring, "ring_mesh").parent = ring
        spin(ring, "Y", 600)
        k.grow((0, -L * 0.18, 0), (rr * 1.1, rr * 0.15, rr * 1.1))
    engines(k, hb, ne, er)
    spread(k, hb, (guns + 1) // 2, s, -L * 0.42, L * 0.2, "top")
    spread(k, hb, guns // 2, s, -L * 0.36, L * 0.3, "bottom")
    k.lights(hb.hw(-L * 0.3) + 0.2, -L * 0.3, 0.0, 0.06 + L * 0.003)
    k.flanks(hb, int(6 + L * 0.4), 0.1 + L * 0.02)


def g_miner(k, L, W, H, ne, er, guns, s, ex):
    """A mining barge: a wide low hull carrying an ore hopper, two arms reaching forward with claws and a
    drill between them. Turrets on the arms and the hull."""
    hb = k.hull_part("hull", W * 0.62, L * 0.62, H, y=-L * 0.1, taper=(0.86, 0.9), chamfer=H * 0.12)
    top = hb.top(hb.y)
    hw, hl = hb.w * 0.32, hb.l * 0.27
    v = ex.get("v", 0)
    rx = (math.radians(90), 0, 0)
    rock = mat("ore_rock", "4a4038", 0.1, 0.9)
    if v in (0, 2):  # an open ore hopper on the deck
        for sx in (-1, 1):
            k.part("hopper_wall", hb.w * 0.05, hl * 2, H * 0.5, x=sx * hw, y=hb.y, z=top + H * 0.22, mats=k.A)
            # (a touch lower than the side walls, so where they cross their tops don't sit in the same plane)
            k.part("hopper_wall", hw * 2 + hb.w * 0.05, hb.w * 0.05, H * 0.47, y=hb.y + sx * hl, z=top + H * 0.205, mats=k.A)
        for i in range(9):
            ico("ore", k.rng.uniform(0.12, 0.2) * hw * 2, (k.rng.uniform(-hw, hw) * 0.75, hb.y + k.rng.uniform(-hl, hl) * 0.75,
                                                          top + H * 0.15), rock, 1, parent=k.body)
    elif v == 1:  # two long ore tanks on the deck
        for sx in (-1, 1):
            c = (sx * hw * 0.7, hb.y, top + H * 0.32)
            along_y(H * 0.34, hl * 2.4, c, k.hull2, parent=k.body, segs=18)
            for j in range(3):
                along_y(H * 0.36, hl * 0.12, (c[0], hb.y + (j - 1) * hl * 0.8, c[2]), k.acc, parent=k.body, segs=18)
            k.grow(c, (H * 0.36, hl * 1.2, H * 0.36))
    elif v == 3:  # a great ore silo under a gantry
        ico("ore_silo", hw * 1.05, (0, hb.y, top + hw * 0.7), k.hull2, 2, parent=k.body, smooth=True)
        torus("silo_band", hw * 1.0, hw * 0.06, (0, hb.y, top + hw * 0.7), k.acc, parent=k.body, seg=40, ring=8)
        for sx in (-1, 1):
            box("gantry_leg", (hw * 0.12, hw * 0.12, hw * 1.9), (sx * hw * 1.15, hb.y, top + hw * 0.95), k.gunm, 0.0, parent=k.body)
        box("gantry_beam", (hw * 2.5, hw * 0.16, hw * 0.16), (0, hb.y, top + hw * 1.9), k.gunm, 0.0, parent=k.body)
        k.grow((0, hb.y, top + hw), (hw * 1.3, hw * 1.1, hw * 1.0))
    else:  # a smelter: furnace towers and smokestacks glowing on the deck
        hot = mat("forge_glow", "ff8a3d", 0.0, 0.4, emit=2.5)
        for j, sx in enumerate((-1, 0, 1)):
            h = H * (1.3 + 0.35 * (j % 2))
            twr = k.part("furnace", hw * 0.5, hl * 0.6, h, x=sx * hw * 0.7, y=hb.y, z=top + h / 2, mats=k.D, chamfer=hw * 0.05)
            box("furnace_glow", (hw * 0.52, 0.06, h * 0.25), (twr.x, twr.front() + 0.02, twr.z), hot, 0.0, parent=k.body)
            cyl("stack", hw * 0.1, h * 0.6, (twr.x, hb.y - hl * 0.15, twr.top(hb.y) + h * 0.3), k.dark, parent=k.body, segs=12)
            ico("stack_glow", hw * 0.1, (twr.x, hb.y - hl * 0.15, twr.top(hb.y) + h * 0.6), hot, 1, parent=k.body)
            k.grow((twr.x, hb.y, twr.top(hb.y) + h * 0.3), (hw * 0.12, hw * 0.12, h * 0.3))
    if v == 1:
        # no arms: a ring of mining lasers round the bow, turrets on the tanks
        R = max(hb.hw(hb.front()), hb.hh(hb.front())) * 1.25
        torus("laser_ring", R, R * 0.09, (0, hb.front() + L * 0.03, 0), k.gunm, rot=rx, parent=k.body, seg=40, ring=8)
        for a in range(8):
            ang = a * math.pi / 4
            box("ring_emitter", (R * 0.18, R * 0.3, R * 0.18), (math.cos(ang) * R, hb.front() + L * 0.05, math.sin(ang) * R), k.acc,
                0.02, parent=k.body)
            ico("emitter_lens", R * 0.07, (math.cos(ang) * R, hb.front() + L * 0.09, math.sin(ang) * R), k.win, 1, parent=k.body)
        k.grow((0, hb.front() + L * 0.05, 0), (R * 1.1, L * 0.06, R * 1.1))
        for sx in (-1, 1):
            k.mount(sx * hw * 0.7, hb.y + hl * 0.5, top + H * 0.66, "top", s)
    else:
        ax = W * 0.38
        for sx in (-1, 1):
            k.part("shoulder", W * 0.22, W * 0.22, H * 0.8, x=sx * ax, y=hb.front() - W * 0.05, mats=k.A)
            for lower in ((False, True) if v == 2 else (False,)):
                az = -H * 0.55 if lower else 0.0
                arm = k.part("arm", W * 0.14, L * (0.3 if lower else 0.36), H * 0.5, x=sx * ax * (0.8 if lower else 1.0),
                             y=hb.front() + L * (0.14 if lower else 0.17), z=az, mats=k.G, taper=(0.8, 0.8))
                for c in (-1, 0, 1):
                    box("claw", (arm.w * 0.25, L * 0.12, arm.h * 0.4), (arm.x + c * arm.w * 0.33, arm.front() + L * 0.05,
                                                                       az + abs(c) * arm.h * 0.1),
                        k.dark, 0.02, taper=(0.3, 0.5), rot=(0, 0, -sx * 0.25 + c * 0.2), parent=k.body)
                k.grow((arm.x, arm.front() + L * 0.05, az), (arm.w, L * 0.07, arm.h))
                if not lower:
                    k.mount(arm.x, arm.y - arm.l * 0.15, arm.top(arm.y), "top", s)
        reach = 0.32 if v == 2 else 0.2  # (the four-armed digger carries a longer drill)
        k.part("drill_housing", W * 0.25, L * 0.1, H * 0.7, y=hb.front() + L * 0.04, z=-H * 0.1, mats=k.G)
        along_y(W * 0.1, L * reach, (0, hb.front() + L * (0.08 + reach / 2), -H * 0.1), k.gunm, parent=k.body, segs=16, r2=W * 0.006)
        for c in range(4):
            torus("drill_thread", W * (0.085 - c * 0.018), W * 0.008, (0, hb.front() + L * (0.11 + c * reach / 5), -H * 0.1), k.dark,
                  rot=rx, parent=k.body, seg=16, ring=4)
        k.grow((0, hb.front() + L * (0.08 + reach / 2), 0), (W * 0.1, L * reach / 2, W * 0.1))
    br = k.part("bridge", W * 0.24, L * 0.14, H * 0.6, x=-W * 0.2, y=hb.back() + L * 0.1, z=hb.top(hb.back()) + H * 0.28, taper=(0.9, 0.85))
    k.glass_band(br, br.front() + 0.02, br.z + H * 0.08, br.w * 0.8, H * 0.16)
    k.radar(W * 0.2, hb.back() + L * 0.1, hb.top(hb.back()), 0.4 + L * 0.04)
    engines(k, hb, ne, er)
    rest = guns - 2
    spread(k, hb, (rest + 1) // 2, s, hb.back() + hb.l * 0.05, hb.front() - hb.l * 0.05, "bottom")
    for i in range(rest // 2):
        sx = 1 if i % 2 == 0 else -1
        k.mount(hb.side_x(sx, hb.y), hb.y - i * hb.l * 0.15, 0, side(sx), s)
    k.lights(W * 0.31, hb.y, H * 0.2, 0.06 + L * 0.004)
    k.belly(hb, hb.back() + 0.3, hb.front() - 0.3, int(8 + L * 0.4), 0.15 + L * 0.025)


def g_cruiser(k, L, W, H, ne, er, guns, s, ex):
    """A warship: a dagger hull with a spinal ridge, a stepped citadel and bridge tower, armour on the flanks.
    Turrets along the ridge and the keel, behind the citadel and (on the big ones) out on the flanks."""
    v = ex.get("v", 0)
    # v1: twin bridge towers; v2: a slab-sided brick with a second tier; v3: a long narrow needle
    taper = {2: (0.85, 0.9), 3: (0.3, 0.6)}.get(v, (0.45, 0.72))
    hb = k.hull_part("hull", W * (0.75 if v == 3 else 1.0), L, H, taper=taper, chamfer=H * 0.17)
    ridge = k.part("ridge", W * 0.2, L * (0.72 if v == 3 else 0.6), H * 0.34, y=L * 0.06, z=hb.top(L * 0.06) + H * 0.13, taper=(0.6, 0.7),
                   mats=k.A)
    cit = k.part("citadel", W * 0.48, L * 0.24, H * 0.5, y=-L * 0.18, z=hb.top(-L * 0.18) + H * 0.22, taper=(0.85, 0.9))
    if v == 2:
        cit = k.part("upper_citadel", W * 0.36, L * 0.16, H * 0.45, y=-L * 0.2, z=cit.top(-L * 0.2) + H * 0.2, taper=(0.85, 0.9), mats=k.A)
    for tx in ((-W * 0.13, W * 0.13) if v == 1 else (0.0,)):
        tw = k.part("tower", W * (0.14 if v == 1 else 0.2), L * 0.075, H * (0.75 if v == 1 else 0.55), x=tx, y=-L * 0.21,
                    z=cit.top(-L * 0.21) + H * (0.35 if v == 1 else 0.25), taper=(0.85, 0.85))
        k.glass_band(tw, tw.front() + 0.02, tw.z + H * 0.1, tw.w * 0.8, H * 0.08)
    k.mast(tw.x + tw.w * 0.25, tw.y - tw.l * 0.2, tw.top(tw.y), L * 0.08, 0.04 + L * 0.0025)
    k.radar(tw.x - tw.w * 0.25, tw.y - tw.l * 0.2, tw.top(tw.y), 0.4 + L * 0.025)
    for sx in (-1, 1):
        k.part("flank_armor", W * 0.08, L * 0.5, H * 0.75, x=sx * (hb.hw(-L * 0.05) + W * 0.02), y=-L * 0.05, mats=k.A,
               rot=(0, sx * 0.3, -sx * math.atan(hb.slope)))
    k.portholes(hb, -L * 0.05, H * 0.12, L * 0.55, 3 if L > 30 else 2, 0.25 + L * 0.008)
    engines(k, hb, ne, er)
    sides = 2 if guns >= 8 else 0
    top_ridge = min(3 if guns >= 10 else 2, max(1, (guns - sides) // 2 - 1))
    top_back = max(0, (guns - sides) // 2 - top_ridge)
    # only as many behind the citadel as fit there with room to swing; the rest go under the keel
    room = (cit.back() - L * 0.02) - (hb.back() + L * 0.03)
    top_back = min(top_back, max(0, int(room // (s * 1.7))))
    bottom = guns - sides - top_ridge - top_back
    spread(k, ridge, top_ridge, s, ridge.y - ridge.l * 0.05, ridge.front() - ridge.l * 0.08, "top")
    spread(k, hb, top_back, s, hb.back() + L * 0.03, cit.back() - L * 0.02, "top")
    spread(k, hb, bottom, s, -L * 0.4, L * 0.38, "bottom")
    for sx in ((-1, 1) if sides else ()):
        k.mount(hb.side_x(sx, L * 0.15) + sx * 0.1, L * 0.15, 0, side(sx), s)
    k.lights(hb.hw(L * 0.2) + 0.2, L * 0.2, H * 0.1, 0.08 + L * 0.004)
    k.beacon(0, hb.back() + L * 0.05, hb.top(hb.back()) + 0.3, 0.08 + L * 0.003)
    k.deck(hb, ridge.front() + L * 0.01, hb.front() - L * 0.02, int(6 + L * 0.2), 0.2 + L * 0.02)
    k.belly(hb, -L * 0.4, L * 0.4, int(10 + L * 0.4), 0.2 + L * 0.022)


def g_carrier(k, L, W, H, ne, er, guns, s, ex):
    """A carrier: a broad flat hull under a flight deck with runway lights, a hangar mouth in the bow and an
    island tower. Turrets on sponsons down both flanks and under the keel."""
    hb = k.hull_part("hull", W * 0.8, L, H * 0.55, taper=(0.82, 0.9), chamfer=H * 0.08)
    fd = k.part("flight_deck", W * 0.66, L * 0.9, H * 0.05, y=L * 0.02, z=hb.top(L * 0.02) + H * 0.03, mats=[k.deckm, k.seam, k.hull2],
                chamfer=0.1)
    dz = fd.top(0)
    for i in range(10):
        y = L * 0.4 - i * L * 0.085
        box("runway_stripe", (W * 0.02, L * 0.045, 0.06), (0, y, dz + 0.02), k.acc, 0.0, parent=k.body)
        for sx in (-1, 1):
            ico("runway_light", 0.06 + L * 0.0015, (sx * W * 0.26, y, dz + 0.06), k.amber, 1, parent=k.body)
    box("hangar_mouth", (W * 0.55, 0.4, H * 0.3), (0, hb.front() + 0.05, 0.0), k.dark, 0.0, parent=k.body)
    box("hangar_glow", (W * 0.5, 0.2, H * 0.03), (0, hb.front() + 0.18, H * 0.12), k.win, 0.0, parent=k.body)
    isl = k.part("island", W * 0.12, L * 0.18, H * 0.6, x=W * 0.3, y=-L * 0.1, z=dz + H * 0.3, taper=(0.9, 0.9))
    up = k.part("island_bridge", W * 0.1, L * 0.08, H * 0.25, x=W * 0.3, y=-L * 0.07, z=isl.top(-L * 0.07) + H * 0.12)
    k.glass_band(up, up.front() + 0.02, up.z + H * 0.03, up.w * 0.8, H * 0.07)
    k.mast(W * 0.32, -L * 0.12, up.top(-L * 0.12), L * 0.08, 0.04 + L * 0.002)
    k.radar(W * 0.27, -L * 0.13, up.top(-L * 0.13), 0.5 + L * 0.02)
    engines(k, hb, ne, er)
    bottom = max(2, guns // 3)
    sides = guns - bottom
    per = sides // 2
    for sx in (-1, 1):
        n = per + (1 if sx > 0 and sides % 2 else 0)
        for j in range(n):
            y = L * 0.38 - L * 0.76 * (j + 0.5) / n
            sp = k.part("sponson", W * 0.07, L * 0.08, H * 0.35, x=sx * (hb.hw(y) + W * 0.03), y=y, mats=k.A, chamfer=0.2)
            k.mount(sp.side_x(sx, y), y, 0, side(sx), s)
    spread(k, hb, bottom, s, -L * 0.4, L * 0.4, "bottom")
    k.lights(W * 0.42, -L * 0.3, H * 0.1, 0.08 + L * 0.003)
    k.portholes(hb, 0.0, 0.0, L * 0.7, 3, 0.25 + L * 0.008)
    k.belly(hb, -L * 0.45, L * 0.45, int(12 + L * 0.3), 0.2 + L * 0.02)


def g_saucer(k, L, W, H, ne, er, guns, s, ex):
    """A guardian: a squat octagonal fortress inside a shield-emitter ring, with a domed command deck.
    Turrets on armoured sponsons out on the flanks, and on the deck and keel."""
    R = W * 0.38
    v = ex.get("v", 0)
    sides = 6 if v == 1 else 8
    k.main = hb = Part(R * 1.85, R * 1.85, H)
    cyl("hull_core", R, H, (0, 0, 0), k.hull, rot=(0, 0, math.pi / sides), parent=k.body, segs=sides)
    k.grow((0, 0, 0), (R, R, H / 2))
    k.part("deck_plate", R * 1.4, R * 1.4, H * 0.25, z=H * 0.55, chamfer=H * 0.15)
    k.part("belly_plate", R * 1.2, R * 1.2, H * 0.2, z=-H * 0.52, chamfer=H * 0.12)
    for i in range(sides):
        a = i * 2 * math.pi / sides + math.pi / sides
        k.part("rim_armor", R * (0.95 if v == 1 else 0.7), R * 0.12, H * 0.8, x=math.cos(a) * R * 0.96, y=math.sin(a) * R * 0.96,
               rot=(0, 0, a + math.pi / 2), mats=k.A)
    if v == 2:  # a tiered tower rising off the deck, with a spire
        z = H * 0.67
        for j, (rr, hh) in enumerate(((R * 0.4, H * 0.9), (R * 0.28, H * 0.7))):
            cyl("tier", rr, hh, (0, 0, z + hh / 2), k.hull2 if j % 2 else k.hull, parent=k.body, segs=8, r2=rr * 0.85)
            torus("tier_band", rr * 0.95, rr * 0.06, (0, 0, z + hh * 0.7), k.acc, parent=k.body, seg=24, ring=6)
            z += hh
        cyl("spire", R * 0.04, H * 1.2, (0, 0, z + H * 0.6), k.dark, parent=k.body, segs=8, r2=R * 0.01)
        ico("spire_light", R * 0.05, (0, 0, z + H * 1.2), k.navr, 1, parent=k.body)
        k.grow((0, 0, z / 2 + H * 0.6), (R * 0.4, R * 0.4, z / 2 + H * 0.6))
    elif v == 1:  # a low command bridge across the deck instead of a dome
        br = k.part("command_bridge", R * 0.9, R * 0.35, H * 0.35, y=-R * 0.05, z=H * 0.85, taper=(0.8, 0.8))
        k.glass_band(br, br.front() + 0.02, br.z, br.w * 0.8, H * 0.12)
    else:
        cyl("dome", R * 0.5, H * 0.4, (0, -R * 0.1, H * 0.85), k.hull2, parent=k.body, segs=8, r2=R * 0.3)
        cyl("dome_glass", R * 0.38, H * 0.1, (0, -R * 0.1, H * 0.95), k.glass, parent=k.body, segs=8, r2=R * 0.32)
    torus("emitter_ring", R * 1.3, R * 0.045, (0, 0, -H * 0.3), k.gunm, parent=k.body, seg=64, ring=8)
    if v == 1:  # (a second ring, above)
        torus("emitter_ring", R * 1.45, R * 0.04, (0, 0, H * 0.3), k.gunm, parent=k.body, seg=64, ring=8)
        k.grow((0, 0, H * 0.3), (R * 1.5, R * 1.5, H * 0.1))
    for i in range(8):
        a = i * math.pi / 4 + math.pi / 8
        box("emitter", (R * 0.12, R * 0.12, H * 0.2), (math.cos(a) * R * 1.3, math.sin(a) * R * 1.3, -H * 0.3), k.acc, 0.04, rot=(0, 0, a),
            parent=k.body)
        ico("emitter_lamp", R * 0.03, (math.cos(a) * R * 1.3, math.sin(a) * R * 1.3, -H * 0.18), k.win, 1, parent=k.body)
    k.grow((0, 0, -H * 0.3), (R * 1.36, R * 1.36, H * 0.12))
    for sx in (-1, 1):
        sp = k.part("sponson", R * 0.3, R * 0.65, H * 0.5, x=sx * R * 1.0, y=R * 0.1, z=H * 0.08, mats=k.A, chamfer=H * 0.08)
        k.mount(sp.side_x(sx, R * 0.1), R * 0.1, H * 0.08, side(sx), s)
    rest = guns - 2
    for i in range(rest):
        y = (1.0 if i // 2 == 0 else -1.0) * R * (0.62 if v == 2 else 0.45)  # (clear of the tower on a tiered one)
        if i % 2 == 0:
            k.mount(0, y, H * 0.55 + H * 0.125, "top", s)
        else:
            k.mount(0, y, -H * 0.52 - H * 0.1, "bottom", s)
    engines(k, Part(R * 1.5, R * 2.0, H * 0.8), ne, er, y=-R * 0.95)
    k.lights(R * 1.2, -R * 0.3, H * 0.1, 0.06 + W * 0.004)
    k.beacon(0, -R * 0.1, H * 1.1, 0.06 + W * 0.003)
    k.belly(hb, -R * 0.6, R * 0.6, int(8 + W * 0.6), 0.12 + W * 0.03)


# each generated ship's signature features, so no two look alike (see features())
FEATURES = {
    "gnat": ["x_fins"], "wisp": ["sail"], "pike": ["prow_gun"], "bumble": ["tanks", "antennas"],
    "drifter": ["domes", "antennas"], "hornet": ["spikes", "ventral_fin"], "digger": ["radiators"], "porter": ["outriggers"],
    "falcon": ["forward_wings", "dorsal_fin"], "vanguard": ["armor_bands", "prow_gun"], "quarry": ["tanks", "domes"],
    "wayfarer": ["sail", "x_fins"], "brick": ["antennas", "tanks"], "raptor": ["ventral_fin"], "bulwark": ["ring_collar", "domes"],
    "trawler": ["radiators", "hangar_pods"], "phantom": ["split_prow"], "warden": ["antennas", "nacelles"],
    "tempest": ["nacelles", "x_fins"], "excavator": ["outriggers", "antennas"], "pathfinder": ["radiators", "domes"],
    "mantis": ["split_prow", "spikes"], "dominator": ["prow_gun", "radiators"], "atlas": ["ring_collar", "hangar_pods"],
    "valkyrie": ["forward_wings", "nacelles"], "obsidian": ["split_prow", "x_fins"], "juggernaut": ["armor_bands", "outriggers"],
    "harbinger": ["split_prow", "dorsal_fin"], "starminer": ["radiators", "domes", "tanks"], "paragon": ["dorsal_fin", "ring_collar"],
    "oracle": ["sail", "antennas"], "colossus": ["hangar_pods", "antennas"], "starforge": ["ring_collar", "tanks", "radiators"],
    "sovereign": ["prow_gun", "outriggers", "dorsal_fin"], "eclipse": ["sail", "domes", "radiators"],
    "aeon": ["ring_collar", "split_prow", "nacelles", "x_fins"],
}


def features(k, fx):
    """Bolt a ship's signature features onto its main hull (k.main): nacelles, outriggers, fins, a prow gun..."""
    m = k.main
    L, W, H = m.l, m.w, m.h
    BW = k.hi.x - k.lo.x
    rx = (math.radians(90), 0, 0)
    for f in fx:
        if f == "x_fins":
            for a in range(4):
                ang = a * math.pi / 2 + math.pi / 4
                k.plate("x_fin", [(-L * 0.28, H * 0.3), (-L * 0.5, H * 0.3), (-L * 0.55, H * 0.3 + L * 0.15), (-L * 0.43, H * 0.3 + L * 0.15)],
                        max(0.06, H * 0.06), 0.0, plane="yz", rot=(0, ang, 0), mat_=k.acc if a % 2 else k.hull)
        elif f == "nacelles":
            # on pylons straight off the hull's flanks, aft
            r = max(0.3, min(BW * 0.05, L * 0.06))
            hx = m.hw(-L * 0.28) + m.x
            for sx in (-1, 1):
                x = sx * (hx + r * 2.6)
                k.part("pylon", r * 2.2, L * 0.12, r * 0.6, x=sx * (hx + r * 1.0), y=-L * 0.28, mats=k.G)
                nac = k.part("nacelle", r * 2.2, L * 0.42, r * 2.2, x=x, y=-L * 0.28, mats=k.A, taper=(0.7, 0.7), chamfer=r * 0.3)
                box("nacelle_band", (r * 2.35, L * 0.04, r * 2.35), (x, -L * 0.2, 0), k.acc2, 0.0, parent=k.body)
                k.engine(x, nac.back() - 0.05, 0, r * 0.8)
        elif f == "radiators":
            for sx in (-1, 1):
                for sz in (-1, 1):
                    c = (sx * (W / 2 + H * 0.45), -L * 0.05, sz * H * 0.32)
                    box("radiator", (H * 0.9, L * 0.26, 0.05 + L * 0.002), c, k.acc2, 0.0, rot=(0, sx * sz * -0.5, 0), parent=k.body)
                    k.grow(c, (H * 0.45, L * 0.13, H * 0.25))
        elif f == "spikes":
            for i in range(6):
                y = -L * 0.35 + i * L * 0.12
                for sx in (-1, 1):
                    if k.near_mount((m.x + sx * m.hw(y) * 0.85, y, m.top(y)), H * 0.3):
                        continue
                    cyl("spike", H * 0.08 + 0.05, H * 0.6, (m.x + sx * m.hw(y) * 0.85, y, m.top(y) + H * 0.2), k.acc,
                        rot=(0, sx * 0.5, 0), parent=k.body, segs=6, r2=0.0)
        elif f == "prow_gun":
            # a slim rail-gun lance running out of the nose
            rr = H * 0.07 + 0.06
            zt = m.z + m.dip(m.front() - 0.01)
            sleek("prow_gun", (rr * 2.2, L * 0.42, rr * 2.2), (0, m.front() + L * 0.03, zt), [k.gunm], k.body, p=2.0,
                  nose=L * 0.1, tail=rr, droop=0.0)
            torus("muzzle_ring", rr * 0.95, rr * 0.22, (0, m.front() + L * 0.12, zt), k.acc2, rot=rx, parent=k.body, seg=24, ring=8)
            k.grow((0, m.front() + L * 0.12, zt), (rr * 1.2, L * 0.12, rr * 1.2))
        elif f == "dorsal_fin":
            for sx in (-1, 1):
                k.plate("dorsal_fin", [(-L * 0.12, H * 0.45), (-L * 0.44, H * 0.45), (-L * 0.5, H * 0.45 + L * 0.2), (-L * 0.32, H * 0.45 + L * 0.2)],
                        max(0.07, H * 0.06), 0.0, plane="yz", x=sx * m.hw(-L * 0.3) * 0.75, rot=(0, sx * 0.18, 0), mat_=k.acc)
        elif f == "ventral_fin":
            k.plate("ventral_fin", [(-L * 0.2, -H * 0.45), (-L * 0.46, -H * 0.45), (-L * 0.5, -H * 0.45 - L * 0.16), (-L * 0.36, -H * 0.45 - L * 0.16)],
                    max(0.07, H * 0.06), 0.0, plane="yz", mat_=k.acc)
        elif f == "outriggers":
            for sx in (-1, 1):
                x = sx * (BW / 2 + W * 0.22)
                for y in (L * 0.12, -L * 0.22):
                    k.part("strut", W * 0.3, L * 0.05, H * 0.16, x=sx * (BW / 2 + W * 0.07), y=y, mats=k.G)
                pod = k.part("outrigger", W * 0.17, L * 0.58, H * 0.45, x=x, y=-L * 0.05, mats=k.D, taper=(0.6, 0.7), chamfer=H * 0.06)
                k.portholes(pod, pod.y, 0.0, pod.l * 0.6, 1, 0.2 + L * 0.006)
                k.engine(x, pod.back() - 0.05, 0, W * 0.05 + 0.1)
        elif f == "antennas":
            for i in range(4):
                y = -L * 0.3 + i * L * 0.12
                x = (m.hw(y) * 0.55) * (1 if i % 2 else -1)
                h = H * 0.6 + L * 0.04 * (1 + i % 2)
                if k.near_mount((x, y, m.top(y)), 0.2):
                    continue
                cyl("antenna", 0.025 + L * 0.0008, h, (x, y, m.top(y) + h / 2), k.dark, parent=k.body, segs=6)
                ico("antenna_tip", 0.05 + L * 0.0015, (x, y, m.top(y) + h), k.amber, 1, parent=k.body)
                k.grow((x, y, m.top(y) + h / 2), (0.1, 0.1, h / 2))
        elif f == "domes":
            for sx in (-1, 1):
                y = L * 0.1 * sx
                c = (sx * m.hw(y) * 0.5, y, m.top(y))
                if k.near_mount(c, H * 0.3 + 0.1):
                    c = (sx * m.hw(y) * 0.5, y - L * 0.22 * sx, m.top(y - L * 0.22 * sx))
                    if k.near_mount(c, H * 0.3 + 0.1):
                        continue
                ico("sensor_dome", H * 0.28 + 0.1, c, k.glass, 2, parent=k.body, smooth=True)
                cyl("dome_base", H * 0.3 + 0.11, H * 0.08, c, k.dark, parent=k.body, segs=16)
        elif f == "forward_wings":
            t = max(0.1, H * 0.12)
            for sx in (-1, 1):
                k.plate("fwd_wing", [(sx * m.hw(0) * 0.9, -L * 0.25), (sx * BW * 0.48, -L * 0.02), (sx * BW * 0.48, -L * 0.1),
                                     (sx * m.hw(0) * 0.9, -L * 0.36)], t, H * 0.1, mat_=k.hull2)
                k.plate("fwd_wing_tip", [(sx * BW * 0.44, -L * 0.04), (sx * BW * 0.5, -L * 0.0), (sx * BW * 0.5, -L * 0.1), (sx * BW * 0.44, -L * 0.12)],
                        t * 1.3, H * 0.1, mat_=k.acc)
        elif f == "ring_collar":
            R = max(m.hw(L * 0.1), m.hh(L * 0.1)) * 1.35 + 0.2
            torus("collar", R, R * 0.08, (m.x, L * 0.1, m.z), k.gunm, rot=rx, parent=k.body, seg=40, ring=8)
            for a in range(6):
                ang = a * math.pi / 3
                box("collar_node", (R * 0.16, R * 0.2, R * 0.16), (m.x + math.cos(ang) * R, L * 0.1, m.z + math.sin(ang) * R), k.acc, 0.02,
                    parent=k.body)
            k.grow((m.x, L * 0.1, m.z), (R * 1.1, R * 0.1, R * 1.1))
        elif f == "armor_bands":
            for y in (L * 0.28, L * 0.02, -L * 0.24):
                box("armor_band", (m.hw(y) * 2.06, L * 0.035, m.hh(y) * 2.06), (m.x, y, m.z), k.acc, 0.0, parent=k.body)
        elif f == "split_prow":
            for sx in (-1, 1):
                k.part("prong", W * 0.12, L * 0.3, H * 0.4, x=sx * W * 0.2, y=m.front() + L * 0.08, z=-H * 0.05, taper=(0.3, 0.5), mats=k.A)
            box("prong_glow", (W * 0.2, 0.08, H * 0.12), (0, m.front() + L * 0.02, -H * 0.05), k.win, 0.0, parent=k.body)
        elif f == "sail":
            # aft, and out toward the edge of the hull, clear of the turrets on the spine
            x = -m.hw(-L * 0.33) * 0.8
            pts = [(-L * 0.18, H * 0.4), (-L * 0.48, H * 0.4), (-L * 0.43, H * 0.4 + L * 0.28), (-L * 0.22, H * 0.4 + L * 0.24)]
            k.plate("sail", pts, max(0.05, H * 0.03), 0.0, plane="yz", x=x, mat_=k.glass)
            k.plate("sail_frame", [(-L * 0.18, H * 0.4), (-L * 0.48, H * 0.4), (-L * 0.48, H * 0.4 + L * 0.02), (-L * 0.18, H * 0.4 + L * 0.02)],
                    max(0.08, H * 0.05), 0.0, plane="yz", x=x, mat_=k.dark)
            cyl("sail_mast", 0.04 + L * 0.001, L * 0.26, (x, -L * 0.33, H * 0.4 + L * 0.13), k.dark, parent=k.body, segs=6)
        elif f == "tanks":
            for sx in (-1, 1):
                for y in (L * 0.05, -L * 0.22):
                    c = (sx * (m.hw(y) + H * 0.22), y, -H * 0.18)
                    if k.near_mount(c, H * 0.25 + L * 0.11):
                        continue
                    along_y(H * 0.22 + 0.05, L * 0.22, c, k.hull2, parent=k.body, segs=14)
                    along_y(H * 0.24 + 0.05, L * 0.02, c, k.acc, parent=k.body, segs=14)
                    k.grow(c, (H * 0.25, L * 0.11, H * 0.25))
        elif f == "hangar_pods":
            for sx in (-1, 1):
                hp = k.part("hangar_pod", W * 0.18, L * 0.24, H * 0.6, x=sx * (BW / 2 + W * 0.08), y=L * 0.05, mats=k.D, chamfer=H * 0.06)
                box("hangar_door", (0.08, hp.l * 0.6, hp.h * 0.5), (hp.side_x(sx, hp.y) + sx * 0.03, hp.y, 0), k.dark, 0.0, parent=k.body)
                box("hangar_light", (0.06, hp.l * 0.55, 0.06), (hp.side_x(sx, hp.y) + sx * 0.06, hp.y, hp.h * 0.28), k.win, 0.0,
                    parent=k.body)

ARCHETYPES = {"dart": g_dart, "wedge": g_wedge, "block": g_block, "twin": g_twin, "spine": g_spine, "miner": g_miner,
              "cruiser": g_cruiser, "carrier": g_carrier, "saucer": g_saucer}


def fleet_ship(sid):
    arch, L, W, H, ne, er, guns, s, ch, ca, cg, ex = FLEET[sid]
    k = Kit(sid, ch, ca, cg)
    ARCHETYPES[arch](k, L, W, H, ne, er, guns, s, ex)
    features(k, FEATURES.get(sid, []))
    if len(k.mounts) != guns:
        raise RuntimeError("%s: %d mounts, wanted %d" % (sid, len(k.mounts), guns))
    meta = k.finish("ships")
    if "scale" in ex:
        meta["scale"] = ex["scale"]
    return meta


# ---------------------------------------------------------------- weapon turrets

# Every weapon has its own turret on the same Base / Yaw housing: only the Pitch part (what it shoots with)
# differs. kind: (barrel metal, accent, glow colours)
TURRET_KINDS = {
    "mining_lasers": ("4a5262", "2a8a6a", "66ffcc"),
    "scatter_guns": ("4e4a46", "8a5a2e", "ffb36b"),
    "pulse_cannons": ("4a4440", "a84a1a", "ff8a3d"),
    "ion_repeaters": ("404a5a", "2a4a9a", "7aa8ff"),
    "cryo_projectors": ("5a6670", "6aa8c8", "bff4ff"),
    "seeker_darts": ("4a4248", "a83a6a", "ff66aa"),
    "rail_drivers": ("5a6070", "8090a8", "e8f6ff"),
    "deep_core_drills": ("5a5040", "a88a2a", "ffd24a"),
    "nova_lances": ("443a52", "9a3aa8", "ff66ff"),
    "prism_cannons": ("4a4050", "c84a8a", "ff5fa2"),
    "flak_battery": ("4a4a44", "6a6a3a", "ffe08a"),
    "plasma_projectors": ("3a4a48", "2a8a7a", "5affd8"),
    "torpedo_bays": ("444850", "8a3a2a", "ff7a4a"),
    "graviton_lances": ("3a3450", "5a3aa8", "a080ff"),
}


def turret_kind(kind):
    """turret_<kind>.glb: the common base and housing, with this weapon's own business end."""
    c_metal, c_acc, c_glow = TURRET_KINDS[kind]
    rng = random.Random("turret_" + kind)
    metal = mat("t_%s_metal" % kind, c_metal, 0.75, 0.35)
    metal2 = mat("t_%s_metal2" % kind, shade(c_metal, 0.8), 0.75, 0.4)
    acc = mat("t_%s_accent" % kind, c_acc, 0.5, 0.4)
    seam = mat("turret_seam", "14181f", 0.6, 0.7)
    dark = mat("dark_metal", "1c2230", 0.6, 0.6)
    glow = mat("t_%s_glow" % kind, c_glow, 0.0, 0.3, emit=3.0)
    r = root("turret_" + kind)
    base = root("Base")
    base.parent = r
    cyl("ring", 0.55, 0.16, (0, 0, 0.08), dark, parent=base, segs=28)
    cyl("ring_top", 0.5, 0.06, (0, 0, 0.19), metal2, parent=base, segs=28)
    box("base_band", (1.12, 0.12, 0.05), (0, 0, 0.17), acc, 0.0, parent=base)
    merge(base, "Base_mesh").parent = base
    yaw = root("Yaw")
    yaw.parent = r
    yaw.location = (0, 0, 0.22)
    plated("housing", (0.78, 0.82, 0.36), (0, -0.06, 0.18), [metal, seam, metal2], yaw, cell=0.22, rng=rng, chamfer=0.07,
           depth=0.012, seam=0.01, taper=(0.85, 0.9))
    for sx in (-1, 1):
        box("cheek", (0.1, 0.62, 0.5), (sx * 0.44, 0.02, 0.32), acc, 0.02, parent=yaw, taper=(1.0, 0.7))
    box("back", (0.6, 0.18, 0.28), (0, -0.5, 0.16), dark, 0.02, parent=yaw)
    ico("lens", 0.035, (0.26, -0.2, 0.43), glow, 1, parent=yaw)
    merge(yaw, "Yaw_mesh").parent = yaw
    pitch = root("Pitch")
    pitch.parent = yaw
    pitch.location = (0, 0.06, 0.34)
    rx = (math.radians(90), 0, 0)
    tip = 1.45
    if kind == "mining_lasers":
        box("mantlet", (0.5, 0.32, 0.3), (0, 0.06, 0), metal2, 0.04, parent=pitch)
        along_y(0.12, 0.9, (0, 0.6, 0), metal, parent=pitch, segs=16, r2=0.09)
        for c in range(3):
            torus("focus_ring", 0.13 - c * 0.012, 0.025, (0, 0.5 + c * 0.2, 0), acc, rot=rx, parent=pitch, seg=16, ring=6)
        cyl("emitter", 0.13, 0.12, (0, 1.1, 0), dark, rot=(math.radians(-90), 0, 0), parent=pitch, segs=16, r2=0.16)
        ico("lens", 0.09, (0, 1.17, 0), glow, 2, parent=pitch)
        tip = 1.22
    elif kind == "scatter_guns":
        box("mantlet", (0.62, 0.34, 0.36), (0, 0.06, 0), metal2, 0.04, parent=pitch)
        for sx in (-1, 1):
            for sz in (-1, 1):
                along_y(0.07, 0.62, (sx * 0.12, 0.5, sz * 0.09), metal, parent=pitch, segs=10, r2=0.1)
        box("shroud", (0.5, 0.2, 0.36), (0, 0.32, 0), acc, 0.03, parent=pitch)
        tip = 0.86
    elif kind == "pulse_cannons":
        box("mantlet", (0.62, 0.36, 0.34), (0, 0.06, 0), metal2, 0.04, parent=pitch)
        along_y(0.15, 1.0, (0, 0.72, 0), metal, parent=pitch, segs=16)
        for c in range(4):
            along_y(0.19, 0.06, (0, 0.42 + c * 0.16, 0), dark, parent=pitch, segs=16)
        torus("muzzle_glow", 0.15, 0.03, (0, 1.22, 0), glow, rot=rx, parent=pitch, seg=16, ring=6)
        tip = 1.28
    elif kind == "ion_repeaters":
        box("mantlet", (0.5, 0.32, 0.3), (0, 0.06, 0), metal2, 0.04, parent=pitch)
        for i in range(6):
            a = i * math.pi / 3
            along_y(0.035, 1.1, (math.cos(a) * 0.1, 0.78, math.sin(a) * 0.1), metal, parent=pitch, segs=8)
        for y in (0.35, 0.8, 1.28):
            along_y(0.16, 0.06, (0, y, 0), acc, parent=pitch, segs=12)
        ico("core", 0.05, (0, 1.32, 0), glow, 1, parent=pitch)
        tip = 1.36
    elif kind == "cryo_projectors":
        box("mantlet", (0.6, 0.32, 0.3), (0, 0.06, 0), metal2, 0.04, parent=pitch)
        for sx in (-1, 1):
            along_y(0.06, 1.0, (sx * 0.12, 0.72, 0), metal, parent=pitch, segs=12, r2=0.075)
            along_y(0.09, 0.5, (sx * 0.3, 0.25, 0.04), acc, parent=pitch, segs=12)
            ico("frost", 0.05, (sx * 0.12, 1.24, 0), glow, 1, parent=pitch)
        tip = 1.26
    elif kind == "seeker_darts":
        box("launcher", (0.66, 0.6, 0.42), (0, 0.3, 0.02), metal, 0.04, parent=pitch)
        box("launcher_band", (0.68, 0.08, 0.44), (0, 0.45, 0.02), acc, 0.0, parent=pitch)
        for i in range(3):
            for j in range(2):
                along_y(0.06, 0.04, (-0.2 + i * 0.2, 0.61, -0.08 + j * 0.18), dark, parent=pitch, segs=10)
                ico("dart_tip", 0.03, (-0.2 + i * 0.2, 0.62, -0.08 + j * 0.18), glow, 1, parent=pitch)
        tip = 0.66
    elif kind == "rail_drivers":
        box("mantlet", (0.56, 0.34, 0.3), (0, 0.06, 0), metal2, 0.04, parent=pitch)
        for sx in (-1, 1):
            box("rail", (0.06, 1.6, 0.18), (sx * 0.1, 0.95, 0), metal, 0.01, parent=pitch)
        for c in range(5):
            torus("coil", 0.17, 0.03, (0, 0.4 + c * 0.26, 0), acc, rot=rx, parent=pitch, seg=16, ring=6)
        box("spark_gap", (0.1, 1.4, 0.04), (0, 0.95, 0), glow, 0.0, parent=pitch)
        tip = 1.78
    elif kind == "deep_core_drills":
        box("mantlet", (0.56, 0.3, 0.34), (0, 0.06, 0), metal2, 0.04, parent=pitch)
        along_y(0.2, 0.25, (0, 0.32, 0), dark, parent=pitch, segs=16)
        along_y(0.18, 0.62, (0, 0.75, 0), acc, parent=pitch, segs=16, r2=0.02)
        for c in range(4):
            torus("thread", 0.15 - c * 0.035, 0.022, (0, 0.55 + c * 0.13, 0), metal, rot=rx, parent=pitch, seg=16, ring=4)
        ico("bit", 0.035, (0, 1.06, 0), glow, 1, parent=pitch)
        tip = 1.1
    elif kind == "nova_lances":
        box("mantlet", (0.5, 0.32, 0.3), (0, 0.06, 0), metal2, 0.04, parent=pitch)
        along_y(0.06, 1.75, (0, 1.0, 0), metal, parent=pitch, segs=12, r2=0.04)
        for c in range(4):
            octa("crystal", 0.07, 0.11, (0, 0.5 + c * 0.32, 0), glow, rot=rx, parent=pitch)
            torus("lance_ring", 0.12, 0.02, (0, 0.5 + c * 0.32, 0), acc, rot=rx, parent=pitch, seg=12, ring=4)
        tip = 1.9
    elif kind == "prism_cannons":
        box("mantlet", (0.6, 0.32, 0.34), (0, 0.06, 0), metal2, 0.04, parent=pitch)
        for i in range(3):
            a = i * 2 * math.pi / 3 + math.pi / 2
            along_y(0.05, 1.0, (math.cos(a) * 0.1, 0.72, math.sin(a) * 0.1), metal, parent=pitch, segs=10)
        along_y(0.16, 0.08, (0, 0.5, 0), acc, parent=pitch, segs=12)
        octa("prism", 0.11, 0.14, (0, 1.28, 0), glow, rot=rx, parent=pitch)
        tip = 1.42
    elif kind == "flak_battery":
        box("drum", (0.62, 0.42, 0.42), (0, 0.12, 0), metal2, 0.05, parent=pitch)
        box("drum_band", (0.64, 0.08, 0.44), (0, 0.2, 0), acc, 0.0, parent=pitch)
        for sx in (-1, 1):
            for sz in (-1, 1):
                along_y(0.055, 0.85, (sx * 0.16, 0.7, sz * 0.12), metal, parent=pitch, segs=10)
                along_y(0.07, 0.1, (sx * 0.16, 1.1, sz * 0.12), dark, parent=pitch, segs=10)
        tip = 1.16
    elif kind == "plasma_projectors":
        box("mantlet", (0.56, 0.32, 0.32), (0, 0.06, 0), metal2, 0.04, parent=pitch)
        along_y(0.09, 1.05, (0, 0.72, 0), metal, parent=pitch, segs=14)
        for c in range(3):
            ico("chamber", 0.13, (0, 0.45 + c * 0.25, 0), glow if c == 1 else acc, 2, parent=pitch)
        along_y(0.13, 0.12, (0, 1.22, 0), dark, parent=pitch, segs=14, r2=0.16)
        tip = 1.3
    elif kind == "torpedo_bays":
        box("mantlet", (0.6, 0.34, 0.36), (0, 0.06, 0), metal2, 0.04, parent=pitch)
        along_y(0.2, 0.95, (0, 0.65, 0), metal, parent=pitch, segs=16)
        along_y(0.23, 0.1, (0, 1.1, 0), acc, parent=pitch, segs=16)
        for a in range(4):
            ang = a * math.pi / 2 + math.pi / 4
            box("tube_fin", (0.04, 0.4, 0.14), (math.cos(ang) * 0.24, 0.4, math.sin(ang) * 0.24), dark, 0.0, rot=(0, -ang, 0),
                parent=pitch)
        ico("warhead", 0.12, (0, 1.12, 0), glow, 1, parent=pitch)
        tip = 1.2
    else:  # graviton_lances
        box("mantlet", (0.56, 0.32, 0.32), (0, 0.06, 0), metal2, 0.04, parent=pitch)
        along_y(0.07, 1.3, (0, 0.85, 0), metal, parent=pitch, segs=12)
        for y, rr in ((0.75, 0.24), (1.3, 0.19)):
            torus("grav_ring", rr, 0.035, (0, y, 0), acc, rot=rx, parent=pitch, seg=24, ring=6)
            torus("grav_glow", rr * 0.8, 0.02, (0, y, 0), glow, rot=rx, parent=pitch, seg=24, ring=6)
        ico("singularity", 0.07, (0, 1.5, 0), glow, 2, parent=pitch)
        tip = 1.56
    merge(pitch, "Pitch_mesh").parent = pitch
    empty("Muzzle", (0, tip, 0), pitch)
    export(r, os.path.join(OUT, "props", "turret_%s.glb" % kind))


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

        for x in (-2.2, 0.0, 2.2):
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
    every = list(SHIPS) + list(FLEET) + list(ENEMIES) + ["sentinel", "turret"] + ["turret_" + k for k in TURRET_KINDS]
    for sid in (argv or every):
        reset()
        if sid == "turret":
            turret()
            continue
        if sid.startswith("turret_"):
            turret_kind(sid[7:])
            continue
        meta[sid] = player_ship(sid) if sid in SHIPS else (fleet_ship(sid) if sid in FLEET else pirate(sid))
    os.makedirs(OUT, exist_ok=True)
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=1)
    print("DONE", len(meta))
