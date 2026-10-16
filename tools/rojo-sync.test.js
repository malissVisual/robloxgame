#!/usr/bin/env node
/*
 * Test rojo-syncu: node tools/rojo-sync.test.js   (vypíše ALL CHECKS PASSED)
 *
 *   1) MessagePack tam a zpět, i s 500 kB řetězcem.
 *   2) .rbxm z writeRbxm přečtený NEZÁVISLÝM čtenářem (níže, podle rbx-dom
 *      docs/binary.md, s plným LZ4 dekodérem): hlavička, bloky, referenty,
 *      500 kB Source s češtinou do bajtu stejný.
 *   3) Dělení patche: změněný skript jde jako znovuvytvoření (changedClassName =
 *      jeho třída, celé Source), smazání + nové vytvoření téhož id v jedné
 *      zprávě, přidané podstromy celé, dávky do PIECE_BYTES, --in-place jako dřív.
 *   4) Opravdový server nad dočasným projektem: handshake, read, WebSocket
 *      (vlastní klient), čerstvé skripty po Connect + kontrolní zpráva,
 *      /api/serialize jako potvrzení, živá změna, druhé spojení (Play test: jen
 *      přepsání, nic znovu), chybějící potvrzení, --in-place.
 *
 * Dočasné soubory jdou do os.tmpdir() (TMPDIR) a na konci se smažou.
 */

"use strict";

const assert = require("assert");
const childProcess = require("child_process");
const fs = require("fs");
const http = require("http");
const net = require("net");
const os = require("os");
const path = require("path");

const SYNC_PATH = path.join(__dirname, "rojo-sync.js");
const sync = require(SYNC_PATH);

let failures = 0;
let checks = 0;

function check(condition, message) {
	checks += 1;
	if (!condition) {
		failures += 1;
		console.log(`FAIL: ${message}`);
	}
}

// ───────────────────────────────────────────── Nezávislý čtenář .rbxm ──

function lz4Decompress(src, outLength) {
	const out = Buffer.alloc(outLength);
	let i = 0;
	let o = 0;
	while (i < src.length) {
		const token = src[i++];
		let literals = token >> 4;
		if (literals === 15) {
			let byte;
			do {
				byte = src[i++];
				literals += byte;
			} while (byte === 255);
		}
		src.copy(out, o, i, i + literals);
		i += literals;
		o += literals;
		if (i >= src.length) {
			break; // poslední sekvence má jen literály
		}
		const offset = src[i] | (src[i + 1] << 8);
		i += 2;
		let matchLength = token & 15;
		if (matchLength === 15) {
			let byte;
			do {
				byte = src[i++];
				matchLength += byte;
			} while (byte === 255);
		}
		matchLength += 4;
		if (offset === 0 || offset > o) {
			throw new Error(`LZ4: špatný offset ${offset}`);
		}
		for (let k = 0; k < matchLength; k++) {
			out[o] = out[o - offset];
			o += 1;
		}
	}
	if (o !== outLength) {
		throw new Error(`LZ4: ${o} bajtů místo ${outLength}`);
	}
	return out;
}

function readInterleaved(data, at, count, accumulate) {
	const values = [];
	let previous = 0;
	for (let i = 0; i < count; i++) {
		const zigzag =
			((data[at + i] << 24) | (data[at + count + i] << 16) | (data[at + 2 * count + i] << 8) | data[at + 3 * count + i]) >>> 0;
		let value = (zigzag >>> 1) ^ -(zigzag & 1);
		if (accumulate) {
			value += previous;
			previous = value;
		}
		values.push(value);
	}
	return values;
}

