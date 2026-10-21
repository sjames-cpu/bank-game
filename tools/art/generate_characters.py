"""Generates BankSim's character sprite variants from the original sheets.

Every sheet keeps the original in-house format (see ART.md): 96x24 PNGs of
six 16x24 frames per direction (down, up, side; left is side mirrored),
frames 0-1 idle and 2-5 walk, wrapped in a SpriteFrames .tres with the same
six animations as assets/sprites/player_frames.tres (which is used as the
.tres template, so frame timing never drifts).

Sources (never overwritten): assets/sprites/player_*.png and
customer_{a,b,c}_*.png, the original designs by lym221-not.

Outputs, all in assets/sprites/:
  - staff_01 .. staff_10: the bank staff uniform (navy-blue blazer, white
    shirt front, charcoal trousers, gold name tag), built on the player's
    body so proportions and animation match. Two hair styles: the player's
    short cut, and customer A's ponytail. Each look has its own hair and
    skin colours. staff_01-06 belong to the starting roster
    (StaffRosterData); staff_07-10 are the looks new hires are given.
  - regional_manager: the Regional Manager who visits on review days, the
    player's body and suit recoloured (light grey suit, burgundy tie,
    silver hair).
  - customer_{a,b,c}2 .. 4: recolours of each customer design (hair, skin,
    clothing), nine new looks alongside the three originals.

Standard library only (no Pillow): PNGs are read and written with zlib.
Output is deterministic, so

    python tools/art/generate_characters.py            # (re)write the art
    python tools/art/generate_characters.py --check    # verify it's current

--check exits 1 if any generated file is missing or differs.
"""

import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPRITES = ROOT / "assets" / "sprites"
DIRECTIONS = ("down", "up", "side")
FRAME_W, FRAME_H, FRAMES = 16, 24, 6

# --- PNG I/O (8-bit RGBA, non-interlaced) -------------------------------------


