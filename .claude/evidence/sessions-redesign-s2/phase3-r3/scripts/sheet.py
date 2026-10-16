"""Sheet-pt helpers. Board: 3x render, sheet top `btop` pt, x = px/3. App: frames with geom.json
(L, T px; s scale) -> sheet pt = (px/3 - L/3)/s, (px/3 - T/3)/s. Laid-out sheet width: board 390, app 402."""
import json, os
import numpy as np
from lib import E, load, runs_of, modal

G = json.load(open(os.path.join(E, "scripts", "geom.json")))


class Sheet:
    def __init__(self, kind, img, btop=None, gname=None):
        self.kind = kind
        self.a = load(img)
        if kind == "board":
            self.L, self.T, self.s = 0.0, btop * 3.0, 1.0
            self.W = 390
        else:
            g = G[gname]
            self.L, self.T, self.s = float(g["L"]), float(g["T"]), g["s"]
            self.W = 402

    def px(self, x, y):
        return int(round(self.L + x * 3 * self.s)), int(round(self.T + y * 3 * self.s))

    def ptx(self, X):
        return round((X - self.L) / 3 / self.s, 2)

    def pty(self, Y):
        return round((Y - self.T) / 3 / self.s, 2)

    def box(self, x0, y0, x1, y1):
        X0, Y0 = self.px(x0, y0); X1, Y1 = self.px(x1, y1)
        return X0, Y0, max(X1, X0 + 1), max(Y1, Y0 + 1)

    def rows(self, x0, y0, x1, y1, thr=30, bg=None):
        X0, Y0, X1, Y1 = self.box(x0, y0, x1, y1)
        reg = self.a[Y0:Y1, X0:X1]
        b = modal(reg) if bg is None else np.array(bg)
        m = np.abs(reg - b).max(axis=2) > thr
        out = []
        for s, e in runs_of(m.any(axis=1)):
            xs = np.where(m[s:e + 1].any(axis=0))[0]
            out.append((self.pty(Y0 + s), self.pty(Y0 + e + 1), self.ptx(X0 + xs.min()), self.ptx(X0 + xs.max() + 1)))
        return out, b.tolist()

    def cols(self, x0, y0, x1, y1, thr=30, bg=None):
        X0, Y0, X1, Y1 = self.box(x0, y0, x1, y1)
        reg = self.a[Y0:Y1, X0:X1]
        b = modal(reg) if bg is None else np.array(bg)
        m = np.abs(reg - b).max(axis=2) > thr
        out = []
        for s, e in runs_of(m.any(axis=0)):
            ys = np.where(m[:, s:e + 1].any(axis=1))[0]
            out.append((self.ptx(X0 + s), self.ptx(X0 + e + 1), self.pty(Y0 + ys.min()), self.pty(Y0 + ys.max() + 1)))
        return out, b.tolist()

    def bbox(self, x0, y0, x1, y1, thr=30, bg=None):
        X0, Y0, X1, Y1 = self.box(x0, y0, x1, y1)
        reg = self.a[Y0:Y1, X0:X1]
        b = modal(reg) if bg is None else np.array(bg)
        m = np.abs(reg - b).max(axis=2) > thr
        ys, xs = np.where(m)
        if len(xs) == 0:
            return None
        return (self.ptx(X0 + xs.min()), self.pty(Y0 + ys.min()), self.ptx(X0 + xs.max() + 1), self.pty(Y0 + ys.max() + 1))

    def vscan(self, x, y0, y1, thr=4):
        X, Y0 = self.px(x, y0); _, Y1 = self.px(x, y1)
        col = self.a[Y0:Y1, X]
        out = []
        for i in range(1, len(col)):
            if np.abs(col[i] - col[i - 1]).max() > thr:
                out.append((self.pty(Y0 + i), col[i - 1].tolist(), col[i].tolist()))
        return out

    def hscan(self, y, x0, x1, thr=4):
        X0, Y = self.px(x0, y); X1, _ = self.px(x1, y)
        row = self.a[Y, X0:X1]
        out = []
        for i in range(1, len(row)):
            if np.abs(row[i] - row[i - 1]).max() > thr:
                out.append((self.ptx(X0 + i), row[i - 1].tolist(), row[i].tolist()))
        return out

    def sample(self, x, y):
        X, Y = self.px(x, y)
        return self.a[Y, X].tolist()

    def peak(self, x0, y0, x1, y1):
        X0, Y0, X1, Y1 = self.box(x0, y0, x1, y1)
        reg = self.a[Y0:Y1, X0:X1].reshape(-1, 3)
        i = reg.max(axis=1).argmax()
        return reg[i].tolist()


def both(fn, label, *args, app_args=None, **kw):
    """Run fn on board and app and print side by side."""
    pass