function readRbxm(buffer) {
	assert.strictEqual(buffer.toString("latin1", 0, 8), "<roblox!", "magic");
	assert.deepStrictEqual([...buffer.subarray(8, 14)], [0x89, 0xff, 0x0d, 0x0a, 0x1a, 0x0a], "podpis");
	assert.strictEqual(buffer.readUInt16LE(14), 0, "verze formátu");
	const classCount = buffer.readInt32LE(16);
	const instanceCount = buffer.readInt32LE(20);
	assert.ok(buffer.subarray(24, 32).every((byte) => byte === 0), "rezervované bajty hlavičky");

	const classes = new Map(); // classId → { name, refs }
	const instances = new Map(); // ref → { className, props, parent }
	const chunkNames = [];
	let pos = 32;
	for (;;) {
		const name = buffer.toString("latin1", pos, pos + 4);
		const compressed = buffer.readUInt32LE(pos + 4);
		const uncompressed = buffer.readUInt32LE(pos + 8);
		assert.strictEqual(buffer.readUInt32LE(pos + 12), 0, `rezervované bajty bloku ${name}`);
		pos += 16;
		const data = compressed === 0
			? buffer.subarray(pos, pos + uncompressed)
			: lz4Decompress(buffer.subarray(pos, pos + compressed), uncompressed);
		pos += compressed || uncompressed;
		chunkNames.push(name);

		let at = 0;
		const u32 = () => {
			const value = data.readUInt32LE(at);
			at += 4;
			return value;
		};
		const str = () => {
			const length = u32();
			const value = data.toString("utf8", at, at + length);
			at += length;
			return value;
		};

		if (name === "INST") {
			const classId = u32();
			const className = str();
			const format = data[at++];
			const count = u32();
			const refs = readInterleaved(data, at, count, true);
			at += count * 4;
			if (format === 1) {
				at += count;
			}
			classes.set(classId, { name: className, refs });
			for (const ref of refs) {
				instances.set(ref, { className, props: {}, parent: undefined });
			}
		} else if (name === "PROP") {
			const info = classes.get(u32());
			const propName = str();
			const type = data[at++];
			if (type === 0x01) {
				for (const ref of info.refs) {
					instances.get(ref).props[propName] = str();
				}
			} else if (type === 0x13) {
				const values = readInterleaved(data, at, info.refs.length, true);
				at += info.refs.length * 4;
				info.refs.forEach((ref, i) => {
					instances.get(ref).props[propName] = { ref: values[i] };
				});
			} else {
				throw new Error(`neznámý typ vlastnosti 0x${type.toString(16)}`);
			}
		} else if (name === "PRNT") {
			assert.strictEqual(data[at++], 0, "verze PRNT");
			const count = u32();
			const children = readInterleaved(data, at, count, true);
			const parents = readInterleaved(data, at + count * 4, count, true);
			at += count * 8;
			children.forEach((child, i) => {
				instances.get(child).parent = parents[i];
			});
		} else if (name === "END\0") {
			assert.strictEqual(data.toString("latin1"), "</roblox>", "konec");
			break;
		}
		if (name !== "END\0") {
			assert.strictEqual(at, data.length, `blok ${name} přečtený celý`);
		}
	}
	assert.strictEqual(pos, buffer.length, "za END nic není");
	assert.strictEqual(classes.size, classCount, "počet tříd v hlavičce");
	assert.strictEqual(instances.size, instanceCount, "počet instancí v hlavičce");
	return { instances, chunkNames };
}

// Model z /api/serialize → { id: { className, name, source } } (jako to čte plugin).
function modelById(buffer) {
	const { instances } = readRbxm(buffer);
	const roots = [...instances.entries()].filter(([, inst]) => inst.parent === -1);
	assert.strictEqual(roots.length, 1, "jeden kořen");
	const [rootRef, root] = roots[0];
	assert.strictEqual(root.className, "Folder", "kořen je Folder");
	const out = {};
	for (const [ref, holder] of instances) {
		if (holder.parent !== rootRef) continue;
		assert.strictEqual(holder.className, "ObjectValue", "pod kořenem jsou ObjectValue");
		const copy = instances.get(holder.props.Value.ref);
		assert.strictEqual(copy.parent, ref, "kopie je dítě své ObjectValue");
		out[holder.props.Name] = { className: copy.className, name: copy.props.Name, source: copy.props.Source };
	}
	return out;
}

