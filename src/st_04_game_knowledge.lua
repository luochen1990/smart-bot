----------------------- basic knowledge about the game -------------------------

const = {
	activeRadius = 100, -- this will decide default refuel level 
	turtle = {
		needfuel = true,
		backpackSlotsNum = 16,
		baseAPIs = {
			"forward", "back", "up", "down", "turnLeft", "turnRight",
			"refuel", "getFuelLevel", "getFuelLimit",
			"select", "getSelectedSlot", "getItemCount", "getItemSpace", "getItemDetail", "transferTo",
			"compare", "compareUp", "compareDown", "compareTo",
			"suck", "suckUp", "suckDown", "drop", "dropUp", "dropDown",
			"dig", "digUp", "digDown", "place", "placeUp", "placeDown",
			"detect", "detectUp", "detectDown", "inspect", "inspectUp", "inspectDown",
			"attack", "attackUp", "attackDown", "equipLeft", "equipRight",
		},
	},
	cheapItems = {
		"minecraft:cobblestone",
		"minecraft:dirt",
		"minecraft:gravel",
	},
	valuableItems = {
		"*:diamond*",
		"*:gold_*",
		"*:redstone*",
		"*:emerald*",
		"*:lapis*",
		"*:*_ore",
	},
	afterDig = {
		["minecraft:stone"] = "minecraft:cobblestone",
		["minecraft:grass_block"] = "minecraft:dirt",
	},
	groundBlocks = {
		"minecraft:dirt",
		"minecraft:stone",
		"minecraft:cobblestone",
		"minecraft:sand",
		"minecraft:end_stone",
		"minecraft:netherrack",
	},
	chestBlocks = {
		"minecraft:chest",
		"minecraft:trapped_chest",
		"minecraft:shulker_box",
	},
	otherContainerBlocks = { -- containers other than turtle or chest
	},
	fuelHeatContent = {
		["minecraft:lava_bucket"] = 1000,
		["minecraft:charcoal"] = 80,
		["minecraft:coal"] = 80,
		["minecraft:stick"] = 5,
		--["minecraft:*_log"] = 15,
		["minecraft:*_planks"] = 15,
		["minecraft:*_carpet"] = 3,
	},
}

const.dir = {
	['E'] = vec.axis.X, ['W'] = -vec.axis.X,
	['U'] = vec.axis.Y, ['D'] = -vec.axis.Y,
	['S'] = vec.axis.Z, ['N'] = -vec.axis.Z,
}
for k, v in pairs(const.dir) do _ENV[k] = v end -- define U/E/S/W/N/D
const.preferDirections = {U, E, S, W, N, D}
const.rotate = { left = const.dir.D, right = const.dir.U, }

showDir = function(d)
	for k, v in pairs(const.dir) do if d == v then return k end end
end

_item = {
	isTurtle = glob("computercraft:turtle_*"),
	isModem = glob("computercraft:wireless_modem*"),
	isChest = glob(const.chestBlocks),
	isContainer = (function()
		local p = glob(const.otherContainerBlocks)
		return function(name) return _item.isChest(name) or _item.isTurtle(name) or p(name) end
	end)(),
	isCheap = glob(const.cheapItems),
	isValuable = glob(const.valuableItems),
	isNotValuable = combine(function(b) return not b end)(glob(const.valuableItems)),
	fuelHeatContent = globDict(const.fuelHeatContent),
}

