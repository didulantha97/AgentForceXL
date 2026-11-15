import { LightningElement, api } from "lwc";

/*
 * Dependency-free SVG chart for the PMS home pages: bar, hbar, line and donut.
 * - Colours: the validated default data-viz palette (categorical order is fixed, never cycled).
 *   Project health uses the reserved status colours, always with a text label.
 * - Every chart has a hover tooltip, and a table view for screen readers and exact values.
 */

const W = 480;
const H = 220;
const PAD = { top: 12, right: 12, bottom: 28, left: 48 };
const CATEGORICAL = [
  "#2a78d6",
  "#eb6834",
  "#1baf7a",
  "#eda100",
  "#e87ba4",
  "#008300",
  "#6250d6",
  "#e34948"
];
const STATUS = { Green: "#0ca30c", Amber: "#fab219", Red: "#d03b3b" };
const SERIES = "#2a78d6";
const MAX_SLICES = 6;

function niceMax(v) {
  if (!v || v <= 0) return 1;
  const exp = Math.pow(10, Math.floor(Math.log10(v)));
  const f = v / exp;
  const step = f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 5 ? 5 : 10;
  return step * exp;
}

/** Column path with a 4px rounded top and a square baseline. */
function columnPath(x, y, w, h) {
  const r = Math.min(4, w / 2, h);
  if (h <= 0) return "";
  return `M${x},${y + h} L${x},${y + r} Q${x},${y} ${x + r},${y} L${x + w - r},${y} Q${x + w},${y} ${x + w},${y + r} L${x + w},${y + h} Z`;
}

/** Horizontal bar path with a 4px rounded right end and a square baseline. */
function barPath(x, y, w, h) {
  const r = Math.min(4, h / 2, w);
  if (w <= 0) return "";
  return `M${x},${y} L${x + w - r},${y} Q${x + w},${y} ${x + w},${y + r} L${x + w},${y + h - r} Q${x + w},${y + h} ${x + w - r},${y + h} L${x},${y + h} Z`;
}

function arc(cx, cy, rOuter, rInner, a0, a1) {
  const large = a1 - a0 > Math.PI ? 1 : 0;
  const p = (r, a) => `${cx + r * Math.sin(a)},${cy - r * Math.cos(a)}`;
  return `M${p(rOuter, a0)} A${rOuter},${rOuter} 0 ${large} 1 ${p(rOuter, a1)} L${p(rInner, a1)} A${rInner},${rInner} 0 ${large} 0 ${p(rInner, a0)} Z`;
}

export default class PmsHomeChart extends LightningElement {
  @api chart;
  @api currencyCode = "SEK";

  showTable = false;
  tip;

  get viewBox() {
    return this.isDonut ? "0 0 220 220" : `0 0 ${W} ${H}`;
  }
  get isBar() {
    return this.chart?.type === "bar";
  }
  get isHbar() {
    return this.chart?.type === "hbar";
  }
  get isLine() {
    return this.chart?.type === "line";
  }
  get isDonut() {
    return this.chart?.type === "donut";
  }
  get isEmpty() {
    const v = this.chart?.values || [];
    return v.length === 0 || v.every((n) => !n);
  }
  get tableLabel() {
    return this.showTable ? "Show chart" : "Show table";
  }
  get ariaLabel() {
    const c = this.chart || {};
    const parts = (c.labels || []).map(
      (l, i) => `${l}: ${this.fmt(c.values[i])}`
    );
    return `${c.title}. ${parts.join(", ")}`;
  }

  // ---------------------------------------------------------------- formatting

  fmt(v, compact) {
    const n = Number(v) || 0;
    const f = this.chart?.format;
    try {
      if (f === "money") {
        return new Intl.NumberFormat(undefined, {
          style: "currency",
          currency: this.currencyCode || "SEK",
          maximumFractionDigits: compact || Math.abs(n) >= 1000 ? 0 : 2,
          notation: compact ? "compact" : "standard"
        }).format(n);
      }
    } catch {
      // unknown currency code: fall through to a plain number
    }
    if (f === "percent") return `${Math.round(n)}%`;
    if (f === "hours")
      return `${new Intl.NumberFormat(undefined, { maximumFractionDigits: 1 }).format(n)} h`;
    return new Intl.NumberFormat(undefined, {
      notation: compact ? "compact" : "standard",
      maximumFractionDigits: 1
    }).format(n);
  }

