"""Figures for the report: waveform + wavefront (from build/systolic.vcd), cycles/speed-up
(from build/sweep.csv), resource table (from synth/pnr logs), block diagrams.
Also cross-checks the first matmul in the VCD against numpy.   Run: make sim sweep synth pnr plots"""
import csv, json, os, re
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, Rectangle

OUT = "docs/img"
BLUE, ORANGE = "#2a78d6", "#eb6834"            # validated categorical slots 1, 2
INK, INK2, GRID, SURF = "#0b0b0b", "#52514e", "#e4e3df", "#fcfcfb"
plt.rcParams.update({"font.size": 10, "axes.edgecolor": INK2, "axes.labelcolor": INK2,
                     "xtick.color": INK2, "ytick.color": INK2, "figure.facecolor": "white",
                     "axes.spines.top": False, "axes.spines.right": False})
N = 4
PERIOD, FIRST_EDGE = 10_000, 5_000             # ps, from tb_systolic.v (#5 clock, 1ps precision)


def read_vcd(path):
    """{full.signal.name: [(time, int_or_None), ...]} for every scalar/vector signal."""
    ids, scope, sigs, t = {}, [], {}, 0
    with open(path) as f:
        for line in f:
            w = line.split()
            if not w:
                continue
            if w[0] == "$scope":
                scope.append(w[2])
            elif w[0] == "$upscope":
                scope.pop()
            elif w[0] == "$var":
                name = ".".join(scope + [w[4]])
                ids.setdefault(w[3], []).append(name)
                sigs[name] = []
            elif w[0][0] == "#":
                t = int(w[0][1:])
            elif w[0][0] in "01xz" and len(w) == 1:
                for n in ids.get(w[0][1:], []):
                    sigs[n].append((t, None if w[0][0] in "xz" else int(w[0][0])))
            elif w[0][0] == "b":
                v = None if re.search("[xz]", w[0]) else int(w[0][1:], 2)
                for n in ids.get(w[1], []):
                    sigs[n].append((t, v))
    return sigs


def at(sig, t):
    v = None
    for tt, vv in sig:
        if tt > t:
            break
        v = vv
    return v


def s(v, bits):  # unsigned -> signed
    return v - (1 << bits) if v is not None and v >> (bits - 1) else v


def first_run(sigs):
    top = "tb_systolic.u_sys."
    start = next(t for t, v in sigs["tb_systolic.start"] if v == 1)
    done = next(t for t, v in sigs[top + "done"] if v == 1 and t > start)
    c0 = (start - FIRST_EDGE) // PERIOD + 1          # cycle index of the edge that samples start
    c1 = (done - FIRST_EDGE) // PERIOD + 1
    return c0 - 1, c1 + 2, done


def sample(sig, cyc):  # value held during cycle `cyc` (2 ns after its rising edge)
    return at(sig, FIRST_EDGE + cyc * PERIOD + 2000)


def numpy_check(sigs, done):
    top = "tb_systolic.u_sys."
    t = done + 2000
    a, b, c = at(sigs[top + "a_buf"], t), at(sigs[top + "b_buf"], t), at(sigs[top + "c"], t)
    A = np.array([s((a >> 8 * i) & 0xFF, 8) for i in range(N * N)], dtype=np.int32).reshape(N, N)
    B = np.array([s((b >> 8 * i) & 0xFF, 8) for i in range(N * N)], dtype=np.int32).reshape(N, N)
    C = np.array([s((c >> 32 * i) & 0xFFFFFFFF, 32) for i in range(N * N)], dtype=np.int64).reshape(N, N)
    assert (A @ B == C).all(), f"numpy mismatch\nA={A}\nB={B}\nC={C}\nA@B={A @ B}"
    print("numpy cross-check of first VCD run: A@B == C  OK\n", C)


