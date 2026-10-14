// 8.3, tools/sandbox-map: lays out the map sheet (design/sandbox/map.png): the overview from above (north to the left,
// screen right = +Z, screen up = +X), plot 1 up close (its warehouse's roof off) and the labels, their spots from the
// export's facts (shared/SandboxMap.luau, SandboxLeadersRules.spot). data = { world: [part], van: [part], facts }
(function () {
  const FONT = "Montserrat, 'DejaVu Sans', sans-serif";
  const INK = '#1f2328', ORANGE = '#f0842c', WHITE = '#ffffff', CREAM = '#fff6e8';
  const ROOF = /^(Roof|Gable|Barge|Ridge|Gutter|Rib|Downpipe|Beam|Lamp|Parapet|Cornice|Header|DoorPanel|Skylight|Solar|Vault|Truss)/;

  let measurer = null;
  function textWidth(text, size, weight) {
    if (!measurer) measurer = document.createElement('canvas').getContext('2d');
    measurer.font = `${weight} ${size}px ${FONT}`;
    return measurer.measureText(text).width;
  }
  function el(svg, name, attrs, text) {
    const e = document.createElementNS('http://www.w3.org/2000/svg', name);
    for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v);
    if (text !== undefined) e.textContent = text;
    svg.appendChild(e);
    return e;
  }

  // A pill label. lines: [{ text, size, weight, color }]; at: [x, y] of its anchor corner (align: 'l' | 'c' | 'r',
  // valign: 't' | 'm' | 'b'); to: optional [x, y] the leader line points at (a dot there).
  const F = 1.2; // every label's words this much bigger (the sheet is read scaled down)
  function pillHeight(lines, padY = 9) {
    return lines.reduce((h, l) => h + l.size * F * 1.18, 0) + 4 * (lines.length - 1) + 2 * padY;
  }
  function pill(svg, lines, at, opts = {}) {
    lines = lines.map(l => ({ ...l, size: l.size * F }));
    const padX = opts.padX ?? 14, padY = opts.padY ?? 9, gap = 4;
    let w = 0, h = 0;
    for (const l of lines) {
      w = Math.max(w, textWidth(l.text, l.size, l.weight || 700));
      h += l.size * 1.18;
    }
    h += gap * (lines.length - 1);
    const bw = w + 2 * padX, bh = h + 2 * padY;
    const align = opts.align || 'l', valign = opts.valign || 'm';
    let x = at[0] - (align === 'c' ? bw / 2 : align === 'r' ? bw : 0);
    let y = at[1] - (valign === 'm' ? bh / 2 : valign === 'b' ? bh : 0);
    if (opts.to) {
      const tx = opts.to[0], ty = opts.to[1];
      const ex = Math.max(x, Math.min(tx, x + bw)), ey = Math.max(y, Math.min(ty, y + bh));
      el(svg, 'line', { x1: ex, y1: ey, x2: tx, y2: ty, stroke: WHITE, 'stroke-width': 6, 'stroke-linecap': 'round', opacity: 0.85 });
      el(svg, 'line', { x1: ex, y1: ey, x2: tx, y2: ty, stroke: opts.lineColor || ORANGE, 'stroke-width': 3, 'stroke-linecap': 'round' });
      el(svg, 'circle', { cx: tx, cy: ty, r: 7, fill: opts.lineColor || ORANGE, stroke: WHITE, 'stroke-width': 3 });
    }
    el(svg, 'rect', { x, y, width: bw, height: bh, rx: 9, fill: opts.fill || INK, 'fill-opacity': opts.opacity ?? 0.92, stroke: opts.stroke || 'none', 'stroke-width': 2 });
    let ty = y + padY;
    for (const l of lines) {
      ty += l.size * 0.98;
      const tx = align === 'c' ? x + bw / 2 : x + padX;
      el(svg, 'text', { x: tx, y: ty, 'font-family': FONT, 'font-size': l.size, 'font-weight': l.weight || 700, fill: l.color || WHITE, 'text-anchor': align === 'c' ? 'middle' : 'start' }, l.text);
      ty += l.size * 0.2 + gap;
    }
    return { x, y, w: bw, h: bh };
  }
  // Words on the map itself (a road's name): white with a dark edge.
  function roadText(svg, text, x, y, size, rotate) {
    const attrs = { x, y, 'font-family': FONT, 'font-size': size * F, 'font-weight': 800, 'text-anchor': 'middle', 'dominant-baseline': 'middle', 'letter-spacing': 3 };
    if (rotate) attrs.transform = `rotate(${rotate} ${x} ${y})`;
    el(svg, 'text', { ...attrs, fill: 'none', stroke: INK, 'stroke-width': 6, 'stroke-linejoin': 'round', opacity: 0.75 }, text);
    el(svg, 'text', { ...attrs, fill: WHITE }, text);
  }

  window.compose = function (data) {
    const { world, van, facts } = data;
    const plots = facts.plots;
    const base = world.filter(p => !p.group.startsWith('Sandbox/Far') && !p.group.startsWith('Sandbox/Boundary'));
    const vans = [];
    for (const plot of plots) vans.push(...window.vanParts(van, plot.vanSpot));
    const sheet = document.getElementById('sheet');
    sheet.innerHTML = '';

    // ── The overview: z -250 … 620 across, x -285 … 285 up ──
    const W = 2400, z0 = -250, z1 = 620, x0 = -285, x1 = 285;
    const k = W / (z1 - z0), H = Math.round((x1 - x0) * k);
    const cz = (z0 + z1) / 2, cx = (x0 + x1) / 2;
    const S = (x, z) => [W / 2 + (z - cz) * k, H / 2 - (x - cx) * k];
    const top = window.renderTop(base.concat(vans), { W, H, k, cx, cz, shadowMap: 8192 });
    sheet.style.width = W + 'px';
    sheet.style.height = H + 'px';
    top.canvas.style.left = '0px';
    top.canvas.style.top = '0px';
    sheet.appendChild(top.canvas);

    // ── The close-up of plot 1 (its warehouse's roof off) ──
    const p1 = plots.find(p => p.id === 1);
    const iz0 = -163, iz1 = -88, ix0 = -233, ix1 = -161, ik = 8.4;
    const IW = Math.round((iz1 - iz0) * ik), IH = Math.round((ix1 - ix0) * ik);
    const icx = (ix0 + ix1) / 2, icz = (iz0 + iz1) / 2;
    const IL = 650, IT = H - IH - 62; // where it sits on the sheet
    const IS = (x, z) => [IL + IW / 2 + (z - icz) * ik, IT + IH / 2 - (x - icx) * ik];
    const near = base.filter(p => {
      if (p.group.startsWith('Warehouses/Warehouse1') && !p.group.includes('/Shown') && ROOF.test(p.name)) return false;
      const [x, , z] = p.p;
      const r = Math.max(...p.s);
      return x + r > ix0 - 20 && x - r < ix1 + 20 && z + r > iz0 - 20 && z - r < iz1 + 20;
    });
    const close = window.renderTop(near.concat(window.vanParts(van, p1.vanSpot)), { W: IW, H: IH, k: ik, cx: icx, cz: icz, shadowMap: 4096 });
    close.canvas.style.left = IL + 'px';
    close.canvas.style.top = IT + 'px';
    close.canvas.style.boxShadow = '0 0 0 5px #ffffff, 0 0 0 9px ' + ORANGE + ', 0 10px 30px rgba(0,0,0,0.5)';
    close.canvas.style.borderRadius = '4px';
    sheet.appendChild(close.canvas);

    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('width', W);
    svg.setAttribute('height', H);
    sheet.appendChild(svg);

    // the unload circles (not painted in the game: the admin's SHOW ZONES shows them)
    for (const plot of plots) {
      const [ux, uy] = S(plot.unload.x, plot.unload.z);
      el(svg, 'circle', { cx: ux, cy: uy, r: plot.unload.r * k, fill: '#3fb6ff', 'fill-opacity': 0.18, stroke: WHITE, 'stroke-width': 3, 'stroke-dasharray': '9 7' });
    }
    // the kiosks (small from up here): an orange ring each
    for (const plot of plots) {
      const [kx, ky] = S(plot.board.x, plot.board.z);
      el(svg, 'circle', { cx: kx, cy: ky, r: 15, fill: 'none', stroke: WHITE, 'stroke-width': 7, opacity: 0.8 });
      el(svg, 'circle', { cx: kx, cy: ky, r: 15, fill: 'none', stroke: ORANGE, 'stroke-width': 4 });
    }
    // plot 1's frame and its line to the close-up
    {
      const r = p1.rect;
      const [ax, ay] = S(r.x1, r.z0), [bx, by] = S(r.x0, r.z1);
      el(svg, 'rect', { x: ax, y: ay, width: bx - ax, height: by - ay, fill: 'none', stroke: ORANGE, 'stroke-width': 4, 'stroke-dasharray': '14 9', rx: 6 });
      el(svg, 'line', { x1: bx, y1: (ay + by) / 2 + 60, x2: IL - 9, y2: IT + 120, stroke: ORANGE, 'stroke-width': 4, 'stroke-dasharray': '14 9' });
    }

    // the plots' names
    for (const plot of plots) {
      const [lx, ly] = S(plot.rect.x1 - 3, plot.rect.z0 + 4);
      pill(svg, [{ text: `PLOT ${plot.id}`, size: 25, weight: 800 }, { text: `Level ${plot.level} · ${plot.levelName}`, size: 19, weight: 600, color: CREAM }], [lx, ly], { align: 'l', valign: 't', padY: 7 });
    }
    // the roads
    {
      const [rx] = S(0, -60);
      roadText(svg, 'DEPOT ROW', rx, S(212, 0)[1], 27, -90);
      roadText(svg, 'DEPOT ROW', rx, S(-100, 0)[1], 27, -90);
      const [, ry] = S(0, 0);
      roadText(svg, 'MAIN STREET  ▸  TO THE HOUSE', S(0, 230)[0], ry, 27, 0);
    }
    // the crossroads' TOP MOVERS board
    {
      const at = S(facts.leaders.x, facts.leaders.z);
      pill(svg, [{ text: 'TOP MOVERS board', size: 25, weight: 800 }, { text: 'the leaderboard at the crossroads', size: 19, weight: 600, color: CREAM }], [at[0] + 80, at[1] - 150], { to: at });
    }
    // the turnaround, the house, its curb and front door
    {
      const t = facts.turnaround;
      const at = S(t.x, t.z - t.r * 0.4);
      pill(svg, [{ text: 'Turnaround', size: 23, weight: 800 }], [at[0] - 160, at[1] - 150], { to: at, align: 'c' });
      const h = facts.house;
      const hb = h.house;
      const hc = S(hb.x + hb.sx * 0.25, hb.z);
      pill(svg, [{ text: 'THE OLD CHALET', size: 27, weight: 800 }, { text: "the owner's big European house:", size: 19, weight: 600, color: CREAM }, { text: 'the one house you empty', size: 19, weight: 600, color: CREAM }], [W - 24, hc[1] - 330], { to: hc, align: 'r', valign: 't' });
      const curb = S(h.curb.x, h.curb.z);
      const door = S(h.door.x - 6, h.door.z);
      pill(svg, [{ text: 'Curb: stop the van here', size: 22, weight: 800 }, { text: 'nose to the road, back to the door', size: 18, weight: 600, color: CREAM }], [door[0] - 26, curb[1] + 105], { to: curb, align: 'r', valign: 't' });
      pill(svg, [{ text: 'Front door', size: 22, weight: 800 }, { text: 'walk in: no key', size: 18, weight: 600, color: CREAM }], [W - 14, curb[1] + 105], { to: door, align: 'r', valign: 't' });
    }

    // ── The close-up's labels: a column right of it, in the order of their targets (no crossing lines) ──
    pill(svg, [{ text: 'PLOT 1 UP CLOSE', size: 24, weight: 800 }, { text: "the roof is taken off here", size: 17, weight: 600, color: CREAM }], [IL + 10, IT + 10], { align: 'l', valign: 't', fill: ORANGE, opacity: 0.95, padY: 7 });
    {
      const [ucx, ucy] = IS(p1.unload.x, p1.unload.z);
      el(svg, 'circle', { cx: ucx, cy: ucy, r: p1.unload.r * ik, fill: '#3fb6ff', 'fill-opacity': 0.14, stroke: WHITE, 'stroke-width': 4, 'stroke-dasharray': '14 10' });
      // a part of plot 1's warehouse by its name, nudged (studs along x and z), on the sheet
      const at = (name, dx, dz) => {
        const part = base.find(p => p.group === 'Warehouses/Warehouse1' && p.name === name);
        return IS(part.p[0] + dx, part.p[2] + dz);
      };
      const spawn = IS(p1.spawn.x, p1.spawn.z);
      el(svg, 'circle', { cx: spawn[0], cy: spawn[1], r: 14, fill: '#38c172', stroke: WHITE, 'stroke-width': 4 });
      const labels = [
        { to: [spawn[0] + 12, spawn[1]], color: '#38c172', lines: [['You appear here', 'by your van, after PLAY']] },
        { to: at('Stand2', 0, -2), lines: [[`Display stands (${p1.stands} at level ${p1.level})`, 'a piece on show earns $ every minute']] },
        { to: IS(p1.unload.x + p1.unload.r * 0.7, p1.unload.z + p1.unload.r * 0.71), lines: [['Unload circle', "back the van in: the load goes", 'into your stock (P → SHOW ZONES shows it)']] },
        { to: IS(p1.vanSpot.x + 1.5, p1.vanSpot.z + 6), lines: [['Your Sprinter van', 'parked back to the warehouse door']] },
        { to: at('TerminalDesk', 0, -0.6), lines: [['UPGRADES desk', 'warehouse levels 1 – 5, More stands,', "lights, the van's engine, Danny's training"]] },
        { to: at('Floor', -p1.size[0] * 0.44, p1.size[2] * 0.2), lines: [[`Your warehouse, level ${p1.level}: ${p1.levelName}`, 'it grows bigger with every level']] },
        { to: IS(p1.board.x, p1.board.z + 0.6), lines: [['Kiosk: take a move here (E)', 'the Moving contracts board']] },
      ];
      const colX = IL + IW + 34;
      const rows = l => { const [head, ...rest] = l.lines[0]; return [{ text: head, size: 20, weight: 800 }, ...rest.map(t => ({ text: t, size: 16, weight: 600, color: CREAM }))]; };
      const total = labels.reduce((a, l) => a + pillHeight(rows(l)), 0);
      const gap = (IH - total) / (labels.length - 1);
      let y = IT;
      for (const l of labels) {
        const box = pill(svg, rows(l), [colX, y], { to: l.to, align: 'l', valign: 't', lineColor: l.color, padY: 9 });
        y += box.h + gap;
      }
    }

    // ── The title, the legend, the compass and the scale ──
    {
      const L = 690, T = 26;
      const box = pill(svg, [
        { text: 'ZOMBIE DELIVERY · THE SANDBOX MAP', size: 34, weight: 800 },
        { text: 'Seen from above. North is to the left. 4 plots, 1 house, 2 roads.', size: 21, weight: 600, color: CREAM },
        { text: 'Here every plot shows another warehouse level; a new player starts at level 1.', size: 21, weight: 600, color: CREAM },
      ], [L, T], { align: 'l', valign: 't', padX: 20, padY: 14 });
      // the legend: an icon, then its words
      const rows = ['unload circle (not painted in the game)', 'a Sprinter van at its plot', 'kiosk (Moving contracts board) at each door'];
      const lh = 32 * F, top = box.y + box.h + 14;
      const lw = Math.max(...rows.map(r => textWidth(r, 19 * F, 600))) + 80;
      el(svg, 'rect', { x: L, y: top, width: lw, height: rows.length * lh + 16, rx: 9, fill: INK, 'fill-opacity': 0.92 });
      rows.forEach((r, i) => {
        const cyRow = top + 8 + i * lh + lh / 2;
        el(svg, 'text', { x: L + 62, y: cyRow + 8, 'font-family': FONT, 'font-size': 19 * F, 'font-weight': 600, fill: WHITE }, r);
        if (i === 0) el(svg, 'circle', { cx: L + 30, cy: cyRow, r: 11, fill: '#3fb6ff', 'fill-opacity': 0.35, stroke: WHITE, 'stroke-width': 2.5, 'stroke-dasharray': '5 4' });
        if (i === 1) el(svg, 'rect', { x: L + 14, y: cyRow - 7, width: 32, height: 14, rx: 3, fill: '#dfe5ea', stroke: '#8a939c', 'stroke-width': 2 });
        if (i === 2) {
          el(svg, 'circle', { cx: L + 30, cy: cyRow, r: 12, fill: 'none', stroke: ORANGE, 'stroke-width': 4 });
          el(svg, 'rect', { x: L + 25, y: cyRow - 2, width: 10, height: 4, fill: WHITE });
        }
      });
    }
    {
      // scale: 100 studs, at the bottom right; the compass (an arrow to the left, N) left of it
      const len = 100 * k, sx = W - 50 - len, sy = H - 92;
      const cxp = sx - 100, cyp = sy - 6;
      el(svg, 'circle', { cx: cxp, cy: cyp, r: 50, fill: INK, 'fill-opacity': 0.9, stroke: WHITE, 'stroke-width': 3 });
      el(svg, 'path', { d: `M ${cxp - 38} ${cyp} L ${cxp + 6} ${cyp - 18} L ${cxp - 2} ${cyp} L ${cxp + 6} ${cyp + 18} Z`, fill: ORANGE });
      el(svg, 'text', { x: cxp + 22, y: cyp + 10, 'font-family': FONT, 'font-size': 30, 'font-weight': 800, fill: WHITE, 'text-anchor': 'middle' }, 'N');
      el(svg, 'rect', { x: sx - 14, y: sy - 44, width: len + 28, height: 74, rx: 9, fill: INK, 'fill-opacity': 0.9 });
      el(svg, 'line', { x1: sx, y1: sy, x2: sx + len, y2: sy, stroke: WHITE, 'stroke-width': 6 });
      el(svg, 'line', { x1: sx, y1: sy - 10, x2: sx, y2: sy + 10, stroke: WHITE, 'stroke-width': 4 });
      el(svg, 'line', { x1: sx + len, y1: sy - 10, x2: sx + len, y2: sy + 10, stroke: WHITE, 'stroke-width': 4 });
      el(svg, 'text', { x: sx + len / 2, y: sy - 16, 'font-family': FONT, 'font-size': 20, 'font-weight': 700, fill: WHITE, 'text-anchor': 'middle' }, '100 studs');
    }
    {
      el(svg, 'text', { x: W - 24, y: H - 18, 'font-family': FONT, 'font-size': 15, 'font-weight': 600, fill: WHITE, 'text-anchor': 'end', opacity: 0.9 },
        `Drawn from the game's code (SandboxMap, SandboxWorld, Warehouse, MoveSites, SandboxLeaders) · version ${facts.version} · parts look, no Blender imports`);
    }
    return { W, H, parts: top.count, closeParts: close.count };
  };
})();
