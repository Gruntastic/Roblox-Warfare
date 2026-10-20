# Armory: weapons and attachments

Generated from `src/shared/Config/Weapons.luau` and `src/shared/Config/Attachments.luau`; do not edit by hand.
Health is 100. "Close" shots-to-kill are body shots at 10 studs; "far" are body shots at the weapon's `farRange`.
Shotgun damage is per pellet (`close x pellets`), and shotgun shots-to-kill assume every pellet lands.
Every weapon name and design is original. Attachments are only earned by weapon level (max 30); none are sold or random.

## Weapons

| Id | Name | Class | Slot | Unlock | Fire | RPM | Damage close / far | Ranges (close / far / max) | Body STK close / far | Head STK close | Mag / reserve | ADS | Move |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| VK7 | VK-7 Vanguard | Assault rifle | Primary | 1 | Auto | 720 | 30 / 21 | 55 / 170 / 900 | 4 / 5 | 3 | 30 / 120 | 0.25s | 0.95 |
| KT9 | KT-9 Kestrel | Assault rifle | Primary | 8 | Auto | 820 | 25 / 18 | 45 / 150 / 900 | 4 / 6 | 3 | 30 / 150 | 0.23s | 0.96 |
| SW3 | SW-3 Sparrow | Assault rifle | Primary | 14 | Burst x3 (0.25s) | 850 | 31 / 23 | 60 / 190 / 900 | 4 / 5 | 3 | 30 / 120 | 0.25s | 0.95 |
| HL4 | HL-4 Halberd | Assault rifle | Primary | 22 | Auto | 600 | 33 / 24 | 60 / 190 / 900 | 4 / 5 | 3 | 25 / 100 | 0.28s | 0.93 |
| BX2 | BX-2 Bastion | Assault rifle | Primary | 30 | Auto | 760 | 28 / 20 | 50 / 160 / 900 | 4 / 5 | 3 | 30 / 120 | 0.24s | 0.95 |
| TR6 | TR-6 Torrent | Assault rifle | Primary | 42 | Auto | 680 | 27 / 19 | 65 / 210 / 950 | 4 / 6 | 3 | 32 / 128 | 0.27s | 0.94 |
| MR5 | MR-5 Mistral | SMG | Primary | 2 | Auto | 850 | 25 / 15 | 22 / 80 / 450 | 4 / 7 | 3 | 30 / 150 | 0.19s | 1 |
| ZP9 | ZP-9 Zephyr | SMG | Primary | 10 | Auto | 950 | 22 / 14 | 18 / 70 / 400 | 5 / 8 | 4 | 32 / 160 | 0.17s | 1.02 |
| CW4 | CW-4 Cinder | SMG | Primary | 18 | Auto | 780 | 26 / 16 | 25 / 90 / 450 | 4 / 7 | 3 | 25 / 125 | 0.2s | 1 |
| MN8 | MN-8 Marten | SMG | Primary | 27 | Auto | 900 | 24 / 15 | 24 / 85 / 450 | 5 / 7 | 4 | 40 / 160 | 0.2s | 0.99 |
| GN2 | GN-2 Gnat | SMG | Primary | 45 | Auto | 1000 | 21 / 13 | 15 / 60 / 350 | 5 / 8 | 4 | 36 / 180 | 0.16s | 1.03 |
| MT1 | MT-1 Mattock | LMG | Primary | 4 | Auto | 750 | 27 / 21 | 55 / 180 / 1000 | 4 / 5 | 3 | 75 / 225 | 0.36s | 0.9 |
| BW5 | BW-5 Bulwark | LMG | Primary | 20 | Auto | 650 | 32 / 24 | 60 / 200 / 1000 | 4 / 5 | 3 | 100 / 200 | 0.42s | 0.87 |
| RP3 | RP-3 Rampart | LMG | Primary | 34 | Auto | 600 | 33 / 25 | 55 / 190 / 1000 | 4 / 4 | 3 | 150 / 300 | 0.48s | 0.85 |
| LS6 | LS-6 Longshank | Marksman | Primary | 3 | Semi | 300 | 52 / 38 | 70 / 260 / 1200 | 2 / 3 | 2 | 15 / 60 | 0.3s | 0.93 |
| RL2 | RL-2 Ridgeline | Marksman | Primary | 25 | Semi | 200 | 60 / 45 | 90 / 320 / 1400 | 2 / 3 | 2 | 10 / 40 | 0.32s | 0.92 |
| HR5 | HR-5 Heron | Sniper | Primary | 4 | Semi, scope 22 FOV | 50 | 110 / 100 | 150 / 400 / 2000 | 1 / 1 | 1 | 5 / 25 | 0.4s | 0.9 |
| GT8 | GT-8 Gannet | Sniper | Primary | 16 | Semi, scope 25 FOV | 60 | 105 / 100 | 120 / 350 / 1800 | 1 / 1 | 1 | 8 / 32 | 0.36s | 0.92 |
| MO1 | MO-1 Monolith | Sniper | Primary | 38 | Semi, scope 18 FOV | 40 | 130 / 115 | 200 / 500 / 2400 | 1 / 1 | 1 | 4 / 20 | 0.48s | 0.86 |
| HG8 | HG-8 Harrow | Shotgun | Primary | 2 | Semi, 5.5 deg cone | 70 | 16x8 / 5x8 | 12 / 40 / 60 | 1 / 3 | 1 | 6 / 30 | 0.25s | 0.96 |
| RV6 | RV-6 Riven | Shotgun | Primary | 12 | Semi, 5 deg cone | 200 | 15x7 / 4x7 | 9 / 35 / 55 | 1 / 4 | 1 | 8 / 32 | 0.25s | 0.95 |
| BL9 | BL-9 Bellow | Shotgun | Primary | 32 | Auto, 6.5 deg cone | 300 | 18x6 / 4x6 | 10 / 32 / 50 | 1 / 5 | 1 | 8 / 32 | 0.3s | 0.93 |
| P12 | P-12 Warden | Pistol | Secondary | 1 | Semi | 420 | 36 / 20 | 30 / 90 / 400 | 3 / 5 | 2 | 12 / 48 | 0.16s | 1 |
| FX3 | FX-3 Ferret | Pistol | Secondary | 6 | Semi | 500 | 30 / 20 | 25 / 80 / 400 | 4 / 5 | 3 | 15 / 60 | 0.15s | 1 |
| OG6 | OG-6 Ogre | Pistol | Secondary | 24 | Semi | 160 | 48 / 32 | 35 / 110 / 500 | 3 / 4 | 2 | 6 / 30 | 0.2s | 0.98 |
| SP3 | SP-3 Sprite | Machine pistol | Secondary | 15 | Auto | 1100 | 20 / 12 | 12 / 45 / 250 | 5 / 9 | 4 | 20 / 100 | 0.15s | 1 |