def waveform(sigs, c0, c1):
    top = "tb_systolic.u_sys."
    names = {0: "IDLE", 1: "CLEAR", 2: "FEED", 3: "DONE"}
    rows = [("clk", None), ("start", sigs["tb_systolic.start"]),
            ("state", sigs[top + "u_ctrl.state"]), ("t", sigs[top + "t"])]
    rows += [(f"a_left[{r}]", ("a", r)) for r in range(N)]
    rows += [(f"b_top[{c}]", ("b", c)) for c in range(N)]
    rows += [("C[0][0]", ("c", 0)), ("C[3][3]", ("c", N * N - 1)), ("done", sigs[top + "done"])]
    fig, ax = plt.subplots(figsize=(13, 0.42 * len(rows) + 0.8))
    for y, (label, sig) in enumerate(rows[::-1]):
        ax.text(c0 - 0.2, y + 0.35, label, ha="right", va="center", color=INK, family="monospace")
        if sig is None:                                    # clock
            for c in range(c0, c1):
                ax.plot([c, c, c + .5, c + .5, c + 1], [y + .05, y + .65, y + .65, y + .05, y + .05], color=INK2, lw=1)
            continue
        if label in ("start", "done"):
            xs, ys = [], []
            for c in range(c0, c1):
                v = sample(sig, c) or 0
                xs += [c, c + 1]; ys += [y + .05 + .6 * v] * 2
            ax.plot(xs, ys, color=BLUE, lw=2)
            continue
        for c in range(c0, c1):
            if isinstance(sig, tuple):
                kind, idx = sig
                bits = 32 if kind == "c" else 8
                raw = sample(sigs[top + {"a": "a_left", "b": "b_top", "c": "c"}[kind]], c)
                v = None if raw is None else s((raw >> bits * idx) & ((1 << bits) - 1), bits)
            else:
                v = sample(sig, c)
            txt = "x" if v is None else names[v] if label == "state" else str(v)
            live = label in ("state", "t") or bool(v)
            ax.add_patch(Rectangle((c + .04, y + .05), .92, .6, fc=(BLUE if live else SURF), alpha=.18 if live else 1,
                                   ec=INK2, lw=.6))
            ax.text(c + .5, y + .35, txt, ha="center", va="center", fontsize=7.5, color=INK)
    ax.set_xlim(c0 - 2.2, c1); ax.set_ylim(-.2, len(rows))
    ax.set_yticks([]); ax.spines["left"].set_visible(False)
    ax.set_xticks(range(c0, c1 + 1, 1)); ax.set_xlabel("clock cycle")
    ax.set_title(f"First {N}x{N} run: skewed operands enter the array (A[i][t-i], B[t-j][j]); "
                 "highlighted = non-zero", loc="left", color=INK)
    fig.tight_layout(); fig.savefig(f"{OUT}/waveform.png", dpi=150); plt.close(fig)


def wavefront(sigs, c0, c1):
    """Which PEs do a useful MAC at each systolic step t (labelled with k)."""
    top = "tb_systolic.u_sys."
    feed = [c for c in range(c0, c1) if sample(sigs[top + "u_ctrl.state"], c) == 2]
    fig, axes = plt.subplots(1, len(feed), figsize=(1.25 * len(feed), 2.0))
    for ax, c in zip(axes, feed):
        t = sample(sigs[top + "t"], c)
        for i in range(N):
            for j in range(N):
                pe = f"{top}u_array.g_row[{i}].g_col[{j}].u_pe."
                a, b = sample(sigs[pe + "a_in"], c), sample(sigs[pe + "b_in"], c)
                on = bool(a) and bool(b)
                ax.add_patch(Rectangle((j, N - 1 - i), .9, .9, fc=BLUE if on else SURF, ec=INK2, lw=.5))
                if on:
                    ax.text(j + .45, N - 1 - i + .45, f"k={t - i - j}", ha="center", va="center", fontsize=6, color="white")
        ax.set_xlim(-.1, N); ax.set_ylim(-.1, N); ax.set_aspect("equal"); ax.axis("off")
        ax.set_title(f"t={t}", fontsize=9, color=INK)
    fig.suptitle("Diagonal wavefront: PE(i,j) multiplies A[i][k]*B[k][j] at step t = i+j+k", color=INK, x=.01, ha="left")
    fig.tight_layout(); fig.savefig(f"{OUT}/wavefront.png", dpi=150); plt.close(fig)