def read_png(path):
    """Returns the image as a list of rows of [r, g, b, a] lists."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")
    pos, idat, width, height = 8, b"", 0, 0
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if (depth, colour, interlace) != (8, 6, 0):
                raise ValueError(f"{path}: only 8-bit RGBA, non-interlaced PNGs are supported")
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length
    raw = zlib.decompress(idat)
    stride = width * 4
    rows, previous, i = [], bytearray(stride), 0
    for _ in range(height):
        kind = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            left = line[x - 4] if x >= 4 else 0
            up = previous[x]
            up_left = previous[x - 4] if x >= 4 else 0
            if kind == 1:
                line[x] = (line[x] + left) & 255
            elif kind == 2:
                line[x] = (line[x] + up) & 255
            elif kind == 3:
                line[x] = (line[x] + (left + up) // 2) & 255
            elif kind == 4:
                guess = left + up - up_left
                pa, pb, pc = abs(guess - left), abs(guess - up), abs(guess - up_left)
                line[x] = (line[x] + (left if pa <= pb and pa <= pc else up if pb <= pc else up_left)) & 255
        rows.append(line)
        previous = line
    return [[list(row[x * 4:x * 4 + 4]) for x in range(width)] for row in rows]


def png_bytes(image):
    height, width = len(image), len(image[0])

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + bytes(channel for pixel in row for channel in pixel) for row in image)
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))

# --- sheets ---------------------------------------------------------------------
# A sheet is {direction: image}. Colours are "#rrggbb" strings in the tables
# below; pixels are compared on RGB with full alpha.


def rgb(hex_colour):
    return [int(hex_colour[i:i + 2], 16) for i in (1, 3, 5)]


def load_sheet(name):
    return {d: read_png(SPRITES / f"{name}_{d}.png") for d in DIRECTIONS}


def copy_sheet(sheet):
    return {d: [[list(p) for p in row] for row in image] for d, image in sheet.items()}


def is_colour(pixel, hex_colour):
    return pixel[3] == 255 and pixel[:3] == rgb(hex_colour)


def recolour(sheet, mapping):
    """Swaps colours all at once ({"#old": "#new"}), so swaps can chain."""
    swaps = {tuple(rgb(old)): rgb(new) for old, new in mapping.items() if old != new}
    result = copy_sheet(sheet)
    for image in result.values():
        for row in image:
            for pixel in row:
                if pixel[3] == 255 and tuple(pixel[:3]) in swaps:
                    pixel[:3] = swaps[tuple(pixel[:3])]
    return result


def set_in_frames(sheet, direction, points, only_on, colour):
    """Sets frame-relative pixels (x, y) in every frame of one direction, but
    only where the pixel is currently `only_on` (so arms and hair in front
    are left alone)."""
    for frame in range(FRAMES):
        for x, y in points:
            pixel = sheet[direction][y][frame * FRAME_W + x]
            if is_colour(pixel, only_on):
                pixel[:3] = rgb(colour)


def recolour_below(sheet, row, old, new):
    """Recolours `old` to `new` in rows at or below `row` (frame-relative)."""
    for image in sheet.values():
        for y in range(row, FRAME_H):
            for pixel in image[y]:
                if is_colour(pixel, old):
                    pixel[:3] = rgb(new)

# --- staff uniform --------------------------------------------------------------

# The player's palette (assets/sprites/player_*.png).
PLAYER_SUIT = "#1e1e26"
PLAYER_TIE = "#7a3a2e"
PLAYER_HAIR = "#deaf6e"
PLAYER_SKIN = "#fad1b2"
# Customer A's (the ponytail).
CUSTOMER_A_HAIR = "#4f3426"
CUSTOMER_A_SKIN = "#e0ac85"

# The uniform: a clearly blue blazer (the player's suit is near-black), the
# tie column turned into a white shirt front, charcoal trousers (the player's
# suit is one colour top to bottom) and a gold name tag on the chest.
BLAZER = "#2d5196"
SHIRT = "#f0f0f0"
TROUSERS = "#34363f"
NAME_TAG = "#e8c547"
# Frame-relative rows from here down are legs (the jacket hem is row 16).
LEGS_FROM_ROW = 17
# Name tag on the wearer's left chest; none on the back.
NAME_TAG_PIXELS = {"down": [(11, 12), (12, 12)], "side": [(11, 12)]}


def uniform_short():
    sheet = recolour(load_sheet("player"), {PLAYER_SUIT: BLAZER, PLAYER_TIE: SHIRT})
    recolour_below(sheet, LEGS_FROM_ROW, BLAZER, TROUSERS)
    for direction, points in NAME_TAG_PIXELS.items():
        set_in_frames(sheet, direction, points, BLAZER, NAME_TAG)
    return sheet


def uniform_ponytail(short):
    """Customer A's head and ponytail on the uniform body: their hair wherever
    it is, the rest of their head above the collar, the uniform below. Their
    skin and hair are brought to the player's colours first, so each look
    recolours one set of colours."""
    head = recolour(load_sheet("customer_a"), {CUSTOMER_A_HAIR: PLAYER_HAIR, CUSTOMER_A_SKIN: PLAYER_SKIN})
    result = copy_sheet(short)
    for direction in DIRECTIONS:
        for y, row in enumerate(head[direction]):
            for x, pixel in enumerate(row):
                if is_colour(pixel, PLAYER_HAIR) or y < 10:
                    result[direction][y][x] = list(pixel)
    return result


# Look id -> (hair style, hair colour, skin colour). Roster looks are fixed
# per staff member (StaffRosterData); hired staff get one of the hire looks
# (StaffLooks.HIRE_LOOKS). Every look differs from the others in at least two
# of style, hair and skin, so staff are told apart without their name label.
STAFF_LOOKS = {
    "staff_01": ("short", "#8a3b22", "#f2c9a6"),     # Derek Voss: auburn
    "staff_02": ("ponytail", "#1c1a1a", "#b07850"),  # Priya Anand: black
    "staff_03": ("short", "#bdbdbd", "#f0c8a8"),     # Walter Higgins: grey
    "staff_04": ("ponytail", "#6b4228", "#d9a074"),  # Nina Ortiz: brown
    "staff_05": ("short", "#1c1a1a", "#c68c62"),     # Marcus Chen: black
    "staff_06": ("ponytail", "#8a3b22", "#7a4e33"),  # Sana Malik: auburn
    "staff_07": ("short", "#6b4228", "#5e3d2b"),     # hire looks
    "staff_08": ("ponytail", "#deaf6e", "#f2c9a6"),
    "staff_09": ("short", "#deaf6e", "#9a6644"),
    "staff_10": ("ponytail", "#bdbdbd", "#e0ac85"),
}

# --- the Regional Manager ------------------------------------------------------

# The Regional Manager who visits on review days (RegionalManager): the
# player's suit, but light grey with a burgundy tie, silver hair and a
# deeper skin tone. No bank uniform or name tag: a visitor from head office,
# told apart from the staff (blue blazers) and the player (near-black suit).
REGIONAL_MANAGER_COLOURS = {
    PLAYER_SUIT: "#6b717e",
    PLAYER_TIE: "#8e2236",
    PLAYER_HAIR: "#d4d4d4",
    PLAYER_SKIN: "#c68c62",
}

# --- customer variants ---------------------------------------------------------

# Each design's colours by role, and the recolours: three per design, for 12
# customer looks in all. Skin tones run light to deep across the set.
CUSTOMER_ROLES = {
    "customer_a": {"hair": "#4f3426", "skin": "#e0ac85", "top": "#34857a", "bottom": "#232a47"},
    "customer_b": {"hair": "#cdcdcd", "skin": "#e8c19e", "top": "#6e2a30", "bottom": "#b09c76"},
    "customer_c": {"hair": "#201a18", "skin": "#966a4a", "top": "#db7a2d", "hat": "#b02c2c", "bottom": "#425475"},
}

CUSTOMER_VARIANTS = {
    "customer_a2": ("customer_a", {"hair": "#1c1a1a", "skin": "#8d5a3b", "top": "#c9a227", "bottom": "#3b3b45"}),
    "customer_a3": ("customer_a", {"hair": "#8a3b22", "skin": "#fad1b2", "top": "#6a4c93", "bottom": "#232a47"}),
    "customer_a4": ("customer_a", {"hair": "#deaf6e", "skin": "#c68c62", "top": "#c8584f", "bottom": "#2f3e5c"}),
    "customer_b2": ("customer_b", {"hair": "#e6e6e6", "skin": "#7a4e33", "top": "#3f6b45", "bottom": "#77736a"}),
    "customer_b3": ("customer_b", {"hair": "#9a9a9a", "skin": "#c68c62", "top": "#2e3f63", "bottom": "#b09c76"}),
    "customer_b4": ("customer_b", {"hair": "#6e6e6e", "skin": "#fad1b2", "top": "#b8862e", "bottom": "#6b5a46"}),
    "customer_c2": ("customer_c", {"hair": "#4f3426", "skin": "#e0ac85", "top": "#4f8a4a", "hat": "#2e3f63", "bottom": "#425475"}),
    "customer_c3": ("customer_c", {"hair": "#1c1a1a", "skin": "#5e3d2b", "top": "#7d828c", "hat": "#d8b23a", "bottom": "#2b2b33"}),
    "customer_c4": ("customer_c", {"hair": "#8a3b22", "skin": "#f2c9a6", "top": "#7a4f9a", "hat": "#2f8f86", "bottom": "#5d7aa8"}),
}

# --- output ---------------------------------------------------------------------


def frames_tres(name):
    """The SpriteFrames for `name`'s three sheets, from player_frames.tres."""
    template = (SPRITES / "player_frames.tres").read_text(encoding="utf-8")
    for direction in DIRECTIONS:
        template = template.replace(f"res://assets/sprites/player_{direction}.png", f"res://assets/sprites/{name}_{direction}.png")
    return template.encode("utf-8")


