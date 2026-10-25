"""Builds Driftlight's stations, stargates, asteroids and other props as GLBs (some animated).

Run:  blender --background --python props.py [-- prop ...]
Props: station, gate, rocks, crystal, crate, wreck, obelisk, spice_stand
"""
import math
import os
import random
import sys

from mathutils import Matrix, Vector, noise

sys.path.append(os.path.dirname(__file__))
from common import *  # noqa: E402,F401,F403

PROPS = os.path.join(OUT, "props")


def prism(name, n, rad, h, z, mats, parent, rng, cell=1.6, rot0=0.0):
    """An n-sided upright prism clad in armour plates (one plated panel per side, around a dark core)."""
    side = 2 * rad * math.tan(math.pi / n)
    cyl(name + "_core", rad * 0.97, h * 0.999, (0, 0, z), mats[1], parent=parent, segs=n, rot=(0, 0, math.pi / n + rot0))
    for i in range(n):
        a = rot0 + i * 2 * math.pi / n
        plated(name, (side * 1.0, 0.8, h), (math.cos(a) * (rad - 0.4), math.sin(a) * (rad - 0.4), z), mats, parent,
               rot=(0, 0, a - math.pi / 2), cell=cell, rng=rng, faces=["+Y"], depth=0.08, seam=0.07)


def ring_frame(a, rad, z=0.0):
    """Surface frame on the outside of a vertical ring wall at angle a: x along the ring, y up, z outward."""
    out = Vector((math.cos(a), math.sin(a), 0))
    tang = Vector((-math.sin(a), math.cos(a), 0))
    return frame(out * rad + Vector((0, 0, z)), tang, Vector((0, 0, 1)), out)


def shuttle(parent, loc, hull, glow, lamp):
    """A small traffic shuttle (nose +Y)."""
    x, y, z = loc
    box("sh", (1.6, 3.2, 0.9), (x, y, z), hull, 0.1, parent=parent, taper=(0.6, 0.7))
    box("sh", (2.6, 1.2, 0.2), (x, y - 0.6, z), hull, 0.05, parent=parent)
    box("sh", (0.9, 0.3, 0.4), (x, y + 1.0, z + 0.4), lamp, 0.0, parent=parent)
    along_y(0.35, 0.2, (x, y - 1.7, z), glow, parent=parent, segs=8)


