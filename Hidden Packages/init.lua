local HiddenPackagesMetadata = {
	title = "Hidden Packages",
	version = "2.0.0"
}

local GameSession = require("Modules/GameSession.lua")
local GameHUD = require("Modules/GameHUD.lua")
local LEX = require("Modules/LuaEX.lua")

local MAPS_FOLDER = "Maps" -- should NOT end with a /
local MAP_DEFAULT = "Maps/packages1.map" -- full path to default map

local MOD_SETTINGS = {
	DebugMode = false,
	ShowPerformanceWindow = false,
	SpawnPackageRange = 100,
	HintAudioEnabled = false,
	HintAudioRange = 150,
	MapPath = MAP_DEFAULT
}

local SESSION_DATA = { -- will persist
	collectedPackageIDs = {}
}

local LOADED_PACKAGES = {}

local HUDMessage_Current = ""
local HUDMessage_Last = 0

-- props
local PACKAGE_PROP = "base/quest/main_quests/prologue/q005/afterlife/entities/q005_hologram_cube.ent"
local PACKAGE_PROP_Z_BOOST = 0.25

-- inits
local activeMappins = {} -- object ids for map pins
local activePackages = {}
local isInGame = false
local isPaused = true
local NEED_TO_REFRESH = false

local lastCheck = 0
local lastAudioHint = 0
local checkThrottle = 1

-- performance stuff
local loopTimesAvg = {}
local performanceTextbox1 = "speed/s"
local performanceTextbox2 = "ms"
local performanceTextbox3 = "avg"


registerHotkey("hp_nearest_pkg", "Mark nearest package", function()
	markNearestPackage()
end)

registerForEvent('onShutdown', function() -- mod reload, game shutdown etc
    reset()
end)

registerForEvent('onInit', function()
	loadSettings()
	NEED_TO_REFRESH = true

	-- scan Maps folder and generate table suitable for nativeSettings
	local mapsPaths = {[1] = false}
	local nsMapsDisplayNames = {[1] = "None"}
	local nsDefaultMap = 1
	local nsCurrentMap = 1
	for k,v in pairs(listFilesInFolder(MAPS_FOLDER)) do
		if LEX.stringEnds(v, ".map") then
			local i = LEX.tableLen(mapsPaths) + 1
			local map_path = MAPS_FOLDER .. "/" .. v
			
			nsMapsDisplayNames[i] = mapProperties(map_path)["display_name"]
			mapsPaths[i] = map_path
			
			if map_path == MAP_DEFAULT then
				nsDefaultMap = i
			end
			
			if map_path == MOD_SETTINGS.MapPath then
				nsCurrentMap = i
			end
		end
	end

	-- generate NativeSettings (if available)
	nativeSettings = GetMod("nativeSettings")
	if nativeSettings ~= nil then

		nativeSettings.addTab("/Hidden Packages", "Hidden Packages")

		nativeSettings.addSubcategory("/Hidden Packages/Maps", "Maps")

		nativeSettings.addSelectorString("/Hidden Packages/Maps", "Map", "These are stored in \'.../mods/Hidden Packages/Maps\''. If set to None the mod is practically disabled.", nsMapsDisplayNames, nsCurrentMap, nsDefaultMap, function(value)
			MOD_SETTINGS.MapPath = mapsPaths[value]
			saveSettings()
			NEED_TO_REFRESH = true
		end)

		nativeSettings.addSubcategory("/Hidden Packages/AudioHints", "Sonar")

		nativeSettings.addSwitch("/Hidden Packages/AudioHints", "Sonar", "Plays a sound when you are moving nearby a package in increasing frequency the closer you get to it", MOD_SETTINGS.HintAudioEnabled, false, function(state)
			MOD_SETTINGS.HintAudioEnabled = state
			saveSettings()
		end)

		nativeSettings.addRangeInt("/Hidden Packages/AudioHints", "Sonar Range", "Sonar starts working when you are this close to a package", 10, 1000, 1, MOD_SETTINGS.HintAudioRange, 150, function(value)
			MOD_SETTINGS.HintAudioRange = value
			saveSettings()
		end)

	end
	-- end NativeSettings

	GameSession.StoreInDir('Sessions')
	GameSession.Persist(SESSION_DATA)
	isInGame = Game.GetPlayer() and Game.GetPlayer():IsAttached() and not Game.GetSystemRequestsHandler():IsPreGame()

    GameSession.OnStart(function()
        debugMsg('Game Session Started')
        isInGame = true
        isPaused = false
        
        if NEED_TO_REFRESH then
        	switchLocationsFile(MOD_SETTINGS.MapPath)
        	NEED_TO_REFRESH = false
        end

        -- check if old legacy data exists and wipe it if so
        if SESSION_DATA.packages then
        	debugMsg("clearing legacy SESSION_DATA.packages")
        	SESSION_DATA.packages = nil
        end
        if SESSION_DATA.locFile then
        	debugMsg("clearing legacy SESSION_DATA.locFile")
        	SESSION_DATA.locFile = nil
        end

        checkIfPlayerNearAnyPackage() -- otherwise if you made a save near a package and just stand still it wont spawn until you move
    end)

    GameSession.OnEnd(function()
        debugMsg('Game Session Ended')
        isInGame = false
        reset()
    end)

	GameSession.OnPause(function()
		isPaused = true
	end)

	GameSession.OnResume(function()
		isPaused = false

        if NEED_TO_REFRESH then
        	switchLocationsFile(MOD_SETTINGS.MapPath)
        	NEED_TO_REFRESH = false
        end
	end)

    Observe('PlayerPuppet', 'OnAction', function(action) -- any player action
    	if not isPaused and isInGame then
    		checkIfPlayerNearAnyPackage()
    	end
    end)

end)

