local HiddenPackagesMetadata = {
	title = "Hidden Packages",
	version = "0.1"
}

local GameSession = require("Modules/GameSession.lua")
local GameUI = require("Modules/GameUI.lua")
local GameHUD = require("Modules/GameHUD.lua")

local showWindow = false
local alwaysShowWindow = false

local LocationsFile = "packages1.txt" -- used as fallback also
local propPath = "base/environment/architecture/common/int/int_mlt_jp_arasaka_a/arasaka_logo_tree.ent" -- spinning red arasaka logo
local propZboost = 0.5 -- arasaka logo is kinda low so boost it upwards a little

-- inits
local spawnedEnts = {} -- prop ids for the spawned packages
local spawnedNames = {} -- names of the spawned packages
local collectedNames = {} -- names of collected packages
local activeMappins = {} -- object ids for map pins
local HiddenPackagesLocations = {} -- locations loaded from file

local isLoaded = false
local newLocationsFile = LocationsFile -- used for text field


registerHotkey("hp_place_waypoint", "Waypoint to next package", function()
	for k,v in ipairs(HiddenPackagesLocations) do
		if tableHasValue(collectedNames, v["id"]) == false then -- check if package is in collectedNames, if so we already got it
			activeMappins[k] = placeMapPin(v["x"], v["y"], v["z"], v["w"])
			GameHUD.ShowMessage("\"Hidden\" Package marked") -- not very hidden when you have a waypoint to it ;)
			break -- only place one
		end
	end
end)

registerForEvent("onOverlayOpen", function()
	showWindow = true
end)

registerForEvent("onOverlayClose", function()
	showWindow = false
end)


