# Art credits

All character, furniture and tile art in BankSim is original to this project. No third-party art packs are used.

## Credits

- **lym221-not** created the original pixel-art designs:
  - the player character
  - the three customer designs (`customer_a`, `customer_b`, `customer_c`)
  - the furniture sprites (`assets/sprites/furniture_*.png`)
  - the office floor and wall tiles (`assets/tilesets/placeholder_tiles.png`)
- The staff uniform looks and the extra customer looks are recolours and small pixel edits of those designs, made by the generator script below.
- The entrance tiles (`assets/tilesets/outdoor_tiles.png`) and the impatience bubble (drawn in code in `scripts/npc/patience_indicator.gd`) were added later in the same style.

## Character sprite format

Every character uses the same format, so they all share one size and style and the same movement code drives them:

- **Sheets:** one 96×24 PNG per direction (`_down`, `_up`, `_side`). Left-facing is the side sheet mirrored in code.
- **Frames:** six 16×24 frames per sheet. Frames 0–1 are the idle animation (2 fps); frames 2–5 are the walk animation (8 fps).
- **SpriteFrames:** each character has a `<name>_frames.tres` with the animations `idle_down`, `walk_down`, `idle_up`, `walk_up`, `idle_side` and `walk_side`.
- **Scale:** sprites sit on the room's 32×32 tile grid with nearest-neighbour filtering. The camera shows them at 2× by default and 1× in the overview (Z), so every art pixel is a whole number of screen pixels at both zooms.

| Sheets | What they are | Made by |
|---|---|---|
| `player_*` | The player | lym221-not (source) |
| `customer_a_*`, `customer_b_*`, `customer_c_*` | The three customer designs | lym221-not (source) |
| `customer_a2`–`a4`, `b2`–`b4`, `c2`–`c4` | Recolours of each customer design: hair, skin and clothing | generator |
| `staff_01`–`staff_06` | The bank uniform worn by the six starting staff, one look each (`StaffRosterData`) | generator |
| `staff_07`–`staff_10` | Uniform looks given to newly hired staff (`StaffLooks.HIRE_LOOKS`) | generator |
| `guard_1`, `guard_2` | The armored truck crew: the player recoloured into a guard uniform (olive jacket, dark shirt and trousers, a silver badge), two hair and skin looks (`StaffLooks.GUARD_LOOKS`) | generator |
| `regional_manager` | The Regional Manager who visits on review days: the player recoloured with a light grey suit, burgundy tie and silver hair, no uniform (`StaffLooks.REGIONAL_MANAGER_LOOK`) | generator |

The staff uniform is built on the player's body, so proportions and animation match. It has a blue blazer, a white shirt front, charcoal trousers and a gold name tag. Each look has its own hair style (the player's short cut or customer A's ponytail), hair colour and skin tone.

## Regenerating the art

`tools/art/generate_characters.py` builds every generated sheet and its `.tres` from the source sheets above. It never overwrites the sources. It needs Python 3 and only the standard library (no Pillow), and its output is deterministic.

To rewrite the generated art:

```sh
python tools/art/generate_characters.py
```

To check the committed art matches the script (exits 1 if anything differs):

```sh
python tools/art/generate_characters.py --check
```

To change a look, edit the colour tables at the top of the script (`STAFF_LOOKS`, `CUSTOMER_VARIANTS`, the uniform colours) and run it again. Then open the project in Godot, or run `run_tests.sh`, so new PNGs get their `.import` files, and commit the PNGs, `.tres` and `.import` files together.

A new customer look also needs a line in `CustomerNPC.CUSTOMER_FRAME_SETS`. A new staff look needs adding to `StaffLooks`. `tests/character_art_test.gd` fails if a sheet on disk isn't in its list.