### Descriptions

- **VK7 VK-7 Vanguard**: Mid-weight rifle. Reliable all-rounder with a 4-shot close-range kill.
- **KT9 KT-9 Kestrel**: Light, fast-cycling rifle that trades long-range punch for handling.
- **SW3 SW-3 Sparrow**: Three-round burst rifle that rewards precise, deliberate trigger pulls.
- **HL4 HL-4 Halberd**: Heavy-calibre rifle with a slow cadence and the hardest-hitting rounds in its class.
- **BX2 BX-2 Bastion**: Compact bullpup rifle with full-length barrel performance and a slower reload.
- **TR6 TR-6 Torrent**: Long-barrelled rifle with gentle recoil that keeps its damage at range.
- **MR5 MR-5 Mistral**: Dependable starter SMG with a quick draw and a four-shot kill up close.
- **ZP9 ZP-9 Zephyr**: Skeleton-stocked room-clearer with a blistering fire rate and fast aim.
- **CW4 CW-4 Cinder**: Hard-hitting SMG with a smaller magazine and a slower, steadier cadence.
- **MN8 MN-8 Marten**: High-capacity SMG that keeps firing long after others run dry.
- **GN2 GN-2 Gnat**: Featherweight bullet hose: the fastest SMG, and the shortest reach.
- **MT1 MT-1 Mattock**: Drum-fed light machine gun that handles almost like a rifle.
- **BW5 BW-5 Bulwark**: Belt-boxed machine gun built to lock down a lane for a hundred rounds.
- **RP3 RP-3 Rampart**: Massive 150-round support gun: slow to aim, slower to reload, relentless once set.
- **LS6 LS-6 Longshank**: Semi-automatic marksman rifle: two body shots up close, three across the map.
- **RL2 RL-2 Ridgeline**: Slow, heavy-hitting marksman rifle with a wooden stock and a ten-round mag.
- **HR5 HR-5 Heron**: Scoped sniper rifle that drops a target with one shot to the head or chest.
- **GT8 GT-8 Gannet**: Lighter sniper rifle with a faster follow-up shot and quicker scope-in.
- **MO1 MO-1 Monolith**: Anti-materiel sniper rifle: the longest reach and the slowest everything else.
- **HG8 HG-8 Harrow**: Pump-action shotgun: one clean hit up close ends the fight.
- **RV6 RV-6 Riven**: Semi-automatic tube shotgun that fires as fast as you can pull the trigger.
- **BL9 BL-9 Bellow**: Box-fed automatic shotgun that empties its small magazine in a heartbeat.
- **P12 P-12 Warden**: Service pistol. Fast to draw, three-shot kill up close, weak at range.
- **FX3 FX-3 Ferret**: Lightweight high-capacity pistol with a snappy trigger and mild recoil.
- **OG6 OG-6 Ogre**: Six-shot hand cannon with brutal recoil and rifle-like reach for a sidearm.
- **SP3 SP-3 Sprite**: Fully automatic machine pistol that shreds at arm's length and sputters beyond it.