def station():
    """A citadel about 650 m across: an octagonal plated tower ringed with modules, a hangar with chasing
    guide lights, a big turning habitat ring and a smaller counter-turning ring below, solar arrays on long
    trusses, nodding dishes, blinking beacons and shuttles flying loops round it. Lit windows come from the
    game's hull shader on the "_win" materials (far too many to model)."""
    S = 5.0  # built five times the size of ship-scale props
    rng = random.Random("station")
    hull = mat("st_hull_win", "8a93a6", 0.55, 0.45)
    hull2 = mat("st_hull2_win", "6c7486", 0.55, 0.5)
    seam = mat("st_seam", "1e222c", 0.6, 0.7)
    dark = mat("st_dark", "2a2f3b", 0.6, 0.55)
    trim = mat("st_trim", "c9d1e0", 0.4, 0.4)
    hazard = mat("st_hazard", "d9a03c", 0.4, 0.45)
    lamp = mat("st_light", "ffd27a", 0.0, 0.3, emit=7.0)
    cyan = mat("st_cyan", "7ff0ff", 0.0, 0.2, emit=5.0)
    win = mat("st_window", "ffe2a8", 0.0, 0.3, emit=4.0)
    solar = mat("st_solar", "1d3a6e", 0.3, 0.2, emit=0.25)
    solar2 = mat("st_solar2", "2b4f8a", 0.3, 0.25, emit=0.35)
    sframe = mat("st_solar_frame", "9aa3b5", 0.6, 0.4)
    red = mat("nav_red", "ff3030", 0.0, 0.3, emit=8.0)
    green = mat("nav_green", "30ff70", 0.0, 0.3, emit=8.0)
    white = mat("strobe", "ffffff", 0.0, 0.3, emit=16.0)
    glow = mat("engine_glow", "ff9a3d", 0.0, 0.3, emit=3.0)
    P = [hull, seam, hull2]
    D = [dark, seam, hull2]
    r = root("station")
    core = root("core")
    core.parent = r
    g = Greebler(core, rng, hull2, dark, trim, lamp)
    UPV = Vector((0, 0, 1))

    # the central tower: an octagonal hub with narrower towers above and below
    prism("hub", 8, 8.0 * S, 18.0 * S, 0.0, P, core, rng, cell=7.0)
    prism("upper", 8, 5.2 * S, 10.0 * S, 14.0 * S, P, core, rng, cell=6.0, rot0=math.pi / 8)
    prism("lower", 8, 5.6 * S, 12.0 * S, -15.0 * S, D, core, rng, cell=6.0, rot0=math.pi / 8)
    for z, apo, h, m in ((9.2, 8.5, 0.9, dark), (-9.2, 8.5, 0.9, dark), (4.0, 8.2, 0.5, hazard), (-4.0, 8.2, 0.5, hazard),
                         (0.0, 8.15, 0.25, trim), (14.0, 5.5, 0.4, hazard), (-15.0, 5.9, 0.4, hazard)):
        cyl("band", apo * S / math.cos(math.pi / 8), h * S, (0, 0, z * S), m, parent=core, segs=8,
            rot=(0, 0, math.pi / 8 if abs(z) < 9.5 else 0))
    cyl("cap", 5.2 * S, 3.0 * S, (0, 0, 20.5 * S), trim, parent=core, segs=8, r2=2.6 * S)
    cyl("cap2", 2.6 * S, 1.2 * S, (0, 0, 22.6 * S), dark, parent=core, segs=8)
    cyl("base_cone", 1.6 * S, 4.5 * S, (0, 0, -23.2 * S), hull2, parent=core, segs=8, r2=5.6 * S)
    cyl("spire", 0.5 * S, 7.0 * S, (0, 0, -28.5 * S), dark, parent=core, segs=6, r2=0.15 * S)
    cyl("mast", 0.45 * S, 12.0 * S, (0, 0, 29.0 * S), dark, parent=core, segs=8, r2=0.2 * S)
    for k in range(5):
        box("mast_bar", ((3.0 - k * 0.5) * S, 0.15 * S, 0.15 * S), (0, 0, (24.5 + k * 1.9) * S), trim, 0.0,
            rot=(0, 0, k * 0.6), parent=core)
    # pipes, vents and hatches up every face of the hub and towers
    for i in range(8):
        a = i * math.pi / 4
        for apo, z, h, n in ((8.0, 0.0, 16.0, 26), (5.2, 14.0, 9.0, 12), (5.6, -15.0, 11.0, 14)):
            aa = a + (0 if apo == 8.0 else math.pi / 8)
            F = ring_frame(aa, apo * S + 0.3, z * S)
            g.patch(frame(F.translation, F.col[1].xyz, F.col[0].xyz * -1, F.col[2].xyz), h * S * 0.9,
                    apo * S * 0.7, n, 3.5, kinds=["pipes", "vent", "hatch", "block", "radiator", "tank"])
    # radiator fins on the corners of the lower tower
    for i in range(8):
        a = i * math.pi / 4
        out = Vector((math.cos(a), math.sin(a), 0))
        corner = 5.6 * S / math.cos(math.pi / 8)
        box("rad_fin", (0.15 * S, 2.0 * S, 10.0 * S), tuple(out * (corner + 0.6 * S) + Vector((0, 0, -15.0 * S))), trim, 0.0,
            rot=(0, 0, a - math.pi / 2), parent=core)
        for k in (-1, 1):
            box("rad_fin", (0.12 * S, 1.4 * S, 6.0 * S), tuple(out * (corner + 0.4 * S) + Vector((0, 0, -15.0 * S)) +
                Vector((-math.sin(a), math.cos(a), 0)) * k * 0.5 * S), hull2, 0.0, rot=(0, 0, a - math.pi / 2), parent=core)

    # modules bolted round the hub in two tiers (clear of the hangar, which faces +Y)
    mods = []
    for i in range(12):
        a = math.pi / 2 + 0.95 + i * (2 * math.pi - 1.9) / 11 + rng.uniform(-0.05, 0.05)
        tier = i % 2
        w, l, h = rng.uniform(4.0, 7.5) * S, rng.uniform(4.5, 8.5) * S, rng.uniform(3.5, 5.5) * S
        z = (rng.uniform(-6.0, -2.0) if tier else rng.uniform(1.0, 6.0)) * S
        z = max(-7.0 * S + h / 2, min(7.2 * S - h / 2, z))
        mods.append((a, w, l, h, z))
    for a, w, l, h, z in mods:
        out = Vector((math.cos(a), math.sin(a), 0))
        tang = Vector((-math.sin(a), math.cos(a), 0))
        c = out * (8.0 * S + l / 2 - 0.5 * S) + Vector((0, 0, z))
        plated("module", (w, l, h), tuple(c), P, core, rot=(0, 0, a - math.pi / 2), cell=5.0, rng=rng, chamfer=0.4 * S)
        g.patch(frame(c + UPV * (h / 2), out, tang, UPV), l * 0.85, w * 0.85, int(w * l / 40), 3.0)
        g.patch(frame(c - UPV * (h / 2), out, -tang, -UPV), l * 0.8, w * 0.8, int(w * l / 80), 3.0,
                kinds=["tank", "pipes", "dome", "block"])
        box("mod_cap", (w * 0.9, 0.6 * S, h * 0.9), tuple(c + out * (l / 2)), dark, 0.0, rot=(0, 0, a - math.pi / 2), parent=core)
        box("mod_stripe", (w * 1.02, 0.4 * S, 0.5 * S), tuple(c + out * (l * 0.3)), hazard, 0.0, rot=(0, 0, a - math.pi / 2),
            parent=core)
        light("mod_light", tuple(c + out * (l / 2 + 0.2 * S) + UPV * (h / 2)), 0.35 * S * 0.5, red if a % 2 < 1 else green, r,
              period=120, on=10, phase=int(a * 20) % 120)

    # the hangar: a long module facing +Y with a glowing mouth and chasing guide lights
    bay = Vector((0, 15.5 * S, 0))
    bw, bl, bh = 13.0 * S, 15.0 * S, 8.0 * S
    plated("bay", (bw, bl, bh), tuple(bay), P, core, cell=6.0, rng=rng, chamfer=0.5 * S)
    mouth_y = bay.y + bl / 2
    box("bay_mouth", (9.0 * S, 0.3 * S, 4.6 * S), (0, mouth_y + 0.05 * S, 0), mat("st_bay", "05070c", 0.2, 0.9), 0.0, parent=core)
    box("bay_back", (8.6 * S, 0.2 * S, 4.2 * S), (0, mouth_y + 0.1 * S, 0), mat("st_bay_glow", "1a3a55", 0.0, 0.5, emit=1.5), 0.0,
        parent=core)
    for z in (-2.5, 2.5):
        box("bay_frame", (10.4 * S, 0.5 * S, 0.5 * S), (0, mouth_y + 0.15 * S, z * S), hazard, 0.0, parent=core)
    for x in (-4.95, 4.95):
        box("bay_frame", (0.5 * S, 0.5 * S, 5.5 * S), (x * S, mouth_y + 0.15 * S, 0), hazard, 0.0, parent=core)
    for k in range(10):
        box("bay_glow", (8.0 * S, 0.1 * S, 0.06 * S), (0, mouth_y + 0.25 * S, (-2.0 + k * 0.44) * S), cyan, 0.0, parent=core)
    for k in range(17):
        box("hazard", (0.5 * S, 0.55 * S, 0.7 * S), ((-4.0 + k * 0.5) * S, mouth_y + 0.2 * S, -2.9 * S), hazard if k % 2 else dark,
            0.0, parent=core)
    g.patch(frame(bay + UPV * (bh / 2), Vector((1, 0, 0)), Vector((0, 1, 0)), UPV), bw * 0.9, bl * 0.9, 70, 3.5)
    for sx in (-1, 1):
        g.patch(frame(bay + Vector((sx * bw / 2, 0, 0)), Vector((0, 0, -sx)), Vector((0, 1, 0)), Vector((sx, 0, 0))),
                bh * 0.8, bl * 0.85, 30, 3.0, kinds=["pipes", "vent", "hatch", "block"])
    for k in range(10):
        y = mouth_y + 2.5 * S + k * 3.2 * S
        for sx in (-1, 1):
            cyl("guide_post", 0.12 * S, 1.2 * S, (sx * 5.5 * S, y, -3.2 * S), dark, parent=core, segs=6)
            light("guide", (sx * 5.5 * S, y, -2.5 * S), 0.22 * S, cyan, r, period=60, on=6, phase=(9 - k) * 6)

    # solar arrays on long trusses
    for sx in (-1, 1):
        box("truss", (52.0 * S, 0.9 * S, 0.9 * S), (sx * 34.0 * S, 0, -6.0 * S), dark, 0.05 * S, parent=core)
        box("truss2", (52.0 * S, 0.4 * S, 0.4 * S), (sx * 34.0 * S, 0, -4.8 * S), trim, 0.0, parent=core)
        for k in range(14):
            x = sx * (10.0 + k * 3.8) * S
            box("truss_x", (0.25 * S, 0.25 * S, 1.8 * S), (x, 0, -5.4 * S), trim, 0.0, rot=(math.radians(35), 0, 0), parent=core)
        for k in range(4):
            for sy in (-1, 1):
                x = sx * (36.0 + k * 7.4) * S
                plated("solar", (7.0 * S, 13.0 * S, 0.3 * S), (x, sy * 7.4 * S, -6.0 * S), [solar, sframe, solar2], core, cell=4.0,
                       rng=rng, faces=["+Z", "-Z"], depth=0.0, seam=0.5)
                box("solar_spar", (0.3 * S, 14.6 * S, 0.5 * S), (x, sy * 7.4 * S, -6.0 * S), sframe, 0.0, parent=core)
        light("tip", (sx * 62.0 * S, 0, -6.0 * S), 0.5 * S, red if sx < 0 else green, r, period=60, on=8, phase=0 if sx < 0 else 30)

    # antennas, a comms array and strobes on the tower
    g.patch(frame((0, 0, 23.2 * S), Vector((1, 0, 0)), Vector((0, 1, 0)), UPV), 4.0 * S, 4.0 * S, 14, 3.5,
            kinds=["antenna", "block", "dome", "radiator"])
    light("beacon", (0, 0, 35.2 * S), 0.8 * S, red, r, period=60, on=8)
    light("beacon_lo", (0, 0, -32.2 * S), 0.6 * S, red, r, period=60, on=8, phase=30)
    for i in range(8):
        a = i * math.pi / 4 + math.pi / 8
        light("strobe", (math.cos(a) * 8.7 * S, math.sin(a) * 8.7 * S, 9.8 * S), 0.3 * S, white, r, period=80, on=3, phase=i * 4)
        light("strobe", (math.cos(a) * 8.7 * S, math.sin(a) * 8.7 * S, -9.8 * S), 0.3 * S, white, r, period=80, on=3,
              phase=40 + i * 4)
    # an upper tier of modules round the upper tower, above the habitat ring's spokes
    for i in range(7):
        a = i * 2 * math.pi / 7 + 0.3
        w, l, h = rng.uniform(3.0, 5.0) * S, rng.uniform(4.0, 6.5) * S, rng.uniform(3.0, 4.5) * S
        z = rng.uniform(11.5, 16.5) * S
        out = Vector((math.cos(a), math.sin(a), 0))
        tang = Vector((-math.sin(a), math.cos(a), 0))
        c = out * (5.2 * S + l / 2 - 0.4 * S) + UPV * z
        plated("upper_module", (w, l, h), tuple(c), P, core, rot=(0, 0, a - math.pi / 2), cell=5.0, rng=rng, chamfer=0.3 * S)
        g.patch(frame(c + UPV * (h / 2), out, tang, UPV), l * 0.85, w * 0.85, int(w * l / 45), 2.6)
        light("upper_light", tuple(c + out * (l / 2 + 0.15 * S) + UPV * (h / 2)), 0.3 * S, white if i % 2 else red, r,
              period=60, on=4, phase=i * 8)
    # a lower tier low on the hub, below the small ring
    for i in range(6):
        a = i * math.pi / 3 + 0.5
        w, l, h = rng.uniform(3.5, 5.5) * S, rng.uniform(4.0, 7.0) * S, rng.uniform(3.0, 4.0) * S
        z = -16.0 * S
        out = Vector((math.cos(a), math.sin(a), 0))
        tang = Vector((-math.sin(a), math.cos(a), 0))
        c = out * (5.6 * S + l / 2 - 0.4 * S) + UPV * z
        plated("lower_module", (w, l, h), tuple(c), D, core, rot=(0, 0, a - math.pi / 2), cell=5.0, rng=rng, chamfer=0.3 * S)
        g.patch(frame(c - UPV * (h / 2), out, -tang, -UPV), l * 0.8, w * 0.8, int(w * l / 60), 2.6,
                kinds=["tank", "pipes", "dome", "radiator"])
    # four long docking arms from the base of the tower, each ending in a docking module with ships berthed
    hull_ship = mat("st_berthed", "5a6070", 0.5, 0.5)
    for i in range(4):
        a = i * math.pi / 2 + math.pi / 4
        out = Vector((math.cos(a), math.sin(a), 0))
        tang = Vector((-math.sin(a), math.cos(a), 0))
        z = -22.4 * S
        arm_len = 34.0 * S
        mid = out * (5.0 * S + arm_len / 2) + UPV * z
        plated("arm", (2.2 * S, arm_len, 1.8 * S), tuple(mid), P, core, rot=(0, 0, a - math.pi / 2), cell=4.0, rng=rng,
               faces=["+Z", "-Z", "+X", "-X"])
        for side in (-1, 1):
            cyl("arm_pipe", 0.25 * S, arm_len, tuple(mid + tang * side * 1.4 * S + UPV * 0.5 * S), dark,
                rot=(math.radians(90), 0, a - math.pi / 2), parent=core, segs=8)
        for k in range(10):
            p = out * (7.0 * S + k * 3.2 * S) + UPV * z
            box("arm_rib", (2.8 * S, 0.3 * S, 2.4 * S), tuple(p), trim, 0.0, rot=(0, 0, a - math.pi / 2), parent=core)
            light("arm_light", tuple(p + UPV * 1.4 * S), 0.18 * S, cyan if k % 2 else lamp, r, period=60, on=6,
                  phase=(k * 6) % 60)
        dock = out * (5.0 * S + arm_len + 3.5 * S) + UPV * z
        plated("dock_module", (9.0 * S, 7.0 * S, 6.0 * S), tuple(dock), P, core, rot=(0, 0, a - math.pi / 2), cell=5.0, rng=rng,
               chamfer=0.5 * S)
        g.patch(frame(dock + UPV * 3.0 * S, out, tang, UPV), 6.5 * S, 8.5 * S, 30, 2.6)
        light("dock_beacon", tuple(dock + UPV * 3.4 * S + out * 3.2 * S), 0.45 * S, red, r, period=60, on=8, phase=i * 15)
        for side in (-1, 1):  # a ship tied up at each side of the docking module
            sp = dock + tang * side * 6.4 * S - UPV * 0.5 * S
            box("berthed", (2.4 * S, 6.0 * S, 1.6 * S), tuple(sp), hull_ship, 0.1 * S, rot=(0, 0, a - math.pi / 2), parent=core,
                taper=(0.6, 0.8))
            box("berthed_wing", (4.2 * S, 2.0 * S, 0.3 * S), tuple(sp - out * 1.0 * S), hull_ship, 0.05 * S,
                rot=(0, 0, a - math.pi / 2), parent=core)
            box("gangway", (2.0 * S, 1.2 * S, 0.8 * S), tuple(dock + tang * side * 5.0 * S), dark, 0.0,
                rot=(0, 0, a - math.pi / 2), parent=core)
    # a cluster of fuel tanks round the spire under the station
    for i in range(6):
        a = i * math.pi / 3
        p = Vector((math.cos(a), math.sin(a), 0)) * 4.2 * S + UPV * -27.0 * S
        ico("tank", 2.2 * S, tuple(p), hull2, 3, parent=core, smooth=True)
        cyl("tank_band", 2.25 * S, 0.4 * S, tuple(p), hazard, parent=core, segs=24)
        cyl("tank_strut", 0.2 * S, 3.5 * S, tuple(p * 0.5 + UPV * -13.5 * S), dark, rot=(0, math.radians(90), a), parent=core,
            segs=6)
    # an antenna crown round the top of the upper tower
    for i in range(12):
        a = i * math.pi / 6
        p = Vector((math.cos(a), math.sin(a), 0)) * 4.4 * S + UPV * 22.0 * S
        h = (3.0 if i % 3 == 0 else 1.6) * S
        cyl("crown_mast", 0.08 * S, h, tuple(p + UPV * h / 2), dark, parent=core, segs=6)
        if i % 3 == 0:
            light("crown_light", tuple(p + UPV * h), 0.2 * S, red, r, period=60, on=6, phase=i * 3)
    merge(core, "core_mesh")

    # turning dishes on the upper tower
    for i, (a, z, period) in enumerate(((0.6, 16.0, 400), (3.8, 12.0, 240), (2.2, 17.5, 300))):
        d = root("dish%d" % i)
        d.parent = r
        d.location = (math.cos(a) * 5.4 * S, math.sin(a) * 5.4 * S, z * S)
        d.rotation_euler = (0, 0, a)
        cyl("dish_arm", 0.25 * S, 2.4 * S, (1.2 * S, 0, 0), dark, rot=(0, math.radians(90), 0), parent=d, segs=8)
        dish = cyl("dish", 0.3 * S, 0.9 * S, (2.6 * S, 0, 0.8 * S), trim, parent=d, segs=24, r2=2.6 * S)
        dish.rotation_euler = (0, math.radians(-50), 0)
        cyl("feed", 0.08 * S, 2.2 * S, (3.3 * S, 0, 1.6 * S), dark, parent=d, segs=6).rotation_euler = (0, math.radians(-50), 0)
        dm = merge(d, "dish%d_mesh" % i)
        dm.parent = d
        sway(d, "Z", 0.7, period, phase=i)

    # the habitat ring turns slowly above the modules; its running lights chase round it
    ring = root("ring")
    ring.parent = r
    ring.location = (0, 0, 9.0 * S)
    R = 26.0 * S
    torus("collar", 9.6 * S, 0.9 * S, (0, 0, 0), trim, parent=ring, seg=48, ring=8)
    torus("ring", R, 2.8 * S, (0, 0, 0), hull, parent=ring, seg=128, ring=20)
    for z in (1.9, -1.9):
        torus("ring_rail", R + 2.75 * S, 0.35 * S, (0, 0, z * S), trim, parent=ring, seg=128, ring=6)
    torus("ring_inner", R - 2.6 * S, 0.5 * S, (0, 0, 0), dark, parent=ring, seg=128, ring=6)
    # plated armour segments clad the outside of the ring, with gaps between them
    nseg = 40
    for i in range(nseg):
        a = (i + 0.5) * 2 * math.pi / nseg
        out = Vector((math.cos(a), math.sin(a), 0))
        seg_len = 2 * math.pi * (R + 2.6 * S) / nseg * 0.86
        plated("ring_seg", (seg_len, 1.2 * S, 3.8 * S), tuple(out * (R + 2.4 * S)), P, ring, rot=(0, 0, a - math.pi / 2), cell=4.0,
               rng=rng, faces=["+Y", "+Z", "-Z"], chamfer=0.25 * S)
        if i % 5 == 2:
            box("ring_vent", (seg_len * 0.5, 0.6 * S, 0.8 * S), tuple(out * (R + 3.0 * S) + UPV * 2.2 * S), dark, 0.0,
                rot=(0, 0, a - math.pi / 2), parent=ring)
    for i in range(16):
        a = (i + 0.25) * math.pi / 8
        out = Vector((math.cos(a), math.sin(a), 0))
        box("ring_rib", (0.8 * S, 1.0 * S, 6.2 * S), tuple(out * (R - 0.4 * S)), trim, 0.0, rot=(0, 0, a - math.pi / 2), parent=ring)
    for i in range(16):
        a = (i + 0.5) * math.pi / 8 + 0.2
        out = Vector((math.cos(a), math.sin(a), 0))
        tang = Vector((-math.sin(a), math.cos(a), 0))
        plated("ring_pod", (5.0 * S, 3.0 * S, 3.0 * S), tuple(out * R + UPV * 3.6 * S), P, ring, rot=(0, 0, a - math.pi / 2),
               cell=4.0, rng=rng, chamfer=0.3 * S)
        g.parent = ring
        g.patch(frame(out * R + UPV * 5.1 * S, tang, -out, UPV), 4.6 * S, 2.6 * S, 5, 2.2)
        g.parent = core
    for i in range(8):
        a = i * math.pi / 4
        out = Vector((math.cos(a), math.sin(a), 0))
        tang = Vector((-math.sin(a), math.cos(a), 0))
        span = R - 12.0 * S
        mid = out * (10.0 * S + span / 2)
        plated("spoke", (2.0 * S, span, 1.6 * S), tuple(mid), P, ring, rot=(0, 0, a - math.pi / 2), cell=5.0, rng=rng,
               faces=["+Z", "-Z", "+X", "-X"])
        cyl("spoke_tube", 0.4 * S, span, tuple(mid + UPV * 1.1 * S), dark, rot=(math.radians(90), 0, a - math.pi / 2),
            parent=ring, segs=8)
        hab = out * R
        plated("habitat", (7.0 * S, 5.0 * S, 6.4 * S), tuple(hab), P, ring, rot=(0, 0, a - math.pi / 2), cell=5.0, rng=rng,
               chamfer=0.4 * S)
        g.parent = ring  # these greebles turn with the ring
        g.patch(frame(hab + UPV * 3.2 * S, tang, -out, UPV), 6.5 * S, 4.5 * S, 12, 2.5)
        g.parent = core
    ring_mesh = merge(ring, "ring_mesh")
    ring_mesh.parent = ring
    for i in range(32):
        a = i * 2 * math.pi / 32 + 0.1
        light("ring_light", (math.cos(a) * (R + 3.0 * S), math.sin(a) * (R + 3.0 * S), 0), 0.35 * S, lamp if i % 2 else cyan, ring,
              period=80, on=10, phase=(i * 5) % 80)
    spin(ring, "Z", 1200)

    # a smaller ring below, turning the other way
    ring2 = root("ring2")
    ring2.parent = r
    ring2.location = (0, 0, -12.0 * S)
    R2 = 19.0 * S
    torus("ring2", R2, 1.4 * S, (0, 0, 0), hull, parent=ring2, seg=96, ring=14)
    torus("ring2_rail", R2 + 1.4 * S, 0.25 * S, (0, 0, 0), hazard, parent=ring2, seg=96, ring=6)
    for i in range(4):
        a = i * math.pi / 2 + math.pi / 4
        out = Vector((math.cos(a), math.sin(a), 0))
        span = R2 - 6.0 * S
        plated("spoke2", (1.4 * S, span, 1.2 * S), tuple(out * (6.0 * S + span / 2)), P, ring2, rot=(0, 0, a - math.pi / 2),
               cell=4.0, rng=rng, faces=["+Z", "-Z", "+X", "-X"])
        plated("pod2", (4.0 * S, 3.0 * S, 3.4 * S), tuple(out * R2), P, ring2, rot=(0, 0, a - math.pi / 2), cell=4.0, rng=rng,
               chamfer=0.3 * S)
    torus("ring2_collar", 6.2 * S, 0.7 * S, (0, 0, 0), trim, parent=ring2, seg=48, ring=8)
    r2m = merge(ring2, "ring2_mesh")
    r2m.parent = ring2
    spin(ring2, "Z", 600, turns=-1)

    # traffic: shuttles on tilted loops round the station
    for i, (rad, tilt, period, z) in enumerate(((230.0, 0.25, 600, 20.0), (270.0, -0.35, 400, -40.0), (200.0, 0.5, 300, 70.0),
                                                 (310.0, -0.15, 1200, 5.0), (250.0, 0.7, 600, -10.0))):
        orbit = root("traffic%d" % i)
        orbit.parent = r
        orbit.location = (0, 0, z)
        orbit.rotation_euler = (tilt, tilt * 0.5, i * 2.0)
        spinner = root("traffic_spin%d" % i)
        spinner.parent = orbit
        sh = root("shuttle%d" % i)
        sh.parent = spinner
        sh.location = (rad, 0, 0)
        if i % 2:
            sh.rotation_euler = (0, 0, math.pi)  # flying the other way round: turn the nose to match
        shuttle(sh, (0, 0, 0), hull2, glow, win)
        sm = merge(sh, "shuttle%d_mesh" % i)
        sm.parent = sh
        spin(spinner, "Z", period, turns=1 if i % 2 == 0 else -1)
    export(r, os.path.join(PROPS, "station.glb"))

