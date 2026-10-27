# Agent handoff: Home: Equestria

Read this first. It is what the previous agent (a long session building the chemistry system and
everything around it) wishes it had been told on day one. It is practical, not a design doc.
Where something is a guess it says so.

## The project and the person

- **Godot 4.5 GDScript** pony game ("Home: Equestria", mare-dev builds, `project.godot`
  version `0.0.3-maredev` at the current base). Desktop and VR. Ponies are LLM-driven
  characters: each has a prompt, awareness, memory and an action vocabulary.
- **The user** (called "dev" in code comments, "Anon" is the player character) plays on a
  **Windows export** and sends back `godot.log` files. They are casual, funny, often short on
  usage, and want things to *work* rather than be explained. Short, direct answers. When
  they ask "confirm my suspicion", answer from the code, not from vibes. Dated user quotes live
  in code comments as `(dev 2026-10-26: "...")`; keep that habit, it is the only requirement
  history there is.
- **Age rules are real and must not be weakened.** Fillies/colts and adults are handled
  differently (romance, flank smacks, adult-only reagents, `YOUNG_HELP` in
  `world/relationships/relationship_runtime.gd`, `welcomes()` in `player_bonds.gd`). Personality
  decides *how* a pony reacts to a potion, but hard safety rules stay hard-coded.
- **Never commit ripped/converted assets** (see `.gitignore`: `world/zones/**`, `.glb`, etc.).

## Environment facts that will bite you

- The cloud checkout has **no private assets**: no zones, no pony models, no terrain. You
  cannot launch the real game. What you *can* do headless:
  - compile-check a script: `godot --headless --path . --check-only --script path/to/file.gd`
    (look for `error`/`Parse Error` in the output; a clean run prints only the engine banner)
  - run the brew regression: `godot --headless --path . --script tools/playtest/chem_brew_test.gd`
    (must end `FAILURES: 0`)
  - write throwaway `SceneTree` tests with **stand-in ponies** (plain `Node3D` with the
    properties your code reads). Cheap, catches most script errors. Beware: `bool(null)` on a
    stand-in blows up; write `x == true`.
  - screenshots: `xvfb-run godot --rendering-driver opengl3 ...` on a tiny project that
    copies only the scripts it needs.
- Use **Godot 4.5-stable exactly** (official release, `Godot_v4.5-stable_linux.x86_64`). Packs made
  by 4.6 are rejected by the 4.5 game ("Pack created with a newer version of the engine").
- GDScript here is **tab-indented**. A mis-indented line after a scripted edit is the most common
  self-inflicted error. After any bulk edit, compile-check.
- **Do not `pkill -f ...`**, it kills your own shell. The GitHub CLI is not available, use the
  GitHub MCP tools. Do not create PRs unless asked.