def sweep_charts():
    rows = list(csv.DictReader(open("build/sweep.csv")))
    n = [int(r["N"]) for r in rows]
    sy = [int(r["systolic"]) for r in rows]
    sq = [int(r["sequential"]) for r in rows]
    fig, ax = plt.subplots(figsize=(6.4, 4))
    ax.plot(n, sq, "-o", color=ORANGE, lw=2, ms=8, label="sequential (1 MAC): N³+1")
    ax.plot(n, sy, "-o", color=BLUE, lw=2, ms=8, label="systolic (N² PEs): 3N")
    for x, a, b in zip(n, sy, sq):
        ax.annotate(str(b), (x, b), textcoords="offset points", xytext=(6, 4), color=INK2, fontsize=9)
        ax.annotate(str(a), (x, a), textcoords="offset points", xytext=(6, -12), color=INK2, fontsize=9)
    ax.set_yscale("log"); ax.set_xticks(n); ax.set_xlabel("matrix size N"); ax.set_ylabel("cycles per matmul (log)")
    ax.grid(axis="y", color=GRID, lw=.8); ax.legend(frameon=False)
    ax.set_title("Measured cycles, start to done", loc="left", color=INK)
    fig.tight_layout(); fig.savefig(f"{OUT}/cycles_vs_n.png", dpi=150); plt.close(fig)

    fig, ax = plt.subplots(figsize=(6.4, 4))
    sp = [b / a for a, b in zip(sy, sq)]
    bars = ax.bar([str(x) for x in n], sp, width=.55, color=BLUE)
    ax.bar_label(bars, labels=[f"{v:.1f}x" for v in sp], padding=3, color=INK)
    ax.set_xlabel("matrix size N"); ax.set_ylabel("speed-up (sequential / systolic cycles)")
    ax.grid(axis="y", color=GRID, lw=.8); ax.set_axisbelow(True)
    ax.set_title("Speed-up in cycles grows as ~N²/3", loc="left", color=INK)
    fig.tight_layout(); fig.savefig(f"{OUT}/speedup.png", dpi=150); plt.close(fig)
    return dict(zip(n, zip(sy, sq)))


def resources():
    """Table image of synth_xilinx + nextpnr-ice40 numbers (skipped if logs are missing)."""
    rows = []
    for t in ("systolic_top", "seq_matmul"):
        try:
            stat = open(f"build/xilinx_{t}.stat").read()
            pnr = json.load(open(f"build/{t}_pnr.json"))
        except FileNotFoundError:
            print("no synth/pnr results yet, skipping resources.png"); return None
        cnt = lambda pat: sum(int(m) for m in re.findall(rf"^\s+(\d+)\s+{pat}\s*$", stat, re.M))
        fmax = list(pnr["fmax"].values())[0]["achieved"]
        lc = pnr["utilization"]["ICESTORM_LC"]
        rows.append([t, cnt(r"LUT\d"), cnt(r"FD\w+"), cnt(r"DSP48\w*"), f'{lc["used"]} / {lc["available"]}', f"{fmax:.1f}"])
    fig, ax = plt.subplots(figsize=(8.5, 1.4)); ax.axis("off")
    tb = ax.table(cellText=rows, colLabels=["design", "Xilinx LUT", "Xilinx FF", "Xilinx DSP48",
                                            "iCE40 HX8K LC", "iCE40 Fmax (MHz)"], loc="center", cellLoc="center")
    tb.scale(1, 1.6)
    for (r, _), cell in tb.get_celld().items():
        cell.set_edgecolor(GRID)
        if r == 0: cell.set_text_props(weight="bold", color=INK)
    fig.tight_layout(); fig.savefig(f"{OUT}/resources.png", dpi=150); plt.close(fig)
    return rows