// ────────────────────────────────────────────────────────────── Pomůcky ──

const ID = (n) => n.toString(16).padStart(32, "0");

function bigSource(version, bytes) {
	const head = `--!strict\n-- Config (test)\nlocal Config = {}\nConfig.Version = "${version}"\n`;
	const line = "Config.Řádek = { 1, 2.5, \"čeština, ñ, 漢字, 🚚\" }\n";
	return head + line.repeat(Math.ceil(bytes / Buffer.byteLength(line))) + "return Config\n";
}

function script(id, parent, name, className, source) {
	return {
		Id: id,
		Parent: parent,
		Name: name,
		ClassName: className,
		Properties: { Source: { String: source } },
		Children: [],
		Metadata: { ignoreUnknownInstances: false },
	};
}

function folder(id, parent, name, children) {
	return { Id: id, Parent: parent, Name: name, ClassName: "Folder", Properties: {}, Children: children, Metadata: { ignoreUnknownInstances: false } };
}

// ───────────────────────────────────────────── 1) MessagePack ──

{
	const big = bigSource("1.0", 500 * 1024);
	const value = { a: [1, -1, 300, -40000, 2 ** 33, 1.5, true, false, null], s: big, b: Buffer.from([1, 2, 3]), m: {} };
	const back = sync.decode(sync.encode(value));
	check(back.s === big, "msgpack: 500 kB řetězec tam a zpět");
	check(JSON.stringify(back.a) === JSON.stringify(value.a), "msgpack: čísla a bool");
	check(Buffer.isBuffer(back.b) && back.b.equals(value.b), "msgpack: bin");
}

// ───────────────────────────────────────────── 2) .rbxm ──

for (const length of [0, 1, 14, 15, 16, 254, 255, 269, 270, 271, 524, 525, 65535, 70000]) {
	const data = Buffer.alloc(length, 0x61);
	data.write("xyz", 0, Math.min(3, length));
	const block = sync.lz4Literals(data);
	let same = false;
	try {
		same = lz4Decompress(block, length).equals(data);
	} catch (err) {
		same = false;
	}
	check(same, `LZ4 blok jen s literály, délka ${length}`);
}

{
	const big = bigSource("8.6", 500 * 1024);
	const tree = {
		instances: {
			[ID(1)]: script(ID(1), ID(9), "Config", "ModuleScript", big),
			[ID(2)]: script(ID(2), ID(9), "Boot", "Script", "print('boot')\n"),
			[ID(3)]: script(ID(3), ID(9), "Main", "LocalScript", ""),
			[ID(4)]: folder(ID(4), ID(9), "Prázdná", []),
		},
	};
	const ids = [ID(1), ID(2), ID(3), ID(4)];
	const rbxm = sync.writeRbxm(sync.serializeIds(tree, ids));
	let model = null;
	try {
		model = modelById(rbxm);
	} catch (err) {
		check(false, `rbxm: nezávislý čtenář selhal: ${err.message}`);
	}
	if (model) {
		check(Object.keys(model).length === 4, "rbxm: čtyři ObjectValue");
		check(model[ID(1)].source === big, "rbxm: 500 kB Source s češtinou a emoji do bajtu stejný");
		check(model[ID(1)].className === "ModuleScript" && model[ID(1)].name === "Config", "rbxm: třída a jméno Configu");
		check(model[ID(2)].className === "Script" && model[ID(2)].source === "print('boot')\n", "rbxm: Script");
		check(model[ID(3)].className === "LocalScript" && model[ID(3)].source === "", "rbxm: prázdný Source");
		check(model[ID(4)].className === "Folder" && model[ID(4)].source === undefined, "rbxm: složka bez Source");
	}
}

// ───────────────────────────────────────────── 3) Dělení patche ──

