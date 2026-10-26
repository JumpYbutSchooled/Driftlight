# Driftlight

A space exploration game: fly a boxy little mining ship through a galaxy of 1,000 systems in ten regions, each
under a sky of its own - its own star (red dwarfs, blue giants, binaries) and its own colourful nebulae. Mine
huge ore veins, refine ore in station furnaces, climb a ladder of 54 ships from a skiff to kilometre-long
capital ships, and survive the pirates of Wild space. Made with Godot 4.7, with every ship, turret, station and
prop modelled in Blender from scripts.

## Download and play (Windows)

1. Go to **[Releases](../../releases/latest)** and download `Driftlight-windows.zip`.
2. Unzip it somewhere you can write to (your Desktop or Documents, not Program Files).
3. Run `Driftlight.exe`. Windows may warn that the app is unrecognised: click *More info*, then *Run anyway*.

The game **updates itself**: when you start it, it checks for a newer release, downloads it in the
background, and installs it when you close the game (or straight away with *Restart to update* on the
title screen). Your saves live in `%APPDATA%\Godot\app_userdata\Driftlight`.

**Backups.** Since v7 the game keeps dated copies of your save in the `backups` folder there: one each time
you start and stop playing, and one every 10 minutes of play (the last 40 are kept). A save it can't use is
moved there, never deleted. If the save is missing or damaged, or an old copy of the game wrote over it, the
newest good backup loads by itself when you press *Continue*. Keep one copy of the game and let it update
itself; an old copy can still write over your save, but v7 and later recover it from the backups.

**Version 8 started everyone over** (as version 4 did). Saves from earlier versions are set aside in the
`backups` folder, never deleted, and you begin again in a Wren. v8 also made progress much slower:

- Everything bought with credits (ready-made gear, probes, raw ore) costs **50 times** what it did.
- Building ships, weapons and modules takes **4 times** the materials.
- Furnaces smelt at half the speed they did in v5-v7, and keep smelting while the game is closed (for up to a
  week). When you come back the game tells you how much was made.

## How to progress

No spoilers - just the shape of it. (The same guide is in the game: press H.)

1. **Mine and smelt.** Shoot ore veins (V surveys what's in them) and collect the chunks: fly into them, let
   your tractor beam pull them in, or press O. Dock at a station with a refinery, load your hold into the
   furnace and collect the materials when they're done - furnaces keep working while you're away, even
   with the game closed. Better ore smelts into more materials.
2. **Build, don't buy.** Everything is built from materials at a station's Fabricator. Markets sell the same
   things ready-made, but for a lot of credits. A Mining Laser is a great first build: its beam locks on and
   cuts ore straight into your hold: click a rock once and it keeps cutting until you click again.
3. **Climb the ship ladder.** There are 54 ships in ten tiers. Each tier costs more than the last and does
   something better - more cargo, more guns, more speed, better mining. Pick the ones that suit you.
4. **Mark up your gear.** Every weapon comes in five marks and every module in three, each built from the
   mark below it. Modules are colour-coded by what they do.
5. **Go where the ore is.** Every region outside the Core has an ore of its own, found nowhere else and never
   below Normal quality. From tier 3 on, ships and the better marks of gear need them. The galaxy map shows
   the regions; the in-game planner tells you where each ore comes from.
6. **Explore - it pays.** Charting new systems, scanning planets and finding anomalies all earn credits, far
   more the further out you go. Wild space is dangerous, but it's where the best things are.
7. **Keep notes.** The notebook remembers every station, refinery, ore field and oddity you've seen. Pin a
   recipe to keep its materials on screen. Plot a route with stops on the galaxy map and press T to let the
   autopilot fly it.
8. **Keep your valuables in storage.** Every station shares one store, and whatever is in it is safe. If your
   ship is destroyed, everything it was carrying is lost - ore, materials, spare gear, spices. Docking stores
   everything for you (you can turn that off). You're rebuilt at the Core's station, wherever you died.

The **Sandbox** (pick it on the title screen) is a separate save where everything is free, with god mode,
peaceful space and spawning tools (F8) - for anyone who just wants to fly the big ships.

## Controls

| | |
|---|---|
| W / S | pitch the nose down / up (swap them in the ESC menu) |
| Q / E | turn |
| A / D | roll |
| R / F | throttle up / down (on autopilot: how hard the autopilot pushes) |
| X | brake (and stop the autopilot), SHIFT boost |
| Mouse | swing the camera freely round the ship (it doesn't steer) |
| Click | fire: the turrets swivel to whatever the crosshair is on; a click locks mining beams on (another stops them) |
| Right-click | select whatever is under the crosshair |
| C (or hold ALT) | free the cursor to click rows on the Overview and things in space |
| 1 / 2 / 3 | approach / orbit / warp to the selected thing |
| 5 | cruise: a fast run to the selected thing, weaving round the asteroids |
| G | salvage, use, decode; near a station or stargate, the autopilot flies you into it |
| T | auto-travel: fly the plotted route on its own, warps and stargates and all |
| O | auto-collect: the autopilot flies you round the loose ore |
| L | ship fitting: choose the weapon on each turret |
| V | survey scan: see what's in the asteroids around you |
| SPACE (hold) | quick warp menu |
| M / N | galaxy map (click: route, shift-click: add a stop, double-click: jump drive / portable wormhole) / system map |
| I / H | inventory (cargo, ship, notebook, guide, stats) / the guide |
| Wheel / middle-click | zoom / put the camera back behind the ship |
| F1 | photo mode (P saves a picture) |
| F3 | debug screen, F8 sandbox tools, F11 fullscreen, ESC menu |

Ships are heavy: speed builds up and bleeds off over a few seconds, and turns carry momentum.
To **dock**, fly into a station's docking bay and on to the landing pad at the back (warping to a
station drops you out in front of the bay, lined up on it). **Stargates** are railguns pointed at
the system they lead to: fly into the mouth and the coils fire you down the barrel into the jump.
Near a station or gate, G hands it to the autopilot. Capital ships are too big for any bay: they dock by
tether, and their jump drives skip the stargates altogether.

## Building it yourself

Open the folder in Godot 4.7, or export from the command line:

```
godot --headless --path . --export-release "Windows Desktop" build/Driftlight/Driftlight.exe
```

The models are generated by the scripts in `tools/blender` (run them with Blender 5 in background mode,
for example `blender --background --factory-startup --python tools/blender/ships.py`).

## Credits

- Engine: [Godot](https://godotengine.org)
- Models: generated with [Blender](https://www.blender.org)
- Font: Barlow Semi Condensed by Jeremy Tribby (SIL Open Font License, see `fonts/Barlow-OFL.txt`)
