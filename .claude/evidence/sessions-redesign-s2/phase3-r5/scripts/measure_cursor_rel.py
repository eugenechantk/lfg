"""Cursor block vs ascender glyph in the same row (board 'l' of lfg, app 'h' of sh)."""
from px import *

B = load("board/board-kbo-fit-3x.png"); A = load("app/term-fit-kbup.png")
print("board fit 'l'", pt(bbox_lum(B, int(91.5 * 3), int(494 * 3), int(98.7 * 3), int(516 * 3), 90)))
print("board fit cursor DOM: y 497.609..511.609 (x 134.859 w 7.234)")
print("app fit 'h'", pt(bbox_lum(A, int(19.4 * 3), int(202 * 3), int(26.8 * 3), int(224 * 3), 90)))
Bw = load("board/board-kbo-wide-3x.png"); Aw = load("app/term-wide-kbup.png")
print("board wide 'l'", pt(bbox_lum(Bw, int((12 + 11 * 6.328) * 3), int(497 * 3), int((12 + 12 * 6.328) * 3), int(515 * 3), 90)))
print("app wide 'h'", pt(bbox_lum(Aw, int((12 + 6.49) * 3), int(188 * 3), int((12 + 2 * 6.49) * 3), int(206 * 3), 90)))