def gate():
    """A stargate: a plated ring with four pylons and two forward prongs, a turning collar and lights that chase
    round the aperture."""
    rng = random.Random("gate")
    metal = mat("gate_metal", "6b6f80", 0.7, 0.4)
    metal2 = mat("gate_metal2", "54586a", 0.7, 0.45)
    seam = mat("gate_seam", "16181f", 0.6, 0.7)
    dark = mat("gate_dark", "2a2c36", 0.7, 0.5)
    trim = mat("gate_trim", "a9b0c4", 0.5, 0.4)
    glow = mat("gate_glow", "7ff0ff", 0.0, 0.2, emit=6.0)
    hot = mat("gate_hot", "e0ffff", 0.0, 0.2, emit=12.0)
    lamp = mat("st_light", "ffd27a", 0.0, 0.3, emit=7.0)
    red = mat("nav_red", "ff3030", 0.0, 0.3, emit=8.0)
    P = [metal, seam, metal2]
    r = root("gate")
    fr = root("frame")
    fr.parent = r
    g = Greebler(fr, rng, metal2, dark, trim, lamp)
    # the ring stands upright (in the XZ plane) so ships fly through it along Y
    R = 24.6
    n = 20
    for i in range(n):
        a = i * 2 * math.pi / n
        out = Vector((math.cos(a), 0, math.sin(a)))
        seg = 2 * (R + 1.6) * math.tan(math.pi / n) + 0.15
        plated("ring", (seg, 6.0, 3.2), tuple(out * R), P, fr, rot=(0, -a + math.pi / 2, 0), cell=1.5, rng=rng,
               faces=["+Z", "+Y", "-Y"], chamfer=0.3)
        box("emitter", (1.6, 4.2, 0.8), tuple(out * (R - 1.9)), glow, 0.0, rot=(0, -a + math.pi / 2, 0), parent=fr)
        box("emitter_frame", (2.4, 4.8, 0.4), tuple(out * (R - 1.65)), dark, 0.0, rot=(0, -a + math.pi / 2, 0), parent=fr)
    torus("inner", 22.1, 0.35, (0, 0, 0), hot, rot=(math.pi / 2, 0, 0), parent=fr, seg=96, ring=6)
    for y in (-3.1, 3.1):
        torus("lip", R - 0.6, 0.45, (0, y, 0), trim, rot=(math.pi / 2, 0, 0), parent=fr, seg=96, ring=6)
    # pylons at the four compass points, the side ones carrying long prongs fore and aft
    for i in range(4):
        a = i * math.pi / 2
        out = Vector((math.cos(a), 0, math.sin(a)))
        c = out * (R + 4.5)
        rot = (0, -a + math.pi / 2, 0)
        for sy in (-1, 1):  # two cheeks with a gap between them for the collar to turn through
            plated("pylon", (6.0, 3.0, 5.0), tuple(out * (R + 3.4) + Vector((0, sy * 3.0, 0))), P, fr, rot=rot, cell=1.2,
                   rng=rng, chamfer=0.3)
        plated("pylon_cap", (6.6, 9.0, 3.4), tuple(out * (R + 7.4)), P, fr, rot=rot, cell=1.4, rng=rng, chamfer=0.5)
        c = out * (R + 5.6)
        F = frame(c + out * 3.5, Vector((-math.sin(a), 0, math.cos(a))) * -1, Vector((0, 1, 0)), out)
        g.patch(F, 5.0, 8.0, 10, 1.2)
        light("pylon_light", tuple(out * (R + 9.6)), 0.45, red, r, period=60, on=8, phase=i * 15)
        if i % 2 == 0:
            for sy in (-1, 1):
                prong = out * (R + 4.6) + Vector((0, sy * 11.0, 0))
                plated("prong", (3.0, 14.0, 3.0), tuple(prong), P, fr, rot=(0, -a + math.pi / 2, 0), cell=1.3, rng=rng,
                       chamfer=0.3)
                tip = prong + Vector((0, sy * 7.6, 0))
                cyl("prong_tip", 1.4, 2.0, tuple(tip), dark, rot=(math.radians(90), 0, 0), parent=fr, segs=8, r2=0.4)
                ico("prong_glow", 0.8, tuple(tip + Vector((0, sy * 1.2, 0))), glow, 2, parent=fr)
                for k in range(4):
                    box("prong_fin", (4.4, 0.25, 4.4), tuple(prong + Vector((0, sy * (k * 3.0 - 4.5), 0))), dark, 0.0,
                        rot=(0, -a, 0), parent=fr)
    merge(fr, "frame_mesh")
    # chasing lights round the aperture
    for i in range(24):
        a = i * 2 * math.pi / 24
        light("chase", (math.cos(a) * (R - 2.5), 3.4, math.sin(a) * (R - 2.5)), 0.35, glow, r, period=48, on=6, phase=i * 2)
        light("chase", (math.cos(a) * (R - 2.5), -3.4, math.sin(a) * (R - 2.5)), 0.35, glow, r, period=48, on=6,
              phase=(24 - i) * 2 % 48)
    # a slow counter-rotating outer collar
    collar = root("collar")
    collar.parent = r
    for i in range(16):
        a = i * math.pi / 8
        out = Vector((math.cos(a), 0, math.sin(a)))
        box("collar_seg", (5.0, 1.8, 1.2), tuple(out * (R + 2.3)), dark, 0.15, rot=(0, -a + math.pi / 2, 0), parent=collar)
        box("collar_light", (1.0, 1.9, 0.3), tuple(out * (R + 2.95)), lamp if i % 2 else glow, 0.0,
            rot=(0, -a + math.pi / 2, 0), parent=collar)
    cm = merge(collar, "collar_mesh")
    cm.parent = collar
    spin(collar, "Y", 600)
    export(r, os.path.join(PROPS, "gate.glb"))

