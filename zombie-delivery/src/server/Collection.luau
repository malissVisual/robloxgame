--!strict
-- 8.0 SANDBOX: your collection (design/sandbox/KONTRAKT.md, "Collection"). Everything you bring home from a move is
-- yours: it waits in your warehouse's stock until you put it on show on a display stand (then it earns money every
-- minute you play) or sell it. The server decides every value; the save keeps the collection.
--
-- STUB: the API the other 8.0 work codes against. The collection agent fills it in (keep these names and shapes).
--
--   Collection.add(player, entry)              one piece into your stock: entry = { item, variant?, condition, name? }
--                                              → its uid (nil: refused, e.g. no save yet)
--   Collection.stock(player)                   { Entry } everything you own (on show or not)
--   Collection.display(player, uid, stand)     put a piece of your stock on display stand `stand` (an index of your
--                                              warehouse's stands) → ok, why
--   Collection.undisplay(player, uid)          take it down (back to the stock) → ok, why
--   Collection.sell(player, uid)               sell it (on show or not) → the money paid (nil: refused), why
--   Collection.incomePerMinute(player)         what your pieces on show earn a minute now
--   Collection.openPicker(player, stand)       (Warehouse: an empty display stand's prompt) ask the player's client to
--                                              pick a piece for it (the "Collection" remote's { kind = "pick", stand })
--   Collection.onChanged(fn)                   fn(player) after any change to a player's collection

local Collection = {}

export type Entry = {
	uid: string,
	item: string, -- Config.Furniture / FurnitureLooks id
	variant: number,
	condition: number, -- 0..1
	name: string,
	stand: number?, -- on show on this display stand of your warehouse (nil: in the stock)
	got: number, -- os.time() it came home
}

local listeners: { (Player) -> () } = {}

function Collection.add(_player: Player, _entry: { item: string, variant: number?, condition: number, name: string? }): string?
	return nil
end

function Collection.stock(_player: Player): { Entry }
	return {}
end

function Collection.display(_player: Player, _uid: string, _stand: number): (boolean, string?)
	return false, "not yet"
end

function Collection.undisplay(_player: Player, _uid: string): (boolean, string?)
	return false, "not yet"
end

function Collection.sell(_player: Player, _uid: string): (number?, string?)
	return nil, "not yet"
end

function Collection.incomePerMinute(_player: Player): number
	return 0
end

function Collection.openPicker(_player: Player, _stand: number) end

function Collection.onChanged(fn: (Player) -> ())
	table.insert(listeners, fn)
end

function Collection.start() end

return Collection