- Branches on `anonymousmare/home-equestria`: `claude/keen-goldberg-d5s3b1` (PR #4, chemistry),
  `claude/dreamy-mccarthy-f430da` (taser, Twilight's voice, and the move to 0.0.3). Commit and push
  after each unit of work (a stop hook nags about uncommitted changes). Commit trailers/attribution
  come from the session reminder.
- **Upstream releases** come from `https://github.com/homedevanon/home-equestria` as one squashed
  commit per version with no shared history: `3617d97` = 0.0.2-maredev, `068e247` = 0.0.3-maredev.
  When the user says the patch "isn't compatible with the new update", the game moved on and the
  patch is overriding newer scripts with old copies. Fix: `git remote add upstream <url>`,
  `git fetch --depth 1 upstream`, then `git diff --binary <old base> upstream/main | git apply -3
  --index` on the working branch, resolve conflicts (so far always "keep both"), compile-check,
  and rebuild the patch with `BASE=<new upstream commit>`.

## Shipping a patch to the user (important, this is how they test)

The user's game is a shipped, script-compiled build. They don't run from source. Changes reach
them as `zz_patch.pck` placed next to the exe (`tools/build/packs.gd` mounts every `.pck` in name
order, later wins, so `zz_` goes last).

```
GODOT=/path/to/Godot_v4.5-stable_linux.x86_64 BASE=068e247 python3 tools/patch/build_patch.py
# -> build/patch/zz_patch.pck   (gitignored)
```

Then deliver with `SendUserFile` and say "replace the old zz_patch.pck". The script packs every file
changed since `BASE` plus new `world/` files, exports with `script_export_mode=2` (compiled), and
strips `.godot/*`, `project.binary` and `.uid` entries with `tools/patch/pck.py`.

- Player builds **hide dev tools** (`world/dev_tools.gd`, `player_build` feature). The patch
  applies `tools/patch/dev_tools_local.diff` to its *copy* of `dev_tools.gd`, so an empty file
  `dev_tools.txt` next to the exe turns dev tools on. That override is deliberately **not** in
  the repo's real `dev_tools.gd`. The chemistry lab is **L**, map teleport is
  **Ctrl+Shift+click** (world click or map click).
- How the user can tell it loaded: godot.log has `[dev] developer tools ON ...`, and `L` opens the
  lab. If a patch "does nothing", suspect: old pck not replaced, wrong engine version, or
  the file list missed a newly added file (new files outside `world/` need to be tracked and
  changed since `BASE` to be picked up).
- The user once hit a Windows editor export error writing `Home: Equestria.exe/.pck`, and asked
  whether to use "export as patch" or "export with debug". The answer we settled on: don't
  use the editor export for iterating, use the script above and drop the pck next to the shipped
  exe. (The root cause of that export error was never established here.)
- **Logs**: ask for `godot.log`. Useful greps: `[chemistry]`, `[tea]`, `[ai]` (what a pony said
  and did, including `dropped unusable tags`), `[llm-request]`, `[hitch]` (just frame timing noise).
  A hard crash leaves **no backtrace** in a release log. If one recurs ask them to run the
  console exe or a debug export.

## Map of the chemistry feature (all under `world/chemistry/`)

| File | Job |
| --- | --- |
| `reagents.json` | ~77 reagents (elements, compounds, medicines, pyro/explosives, drinks, 6 whimsical potions), ~56 reactions, dispenser list. Fields: name, color, kind, drink (`yes`/`no`/`potion`), minutes, felt, uses, serve (hot/cold hints), blast, adult, aura |
| `chem_catalog.gd` | data access, temperature model (kelvin, ROOM 300, half-life 300 s, SCALDING 355 K), `serve_note`, `temp_words` |
| `chem_beaker.gd` | reaction sim (`requires`/`catalysts`/`min_temp`/`blast`), emits `blasted` |
| `chem_container.gd` | procedural vessels: test_tube, potion_bottle, cup, mug, flask, beaker; liquid level, steam |
| `chem_lab_gui.gd` | dev lab on **L**: dispenser, heater, bottling, Bottles tab (give/keep/set off/hold/drink/discard/cure), vessel dropdown |
| `chem_blast.gd` | cartoon explosions (flash/sparks/glitter/confetti/smoke) and witness reactions. Nobody is hurt |
| `pony_potion_effects.gd` | `give()` = a pony drinks: refusals (undrinkable, scalding, asleep, filly+adult reagent), effects node (glow, invisibility via render layer 0, fluster), memory + visual |
| `player_potion_effects.gd` | the same for Anon (glow, invisibility, 1.35x speed for energy, ethanol -> cider) |
| `pony_belongings.gd` | what each pony keeps (`state.pony_belongings`), Anon's saved bottles (`state.chem_bottles`), the `[use_item]` action logic, hand-overs, situation lines |
| `chem_drink_visual.gd` | the pony holding/drinking/receiving/resting with a cup; foreleg reach via `hoof_hold`; unicorn horn glow; cup rests beside a sitting/lying pony |
| `chem_hand.gd` | Anon's held vessel (click drink or give, right-click keep/put away) |
| `chem_tea.gd` | tea sets: the "teapot" is the **cottage tea set** (`furniture == "cottage-tea-set"`, loose item `goods:cottage-tea-set`). Anon presses **E**; ponies use `[pour_tea]` |

Pony-side physics piece: `world/characters/locomotion/pony_hoof_hold.gd` (`reach`, `follow`,
`walk_ok`). A cup in the hoof must keep up while walking: the softened goal is carried with her body
(spring is capped at 1.1 m/s, a trot is faster). Posture code refuses to lower while a hoof is held
unless `walk_ok`.

## How the AI layer works (what you touch to add a pony ability)

A pony's reply is text with bracket tags. The pipeline:

1. **Prompt**: `world/ai/prompts/<pony>.md` (main cast, plus `system.md`/`catalog.json`) or
   `world/characters/background/ai/<id>.md` for background ponies (Noi's "lots of please and thank
   you" is literally in her `.md`; personality is just prose). Situation lines are assembled in
   `world/ai/director_prompts.gd` (`situation_block`, metas such as `potion_context`,
   `chem_cup_context`).
2. **Awareness**: `world/ai/pony_awareness.gd` samples what she can see/hear. The player's gaze is
   coarse: "looking at you / at <named thing> / elsewhere" plus a bearing relative to her facing.
   There is **no** body-part gaze (nothing knows you are looking at a flank, only touch is detected
   via `flank_smack`).
3. **Lore/RAG**: short facts in `world/ai/context_seeds.json` (`lore` array, e.g.
   `chemistry_explosives`) are pulled in by `world_context` when relevant, so ponies can know
   things exist without bloating every prompt.
4. **Actions**: `world/ai/pony_action_schema.gd` decodes tags. To add one you edit: `TYPES`,
   `FIELDS`, `SIGNATURES`, `ALIASES`, `TAG_HELP`, `_channel()`, `validate()`; then
   `pony_action_coordinator.gd` (capability in `context()`, a `dispatch_*`) and
   `pony_action_executor.gd` (the `match` arm). Look at `use_item` and `pour_tea` as the template.
   **Limits per reply: two actions total, one per channel** (gaze / movement / grant / item), so
   `[approach: X]` + `[use_item: ITEM, self]` is fine, two movements are dropped (`Only one movement
   per reply`). No sequencing ("walk there then drink").
5. **Physical events -> AI**: `world/ai/director_contacts.gd` turns `physical_reaction` signals
   into events/memory (potion, potion_toohot, potion_refused, kept, kaboom, flank_smack, ...).
6. **Relationships**: `world/relationships/` (`player_bonds.gd`, `relationship_runtime.gd`,
   `pony_affection.gd`). What counts as welcome contact is decided there.

Explosives: ponies' `[use_item]` path has **no temperature requirement**. Only the lab beaker's
reactions (`min_temp`) do. The pony prompt line says so explicitly (`about()` in `pony_belongings.gd`),
because an AI reading "thermite" tends to assume it needs a furnace.

## Working conventions that paid off

- Read the nearby code first and match it: comment density, naming, `(dev DATE: "quote")` notes,
  tabs. Existing files here are dense, long-lined and heavily commented.
- Keep a changed script loadable under the shipped build: guard private/optional scripts with
  `ResourceLoader.exists` (`game_player_rig.gd` does this for the profiler/console).
- Visuals that follow a pony run in `_physics_process` with physics interpolation, like the pony
  does, or they stutter beside her.
- Verify before you push: compile-check, the brew test, a stand-in test of anything stateful.
  Then build the patch and send it. The user tests on real hardware and reports by log.
- Saved state lives in `world_context.state` (keys `pony_belongings`, `chem_bottles`,
  `belongings_seeded`). Seeding is idempotent (Zecora starts with a bottle).

## Known loose ends and ideas (none are promised)

- A hard crash giving Rarity an invisibility potion happened once and did not repeat (user: "a
  fluke"). Never explained: log had no error. If it returns, suspects are the unicorn-only horn
  glow path in `chem_drink_visual.gd` (`cast_magic` + an `OmniLight3D` on the cup) and
  `_update_invisibility` setting `layers = 0` on every `VisualInstance3D` under a pony.
- Desktop flank-slap key binding was not located (VR uses hand speed). Behaviour and welcome rules
  are in `pony_flank_touch.gd` and `player_bonds.gd`.
- Offered, not requested: rear-gaze awareness (raycast to hindquarters + "he has been looking at
  your flank for 4 s" line + memory), a sequenced multi-step action chain, potion bottles as real
  world/briefcase inventory items.
- Teleport and lab are dev-only on purpose; do not expose them in player builds.