def outputs():
    """Every generated file: path -> bytes."""
    files = {}

    def add(name, sheet):
        for direction in DIRECTIONS:
            files[SPRITES / f"{name}_{direction}.png"] = png_bytes(sheet[direction])
        files[SPRITES / f"{name}_frames.tres"] = frames_tres(name)

    short = uniform_short()
    bases = {"short": short, "ponytail": uniform_ponytail(short)}
    for look, (style, hair, skin) in STAFF_LOOKS.items():
        add(look, recolour(bases[style], {PLAYER_HAIR: hair, PLAYER_SKIN: skin}))
    add("regional_manager", recolour(load_sheet("player"), REGIONAL_MANAGER_COLOURS))
    for name, (design, colours) in CUSTOMER_VARIANTS.items():
        roles = CUSTOMER_ROLES[design]
        add(name, recolour(load_sheet(design), {roles[role]: colour for role, colour in colours.items()}))
    return files


def main(argv):
    check = "--check" in argv
    stale = []
    for path, content in outputs().items():
        if check:
            if not path.exists() or path.read_bytes() != content:
                stale.append(path)
        else:
            path.write_bytes(content)
    if check:
        for path in stale:
            print(f"out of date: {path.relative_to(ROOT)}")
        print("art is up to date" if not stale else f"{len(stale)} file(s) out of date; run without --check")
        return 1 if stale else 0
    print(f"wrote {len(outputs())} files to {SPRITES.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
