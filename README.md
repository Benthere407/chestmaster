# ChestMaster

An Ashita v4 / VanaCore addon for Abyssea's **Sturdy Pyxis** chests on LandSandBoat servers.
Walk up to your chests and ChestMaster opens, destroys or leaves each one by what it holds:
no clicking through menus.

## What it does

- **Knows what's inside.** The chest's contents are read from the server's own menu data
  (LandSandBoat's `sturdypyxis` content table), not guessed from chat text: Cruor, EXP,
  time extensions, every light (soothing, pearlescent, azure, ruby, amber, golden, silvery,
  ebon, by strength), temporary items, items, powerful items and key items, plus the chest colour.
- **Your rule per kind of chest:**

  | Rule | What happens |
  |---|---|
  | **Destroy** | Breaks the chest; you get Cruor (10 x tier). |
  | **Open** | Trades the chest a Forbidden Key. Cruor, EXP, lights and time are applied at once; item chests pop their item list up for you. |
  | **Timed** | Opens one, then destroys that kind until a timer (default 5 min) runs out, then opens the next. Good for Soothing light. |
  | **Leave** | Leaves it to you (its menu can be opened for you). |

- **Auto mode.** Talks to your chests by itself, nearest first, one per second, with a running count:
  `[3/12] Blue chest: Tremendous exp -> Destroy` ... `All chests in range checked - 9 chests done, 3 left for you to check. 4 more of yours are out of range - walk closer.`
  Chests set to Leave are skipped so the round never waits on you; check them after. A round
  stays open while chests keep turning up (AoE lag), and slow chests get up to 3 tries.
- **Only your chests.** A chest counts as yours when it appears where a monster your party or
  alliance claimed just died, or with the server's "concealing a treasure chest" message.
  Other people's chests, free-spawning ones and mimics are left alone.
- **Waits until out of combat** (optional) so chests are handled between pulls, not in the
  middle of AoE farming: a short wait after the last kill (default 3s), monsters attacking you,
  monsters claimed, members engaged, and fights near you (stunned / slept monsters).
  **Combat counts for** Me / My party / Alliance, so you can farm chests while the rest of the
  alliance keeps fighting.
- **Safe with your own clicks.** Chests you click are handled too; clicking one ChestMaster is
  already handling never leaves you stuck, and `/cm unstick` frees you if anything does.
- **On-screen widget** in the VanaCore look: Classic, or YunaUI's **Vex** (menu card or party
  slant; Yuna / Blue & white / Purple) and **Hex link** styles, showing a chest icon, your
  Forbidden Key count and an ON / OFF / WORK tag. Click the tag to turn it on or off (it also frees you if you're ever stuck in a menu).

## Install

1. Copy the `chestmaster` folder (with `chestmaster.lua` and `vcmenu.lua`) into
   `addons/` (Ashita) or `addons/ashita/` (VanaCore).
2. `/addon load chestmaster`
3. `/cm` opens the window: set your rules on the **Contents** page.

## Commands

| Command | |
|---|---|
| `/cm` | show / hide the window |
| `/cm on` / `off` / `toggle` | automation on or off |
| `/cm auto` | auto mode on or off |
| `/cm widget` | show / hide the on-screen widget |
| `/cm last` | the last chest and what was done |
| `/cm unstick` | free yourself if you're ever stuck in place |
| `/cm debug` | debug messages in chat |

Settings are saved per character. **Settings > Debug** can write `chestmaster_trace.log`
(packet trace for fixing problems); it is off by default.

## Notes

- Built and tested against a LandSandBoat-based server. Chest contents, menu options (999 =
  break the chest) and the Forbidden Key trade follow LandSandBoat's
  `scripts/globals/abyssea/sturdypyxis/`.
- Opening uses Forbidden Keys from your main inventory.
- The window uses `vcmenu.lua`, a small VanaCore-style menu library shipped alongside.