{
	const big = bigSource("8.6", 500 * 1024);
	const after = {
		instances: {
			[ID(1)]: script(ID(1), ID(9), "Config", "ModuleScript", big),
			[ID(2)]: script(ID(2), ID(9), "Boot", "Script", "print(2)"),
		},
	};
	const patch = {
		added: {},
		removed: [],
		updated: [
			{ id: ID(1), changedProperties: { Source: { String: big } } },
			{ id: ID(2), changedProperties: { Source: { String: "print(2)" } } },
		],
	};
	const pieces = sync.splitPatch(patch, after, { recreate: true });
	check(pieces.length === 2, "split: každý změněný skript ve vlastní zprávě");
	const config = pieces[0].updated[0];
	check(config.changedClassName === "ModuleScript", "split: Config se vytváří znovu (changedClassName = ModuleScript)");
	check(config.changedProperties.Source.String === big, "split: Config nese celé Source");
	check(config.changedName === undefined, "split: jméno se nemění");
	check(pieces[1].updated[0].changedClassName === "Script", "split: Script zůstává Script");
	const bytes = sync.encode(pieces[0]).length;
	check(bytes > 500 * 1024 && bytes < 600 * 1024, `split: zpráva s Configem má jen Config (${bytes} B)`);

	const inPlace = sync.splitPatch(patch, after, { recreate: false });
	check(inPlace.length === 2 && inPlace[0].updated[0] === patch.updated[0], "split --in-place: update beze změny");

	// Kontrolní id: skripty nad PIECE_BYTES, jinak nejmenší.
	check(JSON.stringify(sync.probeIds(after, [ID(1), ID(2)])) === JSON.stringify([ID(1)]), "probe: velký Config");
	check(JSON.stringify(sync.probeIds(after, [ID(2)])) === JSON.stringify([ID(2)]), "probe: jinak nejmenší skript");
	const probe = sync.probeMessage(after, [ID(1)]);
	check(
		probe.updated.length === 1 && probe.updated[0].changedMetadata.ignoreUnknownInstances === false &&
			Object.keys(probe.updated[0].changedProperties).length === 0 && sync.encode(probe).length < 200,
		"probe: malá zpráva jen s changedMetadata"
	);

	const fresh = sync.freshPieces(after);
	check(fresh.length === 2 && fresh.every((piece) => piece.updated.length === 1 && piece.updated[0].changedClassName), "fresh: každý skript znovu, jeden na zprávu");
}

{
	// Složka se stane skriptem (přibude init.luau) a zároveň složka se skripty
	// přibude a jiné ubudou — přes skutečný buildTree + diffTrees.
	const root = fs.mkdtempSync(path.join(os.tmpdir(), "rojo-sync-split-"));
	try {
		const write = (rel, text) => {
			fs.mkdirSync(path.dirname(path.join(root, rel)), { recursive: true });
			fs.writeFileSync(path.join(root, rel), text);
		};
		write("default.project.json", JSON.stringify({ name: "T", tree: { $className: "DataModel", ReplicatedStorage: { Shared: { $path: "src" } } } }));
		write("src/Pack/a.luau", "return 'a'");
		write("src/Gone.luau", "return 0");
		const before = sync.buildTree(path.join(root, "default.project.json"));
		write("src/Pack/init.luau", "return 'pack'");
		fs.unlinkSync(path.join(root, "src/Gone.luau"));
		const filler = "-- x\n".repeat(30000);
		for (let i = 0; i < 12; i++) {
			write(`src/New/m${i}.luau`, `return ${i}\n${filler}`);
		}
		const after = sync.buildTree(path.join(root, "default.project.json"));
		const patch = sync.diffTrees(before, after);
		const pieces = sync.splitPatch(patch, after, { recreate: true });
		const packId = Object.values(after.instances).find((inst) => inst.Name === "Pack").Id;
		const newId = Object.values(after.instances).find((inst) => inst.Name === "New").Id;
		const packPieces = pieces.filter((piece) => piece.removed.includes(packId) || piece.added[packId]);
		check(packPieces.length === 1, "split: smazání a nové vytvoření Packu v JEDNÉ zprávě");
		check(packPieces.length === 1 && packPieces[0].removed.includes(packId) && packPieces[0].added[packId] && Object.keys(packPieces[0].added).length === 2, "split: Pack i s dítětem a");
		const newPieces = pieces.filter((piece) => piece.added[newId]);
		check(newPieces.length === 1 && Object.keys(newPieces[0].added).length === 13, "split: nová složka i se 12 skripty v jedné zprávě");
		check(pieces.filter((piece) => piece.removed.length && !Object.keys(piece.added).length).length === 1, "split: samotná smazání ve vlastní zprávě");
		for (const piece of pieces) {
			for (const id of Object.keys(piece.added)) {
				const parent = piece.added[id].Parent;
				check(piece.added[parent] || before.instances[parent], `split: rodič přidané ${piece.added[id].Name} existuje`);
			}
		}
	} finally {
		fs.rmSync(root, { recursive: true, force: true });
	}
}