  get rows() {
    const c = this.chart || {};
    return (c.labels || []).map((l, i) => ({
      key: `${i}`,
      label: l,
      value: this.fmt(c.values[i])
    }));
  }

  // ---------------------------------------------------------------- axes

  get yMax() {
    const values = this.chart?.values || [];
    const max = Math.max(0, ...values.map((v) => Number(v) || 0));
    return this.chart?.format === "percent"
      ? Math.max(100, niceMax(max))
      : niceMax(max);
  }

  get gridLines() {
    const max = this.yMax;
    const plotH = H - PAD.top - PAD.bottom;
    return [0, 0.25, 0.5, 0.75, 1].map((t) => {
      const y = PAD.top + plotH * (1 - t);
      return {
        key: `g${t}`,
        y,
        x1: PAD.left,
        x2: W - PAD.right,
        labelX: PAD.left - 6,
        labelY: y + 4,
        label: this.fmt(max * t, true)
      };
    });
  }

  get xLabels() {
    const c = this.chart || {};
    const n = (c.labels || []).length;
    const plotW = W - PAD.left - PAD.right;
    const band = plotW / Math.max(1, n);
    const every = n > 10 ? 2 : 1;
    return (c.labels || [])
      .map((l, i) => ({
        key: `x${i}`,
        label: l,
        x: PAD.left + band * i + band / 2,
        y: H - 8,
        show: i % every === 0
      }))
      .filter((l) => l.show);
  }

  // ---------------------------------------------------------------- bar

  get bars() {
    const c = this.chart || {};
    const n = (c.values || []).length;
    const plotW = W - PAD.left - PAD.right;
    const plotH = H - PAD.top - PAD.bottom;
    const band = plotW / Math.max(1, n);
    const bw = Math.min(24, band - 2);
    const max = this.yMax;
    return (c.values || []).map((v, i) => {
      const val = Math.max(0, Number(v) || 0);
      const h = (val / max) * plotH;
      const x = PAD.left + band * i + (band - bw) / 2;
      const y = PAD.top + plotH - h;
      return {
        key: `b${i}`,
        index: i,
        d: columnPath(x, y, bw, h),
        hitX: PAD.left + band * i,
        hitW: band,
        hitY: PAD.top,
        hitH: plotH,
        fill: SERIES,
        tipX: x + bw / 2,
        tipY: y
      };
    });
  }

  // ---------------------------------------------------------------- hbar

  get hbars() {
    const c = this.chart || {};
    const n = (c.values || []).length;
    const labelW = 128;
    const valueW = 64;
    const rowH = Math.min(28, (H - 8) / Math.max(1, n));
    const bh = Math.min(16, rowH - 6);
    const plotW = W - labelW - valueW;
    const max =
      this.chart?.format === "percent"
        ? Math.max(100, ...(c.values || []).map((v) => Number(v) || 0))
        : Math.max(1, ...(c.values || []).map((v) => Number(v) || 0));
    return (c.values || []).map((v, i) => {
      const val = Math.max(0, Number(v) || 0);
      const w = (val / max) * plotW;
      const y = 4 + rowH * i + (rowH - bh) / 2;
      const label = c.labels[i] || "";
      return {
        key: `h${i}`,
        index: i,
        d: barPath(labelW, y, w, bh),
        track: barPath(labelW, y, plotW, bh),
        label: label.length > 20 ? `${label.slice(0, 19)}…` : label,
        labelY: y + bh / 2 + 4,
        valueX: labelW + plotW + 6,
        value: this.fmt(val),
        fill: c.format === "percent" && val > 100 ? STATUS.Red : SERIES,
        hitY: 4 + rowH * i,
        hitH: rowH,
        tipX: labelW + w,
        tipY: y
      };
    });
  }

  // ---------------------------------------------------------------- line