registerForEvent('onDraw', function()

	if MOD_SETTINGS.ShowPerformanceWindow then
		ImGui.Begin("Hidden Packages - Performance")
		ImGui.Text("loaded packages: " .. tostring(LEX.tableLen(LOADED_PACKAGES)))
		ImGui.Text(performanceTextbox1)
		ImGui.Text(performanceTextbox2)
		ImGui.Text(performanceTextbox3)
		ImGui.Text("checkThrottle: " .. tostring(checkThrottle))
		ImGui.End()
	end

	if MOD_SETTINGS.DebugMode then
		ImGui.Begin("Hidden Packages - Debug")
		ImGui.Text("MOD_SETTINGS.MapPath: " .. tostring(MOD_SETTINGS.MapPath))
		ImGui.Text("Collected: " .. tostring(countCollected()) .. "/" .. tostring(LEX.tableLen(LOADED_PACKAGES)))
		ImGui.Text("isInGame: " .. tostring(isInGame))
		ImGui.Text("isPaused: " .. tostring(isPaused))
		ImGui.Text("NEED_TO_REFRESH: " .. tostring(NEED_TO_REFRESH))
		ImGui.Text("LOADED_PACKAGES: " .. tostring(LEX.tableLen(LOADED_PACKAGES)))
		ImGui.Text("SESSION_DATA.collected: " .. tostring(LEX.tableLen(SESSION_DATA.collectedPackageIDs)))
		ImGui.Text("countCollected(): " .. tostring(countCollected()))
		ImGui.Text("checkThrottle: " .. tostring(checkThrottle))

		local c = 0 
		for k,v in pairs(activePackages) do
			if v then
				c = c + 1
			end
		end
		ImGui.Text("activePackages: " .. tostring(c))

		local c = 0 
		for k,v in pairs(activeMappins) do
			if v then
				c = c + 1
			end
		end
		ImGui.Text("activeMappins: " .. tostring(c))
		ImGui.End()
	end

end)

function spawnPackage(i)
	if activePackages[i] then
		return false
	end

	local pkg = LOADED_PACKAGES[i]
	local entity = spawnObjectAtPos(pkg["x"], pkg["y"], pkg["z"]+PACKAGE_PROP_Z_BOOST, pkg["w"], PACKAGE_PROP)
	if entity then
		activePackages[i] = entity
		return entity
	end
	return false
end

function spawnObjectAtPos(x,y,z,w, prop)
    local transform = Game.GetPlayer():GetWorldTransform()
    local pos = ToVector4{x=x, y=y, z=z, w=w}
    transform:SetPosition(pos)
    return WorldFunctionalTests.SpawnEntity(prop, transform, '') -- returns ID
end

function despawnPackage(i) -- i = package index
	if activePackages[i] then
		destroyObject(activePackages[i])
		activePackages[i] = nil
		return true
	end
    return false
