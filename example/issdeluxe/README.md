# International Superstar Soccer Deluxe (Mega Drive) — disassembly

A complete, **bit-exact, rebuildable** disassembly of *International Superstar
Soccer Deluxe* (Europe) for the Sega Mega Drive, produced with `sega2asm`, plus
an asset export aimed at re-implementing the game in **Godot 4**.

| | |
|---|---|
| ROM | `International Superstar Soccer Deluxe (Europe).md`, 2 MB (16 Mbit) |
| SHA-1 | `CCC60352B43F8C3D536267DD05A8F2C0F3B73DF6` |
| Header | `GM T-95196-50`, (C) Konami 1996, developed by Factor 5 |
| Video | H32 mode (256 × 224), 64×32-cell planes, shadow/highlight enabled |

No ROM data is stored in this repository: the configuration, symbols and tools
regenerate everything from your own copy of the ROM.

## What you get

* **860 segments** that tile the whole ROM with no gaps. Rebuilding them with
  `clownassembler` produces a file identical to the original (`sega2asm verify`).
* **266 KB of 68000 code** found by a recursive control-flow trace
  (1,295 routines, jump tables and code pointers resolved), emitted as 30
  assembly files (26 main, 2 boot, 2 sound) with labels for every branch/call
  target and every referenced data address, so code can be edited and
  reassembled without breaking references.
* Every pointer and offset table written symbolically (`dc.l res07-res_directory`),
  RAM globals written as `(g_next_state-$FF0000)(a6)` and object fields as
  `obj_facing(a5)` (the `obj` layout is declared in the YAML `structs:` block).
* The **Factor 5 resource archive** (87 groups, 478 entries, 900 KB) split
  entry by entry and typed: 354 tile sheets, 71 tilemaps, 82 palettes, all
  decompressed and rendered as indexed PNGs; palettes as `.gpl`/`.json`.
* The 565 KB PCM sample bank, the 26-song music bank and the Z80 PCM driver as
  separate blobs.
* A curated symbols file (`issdeluxe_symbols.txt`) documenting the engine; the
  comments are written above each routine in the generated source.
* `sega2asm godot` turns all of the above into a Godot 4 project (see below).

## Building

