"""Round-1 fix checks: time-column unit letters, the title-bar line, the collapsed state."""
from PIL import Image

S = "/private/tmp/claude-501/-Users-eugenechan-dev-personal-lfg/68284ba9-8aab-498d-9c6e-4a97fab2832f/scratchpad/snaps/"
E = "/Users/eugenechan/dev/personal/lfg/.claude/worktrees/sessions-redesign-s2/.claude/evidence/sessions-redesign-s2/phase4-r1/"
board = Image.open(S + "board-dA2-1x.png").convert("RGB")
app = Image.open(S + "d5-srgb.png").convert("RGB")


def columns(im, y0, y1, x0=14, x1=50, th=90):
    """x runs of ink in a band (separates the digit from the unit letter)."""
    cols = [x for x in range(x0, x1) if any(sum(im.getpixel((x, y))) / 3 > th for y in range(y0, y1))]
    runs, start = [], None
    for i, x in enumerate(cols):
        if start is None:
            start = x
        if i == len(cols) - 1 or cols[i + 1] != x + 1:
            runs.append((start, x + 1)); start = None
    return runs


for label, (y0, y1) in [("2m", (136, 146)), ("6m", (211, 221)), ("1m", (324, 334)), ("4m", (399, 409)),
                        ("9m", (474, 484)), ("3h", (586, 596)), ("1d", (661, 671)), ("2d", (736, 746))]:
    print(f"{label}: board {columns(board, y0, y1)}  app {columns(app, y0, y1)}")

print("title-bar line x=150:", [app.getpixel((150, y)) for y in range(49, 54)])

bc = Image.open(E + "board-working-collapsed-438x942.png").convert("RGB")
ac = Image.open(S + "d5c-srgb.png").convert("RGB")
for name, im in (("board collapsed", bc), ("app collapsed", ac)):
    ys, prev = [], None
    for y in range(40, 860):
        p = im.getpixel((330, y))
        line = 38 <= p[0] <= 50 and abs(p[0] - p[2]) <= 4
        if line and not prev:
            ys.append(y)
        prev = line
    print(name, "separators", ys)