end

function destroyObject(e)
	if Game.FindEntityByID(e) ~= nil then
        Game.FindEntityByID(e):GetEntity():Destroy()
        return true
    end
    return false
end

function collectHP(packageIndex)
	local pkg = LOADED_PACKAGES[packageIndex]

	if not LEX.tableHasValue(SESSION_DATA.collectedPackageIDs, pkg["identifier"]) then
		table.insert(SESSION_DATA.collectedPackageIDs, pkg["identifier"])
	else
		debugMsg("hmmmmm, this package seems to already be collected???")
	end

	unmarkPackage(packageIndex)
	despawnPackage(packageIndex)

	local msg = "Hidden Package " .. tostring(countCollected()) .. " of " .. tostring(LEX.tableLen(LOADED_PACKAGES))
	Game.GetAudioSystem():Play('ui_loot_rarity_legendary')
	HUDMessage(msg)

	-- got all packages?
    if (countCollected() == LEX.tableLen(LOADED_PACKAGES)) and (LEX.tableLen(LOADED_PACKAGES) > 0) then
    	debugMsg("Got all packages")
    	GameHUD.ShowWarning("All Hidden Packages collected!")
    	rewardAllPackages()
    end
end

function reset()
	destroyAllPackageObjects()
	removeAllMappins()
	activePackages = {}
	activeMappins = {}
	lastCheck = 0
	debugMsg("reset() OK")
	return true
end

function destroyAllPackageObjects()
	for k,v in pairs(LOADED_PACKAGES) do
		if activePackages[k] then
			despawnPackage(k)
		end
	end
end