Requirements: Go 1.21+, [clownassembler](https://github.com/Clownacy/clownassembler)
(asm68k compatible) in `PATH` or `$CLOWNASSEMBLER`.

```bash
# from the repository root
go build -o sega2asm .

# put your ROM next to the YAML with this exact name
cp /path/to/rom.md "example/issdeluxe/International Superstar Soccer Deluxe (Europe).md"

cd example/issdeluxe
../../sega2asm -c issdeluxe.yaml        # split: writes ./out/asm and ./out/assets
../../sega2asm verify issdeluxe.yaml    # assemble ./out and compare with the ROM
../../sega2asm godot issdeluxe.yaml     # export ./out/godot (Godot 4.3+ project)
```

`verify` runs `clownassembler -i asm/issdeluxe.asm -o build/issdeluxe.bin` from
`./out` (all include/incbin paths are relative to it) and reports the first
differing ranges and their segments if anything does not match.

### Layout of `out/`

```
out/asm/issdeluxe.asm        main file: includes everything in ROM order
out/asm/include/             ports.asm (hardware registers), variables.asm (RAM),
                             macros.asm (see "Assembler notes")
out/asm/header/              vector table and cartridge header
out/asm/main/                main program ($000200–$05DB50): 26 code files + data
out/asm/boot/                boot / logo module ($144318–$14A150)
out/asm/sound/               68000 sound driver ($1FD954–$200000)
out/asm/archive/             resource archive directory and group offset tables
out/assets/archive/          archive entries: .bin (as stored), .decompressed.bin,
                             .png (indexed), palettes .gpl/.json/.png, tilemaps .json
out/assets/boot/, sound/     boot-module resources, PCM (.wav), songs
out/build/issdeluxe.bin      rebuilt ROM
```

## ROM map

| Range | Contents |
|---|---|
| `$000000–$000200` | Vector table and header |
| `$000200–$020408` | Main program: system library (DMA queue, sprites, objects, fades, pads, decompression), match engine, game states |
| `$020408–$03B09E` | Data tables used by the match engine and menus, interleaved with small code modules |
| `$03B09E–$05D72A` | Front-end program: menus, team/option screens, scenarios, results |
| `$05D72A–$05DB50` | Front-end data |
| `$05DB50–$144318` | **Resource archive** (see formats): 87 groups |
| `$144318–$14A150` | Boot module: Konami / Factor 5 / licence screens (`boot_main`, d0 = screen) |
| `$14A150–$1613EC` | Boot module palettes and five resource groups |
| `$1613EC–$1EB45C` | PCM sample bank (8-bit unsigned samples, addressed by offset) |
| `$1EB45C–$1FD954` | Music bank: 29 offsets (3 instrument/sample tables + 26 songs) |
| `$1FD954–$200000` | 68000 sound driver (16-entry `bra.w` API) with the 248-byte Z80 PCM driver at `$1FDC06` |

Archive groups of note: `res00` uncompressed sprite tiles (players, stored
column-major per sprite), `res07`–`res14` the eight stadium sets
(`load_stadium_tiles`: group = 7 + stadium), `res26`–`res86` full-screen images
(tiles + 64×32 map + 32-colour palette each).

## Engine architecture

**Boot.** `reset` performs the standard TMSS/VDP/Z80 initialisation, then
`main_init` calls `boot_main` four times (logo screens) and `warm_start`
initialises the system (`system_init`), the sound driver (`sound_init`) and
jumps to the first game state.

**States and frames.** A game state is a routine stored in `g_next_state` and
entered through `main_loop_dispatch`. Each state (`state_menu`, `state_screen`,
`state_match`, `state_result`) loads its resources, installs a VBlank handler
in `g_vblank_handler`, starts a palette fade-in and then *busy-waits* until
`g_frame_state` returns to 0. **All game logic runs inside the VBlank
interrupt**: the handler writes scroll registers, flushes the DMA queue, ticks
the sound driver, reads the pads, runs the objects and builds the sprite list.
`g_frame_state`: 1 = fading in, 2 = running, 0 = finished (after the fade-out).
In Godot this maps naturally to one scene per state with the handler body in
`_physics_process` at 60 Hz (50 Hz on PAL: `g_is_pal`).

**Objects.** Everything that moves (players, ball, cursors, menu widgets,
palette fades) is an object in a doubly linked list (`obj_alloc`, `obj_free`,
`objects_update`, `objects_draw`). Layout known so far:

| Offset | Field |
|---|---|
| `+$00` / `+$04` | next / previous object |
| `+$0E` | on-screen flag (1 = visible, $FF = culled) |
| `+$10` | world X |
| `+$14` | world Y (also the depth-sort key) |
| `+$18` | height Z |
| `+$1C` / `+$1E` | computed screen X / Y |
| `+$34` | update callback (−1 = none) |
| `+$38` | think / pre-update callback |
| `+$66` | draw callback (−1 = none) |

**Ball.** `ball_update` integrates height with gravity (`vz -= $1400` per
frame NTSC, `$1CCC` PAL — the square of the 1.2 ratio, since it is an
acceleration), bounces with `vz = -vz/2` (sound effect 88, speed loses
`speed >> tbl_ball_bounce_damp[g_weather]` = 1, 2, 1 for snow, fine, rain),
rolls with friction `speed -= speed >> tbl_ball_friction[g_weather]` (5, 5, 4)
and moves along `obj_heading` (`velocity_from_heading`). Lofted passes and
high kicks have their own update routines (`ball_update_lob`,
`ball_update_high`). `ball_draw` picks the sprite size from the height
(`action = clamp((z − $20) >> 5, 0, 2)`, 3 for a lofted pass) and the spin
frame from `obj_anim_frame` (16.16, + speed/4 per frame rolling, + 1/8 in the
air), and draws a shadow piece `z` pixels below the ball.

**Weather.** `g_weather` is 0 = snow, 1 = fine (the front-end default),
2 = rain. It selects the stadium palette (entries 6–8), keeps (snow) or patches
out (fine, rain) the snow clumps in tiles 238–255, sets the ball friction and
bounce, and animates the plane A overlay: `match_init_hud` loads res16 entry
`g_weather` into plane A (empty for fine weather) and `hud_update` streams
falling-snow frames (res04 entry 7, every 8 frames) or rain frames (entry 8,
every frame) into overlay tiles `$103`–`$106`.

**Motion.** Angles are 0–63 (0 = up the pitch, 16 = right, clockwise);
`direction_to` is a table-driven atan2 and `tbl_direction_x` holds the unit
vectors (8.8 fixed point, shaped for the oblique view). Every speed is stored
as an (NTSC, PAL) pair of 16.16 values with PAL = 1.2 × NTSC
(`tbl_speed_ntsc_pal`), i.e. the game runs its logic once per video frame and
compensates for 50 Hz — a port should run at a fixed 60 Hz tick and use the
NTSC values.

The pitch uses an **oblique projection** (`objects_draw`):
`screen_x = x + y/2 − hscroll`, `screen_y = y/2 − z − vscroll`, with objects
drawn back-to-front by Y. Reproduce this in Godot with a `Node2D` per object and
`z_index`/`y_sort` driven by world Y.

**Video.** VRAM layout (`vdp_init_game`): plane B `$0000`, window `$1000`,
sprites `$1C00`, h-scroll `$1800`, plane A `$2000`, 64×32-cell planes, H32.
All VRAM/CRAM uploads go through a 64-entry DMA queue (`dma_queue_add`,
`dma_queue_add_cram`, flushed by `dma_queue_flush` with a per-frame budget).
Palettes: `g_palette_target` (64 colours) is faded into `g_palette_current`,
which is uploaded every frame. Text is drawn into an off-screen nametable
(`g_text_nametable`) by `text_draw_small` / `text_draw_large`.

In a match the VDP runs in **shadow/highlight mode**: every sprite shadow is
palette line 3 colour 15, which the VDP does not draw but uses to halve the
brightness underneath (colour 14 would highlight). Plane A (the weather
overlay) has the priority bit on every cell, so the pitch itself is never
shadowed. An HBlank chain (`hblank_hud_split`) splits the screen at the HUD;
below the split the backdrop colour (VDP register 7) is line 3 colour 0, the
grass, which shows through every transparent pitch pixel.

**Input.** `joypad_read_all` supports up to 8 controllers through a multitap
(`g_pad_type`, `g_pad_state`). `match_players_update` merges them per team
(`g_pads_home` / `g_pads_away` controllers each, newly pressed and held
buttons in `g_pad_pressed_*` / `g_pad_held_*`) and keeps one control slot per
controller (`g_control_slots`: controlled player, buttons, pad type,
direction remap).

**Sound.** The 68000 driver drives the YM2612/PSG itself; the Z80 only streams
PCM samples. API (call through the `bra.w` table at `$1FD954`):
`sound_init`, `sound_play_music` (d0 = song), `sound_play_sfx` (d0 = effect),
`sound_play_pcm` (a1 = sample), `sound_music_stop`, `sound_update` (every
frame), `sound_reset`. Work RAM is at `g_sound_ram` ($FF31A8).

## Match engine

`state_match_frame` runs, every video frame and inside the VBlank interrupt:
pads → `match_players_update` (controllers, AI scheduling, team analysis) →
`objects_update` (every object's think and update callbacks) →
`camera_update` → crowd sounds → `speech_queue_update` (commentary) →
`objects_draw` → `match_rules_update` (the referee) → `hud_update`.

**AI scheduling.** `g_ai_slot` advances `(slot + 1) & 15` every frame. A
player only runs its expensive decisions when the slot equals its
`obj_ai_slot` (its index 0–10 in the team), so each player thinks once every
16 frames; the referee uses slot 12, the linesman 13 and the goal-mouth
sprite priority of the ball slot 14. In the same slot `match_players_update`
refreshes the player's `obj_landing_dist` and the team's `tm_nearest`,
`tm_second`, `tm_front`, `tm_back` and `tm_cover` (struct `team`, instances
`g_team_home_info` / `g_team_away_info`). A port can run the same logic every
frame, but keeping the 16-frame cadence reproduces the original reaction
times.

**Players.** Player 0 is the goalkeeper (`keeper_ai`: 32 px in front of the
goal line, sliding along it with the angle to the ball; `keeper_save` when
the ball comes within $50, `keeper_rush_out` for balls played into the
area). Outfield players use `player_ai`:

1. loose ball and nearest to where it will land → `player_ai_chase_ball`;
2. opponents in possession and nearest (or second nearest, unless covering)
   → `player_ai_press`;
3. `obj_mark` set → `player_ai_mark` (man-marking);
4. otherwise go to the formation position: X = `tm_lines[obj_role]` +
   `obj_form_x` × 8 (+ $80 for roles flagged to join attacks when the team
   has the ball), Y = pitch centre + `obj_form_y` × 8 (× 10 in possession).
   Defenders (role 0) stay out of the opponents' penalty area, forwards
   (role 2) out of their own, and nobody runs past the opponents' last
   defender (`tm_back`) minus 32 px.

`tbl_team_strategies` holds the eight in-match strategies. They either move
the team's three lines relative to the ball (all up, all back, forwards up
with the defence back, ...) or send a player on a run.
`tbl_kickoff_positions` gives each formation's kick-off layout.

**Rules** (`match_rules_update`).
* Clock: `g_match_clock` counts down minutes, tens, seconds and frames (60 or
  50 per second). At zero the referee waits until no restart is being taken
  and `g_restart_timer` has run out, then calls half time (restart 9) or
  time up ($A).
* Ball out of play: past a touchline → throw-in for the team that did not
  touch it last (`obj_team` of the ball). Past a goal line → goal if it is
  under the bar (z < $3C) and within 92 px of the centre line; a post
  (92–100 px) or the bar (z $3C–$40) makes it rebound; otherwise a corner if
  the defenders touched it last, else a goal kick. Own goals are detected
  from `g_last_touch`.
* Fouls: the fouler (`g_foul_player`) is only punished if the referee sees
  it: `tbl_referee_strictness[officials' kit][random & 3]`, so the four
  referees differ. A foul within $180 px of the fouler's own goal line (only
  the distance to the goal line is checked) is a penalty, otherwise a free
  kick. Whether a card follows depends on the foul, on the player's entry in
  `g_player_status` (bit 7 = already booked) and on how many squad members
  are already flagged there. The settings `g_opt_fouls_off` /
  `g_opt_cards_off` switch fouls and cards off.
