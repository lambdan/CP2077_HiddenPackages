local HiddenPackagesMetadata = {
	title = "Hidden Packages",
	version = "1.0"
}

local GameSession = require("Modules/GameSession.lua")
local GameUI = require("Modules/GameUI.lua")
local GameHUD = require("Modules/GameHUD.lua")

local showWindow = false
local alwaysShowWindow = false

local LocationsFile = "debug.txt"

local spawnedEnts = {}
local spawnedNames = {}
local collectedNames = {}

local playerAtHP = "No"

local HiddenPackagesLocations = {}

local isLoaded = false

local propPath = "base/environment/architecture/common/int/int_mlt_jp_arasaka_a/arasaka_logo_tree.ent" -- spinning red arasaka logo
local propZboost = 0.5 -- arasaka logo is kinda low so boost it upwards a little

registerForEvent("onOverlayOpen", function()
	showWindow = true
end)

registerForEvent("onOverlayClose", function()
	showWindow = false
end)


registerForEvent('onInit', function()

	readHPLocations(LocationsFile)

	isLoaded = Game.GetPlayer() and Game.GetPlayer():IsAttached() and not Game.GetSystemRequestsHandler():IsPreGame()

	GameSession.OnSave(function()
		saveData(LocationsFile .. ".save")
	end)

	GameSession.OnLoad(function()
		reset()
		loadSaveData(LocationsFile .. ".save")
	end)

    Observe('PlayerPuppet', 'OnAction', function(action) -- any player action
        checkIfPlayerAtHP()
    end)

	Observe('QuestTrackerGameController', 'OnInitialize', function()
	    if not isLoaded then
	        --print('Game Session Started')
	        isLoaded = true

	        if not loadSaveData(LocationsFile .. ".save") then
	        	spawnHPs() -- no save so just spawn them
	        end
	    end
	end)

	Observe('QuestTrackerGameController', 'OnUninitialize', function()
	    if Game.GetPlayer() == nil then
	        --print('Game Session Ended')
	        isLoaded = false
	        reset() -- destory all objects and reset tables etc
	    end
	end)
end)

registerForEvent('onDraw', function()

	if showWindow or alwaysShowWindow then
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

		ImGui.Text("Read locations from file:")
		LocationsFile = ImGui.InputText("", LocationsFile, 100)
		if ImGui.Button("Read") then
			readHPLocations(LocationsFile)
		end
		ImGui.Separator()

		if ImGui.Button("Always show window") then
			alwaysShowWindow = not alwaysShowWindow
		end
		ImGui.SameLine()
		ImGui.Text(tostring(alwaysShowWindow))
		ImGui.Separator()

		ImGui.Text("Player Pos:")
		if isLoaded then
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
		else
			ImGui.Text("Not in-game")
		end
		ImGui.Separator()
		--checkIfPlayerAtHP()

		ImGui.Text("PLAYER AT HP: " .. playerAtHP)

		local s = "Available HPs: "
		for k,v in ipairs(spawnedNames) do
			s = s .. v .. ","
		end
		ImGui.Text(s)

		local s = "Collected HPs: "
		for k,v in ipairs(collectedNames) do
			s = s .. v .. ","
		end
		ImGui.Text(s)

		ImGui.Text("Collected: " .. tostring(tableLen(collectedNames)) .. "/" .. tostring(tableLen(HiddenPackagesLocations)))

		ImGui.Text("isLoaded:" .. tostring(isLoaded))

		ImGui.Text("inVehicle: " .. tostring(inVehicle()))

		if ImGui.Button("Give me a hint...")  then
			for k,v in ipairs(HiddenPackagesLocations) do
				if has_value(collectedNames, v["id"]) == false then -- check if package is in collectedNames, if so we already got it
					placeMapPin(v["x"], v["y"], v["z"], v["w"])
					break -- only place one

				end
			end
	end

		ImGui.End()
	end

end)


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
	if not isLoaded then
		return
	end

    local transform = Game.GetPlayer():GetWorldTransform()
    local pos = Game.GetPlayer():GetWorldPosition()
    pos.x = x
    pos.y = y
    pos.z = z + propZboost
    pos.w = w
    transform:SetPosition(pos)

    local ID = WorldFunctionalTests.SpawnEntity(propPath, transform, '')
    print("Object spawned ID: " .. tostring(ID))
    return ID