  get linePoints() {
    const c = this.chart || {};
    const n = (c.values || []).length;
    const plotW = W - PAD.left - PAD.right;
    const plotH = H - PAD.top - PAD.bottom;
    const band = plotW / Math.max(1, n);
    const max = this.yMax;
    return (c.values || []).map((v, i) => ({
      key: `p${i}`,
      index: i,
      x: PAD.left + band * i + band / 2,
      y: PAD.top + plotH - (Math.max(0, Number(v) || 0) / max) * plotH,
      hitX: PAD.left + band * i,
      hitW: band
    }));
  }
  get linePath() {
    return this.linePoints
      .map((p, i) => `${i ? "L" : "M"}${p.x},${p.y}`)
      .join(" ");
  }
  get areaPath() {
    const pts = this.linePoints;
    if (!pts.length) return "";
    const base = H - PAD.bottom;
    return `${this.linePath} L${pts[pts.length - 1].x},${base} L${pts[0].x},${base} Z`;
  }
  get hoverPoint() {
    return this.tip && this.isLine ? this.linePoints[this.tip.index] : null;
  }
  get crosshairY1() {
    return PAD.top;
  }
  get crosshairY2() {
    return H - PAD.bottom;
  }

  // ---------------------------------------------------------------- donut

  get slices() {
    const c = this.chart || {};
    let items = (c.labels || []).map((l, i) => ({
      label: l,
      value: Math.max(0, Number(c.values[i]) || 0)
    }));
    if (items.length > MAX_SLICES) {
      const keep = items.slice(0, MAX_SLICES - 1);
      const rest = items.slice(MAX_SLICES - 1).reduce((s, x) => s + x.value, 0);
      items = [...keep, { label: "Other", value: rest }];
    }
    const total = items.reduce((s, x) => s + x.value, 0) || 1;
    const gap = items.filter((x) => x.value > 0).length > 1 ? 0.02 : 0;
    let a = 0;
    const statusMode = c.key === "health";
    return items.map((x, i) => {
      const sweep = (x.value / total) * Math.PI * 2;
      const a0 = a + gap / 2;
      const a1 = a + sweep - gap / 2;
      a += sweep;
      const color = statusMode ? STATUS[x.label] || "#8a8986" : CATEGORICAL[i];
      return {
        key: `s${i}`,
        index: i,
        d:
          x.value > 0 && a1 > a0
            ? arc(110, 110, 96, 66, a0, Math.min(a1, a0 + Math.PI * 2 - 0.0001))
            : "",
        color,
        swatchStyle: `background:${color}`,
        label: x.label,
        value: this.fmt(x.value),
        share: `${Math.round((x.value / total) * 100)}%`
      };
    });
  }
  get donutTotal() {
    const sum = (this.chart?.values || []).reduce(
      (s, v) => s + (Number(v) || 0),
      0
    );
    return this.fmt(sum, true);
  }

  // ---------------------------------------------------------------- hover

  get tipStyle() {
    if (!this.tip) return "display:none";
    const box = this.isDonut ? 220 : W;
    const boxH = this.isDonut ? 220 : H;
    const left = Math.min(85, Math.max(5, (this.tip.x / box) * 100));
    const top = Math.max(0, (this.tip.y / boxH) * 100);
    return `left:${left}%;top:${top}%`;
  }
  get tipLabel() {
    if (!this.tip) return "";
    return this.isDonut
      ? this.slices[this.tip.index].label
      : this.chart.labels[this.tip.index];
  }
  get tipValue() {
    if (!this.tip) return "";
    if (this.isDonut) {
      const s = this.slices[this.tip.index];
      return `${s.value} (${s.share})`;
    }
    return this.fmt(this.chart.values[this.tip.index]);
  }
  get plotClass() {
    return this.isDonut ? "plot plot-donut" : "plot";
  }

  handleEnter(evt) {
    const i = Number(evt.currentTarget.dataset.index);
    let x;
    let y;
    if (this.isBar) {
      ({ tipX: x, tipY: y } = this.bars[i]);
    } else if (this.isHbar) {
      ({ tipX: x, tipY: y } = this.hbars[i]);
    } else if (this.isLine) {
      ({ x, y } = this.linePoints[i]);
    } else {
      x = 110;
      y = 30;
    }
    this.tip = { index: i, x, y };
  }
  handleLeave() {
    this.tip = null;
  }
  toggleTable() {
    this.showTable = !this.showTable;
  }
}