* Offside: when a pass is played, the team's most advanced player
  (`tm_front`) is flagged (`g_offside_pending`) if, with 16 px of tolerance,
  they are in the opponents' half and beyond the last defender (`tm_back`),
  and the ball is behind that defender.

Restarts are scripts run by the invisible `g_director` object:

| `g_restart_type` | Script | Banner | Commentary | Position |
|---|---|---|---|---|
| 0 | `restart_throw_in` | THROW IN | 3 | 24 px outside the touchline, X clamped 128 px from the goal lines |
| 1 | `restart_goal_kick` | GOAL KICK | 2 / $23 | 128 px from the goal line, 192 px off centre |
| 2 | `restart_corner` | CORNER KICK | 1 / $22 | 8 px inside the corner |
| 3, 4 | `restart_kickoff` | — | $27 | centre spot (4 = start of the match) |
| 5 | `restart_foul` → `restart_free_kick`, or `restart_offside` | FOUL, FREE KICK / OFFSIDE | 4 / $24, 6 | where the foul or offside was |
| 6 | `restart_foul` → `restart_penalty` | FOUL, PENALTY KICK | 5 / $25 | penalty spot |
| 7 | `restart_penalty_spot` | — | — | 256 px from the goal line |
| 8 | `restart_own_goal` | OWN GOAL | $32 | — |
| 9 | `restart_half_time` | HALF TIME | 8 | — |
| $A | `restart_time_up` | TIME UP | $42 | then `match_result_banner` |
| $B | `restart_goal` | scorer's name | cheer (SFX 100) | — |