{
	// Skutečný projekt Zombie Delivery (když je vedle): všechny skripty, kontrola.
	const projectFile = path.join(__dirname, "..", "zombie-delivery", "default.project.json");
	if (fs.existsSync(projectFile)) {
		const tree = sync.buildTree(projectFile);
		const fresh = sync.freshPieces(tree);
		const scripts = Object.values(tree.instances).filter((inst) => ["Script", "LocalScript", "ModuleScript"].includes(inst.ClassName));
		check(fresh.length === scripts.length && fresh.length > 100, `zombie-delivery: ${fresh.length} skriptů po Connect`);
		const probe = sync.probeIds(tree, fresh.map((piece) => piece.updated[0].id)).map((id) => tree.instances[id].Name);
		check(probe.includes("Config"), `zombie-delivery: kontrola obsahuje Config (${probe.join(", ")})`);
		check(typeof sync.diskVersion(tree) === "string", "zombie-delivery: verze na disku");
		check(
			JSON.stringify(tree.pathRoots.map((id) => sync.fullName(tree, id))) ===
				JSON.stringify(["ReplicatedStorage.Shared", "ServerScriptService.Server", "StarterPlayer.StarterPlayerScripts.Client"]),
			"zombie-delivery: kořeny ze $path"
		);
		const model = modelById(sync.writeRbxm(sync.serializeIds(tree, sync.probeIds(tree, fresh.map((piece) => piece.updated[0].id)))));
		check(Object.values(model).every((item) => item.source === tree.instances[Object.keys(model).find((id) => model[id] === item)].Properties.Source.String), "zombie-delivery: velké skripty v .rbxm do bajtu");
	}
	const rootProject = path.join(__dirname, "..", "default.project.json");
	if (fs.existsSync(rootProject)) {
		const tree = sync.buildTree(rootProject);
		const scope = tree.scopes.find((dir) => dir.endsWith("src/shared"));
		check(scope && sync.inScope(`${scope}/Config.luau`.split("/").join(path.sep), tree.scopes), "watcher: soubor ze $path je v dosahu i bez argumentu");
		check(!sync.inScope(path.join(".git", "index"), tree.scopes), "watcher: .git ne");
	}
}

// ───────────────────────────────────────────── 4) Server ──

function freePort() {
	return new Promise((resolve) => {
		const probe = net.createServer();
		probe.listen(0, "127.0.0.1", () => {
			const { port } = probe.address();
			probe.close(() => resolve(port));
		});
	});
}

function request(port, method, urlPath, body) {
	return new Promise((resolve, reject) => {
		const req = http.request({ host: "127.0.0.1", port, method, path: urlPath }, (res) => {
			const chunks = [];
			res.on("data", (chunk) => chunks.push(chunk));
			res.on("end", () => resolve({ status: res.statusCode, body: sync.decode(Buffer.concat(chunks)) }));
		});
		req.on("error", reject);
		req.end(body);
	});
}

