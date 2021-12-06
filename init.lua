local HiddenPackagesMetadata = {
	title = "Hidden Packages",
	version = "1.0"
}

local GameSession = require("Modules/GameSession.lua")
local GameUI = require("Modules/GameUI.lua")
local GameHUD = require("Modules/GameHUD.lua")

local showSettings = false

local spawnedEnts = {}
local spawnedNames = {}
local collectedNames = {}

local playerAtHP = "..."

local HiddenPackagesLocations = {}

function getPlayerPos()

	local gps = Game.GetPlayer():GetWorldPosition() -- returns a ToVector4...
	local position = {} -- ... so we'll convert into a traditional table
	position["x"] = gps["x"]
	position["y"] = gps["y"]
	position["z"] = gps["z"]
	position["w"] = gps["w"]

	print("GPS: ", gps)
	print(position["x"])
	print(position["y"])
	print(position["z"])
	print(position["w"])

	return {position}
end

function printHPpos()
	for k,v in ipairs(HiddenPackagesLocations) do
		print("--- HP " .. k .. " ---")
		for a,b in pairs(v) do
			print(a,b)
		end
		print("------")
	end
end

function spawnObjectAtPos(x,y,z,w)
    local transform = Game.GetPlayer():GetWorldTransform()
    local pos = Game.GetPlayer():GetWorldPosition()
    pos.x = x
    pos.y = y
    pos.z = z
    pos.w = w
    transform:SetPosition(pos)

    --local rID = WorldFunctionalTests.SpawnEntity("base\\quest\\main_quests\\prologue\\q000\\entities\\q000_invisible_radio.ent", transform, '')
    --table.insert(logic.radios, rID)
    local ID = WorldFunctionalTests.SpawnEntity("base\\environment\\decoration\\containers\\baskets\\laundry_basket\\laundry_basket_a_full_a_dst.ent", transform, '')
    print("Object spawned ID: " .. tostring(ID))
    return ID
end

registerForEvent("onOverlayOpen", function()
	showSettings = true
end)

registerForEvent("onOverlayClose", function()
	showSettings = false
end)


registerForEvent('onInit', function()

	--GameSession.OnSave(function()
		--saveData("collected_packages.json")
	--end)

	--GameSession.OnLoad(function()
	--	reset()
	--end)

	--Observe('NPCPuppet', 'SendAfterDeathOrDefeatEvent', function(self)
	--	if self.shouldDie and (IsPlayer(self.myKiller) or self.wasJustKilledOrDefeated) then
	--		local WhatWeKilled = GetInfo(self)
	--		gotKill(WhatWeKilled)
	--	end
	--end)
end)

registerForEvent('onDraw', function()

	--if showSettings then
	if 1 == 1 then
		ImGui.Begin("Hidden Packages")

		if ImGui.Button("Save") then
			saveData("save.json")
		end
		ImGui.SameLine()
		if ImGui.Button("Load") then 
			loadSaveData("save.json")
		end

		if ImGui.Button("Reset/Clean") then
			reset()
		end

		ImGui.Separator()

		if ImGui.Button("Dump HP positions") then
			printHPpos()
		end

		if ImGui.Button("spawnHPs()") then
			spawnHPs()
		end

		if ImGui.Button("destroyAll()") then
			destroyAll()
		end

		ImGui.Separator()

		ImGui.Text("Read locations:")

		if ImGui.Button("debugging.txt") then
			readHPLocations("debugging.txt")
		end

		if ImGui.Button("debugging2.txt") then
			readHPLocations("debugging2.txt")
		end

		ImGui.Separator()

		local gps = Game.GetPlayer():GetWorldPosition()
		local position = {} -- ... so we'll convert into a traditional table
		position["x"] = gps["x"]
		position["y"] = gps["y"]
		position["z"] = gps["z"]
		position["w"] = gps["w"]
		ImGui.Text("X: " .. tostring(position["x"]))
		ImGui.Text("Y: " .. tostring(position["y"]))
		ImGui.Text("Z: " .. tostring(position["z"]))
		ImGui.Text("W: " .. tostring(position["w"]))

		checkIfPlayerAtHP()

		ImGui.Text("PLAYER AT HP: " .. playerAtHP)

		local s = "Available HPs: "
		for k,v in ipairs(spawnedNames) do
			s = s .. v .. ","
		end
		ImGui.Text(s)

		ImGui.Text(tostring(tableLen(collectedNames)) .. "/" .. tostring(tableLen(HiddenPackagesLocations)))


		ImGui.End()
	end

end)

function checkIfPlayerAtHP()
	local atHP = false

	for k,v in ipairs(HiddenPackagesLocations) do
		if isPlayerAtPos(v["x"], v["y"], v["z"], v["w"]) then
			atHP = true
			playerAtHP =  v["id"] .. " !!!"
			collectHP(v["id"])
		end
	end

	if atHP == false then
		playerAtHP = "..."
	end