The second commentary number is the one used on PAL consoles. When a
restart starts, `tbl_restart_setup[g_restart_type]` moves both teams into
position. Every event updates `g_stats_home` / `g_stats_away` (shots, free
kicks, corners, penalties, yellow and red cards, offsides, goals), and
`g_scorers` keeps the minute, team and squad slot of every goal.

**Commentary.** `speech_queue_push` queues sample numbers (4 entries);
`speech_queue_update` plays one every $40 frames through `sound_play_sfx`.

**Controls.** `joypad_read_port` packs every pad as Up, Down, Left, Right, B,
C, A, Start (bits 0–7), plus Z, Y, X, Mode (bits 8–11) on 6-button pads.
`match_players_update` passes B, C, A and Z through the controller's button
layout (`tbl_button_layouts`, 8 selectable rows) to four logical buttons.
Presses stay pending in the control slot until an action consumes them. The
controlled player copies them, with the d-pad, into `obj_input`, and the AI
drives its players by writing the same word, so one set of action state
machines serves both:

| Logical button | With the ball | Without the ball | Ball in the air |
|---|---|---|---|
| pass `$10` | ground pass in the d-pad direction (`player_pass`) | — | header / volley pass |
| lofted `$20` | lofted pass or cross, power from how long it is held | sliding tackle | header / volley at goal |
| shoot `$100` | shot at the goal (`player_shoot`) | — | jumping header (high ball), diving header (further away), standing header or volley (low ball) |
| dash `$40` | sprint while running; stop the ball when standing | sprint | — |
| switch `$200` (Y) | — | switch player (mode per controller: nearest, or in the d-pad direction) | — |