function readHPLocations(path)
	local mapIdentifier = mapProperties(path)["identifier"]

	local lines = {}
	for line in io.lines(path) do
		if (line ~= nil) and (line ~= "") and not (LEX.stringStarts(line, "#")) and not (LEX.stringStarts(line, "//")) then
			if not LEX.stringStarts(line, "IDENTIFIER:") and not LEX.stringStarts(line,"DISPLAY_NAME:") then
				lines[#lines + 1] = line
			end
		end
	end

	local packages = {}
	for k,v in pairs(lines) do
		local vals = {}
		for word in string.gmatch(v, '([^ ]+)') do
			table.insert(vals,word)
		end

		local hp = {}
		-- id is based on coordinates so that the order of the lines in the packages file is not important and can be moved around later on
		hp["identifier"] = mapIdentifier .. ": x=" .. tostring(vals[1]) .. " y=" .. tostring(vals[2]) .. " z=" .. tostring(vals[3]) .. " w=" .. tostring(vals[4])
		hp["x"] = tonumber(vals[1])
		hp["y"] = tonumber(vals[2])
		hp["z"] = tonumber(vals[3])
		hp["w"] = tonumber(vals[4])
		table.insert(packages, hp)
	end
	return packages
end

-- from CET Snippets discord... could be useful, maybe for reward? or warning window?
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

	local position = ToVector4{x=x, y=y, z=z, w=w}
	return Game.GetMappinSystem():RegisterMappin(mappinData, position) -- returns ID
end

function markPackage(i) -- i = package index
	if activeMappins[i] then
		return false
	end

	local pkg = LOADED_PACKAGES[i]
	local mappin_id = placeMapPin(pkg["x"], pkg["y"], pkg["z"], pkg["w"])
	if mappin_id then
		activeMappins[i] = mappin_id
		return mappin_id
	end
	return false
end

function unmarkPackage(i)
	if activeMappins[i] then
        Game.GetMappinSystem():UnregisterMappin(activeMappins[i])
      	activeMappins[i] = nil
        return true
    end
    return false
end	

function removeAllMappins()
	for k,v in pairs(LOADED_PACKAGES) do
		if activeMappins[k] then
			unmarkPackage(k)
		end
	end
end

function findNearestPackage(ignoreFound)
	local lowest = nil
	local nearestPackage = false
	local playerPos = Game.GetPlayer():GetWorldPosition()

	for k,v in pairs(LOADED_PACKAGES) do
		if (LEX.tableHasValue(SESSION_DATA.collectedPackageIDs, v["identifier"]) == false) or (ignoreFound == false) then
			
			local distance = Vector4.Distance(playerPos, ToVector4{x=v["x"], y=v["y"], z=v["z"], w=v["w"]})
			
			if lowest == nil then
				lowest = distance
				nearestPackage = k
			end
			
			if distance < lowest then
				lowest = distance
				nearestPackage = k
			end

		end
	end

	return nearestPackage -- returns package index or false
end

function markNearestPackage()
	removeAllMappins()
	local NP = findNearestPackage(true) -- true to ignore found packages
	if NP then
		markPackage(NP)
		HUDMessage("Nearest Package Marked (" .. string.format("%.f", distanceToPackage(NP)) .. "M away)")
		return true
	end
	HUDMessage("No packages available")
	return false
end

function switchLocationsFile(path)
	if path == false then -- false == mod disabled
		reset()
		LOADED_PACKAGES = {}
		return true
	end

	if LEX.fileExists(path) then
		reset()
		LOADED_PACKAGES = readHPLocations(path)
		checkIfPlayerNearAnyPackage()
		return true
	end
	return false
end

function checkIfPlayerNearAnyPackage()
	local loopStarted = os.clock()

	if MOD_SETTINGS.MapPath == false then -- mod disabled more or less
		return
	end

	if not isInGame or isPaused then
		return
	end

	if (loopStarted - lastCheck) < checkThrottle then
		return -- too soon
	else
		lastCheck = loopStarted
		debugMsg("check at " .. tostring(lastCheck))
	end

	local checkRange = MOD_SETTINGS.SpawnPackageRange
	if MOD_SETTINGS.HintAudioEnabled and MOD_SETTINGS.HintAudioRange > checkRange then
		checkRange = MOD_SETTINGS.HintAudioRange
	end

	local distanceToNearestPackage = nil
	local playerPos = Game.GetPlayer():GetWorldPosition()
	for k,v in pairs(LOADED_PACKAGES) do
		local d = nil

		if math.abs(playerPos["x"] - v["x"]) <= checkRange then
			if math.abs(playerPos["y"] - v["y"]) <= checkRange then
				if math.abs(playerPos["z"] - v["z"]) <= checkRange then
					-- only bother calculating exact distance if we are in the neighborhood
					d = Vector4.Distance(playerPos, ToVector4{x=v["x"], y=v["y"], z=v["z"], w=v["w"]})
				end
			end
		end

		if d ~= nil then
			if distanceToNearestPackage == nil or d < distanceToNearestPackage then
				distanceToNearestPackage = d
			end
		end

		if MOD_SETTINGS.HintAudioEnabled and d ~= nil and d <= MOD_SETTINGS.HintAudioRange and (LEX.tableHasValue(SESSION_DATA.collectedPackageIDs, v["identifier"]) == false) then
			audioHint(k)
		end

		if d ~= nil and d <= MOD_SETTINGS.SpawnPackageRange then -- player is in spawning range of package

			if (LEX.tableHasValue(SESSION_DATA.collectedPackageIDs, v["identifier"]) == false) then
				-- player has not collected package

				if not activePackages[k] then -- package is not already spawned
					spawnPackage(k)
				end

				if (d <= 0.75) and (inVehicle() == false) then -- player is at package and is not in a vehicle, package should be collected
					collectHP(k)
				end

			else
				distanceToNearestPackage = nil
			end

		else -- player is outside of spawning range

			if activePackages[k] then -- out of range, despawn the package if its active
				despawnPackage(k)
			end

		end
	end

	if distanceToNearestPackage ~= nil then
		-- adjust checkThrottle based on distance to nearest package
		if distanceToNearestPackage <= checkRange then
			checkThrottle = distanceToNearestPackage / 100
			
			if checkThrottle < 0.1 then
				checkThrottle = 0.1
			end
		else
			checkThrottle = 1
		end
	else
		checkThrottle = 1 -- otherwise checkThrottle stuck at the spam value when all packages are collected
	end

	if MOD_SETTINGS.ShowPerformanceWindow then
		local loopTime = os.clock() - loopStarted
		
		table.insert(loopTimesAvg, loopTime)
		if LEX.tableLen(loopTimesAvg) > 20 then
			table.remove(loopTimesAvg, 0)
			performanceTextbox3 = "avg: " .. tostring(LEX.tableAvg(loopTimesAvg)) .. "ms"
		end

		performanceTextbox1 = "speed: " .. tostring(1/loopTime) .. "/s"
		performanceTextbox2 = "last loop: " .. tostring(loopTime) .. "ms"
	end

end


function debugMsg(msg)
	if not MOD_SETTINGS.DebugMode then
		return
	end

	print("HP debug: " .. msg)
	if isInGame then
		HUDMessage("HP: " .. msg)
	end
end

function HUDMessage(msg)
	if os:clock() - HUDMessage_Last <= 1 then
		HUDMessage_Current = msg .. "\n" .. HUDMessage_Current
	else
		HUDMessage_Current = msg
	end

	GameHUD.ShowMessage(HUDMessage_Current)
	HUDMessage_Last = os:clock()
end

function clearProgress(LocFile)
	local c = 0
	local clearedTable = {}
	debugMsg("clearProgress(" .. LocFile .. ") - before: " .. tostring(LEX.tableLen(SESSION_DATA.collectedPackageIDs)))
	for k,v in pairs(SESSION_DATA.collectedPackageIDs) do
		if not LEX.stringStarts(v, LocFile .. ":") then
			-- package is not from LocFile, add it to the new (cleared) table
			table.insert(clearedTable, v)
		else
			c = c + 1 -- package is from LocFile and we DO NOT want it back = count it
		end
	end
	SESSION_DATA.collectedPackageIDs = clearedTable
	debugMsg("clearProgress(" .. LocFile .. ") - after: " .. tostring(LEX.tableLen(SESSION_DATA.collectedPackageIDs)) .. " (uncollected: " .. tostring(c) .. ")")
	--debugMsg("clearProgress(" .. LocFile .. ") - uncollected " .. tostring(c) .. " pkgs")
end

function countCollected()
	-- cant just check length of collectedPackageIDs as it may include packages from other location files
	local c = 0
	for k,v in pairs(LOADED_PACKAGES) do
		if LEX.tableHasValue(SESSION_DATA.collectedPackageIDs, v["identifier"]) then
			c = c + 1
		end
	end
	return c
end

function rewardAllPackages()
	Game.AddToInventory("Items.money", 1000000)
	debugMsg("rewardAllPackages() OK")
end

function distanceToPackage(i)
	local pkg = LOADED_PACKAGES[i]
	return distanceToCoordinates(pkg["x"], pkg["y"], pkg["z"], pkg["w"])
end

function distanceToCoordinates(x,y,z,w)
	return Vector4.Distance(Game.GetPlayer():GetWorldPosition(), ToVector4{x=x, y=y, z=z, w=w})
end

function audioHint(i)
	if (os.clock() - lastAudioHint) < 0.1 or isPaused then
		return
	end
	Game.GetAudioSystem():Play('ui_hacking_access_granted')
	lastAudioHint = os.clock()
end

function saveSettings()
	local file = io.open("SETTINGS.json", "w")
	local j = json.encode(MOD_SETTINGS)
	file:write(j)
	file:close()
end

function loadSettings()
	if not LEX.fileExists("SETTINGS.json") then
		return false
	end

	local file = io.open("SETTINGS.json", "r")
	local j = json.decode(file:read("*a"))
	file:close()

	MOD_SETTINGS = j

	return true
end

function listFilesInFolder(folder)
	local files = {}
	for k,v in pairs(dir(folder)) do
		for a,b in pairs(v) do
			if a == "name" then
				table.insert(files, b)
			end
		end
	end
	return files
end

function mapProperties(path)
	local response = {
		amount = 0,
		display_name = "",
		display_name_with_amount = "()",
		identifier = "",
		path = path
	}

	if not LEX.fileExists(path) then
		return false
	end

	for line in io.lines(path) do
		
		if (line ~= nil) and (line ~= "") and not (LEX.stringStarts(line, "#")) and not (LEX.stringStarts(line, "//")) then

			if LEX.stringStarts(line, "DISPLAY_NAME:") then
				response.display_name = LEX.trim(string.match(line, ":(.*)"))
			elseif LEX.stringStarts(line, "IDENTIFIER:") then
				response.identifier = LEX.trim(string.match(line, ":(.*)"))
			else
				response.amount = response.amount + 1
			end
		end

	end

	response.display_name_with_amount = response.display_name .. " (" .. tostring(response.amount) .. ")"

	return response
end