## Attachments

Modifiers are multipliers on the weapon's base stats (see `Pure/WeaponStats.resolve`). "Offered on" counts weapons whose unlock ladder includes it.

| Id | Name | Slot | Classes | Pros | Cons | Offered on |
|---|---|---|---|---|---|---|
| HoloSight | Halo Holographic | Optic | Assault rifle, SMG, LMG, Marksman, Shotgun | Holo reticle, 56 ADS FOV; -5% ADS spread; -7% hip spread | +5% ADS time | 19 |
| MicroDot | Pocket Dot | Optic | SMG, Pistol, Machine pistol | Dot reticle, 60 ADS FOV; -10% ADS spread | +6% equip time | 9 |
| RedDot | Pinpoint Reflex | Optic | Assault rifle, SMG, LMG, Marksman, Shotgun, Pistol, Machine pistol | Dot reticle, 58 ADS FOV; -8% ADS spread | +3% ADS time | 23 |
| ScoutScope | Scout 3x Optic | Optic | Assault rifle, LMG, Marksman | Chevron reticle, 35 ADS FOV; -20% ADS spread | -10% ADS move speed; +15% ADS time | 11 |
| Choke | Tightbore Choke | Muzzle | Shotgun | +30% range | +6% ADS time; +8% hip spread | 3 |
| Compensator | Kickstop Compensator | Muzzle | Assault rifle, SMG, LMG, Marksman, Pistol, Machine pistol | -20% vertical recoil | +5% hip spread; +10% horizontal recoil | 20 |
| FlashGuard | Prong Flash Guard | Muzzle | Assault rifle, SMG, LMG, Marksman, Sniper, Machine pistol | -28% horizontal recoil | +6% vertical recoil | 19 |
| Suppressor | Hush Can | Muzzle | Assault rifle, SMG, LMG, Marksman, Sniper, Shotgun, Pistol, Machine pistol | no flash or tracer for enemies | +5% ADS time; -15% range | 25 |
| FlutedBarrel | Fluted Barrel | Barrel | Marksman, Sniper | -10% ADS time; -10% equip time | -8% range; +15% vertical recoil | 5 |
| LongBarrel | Reach Barrel | Barrel | Assault rifle, SMG, LMG, Marksman, Sniper, Shotgun | +25% range | +8% ADS time; -3% move speed | 22 |
| MatchBarrel | Match Barrel | Barrel | Pistol, Machine pistol | -15% ADS spread; +20% range | +10% equip time; +10% vertical recoil | 4 |
| StubBarrel | Stub Barrel | Barrel | Assault rifle, SMG, LMG, Shotgun | -10% ADS time; +3% move speed | -20% range; +10% vertical recoil | 17 |
| AngledGrip | Swept Grip | Underbarrel | Assault rifle, SMG, LMG, Marksman, Shotgun | -8% ADS time; -5% vertical recoil | +5% horizontal recoil | 17 |
| Brace | Bracer Bipod | Underbarrel | LMG | -30% horizontal recoil; -30% vertical recoil | -15% ADS move speed; +15% ADS time; -5% move speed | 3 |
| VerticalGrip | Ridge Foregrip | Underbarrel | Assault rifle, SMG, LMG, Marksman | -15% vertical recoil | +7% ADS time | 16 |
| DrumMag | Barrelhouse Drum | Magazine | Assault rifle, LMG | +100% mag size | +10% ADS time; -5% move speed; +35% reload time | 7 |
| ExtendedMag | Long Feed Mag | Magazine | Assault rifle, SMG, LMG, Marksman, Sniper, Pistol, Machine pistol | +50% mag size | +5% ADS time; +15% reload time | 19 |
| QuickMag | Snap Mag | Magazine | Assault rifle, SMG, LMG, Marksman, Sniper, Shotgun, Pistol, Machine pistol | -25% reload time | -10% mag size | 23 |