At free kicks and corners the taker turns the aim with the d-pad and the
button picks pass, power kick or long ball (`set_piece_aim`,
`set_piece_kick`). On 3-button pads the lofted button near the opponents'
goal also counts as a long ball. Kick strength comes from the per-power
tables `tbl_kick_pass`, `tbl_kick_drive`, `tbl_kick_rising` and
`tbl_kick_lofted` (speed and vertical speed, NTSC and PAL).

**Player animations.** `players/animations.json` names all 54
`obj_action` values (`action_names`): stand, run, sprint, the pass and kick
family (14 power kick, 15 side-foot pass, 16–18 left, right and backheel,
chosen by the angle between the kick and the facing), headers (19 standing,
21 jumping, 22 diving), 20 overhead kick, 23 sliding tackle, falls,
celebrations (30–34, 53), the defensive wall (38, 50) and more.

## Data formats

**Factor 5 packed stream** (`decompress_factor5`, sega2asm `lzfactor5`):
`'P'`, version (`'1'` = 11-bit window, `'2'` = 16-bit window, `'3'` = stored),
16-bit little-endian unpacked size, then tokens: `0nnnnnnn` copies n+1 literal
bytes; `1…` copies a back-reference (v1: length = bits 6-3 + 3, distance =
bits 2-0:next byte + 1; v2: length = bits 6-0 + 4, distance = next word + 1).
Streams are byte-aligned and packed back to back.

**Resource archive** at `$05DB50`: a directory of 87 longs (offsets from the
archive start, ending with `$FFFF`), each pointing to a group. A group starts
with an offset table — longs when its first word is 0, words otherwise — whose
entries are offsets from the group start to packed streams or raw data. Groups
are padded with `$FF` to an even length. Code accesses entry *e* of group *g* as
`lea res_directory,a0 / adda.l 4*g(a0),a0 / move.w 2*e(a0),d0 / adda.l d0,a0`.

**Graphics.** Tiles are standard 4bpp Mega Drive tiles. Sprite tiles are
column-major within a sprite (a 2×4-cell sprite stores its 8 tiles column by
column). Nametable words: priority (bit 15), palette line (14-13), v-flip (12),
h-flip (11), tile (10-0). CRAM colours: `----BBB-GGG-RRR-`.