# ---------------------------------------------------------------- block diagrams
def box(ax, x, y, w, h, text, fc="white", fs=9):
    ax.add_patch(Rectangle((x, y), w, h, fc=fc, ec=INK2, lw=1.2))
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", fontsize=fs, color=INK)


def arrow(ax, p, q, text="", off=(0, .12), color=INK2):
    ax.add_patch(FancyArrowPatch(p, q, arrowstyle="-|>", mutation_scale=11, color=color, lw=1.2))
    if text:
        ax.text((p[0] + q[0]) / 2 + off[0], (p[1] + q[1]) / 2 + off[1], text, ha="center", fontsize=7.5, color=INK2)


def block_diagram_top():
    fig, ax = plt.subplots(figsize=(13, 6.2)); ax.set_xlim(0, 13); ax.set_ylim(0, 6.2); ax.axis("off")
    box(ax, .1, 2.2, 1.7, 1.8, "Matrix data\ninterface\n\nwe, sel,\naddr, din", fc="#eef4fc")
    box(ax, 2.4, 3.3, 1.6, 1.1, "A buffer\nN×N × INT8")
    box(ax, 2.4, 1.6, 1.6, 1.1, "B buffer\nN×N × INT8")
    arrow(ax, (1.8, 3.4), (2.4, 3.85)); arrow(ax, (1.8, 2.8), (2.4, 2.15))
    box(ax, 4.6, 1.6, 1.8, 2.8, "Skew by\nindexing\n\nrow i: A[i][t−i]\ncol j: B[t−j][j]\n(0 if out of range)", fc="#eef4fc", fs=8.5)
    arrow(ax, (4.0, 3.85), (4.6, 3.85)); arrow(ax, (4.0, 2.15), (4.6, 2.15))
    gx, gy, cs = 7.6, 1.0, .95                                      # PE grid
    for i in range(N):
        for j in range(N):
            x, y = gx + j * cs, gy + (N - 1 - i) * cs
            box(ax, x, y, .7, .7, f"PE\n{i},{j}", fs=7)
            if j < N - 1: arrow(ax, (x + .7, y + .35), (x + cs, y + .35), color=ORANGE)
            if i < N - 1: arrow(ax, (x + .35, y), (x + .35, y - cs + .7), color=BLUE)
        arrow(ax, (6.4, gy + (N - 1 - i) * cs + .35), (gx, gy + (N - 1 - i) * cs + .35), color=ORANGE)
        arrow(ax, (gx + i * cs + .35, 5.3), (gx + i * cs + .35, gy + (N - 1) * cs + .7), color=BLUE)
    ax.text(6.95, 4.75, "a_left[i]  →", fontsize=8, color=ORANGE, ha="center")
    ax.plot([5.5, 5.5, gx + (N - 1) * cs + .35], [4.4, 5.3, 5.3], color=BLUE, lw=1.2)
    ax.text(9.0, 5.45, "b_top[j]  ↓", fontsize=8, color=BLUE, ha="center")
    ax.text(gx + 1.8, .55, "4×4 output-stationary PE array\n(C[i][j] stays in PE(i,j)'s accumulator)", ha="center", fontsize=8, color=INK2)
    box(ax, 11.6, 2.2, 1.3, 1.8, "C read port\n\nrd_addr →\nrd_data\n(INT32)", fc="#eef4fc")
    arrow(ax, (gx + N * cs - .25, 3.1), (11.6, 3.1)); ax.text(11.6, 4.15, "acc ×16 (INT32)", fontsize=7.5, color=INK2)
    box(ax, 4.6, .1, 1.8, 1.0, "Controller FSM\nIDLE→CLEAR→\nFEED→DONE", fc="#fdf0ea", fs=8)
    arrow(ax, (5.5, 1.1), (5.5, 1.6), "t", off=(.12, -.05))
    arrow(ax, (6.4, .6), (gx, .6), "clr, en", off=(0, .08))
    ax.plot([gx, gx + .1], [.6, .6], color=INK2)
    arrow(ax, (1.0, .6), (4.6, .6), "start", off=(0, .08)); arrow(ax, (4.6, .35), (1.0, .35), "done", off=(0, -.28))
    ax.set_title("systolic_top: block diagram", loc="left", color=INK, fontsize=12)
    fig.tight_layout(); fig.savefig(f"{OUT}/block_diagram_top.png", dpi=150); fig.savefig(f"{OUT}/block_diagram_top.svg"); plt.close(fig)