def rocks():
    """Six lumpy asteroid shapes, roughly 1 m across (the game scales and colours them): fractal lumps, sharp
    ridges and a scatter of craters with raised rims."""
    for k in range(6):
        reset()
        rock = mat("rock", "6b625a", 0.0, 0.9)
        rng = random.Random(k * 17 + 3)
        r = root("rock_%d" % k)
        obj = ico("rock", 1.0, (0, 0, 0), rock, 5, parent=r)  # 2562 verts
        off = Vector((rng.uniform(0, 100), rng.uniform(0, 100), rng.uniform(0, 100)))
        squash = Vector((rng.uniform(0.75, 1.15), rng.uniform(0.75, 1.15), rng.uniform(0.6, 0.95)))
        craters = []
        for _ in range(rng.randint(5, 9)):
            c = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))).normalized()
            craters.append((c, rng.uniform(0.18, 0.42)))
        for v in obj.data.vertices:
            p = v.co.normalized()
            n = sum(noise.noise(p * f + off * f) * a for f, a in ((1.2, 0.55), (2.5, 0.25), (5.0, 0.1), (10.0, 0.035)))
            ridge = (1.0 - abs(noise.noise(p * 2.2 + off * 1.7))) ** 6 * 0.08
            dent = 0.0
            for c, cr in craters:
                d = p.angle(c)
                if d < cr * 1.3:
                    x = d / cr
                    dent += (1 - x * x) ** 2 * cr * 0.22 if x < 1 else -math.sin(math.pi * (x - 1) / 0.3) * cr * 0.05
            v.co = Vector((p.x * squash.x, p.y * squash.y, p.z * squash.z)) * (1.0 + n * 0.45 + ridge - dent)
        for poly in obj.data.polygons:
            poly.use_smooth = True
        obj.data.update()  # recompute normals after moving the vertices
        export(r, os.path.join(PROPS, "rock_%d.glb" % k))