registerForEvent('onInit', function()

	loadLastUsed() -- try to load last used locations file, otherwise it will fallback to what is set above
	readHPLocations(LocationsFile)

	isLoaded = Game.GetPlayer() and Game.GetPlayer():IsAttached() and not Game.GetSystemRequestsHandler():IsPreGame()

	GameSession.OnSave(function()
		saveData(LocationsFile .. ".save")
	end)

	GameSession.OnLoad(function()
		reset()
		loadSaveData(LocationsFile .. ".save")
	end)

	Observe('PlayerPuppet', 'OnDeath', function()
  		reset()
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

		ImGui.Text("Collected: " .. tostring(tableLen(collectedNames)) .. "/" .. tostring(tableLen(HiddenPackagesLocations)) .. " (" .. LocationsFile .. ")")

		if tableLen(collectedNames) < tableLen(HiddenPackagesLocations) then
			if ImGui.Button("Place waypoint to a package")  then
				for k,v in ipairs(HiddenPackagesLocations) do
					if tableHasValue(collectedNames, v["id"]) == false then -- check if package is in collectedNames, if so we already got it
						activeMappins[k] = placeMapPin(v["x"], v["y"], v["z"], v["w"])
						break -- only place one
					end
				end
			end
			if ImGui.Button("Place waypoints to ALL packages")  then
				for k,v in ipairs(HiddenPackagesLocations) do
					if tableHasValue(collectedNames, v["id"]) == false then -- check if package is in collectedNames, if so we already got it
						activeMappins[k] = placeMapPin(v["x"], v["y"], v["z"], v["w"])
					end
				end
			end

			ImGui.Text("NOTE: Waypoints tend to be buggy and not disappear.\nReloading save should fix it.")
		else
			ImGui.Text("You got them all!")
		end

		ImGui.Separator()
		ImGui.Text("Load new locations file:")
		newLocationsFile = ImGui.InputText("", newLocationsFile, 50)
		if ImGui.Button("Load") then
			if file_exists(newLocationsFile) then
				LocationsFile = newLocationsFile
				reset()
				readHPLocations(LocationsFile)
				if not loadSaveData(LocationsFile .. ".save") then
					spawnHPs()
				end
				saveLastUsed()
			else
				print("Hidden Packages ERROR: file " .. newLocationsFile .. " did not exist?")
			end
		end
		ImGui.Separator()

		ImGui.Text("Player Position:")
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
			ImGui.Text("(Not in-game)")
		end

		if ImGui.Button("Always show this window") then
			alwaysShowWindow = not alwaysShowWindow
		end
		ImGui.SameLine()
		ImGui.Text(tostring(alwaysShowWindow))

		ImGui.Text("")
		ImGui.Text(" - Scary buttons - ")
		
		if ImGui.Button("Delete save & reset progress\n(" .. LocationsFile .. ")") then
			deleteSave()
			reset()
			spawnHPs()
		end

		if ImGui.Button("reset()") then
			reset()
		end
		if ImGui.Button("spawnHPs()") then
			spawnHPs()
		end
		if ImGui.Button("destroyAll()") then
			destroyAll()
		end
		if ImGui.Button("printAllHPs()") then
			printAllHPs()
		end

		
		-- randomizers
		ImGui.Text("")
		ImGui.Text(" - Randomizers - ")
		if ImGui.Button("Randomizer (1 package)") then
			LocationsFile = "RANDOM"
			reset()
			generateRandomPackages(1)
			spawnHPs()
			print("HP Randomizer done")
		end

		if ImGui.Button("Randomizer (10 packages)") then
			LocationsFile = "RANDOM"
			reset()
			generateRandomPackages(10)
			spawnHPs()
			print("HP Randomizer done")
		end

		if ImGui.Button("Randomizer (100 packages)") then
			LocationsFile = "RANDOM"
			reset()
			generateRandomPackages(100)
			spawnHPs()
			print("HP Randomizer done")
		end

		if ImGui.Button("Randomizer (1000 packages) (game will be laggy)") then
			LocationsFile = "RANDOM"
			reset()
			generateRandomPackages(1000)
			spawnHPs()
			print("HP Randomizer done")
		end

		if ImGui.Button("Randomizer (10000 packages) (game will be unresponsive)") then
			LocationsFile = "RANDOM"
			reset()
			generateRandomPackages(10000)
			spawnHPs()
			print("HP Randomizer done")
		end

		if ImGui.Button("Randomizer (100000 packages) (game will die)") then
			LocationsFile = "RANDOM"
			reset()
			generateRandomPackages(100000)
			spawnHPs()
			print("HP Randomizer done")
		end
		ImGui.Text("Random packages are very likely to appear in unreachable areas.\nUseful for testing only... unless you really want to go insane")

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

function printAllHPs()
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
    --print("Object spawned ID: " .. tostring(ID))
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
			if not inVehicle() then -- only allow picking them up on foot (like in the GTA games)
				collectHP(v["id"])
			end
		end
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

		if tableHasValue(collectedNames, v["id"]) == false then -- check if package is in collectedNames, if so we already got it --> dont spawn it

			local entID = spawnObjectAtPos(v["x"], v["y"], v["z"], v["w"])
			table.insert(spawnedEnts, entID)
			table.insert(spawnedNames, v["id"])
			activeMappins[k] = false
			print("Hidden Packages: spawned package ", v["id"])

		end
	end
end

function collectHP(name) -- name is more like packageID
	if tableHasValue(spawnedNames, name) == false then -- check if HP is NOT spawned and if so dont allow picking it up
		return
	end

	-- find object ent and destroy(despawn) it
	for k,v in ipairs(spawnedNames) do
		if v == name then
			--print("Destroying", name)
			entity = spawnedEnts[k]
			destroyObject(entity)
			table.remove(spawnedEnts, k)
			table.remove(spawnedNames, k)
			table.insert(collectedNames, name)
			
			-- unregister mappin and remove it
			-- k is not usable here as mappins use HiddenPackageLocations index
			for k2,v2 in ipairs(HiddenPackagesLocations) do
				if v2["id"] == name then
					if activeMappins[k2] then
						Game.GetMappinSystem():UnregisterMappin(activeMappins[k2])
					end
					activeMappins[k2] = false
					break
				end
			end

			break
        end
    end

    if tableLen(collectedNames) == tableLen(HiddenPackagesLocations) then
    	-- got em all
    	local msg = "All Hidden Packages collected!"
    	GameHUD.ShowWarning(msg)
    	-- TODO give reward here
    else
    	local msg = "Hidden Package " .. tostring(tableLen(collectedNames)) .. " of " .. tostring(tableLen(HiddenPackagesLocations))
    	GameHUD.ShowWarning(msg)
    end

end


function tableHasValue(tab,val)
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
	destroyAll()
	collectedNames = {}
	print("Hidden Packages: reset ok")
end

function destroyAll()
	for k,v in ipairs(spawnedEnts) do
		destroyObject(v)
	end
	spawnedNames = {}
	spawnedEnts = {}
	print("Hidden Packages: destroyed all spawned packages")


end

function readHPLocations(filename)
	if not file_exists(filename) then
		print("Hidden Packages: failed to load " .. filename)
		return false
	end
	print("Reading HP locations from " .. filename)

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
		-- id is based on coordinates so that the order of the lines in the packages file is not important and can be moved around later on
		hp["id"] = "hp_x" .. tostring(vals[1]) .. "y" .. tostring(vals[2]) .. "z" .. tostring(vals[3]) .. "w" .. tostring(vals[4])
		hp["x"] = tonumber(vals[1])
		hp["y"] = tonumber(vals[2])
		hp["z"] = tonumber(vals[3])
		hp["w"] = tonumber(vals[4])
		table.insert(HiddenPackagesLocations, hp)
	end

	print("Hidden Packages: loaded locations file " .. filename)
end

-- from CET Snippets discord... could be useful
-- function showCustomShardPopup(titel, text)
--     shardUIevent = NotifyShardRead.new()
--     shardUIevent.title = titel
--     shardUIevent.text = text
--     Game.GetUISystem():QueueEvent(shardUIevent)
-- end

function inVehicle() -- from AdaptiveGraphicsQuality (https://www.nexusmods.com/cyberpunk2077/mods/2920)
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

function placeMapPin(x,y,z,w) -- from CET Snippets discord
	local mappinData = MappinData.new()
	mappinData.mappinType = TweakDBID.new('Mappins.DefaultStaticMappin')
	mappinData.variant = gamedataMappinVariant.CustomPositionVariant -- see more types: https://github.com/WolvenKit/CyberCAT/blob/main/CyberCAT.Core/Enums/Dumped%20Enums/gamedataMappinVariant.cs
	mappinData.visibleThroughWalls = true   

	local position = Game.GetPlayer():GetWorldPosition()
	position.x = x
	position.y = y
	position.z = z + propZboost
	position.w = w

	return Game.GetMappinSystem():RegisterMappin(mappinData, position) -- returns ID 
end

function saveLastUsed()
	data = {
		last_used = LocationsFile
	}
	local file = io.open("LAST_USED", "w")
	local j = json.encode(data)
	file:write(j)
	file:close()
end

function loadLastUsed()
	if not file_exists("LAST_USED") then
		--print("Hidden Packages: no last used found")
		return false
	end

	local file = io.open("LAST_USED","r")
	local j = json.decode(file:read("*a"))
	file:close()

	LocationsFile = j["last_used"]
	newLocationsFile = LocationsFile
	print("Hidden Packages: loaded last used: " .. j["last_used"])
	return true
end

function deleteSave()
	filename = LocationsFile .. ".save"
	if not file_exists(filename) then
		return false
	end

	if os.remove(filename) then
		print("Deleted", filename)
		return true
	else
		return false
	end
end

function generateRandomPackages(n)
	print("Hidden Packages: generating " .. n .. " random packages...")
	HiddenPackagesLocations = {}
	local i = 0
	while (i < n) do
		x = math.random(-2623, 3598)
		y = math.random(-4011, 3640)
		z = math.random(1, 120)
		w = 1

		local hp = {}
		hp["id"] = "hp_x" .. tostring(x) .. "y" .. tostring(y) .. "z" .. tostring(z) .. "w" .. tostring(w)
		hp["x"] = x
		hp["y"] = y
		hp["z"] = z
		hp["w"] = w
		table.insert(HiddenPackagesLocations, hp)

		i = i + 1
	end

end