def block_diagram_pe():
    fig, ax = plt.subplots(figsize=(9, 5)); ax.set_xlim(0, 9); ax.set_ylim(0, 5); ax.axis("off")
    ax.add_patch(Rectangle((1.2, .4), 6.4, 4.0, fc="none", ec=INK2, lw=1, ls="--"))
    ax.text(1.3, 4.2, "PE(i,j)", fontsize=10, color=INK, va="top")
    box(ax, 5.8, 3.2, 1.2, .7, "a_out reg\n8b", fs=8); box(ax, 2.0, .9, 1.2, .7, "b_out reg\n8b", fs=8)
    arrow(ax, (.2, 3.55), (5.8, 3.55), "a_in (INT8)", off=(-4.2, .12), color=ORANGE)
    arrow(ax, (7.0, 3.55), (8.8, 3.55), "a_out → PE(i,j+1)", off=(0, .12), color=ORANGE)
    arrow(ax, (2.6, 4.9), (2.6, 1.6), "b_in", off=(-.3, 1.4), color=BLUE)
    arrow(ax, (2.6, .9), (2.6, .05), "", color=BLUE); ax.text(2.7, .1, "b_out → PE(i+1,j)", fontsize=7.5, color=BLUE)
    ax.add_patch(Rectangle((3.4, 1.0), 2.45, 2.0, fc="#eef4fc", ec=INK2, lw=1)); ax.text(3.5, 2.85, "mac", fontsize=8, color=INK2, va="top")
    box(ax, 3.7, 1.6, .7, .7, "×", fs=14); box(ax, 4.9, 1.6, .7, .7, "+", fs=14)
    arrow(ax, (3.9, 3.55), (3.9, 2.3)); arrow(ax, (2.6, 2.0), (3.7, 2.0)); ax.plot([2.6], [2.0], "o", color=BLUE, ms=4)
    ax.plot([3.9], [3.55], "o", color=ORANGE, ms=4)
    arrow(ax, (4.4, 1.95), (4.9, 1.95), "16b", off=(0, .08))
    box(ax, 6.1, 1.6, 1.0, .7, "acc reg\n32b", fs=8)
    arrow(ax, (5.6, 1.95), (6.1, 1.95), "32b", off=(0, .08))
    ax.plot([7.1, 7.3, 7.3, 5.25, 5.25], [1.95, 1.95, 1.25, 1.25, 1.6], color=INK2, lw=1.2)
    arrow(ax, (7.3, 1.95), (8.8, 1.95), "acc = C[i][j]", off=(0, .12))
    ax.text(4.3, .55, "clr: acc, a_out, b_out ← 0      en: all three registers load      else: hold", fontsize=8, color=INK2, ha="center")
    ax.set_title("Processing element: signed INT8 × INT8 → 16b product, 32b accumulate", loc="left", color=INK, fontsize=11)
    fig.tight_layout(); fig.savefig(f"{OUT}/block_diagram_pe.png", dpi=150); fig.savefig(f"{OUT}/block_diagram_pe.svg"); plt.close(fig)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    sigs = read_vcd("build/systolic.vcd")
    c0, c1, done = first_run(sigs)
    numpy_check(sigs, done)
    waveform(sigs, c0, c1)
    wavefront(sigs, c0, c1)
    print("sweep:", sweep_charts())
    print("resources:", resources())
    block_diagram_top(); block_diagram_pe()
    print("wrote", sorted(os.listdir(OUT)))