def crystal():
    c = mat("crystal", "ffffff", 0.0, 0.15)
    r = root("crystal")
    octa("c0", 0.35, 1.0, (0, 0, 0.1), c, parent=r)
    octa("c1", 0.25, 0.7, (0.3, 0.1, -0.1), c, rot=(0.4, 0.5, 0), parent=r)
    octa("c2", 0.22, 0.6, (-0.25, -0.15, -0.05), c, rot=(-0.5, -0.3, 0.3), parent=r)
    octa("c3", 0.14, 0.4, (0.05, 0.3, -0.2), c, rot=(0.9, -0.2, 0.4), parent=r)
    export(r, os.path.join(PROPS, "crystal.glb"))


def crate():
    rng = random.Random("crate")
    body = mat("crate_body", "8a6a34", 0.3, 0.7)
    body2 = mat("crate_body2", "6f5428", 0.3, 0.75)
    seam = mat("crate_seam", "241a0c", 0.5, 0.8)
    edge = mat("crate_edge", "3a2c18", 0.6, 0.5)
    stripe = mat("crate_stripe", "ffd24a", 0.2, 0.5)
    lamp = mat("crate_light", "ff6a3d", 0.0, 0.3, emit=8.0)
    metal = mat("crate_metal", "4a4f5c", 0.8, 0.4)
    r = root("crate")
    parts = root("crate_parts")
    parts.parent = r
    plated("body", (2.4, 2.4, 2.4), (0, 0, 0), [body, seam, body2], parts, cell=0.6, rng=rng, depth=0.03, seam=0.03)
    for x in (-1, 1):
        for y in (-1, 1):
            box("edge", (0.3, 0.3, 2.6), (x * 1.15, y * 1.15, 0), edge, 0.04, parent=parts)
            box("edge", (0.3, 2.6, 0.3), (x * 1.15, 0, y * 1.15), edge, 0.04, parent=parts)
            box("edge", (2.6, 0.3, 0.3), (0, x * 1.15, y * 1.15), edge, 0.04, parent=parts)
            for z in (-1, 1):
                box("corner", (0.42, 0.42, 0.42), (x * 1.15, y * 1.15, z * 1.15), metal, 0.05, parent=parts)
    box("stripe", (2.46, 2.46, 0.4), (0, 0, 0), stripe, 0.0, parent=parts)

    for sx in (-1, 1):
        box("handle", (0.1, 0.9, 0.12), (sx * 1.3, 0, 0.6), metal, 0.0, parent=parts)
        box("handle", (0.1, 0.12, 0.3), (sx * 1.26, 0.4, 0.6), metal, 0.0, parent=parts)
        box("handle", (0.1, 0.12, 0.3), (sx * 1.26, -0.4, 0.6), metal, 0.0, parent=parts)
        box("latch", (0.5, 0.12, 0.3), (0.5 * sx, 1.28, -0.5), metal, 0.0, parent=parts)
        box("latch", (0.5, 0.12, 0.3), (0.5 * sx, -1.28, -0.5), metal, 0.0, parent=parts)
    box("label", (1.0, 0.04, 0.5), (0, 1.22, 0.55), mat("crate_label", "e8e2d0", 0.0, 0.6), 0.0, parent=parts)
    cyl("lamp_base", 0.3, 0.12, (0, 0, 1.28), metal, parent=parts, segs=10)
    m = merge(parts, "crate_mesh")
    m.parent = r
    bpy.data.objects.remove(parts)
    light("light", (0, 0, 1.42), 0.2, lamp, r, period=48, on=8)
    export(r, os.path.join(PROPS, "crate.glb"))