end


function checkIfPlayerAtHP()
	if not isLoaded then
		return
	end

	local atHP = false

	for k,v in ipairs(HiddenPackagesLocations) do
		if isPlayerAtPos(v["x"], v["y"], (v["z"] + propZboost), v["w"]) then
			atHP = true
			playerAtHP =  "Yes: " .. v["id"]
			if not inVehicle() then
				collectHP(v["id"])
			end
		end
	end

	if atHP == false then
		playerAtHP = "No"
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
        --print("Destroyed object: ", e)
    else
    	--print("NOT DESTROYED OBJECT (nil): ", e)
    end
end

function spawnHPs()
	for k,v in ipairs(HiddenPackagesLocations) do

		if has_value(collectedNames, v["id"]) == false then -- check if package is in collectedNames, if so we already got it --> dont spawn it

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
			--print("Destroying", name)
			entity = spawnedEnts[k]
			destroyObject(entity)
			table.remove(spawnedEnts, k)
			table.remove(spawnedNames, k)
			table.insert(collectedNames, name)
        end
    end

    if tableLen(collectedNames) == tableLen(HiddenPackagesLocations) then
    	-- got em all
    	local msg = "All Hidden Packages collected!" -- VC message
    	GameHUD.ShowWarning(msg)
    else
    	local msg = "Hidden Package " .. tostring(tableLen(collectedNames)) .. " of " .. tostring(tableLen(HiddenPackagesLocations))
    	GameHUD.ShowWarning(msg)
    end

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
		return false -- nothing to save
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
	return true
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
	return true
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
	print("Reading " .. filename)

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
		hp["id"] = "hp" .. tostring(k)
		hp["x"] = tonumber(vals[1])
		hp["y"] = tonumber(vals[2])
		hp["z"] = tonumber(vals[3])
		hp["w"] = tonumber(vals[4])
		table.insert(HiddenPackagesLocations, hp)
	end

	print("Loaded " .. filename)
end

-- from CET Snippets discord... could be useful
-- function showCustomShardPopup(titel, text)
--     shardUIevent = NotifyShardRead.new()
--     shardUIevent.title = titel
--     shardUIevent.text = text
--     Game.GetUISystem():QueueEvent(shardUIevent)
-- end

-- custom map pin
-- registerHotkey('PlaceCustomMapPin', 'Place a map pin at player\'s position', function()
--     local mappinData = MappinData.new()
--     mappinData.mappinType = TweakDBID.new('Mappins.DefaultStaticMappin')
--     mappinData.variant = gamedataMappinVariant.FastTravelVariant
--     mappinData.visibleThroughWalls = true
    
--     local position = Game.GetPlayer():GetWorldPosition()
    
--     Game.GetMappinSystem():RegisterMappin(mappinData, position)
-- end)

function inVehicle() -- stolen from AdaptiveGraphicsQuality (https://www.nexusmods.com/cyberpunk2077/mods/2920)
	local ws = Game.GetWorkspotSystem()
	local player = Game.GetPlayer()
	if ws and player then
		local info = ws:GetExtendedInfo(player)
		if info then
			return ws:IsActorInWorkspot(player)
				and not not Game['GetMountedVehicle;GameObject'](Game.GetPlayer())
		end
	end
end

function placeMapPin(x,y,z,w)
	local mappinData = MappinData.new()
	mappinData.mappinType = TweakDBID.new('Mappins.DefaultStaticMappin')
	mappinData.variant = gamedataMappinVariant.CustomPositionVariant
	mappinData.visibleThroughWalls = true   

	local position = Game.GetPlayer():GetWorldPosition()
	position.x = x
	position.y = y
	position.z = z + propZboost
	position.w = w

	Game.GetMappinSystem():RegisterMappin(mappinData, position)
end