// Vlastní WebSocket klient (nezávislý na serverových rámcích): zprávy → pole.
function openSocket(port, cursor) {
	return new Promise((resolve, reject) => {
		const req = http.request({
			host: "127.0.0.1",
			port,
			path: `/api/socket/${cursor}`,
			headers: { Connection: "Upgrade", Upgrade: "websocket", "Sec-WebSocket-Key": "dGhlIHNhbXBsZSBub25jZQ==", "Sec-WebSocket-Version": "13" },
		});
		req.on("upgrade", (res, socket, head) => {
			const packets = [];
			let buffer = head;
			const parse = () => {
				while (buffer.length >= 2) {
					let length = buffer[1] & 0x7f;
					let offset = 2;
					if (length === 126) {
						if (buffer.length < 4) return;
						length = buffer.readUInt16BE(2);
						offset = 4;
					} else if (length === 127) {
						if (buffer.length < 10) return;
						length = Number(buffer.readBigUInt64BE(2));
						offset = 10;
					}
					if (buffer.length < offset + length) return;
					const opcode = buffer[0] & 0x0f;
					if (opcode === 0x2) {
						packets.push(sync.decode(buffer.subarray(offset, offset + length)));
					}
					buffer = buffer.subarray(offset + length);
				}
			};
			socket.on("data", (chunk) => {
				buffer = Buffer.concat([buffer, chunk]);
				parse();
			});
			parse();
			check(res.headers["sec-websocket-accept"] === "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", "websocket: Sec-WebSocket-Accept");
			resolve({ socket, packets });
		});
		req.on("error", reject);
		req.end();
	});
}

function startSync(projectDir, port, extra) {
	const child = childProcess.spawn(process.execPath, [SYNC_PATH, projectDir, ...(extra || [])], {
		env: { ...process.env, ROJO_PORT: String(port), ROJO_SYNC_ACK_MS: "1500" },
		stdio: ["ignore", "pipe", "pipe"],
	});
	let output = "";
	child.stdout.on("data", (chunk) => (output += chunk));
	child.stderr.on("data", (chunk) => (output += chunk));
	// Čeká, až se vzor v dosavadním výstupu objeví aspoň `times`krát.
	const waitFor = async (pattern, ms = 10000, times = 1) => {
		const global = new RegExp(pattern.source, "g");
		const until = Date.now() + ms;
		while (Date.now() < until) {
			if ((output.match(global) || []).length >= times) return true;
			await sleep(50);
		}
		return false;
	};
	return { child, waitFor, output: () => output };
}

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function waitPackets(packets, count, ms = 10000) {
	const until = Date.now() + ms;
	while (packets.length < count && Date.now() < until) {
		await sleep(20);
	}
	return packets.length >= count;
}