def wreck():
    """A broken-up hull: two plated halves split apart, bare ribs and girders at the break, loose cables,
    scorched panels, drifting plates and flickering embers."""
    rng = random.Random(7)
    hull = mat("wreck_hull", "5d6170", 0.4, 0.7)
    burnt = mat("wreck_burnt", "1c1e24", 0.3, 0.9)
    seam = mat("wreck_seam", "111216", 0.4, 0.9)
    rust = mat("wreck_rust", "8a5a2e", 0.2, 0.85)
    dark = mat("dark_metal", "1c2230", 0.6, 0.6)
    ember = mat("wreck_ember", "ff6a2a", 0.0, 0.4, emit=5.0)
    win = mat("wreck_window", "ffb060", 0.0, 0.4, emit=2.0)
    P = [hull, seam, burnt]
    r = root("wreck")
    parts = root("wreck_parts")
    parts.parent = r
    g = Greebler(parts, rng, hull, dark, rust)
    sections = [((6.0, 7.0, 2.6), (0.5, 5.0, 0.3), (0.1, 0.05, 0.12), (0.8, 0.8), -1),
                ((6.4, 6.0, 2.8), (-0.6, -4.5, -0.4), (-0.12, 0.08, -0.2), None, 1)]
    for size, loc, rot, taper, brk in sections:
        o = plated("section", size, loc, P, parts, rot=rot, taper=taper, cell=1.0, rng=rng, depth=0.06, seam=0.05, chamfer=0.15)
        M = o.matrix_basis.copy()
        hw, hl, hh = size[0] / 2, size[1] / 2, size[2] / 2
        # greebles on top, and ribs + girders sticking out of the broken end
        to_frame(g.patch(frame((0, 0, hh), (1, 0, 0), (0, 1, 0), (0, 0, 1)), size[0] * 0.8, size[1] * 0.7, 10, 0.8), M)
        end = brk * hl
        ribs = []
        for k in range(3):
            y = end + brk * (0.3 + k * 0.6)
            sc = 1.0 - k * 0.12
            ribs.append(box("rib", (hw * 2 * sc, 0.18, 0.18), (0, y, hh * sc), rust, 0.0, parent=parts))
            ribs.append(box("rib", (0.18, 0.18, hh * 2 * sc), (-hw * sc, y, 0), rust, 0.0, parent=parts))
            if k < 2:
                ribs.append(box("rib", (0.18, 0.18, hh * 2 * sc), (hw * sc, y, 0), rust, 0.0, parent=parts))
            ribs.append(box("rib", (hw * 1.4 * sc, 0.18, 0.18), (-hw * 0.3, y, -hh * sc), rust, 0.0, parent=parts))
        for k in range(5):
            x = rng.uniform(-hw * 0.8, hw * 0.8)
            z = rng.uniform(-hh * 0.8, hh * 0.8)
            ln = rng.uniform(1.0, 2.5)
            ribs.append(along_y(0.1, ln, (x, end + brk * ln / 2, z), rust, parent=parts, segs=6))
        ribs.append(box("burn", (size[0] * 1.02, 0.8, size[2] * 1.02), (0, end - brk * 0.3, 0), burnt, 0.0, parent=parts))
        to_frame(ribs, M)
        w = windows(frame((hw + 0.02, 0, 0), (0, 1, 0), (0, 0, 1), (1, 0, 0)), size[1] * 0.7, 0.6, 2, win, rng, parts, gap=0.5,
                    lit=0.25)
        if w:
            to_frame([w], M)
    # cables trailing across the gap
    for k in range(4):
        x, z = rng.uniform(-2, 2), rng.uniform(-1, 1)
        pts = [Vector((x, 1.6, z)), Vector((x + rng.uniform(-1, 1), 0.3, z - 0.8)), Vector((x + rng.uniform(-1, 1), -1.0, z - 0.5)),
               Vector((x, -1.4, z + 0.2))]
        for a, b in zip(pts, pts[1:]):
            d = b - a
            c = cyl("cable", 0.06, d.length, tuple((a + b) / 2), dark, parent=parts, segs=5)
            c.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    for i in range(8):
        box("plate", (rng.uniform(1, 2.5), rng.uniform(1, 2.5), 0.15),
            (rng.uniform(-6, 6), rng.uniform(-8, 8), rng.uniform(-3, 3)), hull if i % 3 else burnt, 0.05,
            rot=(rng.uniform(0, 3), rng.uniform(0, 3), rng.uniform(0, 3)), parent=parts)
    m = merge(parts, "wreck_mesh")
    m.parent = r
    bpy.data.objects.remove(parts)
    for i in range(7):
        light("ember", (rng.uniform(-2.5, 2.5), rng.uniform(-1.5, 1.5), rng.uniform(-0.8, 1.3)), rng.uniform(0.1, 0.22), ember, r,
              period=rng.choice((24, 40, 48, 60)), on=rng.randint(3, 14), phase=rng.randint(0, 20))
    export(r, os.path.join(PROPS, "wreck.glb"))