**Text.** Upper-case ASCII, digits and punctuation; `@` is the space
character, `` ` `` the apostrophe, lower case is used in scenario texts, `$FF`
ends a string (`issdeluxe.tbl`).

## Porting to Godot

`sega2asm godot issdeluxe.yaml` writes `out/godot`, a Godot 4.3+ project:

* `data/manifest.json` — every asset with its ROM address, size, compression,
  palette/tile references and the files generated for it.
* `assets/tiles/*.idx.png` — **index textures** (pixel = colour index 0–15)
  and `*.png` coloured previews. Draw index textures with
  `md/md_indexed.gdshader` and a palette texture to keep the original palette
  behaviour (team kits are palette swaps; fades are palette arithmetic —
  `MDPalette.fade_step_to_black` mirrors `fade_out_step`).
* `assets/palettes/*.pal.png` (16 × N, one row per line) and `*.json` (CRAM words).
* `assets/tilemaps/*.json` — nametables; `md/md_tilemap.gd` (`MDTilemap`)
  rebuilds them as two `TileMapLayer`s (low / high priority) with one atlas
  per palette line and flip alternatives, when the tiles and palette of the map
  are known.
* `assets/sound/*.wav`, `assets/text/*.json`.
* `md/md_asset_browser.tscn` (main scene) — browse all assets with their ROM
  addresses.

Then run the game-specific extractor, which adds `assets/iss/`:

```bash
go run ./example/issdeluxe/extract -rom "<rom>" -out example/issdeluxe/out/godot
```

* `iss/players/frames/f_XXXXXX_{r,l}.png` — all 611 player animation frames
  (right- and left-facing), assembled exactly like the game's sprite code does
  (body tiles from `res00`, head, hair and kit tiles, ground shadow). Pixels are
  CRAM indices `line*16 + colour`: body on line 0 (home kit), heads/skin on
  line 2, the shadow is line 3 colour 15. Draw them with `md_indexed.gdshader`
  (`shadow_highlight = true` turns colour 15 of line 3 into a 50 % darkening,
  like the VDP) and `palette_match.pal.png`, or swap line 0 for any team's
  kit from `kits.json`.
* `iss/players/animations.json` — 54 actions × 8 directions → frame lists,
  with each frame's origin and hardware sprite pieces (`$0210DE` table).
  Direction = `((facing + 4) & $38) >> 3` for a 0–63 facing angle.
* `iss/players/kits.json` — first/second kit palettes and head colour masks for
  all 43 teams.
* `iss/teams.json` — all 43 squads with the team name (read off the name
  plate graphics: 0 England, 1 Germany … 41 All Amer.Star, 42 the practice
  side), flag and name plate images, 20 players each with name and the raw
  12-byte record (attributes, body type, face and hair styles), team ratings
  and kit-clash codes.
* `iss/ball/` — the ball (`tbl_ball_anims`): 5 actions × 8 directions, each
  frame as a ball image (right / left) and a shadow image.
* `iss/npc/` — every non-player character drawn by `npc_draw`: referee and
  linesman (standing, running, flag signals, yellow and red cards, whistle),
  medics, the stretcher and the dog that runs on the pitch (it can steal the
  linesman's flag). 21 named actions × 8 directions, 178 frames, plus the four
  officials' kit variants (`kits.json`).
* `iss/flags/` — the waving corner and halfway flags (4 frames, 6 video
  frames each) and where they stand.
* `iss/stadiums/` — the 8 stadiums in snow / fine / rain weather (`g_weather`
  0–2): full renders (e.g. 2720 × 832 px, transparent pixels filled with the
  backdrop colour), 16 × 16 metatile atlases with their maps (the game's own
  streaming format), tile sheets as index images, palettes and the pitch
  bounds in pitch coordinates (`tbl_pitch_bounds`: left, right, top, bottom;
  the touchlines and goal lines).
* `iss/weather/` — the plane A snow and rain overlays: one 512 × 256 index
  image per animation state (32 for snow at 8 frames each, 16 for rain at one
  frame each), tiled over the stadium from its origin.
* `iss/hud/` — the match HUD: the window plane (`window.png`, 32 × 32
  cells), the 42 team flags and name plates, score / clock digits, the
  radar background and, per stadium, the pitch → radar pixel mapping and the
  dot colours (`hud.json` gives every item's cells).
* `iss/*.gd` — `ISSPitch` (a `TileMapLayer` building any stadium),
  `ISSWeather` (the animated overlay), `ISSFlags` (the six flags), `ISSHud`
  (flags, names, score, clock and a live radar), `ISSPlayerSprite` (animated player with
  kit swapping through the palette shader), `ISSBallSprite` (ball and shadow,
  size from the height), `ISSNPCSprite` (officials with kit variants, medics,
  dog), `ISSProjection` (pitch ↔ map coordinates, heading vectors) and
  `iss/iss_demo.tscn`, a runnable demo: open the project in Godot 4.3+, open
  the scene and press F6 (arrows scroll, +/− change stadium, W the weather,
  K the officials' kit, B kicks the ball).

The generated project has been checked with Godot 4.3: it imports without
errors, and the demo runs headless and renders under Xvfb (OpenGL). To check
your own extraction:

```bash
godot --headless --path example/issdeluxe/out/godot --import
godot --headless --path example/issdeluxe/out/godot -s res://iss/iss_selftest.gd   # prints "iss_selftest: OK"
```

**Stadium format.** Each stadium group (`res07`–`res14`) holds a metatile map
(`width, height` in 16 × 16 metatiles, then one word per metatile), a metatile
table (four nametable words per metatile, tile numbers relative to the
stadium's first VRAM tile), 256 + 663 tiles, an 18-tile patch replacing the
snow clumps of tiles 238–255 in fine and rain weather, and one palette line
per weather (entries 6–8 for `g_weather` 0 snow, 1 fine, 2 rain).
`camera_update` streams rows and columns of cells into plane B as the camera
moves (`pitch_draw_row` / `pitch_draw_column`).

Suggested mapping of the original systems:

| Mega Drive | Godot |
|---|---|
| Game state + VBlank handler | Scene + `_physics_process` (60/50 Hz) |
| Object list and callbacks | Nodes; `update`/`think`/`draw` → `_physics_process` / `_draw` |
| Planes A/B, window | `MDTilemap` / `TileMapLayer`s, `Camera2D` for scrolling |
| Sprite attribute buffer | `Sprite2D` / `AnimatedSprite2D` with the indexed shader |
| Shadow/highlight mode | `md_indexed.gdshader` with `shadow_highlight` (line 3 colours 14/15 → 50 % white/black) |
| Plane A weather overlay | `ISSWeather`: repeating `Sprite2D` region above the players |
| CRAM + fades | Palette textures + `md_indexed.gdshader` uniforms |
| Oblique pitch projection | `screen = Vector2(x + y/2, y/2 - z)` |
| Sound driver | `AudioStreamPlayer`s; songs recorded from the original or re-sequenced from the music bank |

## Assembler notes

* Output targets `clownassembler` / asm68k syntax.
* The original assembler kept `ADD/SUB/AND/OR/CMP #imm,Dn` in their `<ea>,Dn`
  encodings; asm68k-style assemblers silently turn them into `ADDI/…`, so they
  are emitted through the `add_ea`, `sub_ea`, `and_ea`, `or_ea`, `cmp_ea`
  macros in `include/macros.asm` (e.g. `and_ea.w #$000F,d0`).
* Encodings no assembler can reproduce (garbage in extension words) are kept as
  `dc.w` with the instruction in a comment.

## Regenerating and improving the segment map

`issdeluxe.yaml` is generated by `generate/main.go` from a control-flow trace
and the archive structure:

```bash
go run ./example/issdeluxe/generate -rom "<rom>" -o example/issdeluxe/issdeluxe.yaml -report trace.txt
```

`trace.txt` lists code/data regions, resolved tables, cross references and
unresolved indirect jumps. To document the game further, add names and
comments to `issdeluxe_symbols.txt` (`name = $ADDRESS ; comment`) — RAM
addresses become equates, ROM addresses labels — and re-run the split. Labels
must sit on instruction, hint or segment boundaries; `sega2asm` warns otherwise.

## Status and next steps

Done: full code/data separation, bit-exact rebuild, all compressed data decoded,
archive typed, core engine documented (boot, states, frame loop, objects, DMA,
sprites, fades, pads, text, sound API, resource loading), player animation
system decoded and exported (frames, animation tables, kits for 43 teams),
ball, non-player characters (officials, medics, stretcher, dog) and pitch
flags exported,
stadium format decoded and all 8 stadiums exported with a Godot builder,
weather (palettes, tile patch, animated plane A overlay) and the match's
shadow/highlight and backdrop rules reproduced in Godot. Match engine
architecture named: AI scheduler, player and goalkeeper AI, team state and
strategies, referee rules (clock, out of play, goals, fouls, offside, cards),
restart scripts, statistics and commentary.

Open work, in rough order of value for a port:
1. The remaining small sprites in `$02D4B2`–`$02D7DA` (ball marker, the
   flickering object of the state_result scene) and the HUD's banner text
   (`banner_draw` font).
2. Screen composition for `res26`–`res86` (VRAM base and shared UI tiles used
   by the front-end loaders) so their tilemaps render.
3. Meaning of the eight player attribute bytes and the five team ratings;
   formations (`$037E0E`) and tactics.
4. Match engine, remaining: the individual goalkeeper states, strategy
   names, game modes 0–12, the state_result scene (16 × 16 ball), camera.
5. Music bank format and sample boundaries inside the PCM bank.
