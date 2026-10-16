// 8.3, tools/sandbox-map: lays out the map sheet (design/sandbox/map.png). 8.9: the whole map from above, north up
// (screen right = +X, screen down = +Z); 9.4 the countryside: its lanes, landmarks and the six places to empty
// labelled; a panel on the right with the title, the legend, plot 1 up close (its warehouse's roof off, north up, its
// parts numbered) and the scale. The labels' spots from the export's facts (shared/SandboxMap.luau,
// SandboxLeadersRules.spot). data = { world: [part], van: [part], facts }
(function () {
  const FONT = "Montserrat, 'DejaVu Sans', sans-serif";
  const INK = '#1f2328', ORANGE = '#f0842c', WHITE = '#ffffff', CREAM = '#fff6e8', GREEN = '#38c172';
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
  // Words on the map itself (a street's name): white with a dark edge.
  function roadText(svg, text, x, y, size, rotate) {
    const attrs = { x, y, 'font-family': FONT, 'font-size': size * F, 'font-weight': 800, 'text-anchor': 'middle', 'dominant-baseline': 'middle', 'letter-spacing': 2 };
    if (rotate) attrs.transform = `rotate(${rotate} ${x} ${y})`;
    el(svg, 'text', { ...attrs, fill: 'none', stroke: INK, 'stroke-width': 6, 'stroke-linejoin': 'round', opacity: 0.8 }, text);
    el(svg, 'text', { ...attrs, fill: WHITE }, text);
  }
  // A numbered marker (the close-up's parts).
  function marker(svg, at, n, color) {
    el(svg, 'circle', { cx: at[0], cy: at[1], r: 17, fill: color || ORANGE, stroke: WHITE, 'stroke-width': 4 });
    el(svg, 'text', { x: at[0], y: at[1] + 7, 'font-family': FONT, 'font-size': 20, 'font-weight': 800, fill: WHITE, 'text-anchor': 'middle' }, String(n));
  }

  // A street's longest stretch between its junctions (other streets touching it): where its name goes.
  function nameSpot(road, roads, avoid) {
    const alongX = road.x1 - road.x0 >= road.z1 - road.z0;
    const lo = alongX ? road.x0 : road.z0, hi = alongX ? road.x1 : road.z1;
    let spans = [[lo, hi]];
    // (9.4: off the other roads that meet it and off the plots' name pills (`avoid`) lying over it)
    for (const q of roads.concat(avoid || [])) {
      if (q === road) continue;
      const touch = q.x0 <= road.x1 && q.x1 >= road.x0 && q.z0 <= road.z1 && q.z1 >= road.z0;
      if (!touch) continue;
      const a = (alongX ? q.x0 : q.z0) - 6, b = (alongX ? q.x1 : q.z1) + 6;
      const next = [];
      for (const [s0, s1] of spans) {
        if (b <= s0 || a >= s1) next.push([s0, s1]);
        else {
          if (a > s0) next.push([s0, a]);
          if (b < s1) next.push([b, s1]);
        }
      }
      spans = next;
    }
    spans.sort((p, q) => (q[1] - q[0]) - (p[1] - p[0]));
    const [s0, s1] = spans[0] || [lo, hi];
    const m = (s0 + s1) / 2;
    return alongX ? { x: m, z: (road.z0 + road.z1) / 2, alongX } : { x: (road.x0 + road.x1) / 2, z: m, alongX };
  }

  window.compose = function (data) {
    const { world, van, facts } = data;
    const plots = facts.plots;
    const B = facts.bounds;
    const base = world.filter(p => !p.group.startsWith('Sandbox/Far') && !p.group.startsWith('Sandbox/Boundary'));
    const vans = [];
    for (const plot of plots) vans.push(...window.vanParts(van, plot.vanSpot));
    const sheet = document.getElementById('sheet');
    sheet.innerHTML = '';

    // ── The overview: the Bounds, north up ──
    const MW = 2400, k = MW / (B.x1 - B.x0), MH = Math.round((B.z1 - B.z0) * k);
    const PANEL = 800, W = MW + PANEL, H = MH;
    const cx = (B.x0 + B.x1) / 2, cz = (B.z0 + B.z1) / 2;
    const S = (x, z) => [MW / 2 + (x - cx) * k, MH / 2 + (z - cz) * k];
    const top = window.renderTop(base.concat(vans), { W: MW, H: MH, k, cx, cz, shadowMap: 8192, northUp: true });
    sheet.style.width = W + 'px';
    sheet.style.height = H + 'px';
    sheet.style.background = '#1d2127';
    top.canvas.style.left = '0px';
    top.canvas.style.top = '0px';
    sheet.appendChild(top.canvas);

    // ── Plot 1 up close (its warehouse's roof off), north up, in the panel ──
    const p1 = plots.find(p => p.id === 1);
    const ix0 = -233, ix1 = -161, iz0 = -165, iz1 = -88, ik = 9.6;
    const IW = Math.round((ix1 - ix0) * ik), IH = Math.round((iz1 - iz0) * ik);
    const icx = (ix0 + ix1) / 2, icz = (iz0 + iz1) / 2;
    const IL = MW + Math.round((PANEL - IW) / 2), IT = 470;
    const IS = (x, z) => [IL + IW / 2 + (x - icx) * ik, IT + IH / 2 + (z - icz) * ik];
    const near = base.filter(p => {
      if (p.group.startsWith('Warehouses/Warehouse1') && !p.group.includes('/Shown') && ROOF.test(p.name)) return false;
      const [x, , z] = p.p;
      const r = Math.max(...p.s);
      return x + r > ix0 - 20 && x - r < ix1 + 20 && z + r > iz0 - 20 && z - r < iz1 + 20;
    });
    const close = window.renderTop(near.concat(window.vanParts(van, p1.vanSpot)), { W: IW, H: IH, k: ik, cx: icx, cz: icz, shadowMap: 4096, northUp: true });
    close.canvas.style.left = IL + 'px';
    close.canvas.style.top = IT + 'px';
    close.canvas.style.boxShadow = '0 0 0 5px #ffffff, 0 0 0 9px ' + ORANGE + ', 0 10px 30px rgba(0,0,0,0.5)';
    close.canvas.style.borderRadius = '4px';
    sheet.appendChild(close.canvas);

    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('width', W);
    svg.setAttribute('height', H);
    sheet.appendChild(svg);

    // ── On the map ──
    // the unload circles (not painted in the game) and the kiosks
    for (const plot of plots) {
      const [ux, uy] = S(plot.unload.x, plot.unload.z);
      el(svg, 'circle', { cx: ux, cy: uy, r: plot.unload.r * k, fill: '#3fb6ff', 'fill-opacity': 0.2, stroke: WHITE, 'stroke-width': 2, 'stroke-dasharray': '5 4' });
      const [kx, ky] = S(plot.board.x, plot.board.z);
      el(svg, 'circle', { cx: kx, cy: ky, r: 9, fill: 'none', stroke: WHITE, 'stroke-width': 5, opacity: 0.8 });
      el(svg, 'circle', { cx: kx, cy: ky, r: 9, fill: 'none', stroke: ORANGE, 'stroke-width': 3 });
    }
    // the six houses to empty: an orange frame each, numbered
    const enter = facts.enter || [];
    enter.forEach((h, i) => {
      const [ax, ay] = S(h.box.x0, h.box.z0), [bx, by] = S(h.box.x1, h.box.z1);
      el(svg, 'rect', { x: ax - 5, y: ay - 5, width: bx - ax + 10, height: by - ay + 10, fill: 'none', stroke: WHITE, 'stroke-width': 6, rx: 5, opacity: 0.85 });
      el(svg, 'rect', { x: ax - 5, y: ay - 5, width: bx - ax + 10, height: by - ay + 10, fill: 'none', stroke: ORANGE, 'stroke-width': 4, 'stroke-dasharray': '10 6', rx: 5 });
      if (i > 0) marker(svg, [(ax + bx) / 2, (ay + by) / 2], i + 1);
    });
    // plot 1's frame (it is up close in the panel)
    {
      const r = p1.rect;
      const [ax, ay] = S(r.x0, r.z0), [bx, by] = S(r.x1, r.z1);
      el(svg, 'rect', { x: ax, y: ay, width: bx - ax, height: by - ay, fill: 'none', stroke: ORANGE, 'stroke-width': 3, 'stroke-dasharray': '10 7', rx: 4 });
    }
    // the roads' names (each once: on its longest rect, never on a yard)
    const longest = {};
    for (const road of facts.roads) {
      const len = Math.max(road.x1 - road.x0, road.z1 - road.z0);
      if (!road.yard && (!longest[road.name] || len > longest[road.name].len)) longest[road.name] = { road, len };
    }
    // (the plots' name pills, about 230 × 64 px from each plot's north-west corner: a lane's name keeps off them)
    const pills = plots.map(plot => ({ x0: plot.rect.x0, x1: plot.rect.x0 + 230 / k, z0: plot.rect.z0, z1: plot.rect.z0 + 64 / k }));
    for (const { road } of Object.values(longest)) {
      const at = nameSpot(road, facts.roads, pills);
      const [x, y] = S(at.x, at.z);
      roadText(svg, road.name.toUpperCase(), x, y, road.lane ? 14 : 16, at.alongX ? 0 : -90);
    }
    // the plots' names
    for (const plot of plots) {
      const [lx, ly] = S(plot.rect.x0 + 3, plot.rect.z0 + 3);
      pill(svg, [{ text: `PLOT ${plot.id}`, size: 17, weight: 800 }, { text: `Level ${plot.level} · ${plot.levelName}`, size: 13, weight: 600, color: CREAM }], [lx, ly], { align: 'l', valign: 't', padY: 5, padX: 9 });
    }
    // the landmarks
    const mark = id => (facts.landmarks || []).find(l => l.id === id);
    const mid = r => [(r.x0 + r.x1) / 2, (r.z0 + r.z1) / 2];
    const labels = [];
    const pond = mark('pond'), d5 = mark('d5'), barn = mark('barn'), halt = mark('halt'), apiary = mark('apiary');
    const woods = (facts.woods || [])[0];
    const spot = id => (facts.enter || []).find(h => h.id === id);
    const at = (h, dx, dz) => S((h.box.x0 + h.box.x1) / 2 + dx, (h.box.z0 + h.box.z1) / 2 + dz);
    if (pond && spot('pond_cabin')) labels.push({ lines: [['THE POND CABIN (2)', 'by the fish pond: a jetty, reeds, a boat']], at: S(-1160, 640), to: at(spot('pond_cabin'), 0, 0), align: 'l' });
    if (spot('lone_house')) labels.push({ lines: [['THE LONE HOUSE (3)', 'alone by Hill Road, its garden']], at: S(-760, -380), to: at(spot('lone_house'), 0, 0), align: 'l' });
    if (woods && spot('forest_lodge')) labels.push({ lines: [['THE FOREST LODGE (4)', 'in a clearing of the forest']], at: S(-1160, -620), to: at(spot('forest_lodge'), 0, 0), align: 'l' });
    if (spot('old_mill')) labels.push({ lines: [['THE OLD MILL (5)', 'the millrace past it, a weir, a footbridge']], at: S(-990, 120), to: at(spot('old_mill'), 0, 0), align: 'l' });
    if (apiary && spot('orchard_cottage')) labels.push({ lines: [['THE ORCHARD COTTAGE (6)', 'fruit trees, beehives, a fence']], at: S(-120, -620), to: at(spot('orchard_cottage'), 0, 0), align: 'l' });
    if (d5) labels.push({ lines: [['D5 MOTORWAY', 'cars on it (on every screen,', 'scenery only)']], at: S(300, 230), to: S(360, 250), align: 'r' });
    if (halt) labels.push({ lines: [['MEADOW HALT', 'the railway, under the D5']], at: S(120, 650), to: S(...mid(halt)), align: 'r' });
    if (barn) labels.push({ lines: [['THE FARM', 'barn, tractor, bales, paddock']], at: S(-420, 470), to: S(...mid(barn)), align: 'l' });
    {
      const t = facts.turnaround;
      labels.push({ lines: [['Turnaround']], at: S(t.x + 70, t.z - 60), to: S(t.x + t.r * 0.5, t.z - t.r * 0.3), align: 'l' });
      const h = facts.house;
      labels.push({ lines: [['THE OLD FARMSTEAD (1)', 'the farm: the big house to empty']], at: S(h.lot.x1 + 40, h.house.z + 30), to: S(h.house.x + h.house.sx * 0.3, h.house.z), align: 'l' });
      labels.push({ lines: [['TOP MOVERS board', 'the leaderboard at the crossroads']], at: S(-40, -8), to: S(facts.leaders.x, facts.leaders.z), align: 'r' });
    }
    for (const l of labels) {
      const [head, ...rest] = l.lines[0];
      const lines = [{ text: head, size: 19, weight: 800 }, ...rest.map(t => ({ text: t, size: 14, weight: 600, color: CREAM }))];
      pill(svg, lines, l.at, { to: l.to || undefined, align: l.align, valign: 'm', opacity: l.plain ? 0.8 : 0.92 });
    }

    // ── The panel (the sheet's own dark ground, right of the map) ──
    const PL = MW + 34;
    {
      let y = 30;
      const title = pill(svg, [
        { text: 'ZOMBIE DELIVERY · THE SANDBOX MAP', size: 25, weight: 800 },
        { text: 'The countryside · seen from above, north up', size: 17, weight: 600, color: CREAM },
        { text: `4 plots · ${Object.keys(longest).length} roads · 6 places to empty, each on its own`, size: 17, weight: 600, color: CREAM },
      ], [PL, y], { align: 'l', valign: 't', padX: 18, padY: 14 });
      y = title.y + title.h + 16;
      const rows = ['unload circle (not painted in the game)', 'a Sprinter van at its plot', 'kiosk: take a move there (E)', 'a place to empty:'];
      const names = (facts.enter || []).map((h, i) => `${i + 1} ${h.name.replace(/^The /, '')}`);
      if (names.length) rows.push('   ' + names.slice(0, 3).join(' · '), '   ' + names.slice(3).join(' · '));
      const lh = 30 * F;
      const lw = PANEL - 68;
      el(svg, 'rect', { x: PL, y, width: lw, height: rows.length * lh + 16, rx: 9, fill: INK, 'fill-opacity': 0.92 });
      rows.forEach((r, i) => {
        const cyRow = y + 8 + i * lh + lh / 2;
        el(svg, 'text', { x: PL + 62, y: cyRow + 7, 'font-family': FONT, 'font-size': 16 * F, 'font-weight': 600, fill: WHITE }, r);
        if (i === 0) el(svg, 'circle', { cx: PL + 30, cy: cyRow, r: 11, fill: '#3fb6ff', 'fill-opacity': 0.35, stroke: WHITE, 'stroke-width': 2.5, 'stroke-dasharray': '5 4' });
        if (i === 1) el(svg, 'rect', { x: PL + 14, y: cyRow - 7, width: 32, height: 14, rx: 3, fill: '#dfe5ea', stroke: '#8a939c', 'stroke-width': 2 });
        if (i === 2) {
          el(svg, 'circle', { cx: PL + 30, cy: cyRow, r: 11, fill: 'none', stroke: ORANGE, 'stroke-width': 4 });
          el(svg, 'rect', { x: PL + 25, y: cyRow - 2, width: 10, height: 4, fill: WHITE });
        }
        if (i === 3) el(svg, 'rect', { x: PL + 15, y: cyRow - 10, width: 30, height: 20, rx: 3, fill: 'none', stroke: ORANGE, 'stroke-width': 3, 'stroke-dasharray': '6 4' });
      });
    }
    // the close-up: its title on it, its parts numbered, their words under it
    pill(svg, [{ text: 'PLOT 1 UP CLOSE', size: 21, weight: 800 }, { text: 'the roof is taken off here', size: 15, weight: 600, color: CREAM }], [IL + 10, IT + 10], { align: 'l', valign: 't', fill: ORANGE, opacity: 0.95, padY: 7 });
    {
      const [ucx, ucy] = IS(p1.unload.x, p1.unload.z);
      el(svg, 'circle', { cx: ucx, cy: ucy, r: p1.unload.r * ik, fill: '#3fb6ff', 'fill-opacity': 0.14, stroke: WHITE, 'stroke-width': 4, 'stroke-dasharray': '14 10' });
      const at = (name, dx, dz) => {
        const part = base.find(p => p.group === 'Warehouses/Warehouse1' && p.name === name);
        return part ? IS(part.p[0] + dx, part.p[2] + dz) : IS(p1.door.x, p1.door.z);
      };
      const items = [
        { to: IS(p1.spawn.x, p1.spawn.z), color: GREEN, lines: ['You appear here', 'by your van, after PLAY'] },
        { to: at('Stand2', 0, 0), lines: [`Display stands (${p1.stands} at level ${p1.level})`, 'a piece on show earns $ every minute'] },
        { to: IS(p1.unload.x - p1.unload.r * 0.7, p1.unload.z + p1.unload.r * 0.4), lines: ['Unload circle', 'back the van in: the load goes into your stock (P → SHOW ZONES shows it)'] },
        { to: IS(p1.vanSpot.x, p1.vanSpot.z + 4), lines: ['Your Sprinter van', 'parked back to the warehouse door'] },
        { to: at('TerminalDesk', 0, 0), lines: ['UPGRADES desk', "warehouse levels 1 – 5, More stands, lights, the van's engine, Danny's training"] },
        { to: at('Floor', p1.size[0] * 0.3, -p1.size[2] * 0.3), lines: [`Your warehouse, level ${p1.level}: ${p1.levelName}`, 'it grows bigger with every level'] },
        { to: IS(p1.board.x, p1.board.z), lines: ['Kiosk: take a move here (E)', 'the Moving contracts board: a house to empty'] },
      ];
      let y = IT + IH + 40;
      items.forEach((it, i) => {
        marker(svg, it.to, i + 1, it.color);
        marker(svg, [PL + 18, y + 14], i + 1, it.color);
        el(svg, 'text', { x: PL + 48, y: y + 21, 'font-family': FONT, 'font-size': 18 * F, 'font-weight': 800, fill: WHITE }, it.lines[0]);
        el(svg, 'text', { x: PL + 48, y: y + 48, 'font-family': FONT, 'font-size': 13 * F, 'font-weight': 600, fill: CREAM }, it.lines[1]);
        y += 66;
      });
    }
    // the compass and the scale (100 studs), the footer
    {
      const len = 100 * k, sx = MW + PANEL - 60 - len, sy = H - 110;
      const cxp = sx - 110, cyp = sy - 6;
      el(svg, 'circle', { cx: cxp, cy: cyp, r: 46, fill: INK, 'fill-opacity': 0.9, stroke: WHITE, 'stroke-width': 3 });
      el(svg, 'path', { d: `M ${cxp} ${cyp - 36} L ${cxp + 16} ${cyp + 6} L ${cxp} ${cyp - 2} L ${cxp - 16} ${cyp + 6} Z`, fill: ORANGE });
      el(svg, 'text', { x: cxp, y: cyp + 32, 'font-family': FONT, 'font-size': 22, 'font-weight': 800, fill: WHITE, 'text-anchor': 'middle' }, 'N');
      el(svg, 'rect', { x: sx - 14, y: sy - 44, width: len + 28, height: 74, rx: 9, fill: INK, 'fill-opacity': 0.9 });
      el(svg, 'line', { x1: sx, y1: sy, x2: sx + len, y2: sy, stroke: WHITE, 'stroke-width': 6 });
      el(svg, 'line', { x1: sx, y1: sy - 10, x2: sx, y2: sy + 10, stroke: WHITE, 'stroke-width': 4 });
      el(svg, 'line', { x1: sx + len, y1: sy - 10, x2: sx + len, y2: sy + 10, stroke: WHITE, 'stroke-width': 4 });
      el(svg, 'text', { x: sx + len / 2, y: sy - 16, 'font-family': FONT, 'font-size': 20, 'font-weight': 700, fill: WHITE, 'text-anchor': 'middle' }, '100 studs');
      const foot = ["Drawn from the game's code (SandboxMap, SandboxWorld, VillageWorld,", `Warehouse, MoveSites, SandboxLeaders) · version ${facts.version}`, 'parts look, no Blender imports'];
      foot.forEach((t, i) => el(svg, 'text', { x: PL, y: H - 250 + i * 22, 'font-family': FONT, 'font-size': 15, 'font-weight': 600, fill: WHITE, opacity: 0.85 }, t));
    }
    return { W, H, parts: top.count, closeParts: close.count };
  };
})();