async function serverTest() {
	const root = fs.mkdtempSync(path.join(os.tmpdir(), "rojo-sync-server-"));
	const procs = [];
	try {
		const write = (rel, text) => {
			fs.mkdirSync(path.dirname(path.join(root, rel)), { recursive: true });
			fs.writeFileSync(path.join(root, rel), text);
		};
		write("default.project.json", JSON.stringify({
			name: "SyncTest",
			tree: {
				$className: "DataModel",
				ReplicatedStorage: { Shared: { $path: "src/shared" } },
				ServerScriptService: { Server: { $path: "src/server" } },
			},
		}));
		const config1 = bigSource("1.0", 500 * 1024);
		write("src/shared/Config.luau", config1);
		write("src/shared/Small.luau", "return 1\n");
		write("src/server/Boot.server.luau", "print('boot')\n");

		const port = await freePort();
		const run = startSync(root, port);
		procs.push(run.child);
		check(await run.waitFor(/adresa:/), "server: start");
		check(/verze:\s+1\.0/.test(run.output()), "server: ukáže verzi na disku");

		const info = await request(port, "GET", "/api/rojo");
		check(info.status === 200 && info.body.protocolVersion === 5 && typeof info.body.rootInstanceId === "string", "server: handshake");
		const sessionId = info.body.sessionId;
		const read = await request(port, "GET", `/api/read/${info.body.rootInstanceId}`);
		const instances = read.body.instances;
		const byName = (name) => Object.values(instances).find((inst) => inst.Name === name);
		check(read.status === 200 && byName("Config").Properties.Source.String === config1, "server: read s 500 kB Configem");

		// Connect: tři skripty znovu + kontrolní zpráva.
		const ws = await openSocket(port, read.body.messageCursor);
		check(await waitPackets(ws.packets, 4), "server: po Connect přijdou 3 skripty + kontrola");
		const updates = ws.packets.map((packet) => packet.body.messages[0].updated[0]);
		check(ws.packets.every((packet) => packet.sessionId === sessionId && packet.packetType === "messages" && packet.body.messages.length === 1), "server: jeden patch na paket");
		const recreated = updates.slice(0, 3);
		check(recreated.every((update) => update.changedClassName === instances[update.id].ClassName), "server: všechny skripty jako znovuvytvoření");
		check(recreated.every((update) => update.changedProperties.Source.String === instances[update.id].Properties.Source.String), "server: s celým Source");
		const probe = updates[3];
		check(probe && probe.id === byName("Config").Id && probe.changedMetadata && Object.keys(probe.changedProperties).length === 0, "server: kontrola = Config přes changedMetadata");
		check(/Connect: všech 3 skriptů/.test(run.output()), "server: hlásí čerstvé skripty");

		// Plugin na kontrolu odpoví /api/serialize — to je potvrzení.
		const serialized = await request(port, "POST", "/api/serialize", sync.encode({ sessionId, ids: [probe.id] }));
		check(serialized.status === 200 && Buffer.isBuffer(serialized.body.modelContents), "server: /api/serialize vrátí .rbxm");
		const model = modelById(serialized.body.modelContents);
		check(model[probe.id] && model[probe.id].source === config1 && model[probe.id].className === "ModuleScript", "server: v .rbxm je celý Config");
		const refPatch = await request(port, "POST", "/api/ref-patch", sync.encode({ sessionId, ids: [probe.id] }));
		check(refPatch.status === 200 && refPatch.body.patch.removed.length === 0, "server: prázdný ref-patch");
		check(await run.waitFor(/✓ Studio převzalo Connect: 3 skriptů z disku, verze 1\.0 \(za [\d.]+ s\) — můžeš dát Play/), "server: potvrzení Connectu v terminálu");

		// Neznámé id → 400 jako rojo serve 7.7.0.
		const unknown = await request(port, "POST", "/api/serialize", sync.encode({ sessionId, ids: [ID(77)] }));
		check(unknown.status === 400, "server: neznámé id → 400");

		// Živá změna Configu: znovuvytvoření + kontrola, potvrzení.
		const config2 = bigSource("1.1", 500 * 1024);
		const seen = ws.packets.length;
		write("src/shared/Config.luau", config2);
		check(await waitPackets(ws.packets, seen + 2, 8000), "server: změna Configu přijde do 8 s");
		const change = ws.packets[seen].body.messages[0].updated[0];
		check(change && change.id === byName("Config").Id && change.changedClassName === "ModuleScript" && change.changedProperties.Source.String === config2, "server: změněný Config se vytváří znovu");
		check(ws.packets[seen].body.messageCursor === 1, "server: kurzor zprávy");
		const changeProbe = ws.packets[seen + 1] && ws.packets[seen + 1].body.messages[0].updated[0];
		check(changeProbe && changeProbe.changedMetadata && changeProbe.id === change.id, "server: po změně kontrola");
		check(await run.waitFor(/↻ změna \(~1\) → odesláno do Studia .*verze na disku 1\.1/), "server: hlásí změnu a novou verzi");
		await request(port, "POST", "/api/serialize", sync.encode({ sessionId, ids: [changeProbe.id] }));
		check(await run.waitFor(/✓ Studio převzalo změnu \(~1\)/), "server: potvrzení změny");

		// Druhé souběžné spojení (Play test s Auto Connect): žádné čerstvé skripty,
		// změny jen jako přepsání a bez kontroly.
		const second = await openSocket(port, ws.packets[ws.packets.length - 1].body.messageCursor);
		await sleep(500);
		check(second.packets.length === 0, "druhé spojení: po Connect nic znovu nevytváří");
		check(/připojeno podruhé/.test(run.output()), "druhé spojení: hlásí se jako druhé");
		const seenMain = ws.packets.length;
		write("src/server/Boot.server.luau", "print('boot 2')\n");
		check(await waitPackets(second.packets, 1, 8000) && await waitPackets(ws.packets, seenMain + 2, 3000), "druhé spojení: změna dojde oběma");
		const plainUpdate = second.packets[0].body.messages[0].updated[0];
		const mainUpdate = ws.packets[seenMain].body.messages[0].updated[0];
		check(plainUpdate.changedClassName === undefined && plainUpdate.changedProperties.Source.String === "print('boot 2')\n", "druhé spojení: Script jen přepsat (žádné changedClassName)");
		check(mainUpdate.changedClassName === "Script" && mainUpdate.id === plainUpdate.id, "hlavní spojení: týž Script znovu vytvořit");
		check(second.packets[0].body.messageCursor === ws.packets[seenMain].body.messageCursor, "obě podoby mají stejný kurzor");
		await sleep(300);
		check(second.packets.length === 1, "druhé spojení: bez kontrolní zprávy");
		const bootProbe = ws.packets[seenMain + 1].body.messages[0].updated[0];
		await request(port, "POST", "/api/serialize", sync.encode({ sessionId, ids: [bootProbe.id] }));
		check(await run.waitFor(/✓ Studio převzalo změnu \(~1\) \(za/, 10000, 2), "druhé spojení: hlavní potvrdí");
		second.socket.destroy();
		check(await run.waitFor(/· druhé spojení odpojeno/), "druhé spojení: odpojení");

		// Malá změna bez potvrzení → varování s radou.
		write("src/shared/Small.luau", "return 2\n");
		check(await run.waitFor(/! Studio nepotvrdilo změnu \(~1\)/, 12000), "server: varuje, když Studio nepotvrdí");
		check(await run.waitFor(/smaž ReplicatedStorage\.Shared, ServerScriptService\.Server/, 3000), "server: rada, co smazat");
		const late = ws.packets[ws.packets.length - 1].body.messages[0].updated[0];
		await request(port, "POST", "/api/serialize", sync.encode({ sessionId, ids: [late.id] }));
		check(await run.waitFor(/✓ Studio převzalo změnu \(~1\) \(za [\d.]+ s, pozdě\)/), "server: pozdní potvrzení");

		ws.socket.destroy();
		check(await run.waitFor(/· Studio odpojeno/), "server: odpojení");

		// --in-place: po Connect nic navíc.
		const port2 = await freePort();
		const old = startSync(root, port2, ["--in-place"]);
		procs.push(old.child);
		check(await old.waitFor(/režim:\s+--in-place/), "in-place: start");
		const read2 = await request(port2, "GET", `/api/read/${info.body.rootInstanceId}`);
		const ws2 = await openSocket(port2, read2.body.messageCursor);
		await sleep(700);
		check(ws2.packets.length === 0, "in-place: po Connect žádné zprávy");
		ws2.socket.destroy();
	} finally {
		for (const child of procs) {
			child.kill();
		}
		fs.rmSync(root, { recursive: true, force: true });
	}
}

serverTest()
	.catch((err) => {
		check(false, `server: ${err.stack || err}`);
	})
	.then(() => {
		if (failures) {
			console.log(`${failures} z ${checks} kontrol selhalo`);
			process.exit(1);
		}
		console.log(`ALL CHECKS PASSED (${checks})`);
	});