def obelisk():
    rng = random.Random("obelisk")
    stone = mat("ob_stone", "2d2540", 0.2, 0.8)
    stone2 = mat("ob_stone2", "3a3052", 0.2, 0.8)
    base = mat("ob_base", "4a4458", 0.2, 0.8)
    rune = mat("ob_rune", "d050ff", 0.0, 0.3, emit=7.0)
    rune_dim = mat("ob_rune_dim", "5a2090", 0.0, 0.4, emit=0.8)
    r = root("obelisk")
    body = root("body")
    body.parent = r
    col = plated("column", (4.0, 4.0, 20.0), (0, 0, 10.0), [stone, rune_dim, stone2], body, cell=1.6, rng=rng, depth=0.06,
                 seam=0.025, faces=["+X", "-X", "+Y", "-Y"])
    # narrow the top of the column into a point
    for v in col.data.vertices:
        t = (v.co.z + 10.0) / 20.0
        v.co.x *= 1.0 - 0.45 * t
        v.co.y *= 1.0 - 0.45 * t
    cyl("cap", 1.6, 2.6, (0, 0, 21.3), stone, parent=body, segs=4, r2=0.0, rot=(0, 0, math.pi / 4))
    ico("cap_gem", 0.5, (0, 0, 23.0), rune, 1, parent=body)
    for k, (w, h) in enumerate(((9.0, 1.0), (7.4, 0.9), (6.0, 0.8))):
        z = -1.4 + sum(hh for _, hh in ((9.0, 1.0), (7.4, 0.9), (6.0, 0.8))[:k]) + h / 2
        plated("plinth", (w, w, h), (0, 0, z), [base, mat("ob_seam", "1a1426", 0.2, 0.9), stone2], body, cell=1.2, rng=rng, depth=0.03, seam=0.03,
               chamfer=0.1)
    for i in range(4):
        a = i * math.pi / 2 + math.pi / 4
        p = Vector((math.cos(a), math.sin(a), 0)) * 5.6
        cyl("pillar", 0.35, 4.0, tuple(p + Vector((0, 0, 1.0))), stone2, parent=body, segs=6)
        octa("pillar_gem", 0.3, 0.6, tuple(p + Vector((0, 0, 3.6))), rune, parent=body)
    for i in range(6):
        z = 2.5 + i * 2.8
        w = 4.0 * (1.0 - 0.45 * (z / 20.0))
        for f in range(4):
            a = f * math.pi / 2
            box("rune", (w * 0.4, 0.12, 0.9), (math.cos(a) * (w / 2 + 0.07), math.sin(a) * (w / 2 + 0.07), z), rune, 0.0,
                rot=(0, 0, a + math.pi / 2), parent=body)
            box("rune", (0.12, 0.12, 0.5), (math.cos(a) * (w / 2 + 0.07) + math.sin(a) * w * 0.28,
                                            math.sin(a) * (w / 2 + 0.07) - math.cos(a) * w * 0.28, z + 0.6), rune_dim, 0.0,
                rot=(0, 0, a + math.pi / 2), parent=body)
    merge(body, "body_mesh")
    # two tilted rings turn round the column
    for i, (tilt, period) in enumerate(((0.35, 300), (-0.5, 400))):
        hold = root("ring_hold%d" % i)
        hold.parent = r
        hold.location = (0, 0, 9.0 + i * 5.0)
        hold.rotation_euler = (tilt, tilt * 0.6, 0)
        rg = root("rune_ring%d" % i)
        rg.parent = hold
        torus("rune_ring", 5.0 - i * 0.8, 0.12, (0, 0, 0), rune_dim, parent=rg, seg=64, ring=6)
        for k in range(6):
            a = k * math.pi / 3
            box("ring_glyph", (0.5, 0.15, 0.5), (math.cos(a) * (5.0 - i * 0.8), math.sin(a) * (5.0 - i * 0.8), 0), rune, 0.0,
                rot=(0, 0, a), parent=rg)
        rm = merge(rg, "rune_ring%d_mesh" % i)
        rm.parent = rg
        spin(rg, "Z", period, turns=1 if i == 0 else -1)
    # glowing shards orbit the obelisk
    shards = root("shards")
    shards.parent = r
    shards.location = (0, 0, 11.0)
    for i in range(7):
        a = i * 2 * math.pi / 7
        octa("shard", 0.55, 1.3, (math.cos(a) * 7.5, math.sin(a) * 7.5, math.sin(a * 3) * 1.6), rune, rot=(0.3, 0.2, a),
             parent=shards)
    sm = merge(shards, "shards_mesh")
    sm.parent = shards
    spin(shards, "Z", 600)
    export(r, os.path.join(PROPS, "obelisk.glb"))