end

function isPlayerAtPos(x,y,z,w)
	local playerPos = Game.GetPlayer():GetWorldPosition()
	if math.abs(playerPos["x"] - x) < 0.5 then
		if math.abs(playerPos["y"] - y) < 0.5 then
			if math.abs(playerPos["z"] - z) < 0.5 then
				if playerPos["w"] == w then
					return true
				end
			end
		end
	end
	return false
end

function destroyObject(e)
	if Game.FindEntityByID(e) ~= nil then
        Game.FindEntityByID(e):GetEntity():Destroy()
        print("Destroyed object: ", e)
    else
    	print("NOT DESTROYED OBJECT (nil): ", e)
    end
end

function spawnHPs()
	for k,v in ipairs(HiddenPackagesLocations) do

		if has_value(collectedNames, v["id"]) == false then

			local entID = spawnObjectAtPos(v["x"], v["y"], v["z"], v["w"])
			table.insert(spawnedEnts, entID)
			table.insert(spawnedNames, v["id"])
			print("Spawned", v["id"])

		end
	end
end

function collectHP(name)
	if has_value(spawnedNames, name) == false then
		return
	end

	--GameHUD.ShowMessage(tostring(name) .. " COLLECTED")
	-- find ent and destroy it
	for k,v in ipairs(spawnedNames) do
		if v == name then
			print("Destroying", name)
			entity = spawnedEnts[k]
			destroyObject(entity)
			table.remove(spawnedEnts, k)
			table.remove(spawnedNames, k)
			table.insert(collectedNames, name)
        end
    end

    local msg = "Hidden Package " .. tostring(tableLen(collectedNames)) .. " of " .. tostring(tableLen(HiddenPackagesLocations))
    GameHUD.ShowMessage(msg)
end


function has_value(tab,val)
	for i,v in ipairs(tab) do
		if val == v then
			return true
		end
	end
	return false
end

function tableLen(table)
	local i = 0
	for p in pairs(table) do
		i = i + 1
	end
	return i
end

function saveData(filename)
	if tableLen(collectedNames) == 0 then
		print("Hidden Packages: nothing to save?")
		return -- nothing to save
	end

	-- convert table to string
	local s = ""
	for k,v in ipairs(collectedNames) do
		s = s .. v .. ","
	end

	data = {
		collected_packages = s
	}

	local file = io.open(filename, "w")
	local j = json.encode(data)
	file:write(j)
	file:close()
	print("Hidden Packages: saved to " .. filename)
end

function loadSaveData(filename)
	if not file_exists(filename) then
		print("Hidden Packages: failed to load save, didnt exist?")
		return false
	end

	local file = io.open(filename,"r")
	local j = json.decode(file:read("*a"))
	file:close()

	collectedNames = {}
	local s = j["collected_packages"]
	for word in string.gmatch(s, '([^,]+)') do -- https://stackoverflow.com/a/19262818
		table.insert(collectedNames, word)
	end

	destroyAll()
	spawnHPs()
	print("Hidden Packages: loaded " .. filename)
end

function file_exists(filename) -- https://stackoverflow.com/a/4991602
    local f=io.open(filename,"r")
    if f~=nil then io.close(f) return true else return false end
end

function reset()
	print("reset()")
	destroyAll()
	collectedNames = {}
end

function destroyAll()
	print("destroyAll()")
	for k,v in ipairs(spawnedEnts) do
		destroyObject(v)
	end
	spawnedNames = {}
	spawnedEnts = {}


end

function readHPLocations(filename)
	if not file_exists(filename) then
		print("Hidden Packages: faield to load " .. filename)
		return false
	end

	HiddenPackagesLocations = {}
	lines = {}
	for line in io.lines(filename) do
		if (line ~= nil) and (line ~= "") and not (string.match(line, "#")) then 
			lines[#lines + 1] = line
		end
	end

	for k,v in pairs(lines) do
		local vals = {}
		for word in string.gmatch(v, '([^ ]+)') do
			table.insert(vals,word)
		end

		local hp = {}
		hp["id"] = vals[1]
		hp["x"] = tonumber(vals[2])
		hp["y"] = tonumber(vals[3])
		hp["z"] = tonumber(vals[4])
		hp["w"] = tonumber(vals[5])

		table.insert(HiddenPackagesLocations, hp)
	end

	print("Loaded " .. filename)
end


-- TODO
-- save file name based on which locations txt you use (eg debugging.txt -> debugging.txt.save.json)
-- 100 good locations! and a map for them!
-- more testing... this has gone way too smooth. seems to go crazy if you dont restart game if you reload stuff a bunch of times.
-- make sister mod that just spits out locations to a txt so you can easily make locations