## Attachment unlocks per weapon (weapon level)

- **VK7** (Optic, Muzzle, Barrel, Underbarrel, Magazine): RedDot 2, Compensator 4, VerticalGrip 6, QuickMag 8, HoloSight 10, Suppressor 12, StubBarrel 14, ExtendedMag 16, AngledGrip 18, FlashGuard 20, LongBarrel 22, ScoutScope 24, DrumMag 26
- **KT9** (Optic, Muzzle, Barrel, Underbarrel, Magazine): RedDot 2, Compensator 4, VerticalGrip 6, QuickMag 8, HoloSight 10, Suppressor 12, StubBarrel 14, ExtendedMag 16, AngledGrip 18, FlashGuard 20, LongBarrel 22, ScoutScope 24, DrumMag 26
- **SW3** (Optic, Muzzle, Barrel, Underbarrel, Magazine): RedDot 2, Compensator 4, VerticalGrip 6, QuickMag 8, HoloSight 10, Suppressor 12, StubBarrel 14, ExtendedMag 16, AngledGrip 18, FlashGuard 20, LongBarrel 22, ScoutScope 24, DrumMag 26
- **HL4** (Optic, Muzzle, Barrel, Underbarrel, Magazine): RedDot 2, Compensator 4, VerticalGrip 6, QuickMag 8, HoloSight 10, Suppressor 12, StubBarrel 14, ExtendedMag 16, AngledGrip 18, FlashGuard 20, LongBarrel 22, ScoutScope 24, DrumMag 26
- **BX2** (Optic, Muzzle, Barrel, Underbarrel, Magazine): RedDot 2, Compensator 4, VerticalGrip 6, QuickMag 8, HoloSight 10, Suppressor 12, StubBarrel 14, ExtendedMag 16, AngledGrip 18, FlashGuard 20, LongBarrel 22, ScoutScope 24, DrumMag 26
- **TR6** (Optic, Muzzle, Barrel, Underbarrel, Magazine): RedDot 2, Compensator 4, VerticalGrip 6, QuickMag 8, HoloSight 10, Suppressor 12, StubBarrel 14, ExtendedMag 16, AngledGrip 18, FlashGuard 20, LongBarrel 22, ScoutScope 24, DrumMag 26
- **MR5** (Optic, Muzzle, Barrel, Underbarrel, Magazine): RedDot 2, Suppressor 4, AngledGrip 6, QuickMag 8, MicroDot 10, Compensator 12, StubBarrel 14, ExtendedMag 16, VerticalGrip 18, HoloSight 20, FlashGuard 22, LongBarrel 24
- **ZP9** (Optic, Muzzle, Barrel, Underbarrel, Magazine): RedDot 2, Suppressor 4, AngledGrip 6, QuickMag 8, MicroDot 10, Compensator 12, StubBarrel 14, ExtendedMag 16, VerticalGrip 18, HoloSight 20, FlashGuard 22, LongBarrel 24
- **CW4** (Optic, Muzzle, Barrel, Underbarrel, Magazine): RedDot 2, Suppressor 4, AngledGrip 6, QuickMag 8, MicroDot 10, Compensator 12, StubBarrel 14, ExtendedMag 16, VerticalGrip 18, HoloSight 20, FlashGuard 22, LongBarrel 24
- **MN8** (Optic, Muzzle, Barrel, Underbarrel, Magazine): RedDot 2, Suppressor 4, AngledGrip 6, QuickMag 8, MicroDot 10, Compensator 12, StubBarrel 14, ExtendedMag 16, VerticalGrip 18, HoloSight 20, FlashGuard 22, LongBarrel 24
- **GN2** (Optic, Muzzle, Barrel, Underbarrel, Magazine): RedDot 2, Suppressor 4, AngledGrip 6, QuickMag 8, MicroDot 10, Compensator 12, StubBarrel 14, ExtendedMag 16, VerticalGrip 18, HoloSight 20, FlashGuard 22, LongBarrel 24
- **MT1** (Optic, Muzzle, Barrel, Underbarrel, Magazine): RedDot 2, VerticalGrip 4, Compensator 6, QuickMag 8, HoloSight 10, Brace 12, FlashGuard 14, StubBarrel 16, ScoutScope 18, Suppressor 20, LongBarrel 22, AngledGrip 24, DrumMag 26
- **BW5** (Optic, Muzzle, Barrel, Underbarrel, Magazine): RedDot 2, VerticalGrip 4, Compensator 6, QuickMag 8, HoloSight 10, Brace 12, FlashGuard 14, StubBarrel 16, ScoutScope 18, Suppressor 20, LongBarrel 22, AngledGrip 24
- **RP3** (Optic, Muzzle, Barrel, Underbarrel, Magazine): RedDot 2, VerticalGrip 4, Compensator 6, QuickMag 8, HoloSight 10, Brace 12, FlashGuard 14, StubBarrel 16, ScoutScope 18, Suppressor 20, LongBarrel 22, AngledGrip 24
- **LS6** (Optic, Muzzle, Barrel, Underbarrel, Magazine): RedDot 2, Compensator 4, VerticalGrip 6, QuickMag 8, ScoutScope 10, Suppressor 12, FlutedBarrel 14, ExtendedMag 16, HoloSight 18, FlashGuard 20, LongBarrel 22, AngledGrip 24
- **RL2** (Optic, Muzzle, Barrel, Underbarrel, Magazine): RedDot 2, Compensator 4, VerticalGrip 6, QuickMag 8, ScoutScope 10, Suppressor 12, FlutedBarrel 14, ExtendedMag 16, HoloSight 18, FlashGuard 20, LongBarrel 22, AngledGrip 24
- **HR5** (Muzzle, Barrel, Magazine): FlashGuard 3, QuickMag 7, Suppressor 11, FlutedBarrel 15, ExtendedMag 19, LongBarrel 23
- **GT8** (Muzzle, Barrel, Magazine): FlashGuard 3, QuickMag 7, Suppressor 11, FlutedBarrel 15, ExtendedMag 19, LongBarrel 23
- **MO1** (Muzzle, Barrel, Magazine): FlashGuard 3, QuickMag 7, Suppressor 11, FlutedBarrel 15, ExtendedMag 19, LongBarrel 23
- **HG8** (Optic, Muzzle, Barrel): RedDot 2, Choke 6, StubBarrel 10, HoloSight 14, Suppressor 18, LongBarrel 22
- **RV6** (Optic, Muzzle, Barrel): RedDot 2, Choke 6, StubBarrel 10, HoloSight 14, Suppressor 18, LongBarrel 22
- **BL9** (Optic, Muzzle, Barrel, Underbarrel, Magazine): RedDot 2, Choke 5, AngledGrip 8, QuickMag 11, HoloSight 14, StubBarrel 17, Suppressor 20, LongBarrel 23
- **P12** (Optic, Muzzle, Barrel, Magazine): MicroDot 3, Compensator 6, QuickMag 9, Suppressor 12, MatchBarrel 15, ExtendedMag 18, RedDot 21
- **FX3** (Optic, Muzzle, Barrel, Magazine): MicroDot 3, Compensator 6, QuickMag 9, Suppressor 12, MatchBarrel 15, ExtendedMag 18, RedDot 21
- **OG6** (Optic, Muzzle, Barrel): MicroDot 4, Compensator 8, MatchBarrel 12, RedDot 16
- **SP3** (Optic, Muzzle, Barrel, Magazine): MicroDot 3, Compensator 6, QuickMag 9, Suppressor 12, MatchBarrel 15, ExtendedMag 18, RedDot 21

## Model conventions

- Grip origin at (0, 0, 0), barrel along -Z, +Y up. Long guns are 2.5-4.5 studs, handguns about 1 stud.
- The part named `Magazine` is replaced by magazine attachments. Magazine anchors sit 0.25 studs below the top of the mag well, so attachment magazines line up on every weapon.
- Iron-sighted weapons have `RearSight` and `FrontSight`; `sightOffset` is level with the top of the rear sight. Sniper rifles carry a built-in scope body (`ScopeTube` and related parts) instead and take no Optic attachments.
- Every weapon with an underbarrel slot has a `Handguard` above `anchors.underbarrel`.

Tables are generated by a Lune script that reads the config modules; the balance bands are enforced by `tests/specs/roster.spec.luau`.