def spice_stand():
    deck = mat("sp_deck", "7a5a3a", 0.1, 0.8)
    wood = mat("sp_wood", "3a2a1f", 0.1, 0.85)
    red = mat("sp_red", "c0392b", 0.0, 0.6)
    white = mat("sp_white", "f4e9d8", 0.0, 0.6)
    red.use_backface_culling = False
    white.use_backface_culling = False
    lamp = mat("sp_lamp", "ffb03d", 0.0, 0.3, emit=6.0)
    jars = [mat("sp_jar%d" % i, c, 0.0, 0.3, emit=1.5) for i, c in enumerate(["ff6a3d", "ffb03d", "ff7de9", "b9a6ff"])]
    r = root("spice_stand")
    cyl("platform", 7.0, 0.8, (0, 0, 0), deck, segs=16, bevel=0.1, parent=r)
    cyl("rim", 7.3, 0.4, (0, 0, -0.5), wood, segs=16, parent=r)
    for i in range(4):
        a = i * math.pi / 2 + math.pi / 4
        cyl("post", 0.25, 6.0, (math.cos(a) * 5.0, math.sin(a) * 5.0, 3.2), wood, segs=8, parent=r)
    # striped cone awning, alternating red and white segments
    n = 12
    for i in range(n):
        a0, a1 = i * 2 * math.pi / n, (i + 1) * 2 * math.pi / n
        bm_r = 7.5
        import bmesh
        bm = bmesh.new()
        tip = bm.verts.new((0, 0, 8.4))
        v0 = bm.verts.new((math.cos(a0) * bm_r, math.sin(a0) * bm_r, 6.0))
        v1 = bm.verts.new((math.cos(a1) * bm_r, math.sin(a1) * bm_r, 6.0))
        bm.faces.new((tip, v0, v1))  # one face; the materials are double-sided
        mesh = bpy.data.meshes.new("awning")
        bm.to_mesh(mesh)
        bm.free()
        mesh.materials.append(red if i % 2 == 0 else white)
        o = bpy.data.objects.new("awning", mesh)
        bpy.context.scene.collection.objects.link(o)
        o.parent = r
    box("counter", (6.0, 1.6, 1.4), (0, -2.0, 1.1), wood, 0.08, parent=r)
    for i in range(4):
        cyl("jar", 0.42, 0.9, (-2.0 + i * 1.3, -2.0, 2.25), jars[i], segs=10, parent=r)
    for i in range(3):
        box("sack", (1.2, 1.2, 1.0), (-2.5 + i * 2.2, 2.4, 0.9), red if i == 1 else white, 0.2, parent=r)
    cyl("lamp_cord", 0.04, 1.4, (0, 0, 7.0), wood, segs=6, parent=r)
    ico("lamp", 0.5, (0, 0, 6.1), lamp, 1, parent=r)
    m = merge(r, "stand_mesh")
    m.parent = r
    export(r, os.path.join(PROPS, "spice_stand.glb"))


BUILDERS = {"station": station, "gate": gate, "rocks": rocks, "crystal": crystal, "crate": crate, "wreck": wreck,
            "obelisk": obelisk, "spice_stand": spice_stand}

if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for name in (argv or list(BUILDERS)):
        reset()
        BUILDERS[name]()
    print("DONE")
