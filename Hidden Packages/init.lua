local HiddenPackagesMetadata = {
	title = "Hidden Packages",
	version = "1.0.3.1"
}

local GameSession = require("Modules/GameSession.lua")
--local GameUI = require("Modules/GameUI.lua")
local GameHUD = require("Modules/GameHUD.lua")
local LEX = require("Modules/LuaEX.lua")

local reservedFilenames = {"SETTINGS.json", "DEBUG", "RANDOMIZER", "PERFORMANCE", "DEFAULT", "init.lua", "db.sqlite3", "Hidden Packages.log"}
local defaultLocationsFile = "packages1.map" -- should not have the Maps/

local userData = { -- will persist
	collectedPackageIDs = {}
}

local MOD_SETTINGS = {
	DebugMode = false,
	RandomizerShown = false,
	RandomizerAmount = 100,
	ShowPerformanceWindow = false,
	CreationModeFile = "CREATED.map",
	NearPackageRange = 100,
	HintAudioEnabled = false,
	HintAudioRange = 200,
	MapFile = defaultLocationsFile
}

local LOADED_PACKAGES = {}

local HUDMessage_Current = ""
local HUDMessage_Last = 0

local statusMsg = ""
local showCreationWindow = false
local showScaryButtons = false

local Create_NewCreationFile = MOD_SETTINGS.CreationModeFile
local Create_NewLocationComment = ""
local Create_Message = ""

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
local performanceTextbox1 = "text 1"
local performanceTextbox2 = "text 2"
local performanceTextbox3 = "text 3"


registerHotkey("hp_nearest_pkg", "Mark nearest package", function()
	markNearestPackage()
end)

registerHotkey("hp_toggle_create_window", "Toggle creation window", function()
	showCreationWindow = not showCreationWindow
	if showCreationWindow == false then
		switchLocationsFile(MOD_SETTINGS.MapFile) -- restore
		checkIfPlayerNearAnyPackage()
	end
end)

registerForEvent("onOverlayOpen", function()
	showWindow = true
end)

registerForEvent("onOverlayClose", function()
	showWindow = false
end)

registerForEvent('onShutdown', function() -- mod reload, game shutdown etc
    reset()
end)

registerForEvent('onInit', function()
	if loadSettings() then
		print("Hidden Packages: loaded settings")
	else
		print("Hidden Packages: no settings file found, using defaults")
	end

	LOADED_PACKAGES = readHPLocations(MOD_SETTINGS.MapFile)

	-- generate NativeSettings
	nativeSettings = GetMod("nativeSettings")
	nativeSettings.addTab("/Hidden Packages", "Hidden Packages")

	nativeSettings.addSubcategory("/Hidden Packages/Maps", "Maps")

	-- scan Maps folder and generate table suitable for nativeSettings
	local mapsFilenames = {[1] = "NONE"}
	local nsMaps = {[1] = "None (Mod disabled)"}
	local nsDefaultMap = 1
	local nsCurrentMap = 1
	for k,v in pairs(listFilesInFolder("Maps")) do
		if LEX.stringEnds(v, ".map") then
			--print(v, "should be added")
			local i = LEX.tableLen(nsMaps) + 1
			nsMaps[i] = getMapProperty(v, "displayname")
			mapsFilenames[i] = v
			if v == defaultLocationsFile then
				nsDefaultMap = i
			end
			if v == MOD_SETTINGS.MapFile then
				nsCurrentMap = i
			end
		end
	end

	nativeSettings.addSelectorString("/Hidden Packages/Maps", "Map", "Which map to use (stored in the \'.../mods/Hidden Packages/Maps\' folder). When set to None the mod is practically disabled.", nsMaps, nsCurrentMap, nsDefaultMap, function(value)
		--print("changed list to", nsMaps[value])
		MOD_SETTINGS.MapFile = mapsFilenames[value]
		saveSettings()
		NEED_TO_REFRESH = true
	end)

	nativeSettings.addSubcategory("/Hidden Packages/AudioHints", "Audio Hints")

	nativeSettings.addSwitch("/Hidden Packages/AudioHints", "Audio Hint", "Plays a sound when you are near a package, in increasing frequency the closer you get close to the package", MOD_SETTINGS.HintAudioEnabled, false, function(state)
		MOD_SETTINGS.HintAudioEnabled = state
		saveSettings()
	end)

	nativeSettings.addRangeInt("/Hidden Packages/AudioHints", "Audio Hint Range", "Start playing audio hint when this close to a package", 50, 500, 1, MOD_SETTINGS.HintAudioRange, 200, function(value)
		MOD_SETTINGS.HintAudioRange = value
		saveSettings()
	end)

	nativeSettings.addSubcategory("/Hidden Packages/Advanced", "Advanced / Development")

	nativeSettings.addRangeInt("/Hidden Packages/Advanced", "Near Package Range", "Spawn package when this close to one", 10, 200, 1, MOD_SETTINGS.NearPackageRange, 100, function(value)
		MOD_SETTINGS.NearPackageRange = value
		saveSettings()
	end)

	nativeSettings.addSwitch("/Hidden Packages/Advanced", "Debug Mode", "Enables debug mode (spams messages about what is going on)", MOD_SETTINGS.DebugMode, false, function(state)
		MOD_SETTINGS.DebugMode = state
		saveSettings()
	end)
	nativeSettings.addSwitch("/Hidden Packages/Advanced", "Show Randomizer", "Enables the (dumb) randomizer in the CET overlay", MOD_SETTINGS.RandomizerShown, false, function(state)
		MOD_SETTINGS.RandomizerShown = state
		saveSettings()
	end) 
	nativeSettings.addSwitch("/Hidden Packages/Advanced", "Show Performance Window", "Show performance metrics", MOD_SETTINGS.ShowPerformanceWindow, false, function(state)
		MOD_SETTINGS.ShowPerformanceWindow = state
		saveSettings()
	end)
	-- end NativeSettings

	GameSession.StoreInDir('Sessions')
	GameSession.Persist(userData)
	isInGame = Game.GetPlayer() and Game.GetPlayer():IsAttached() and not Game.GetSystemRequestsHandler():IsPreGame()

    GameSession.OnStart(function()
        -- Triggered once the load is complete and the player is in the game
        -- (after the loading screen for "Load Game" or "New Game")
        debugMsg('Game Session Started')
        isInGame = true
        isPaused = false
        
        if NEED_TO_REFRESH then
        	switchLocationsFile(MOD_SETTINGS.MapFile)
        	NEED_TO_REFRESH = false
        end

        -- check if old legacy data exists and wipe it if so
        if userData.packages then
        	debugMsg("clearing legacy userData.packages")
        	userData.packages = nil
        end
        if userData.locFile then
        	debugMsg("clearing legacy userData.locFile")
        	userData.locFile = nil
        end

        Create_Message = "Lets go place some packages"
        checkIfPlayerNearAnyPackage() -- otherwise if you made a save near a package and just stand still it wont spawn until you move
    end)

	--GameSession.OnSave(function()
	--end)

	--GameSession.OnLoad(function()
    --    LOADED_PACKAGES = readHPLocations(MOD_SETTINGS.MapFile)
	--end)

    GameSession.OnEnd(function()
        -- Triggered once the current game session has ended
        -- (when "Load Game" or "Exit to Main Menu" selected)
        debugMsg('Game Session Ended')
        isInGame = false
        reset() -- destroy all objects and reset tables etc
        -- should maybe wipe userData here but it gets properly set when starting a new game or loading a game anyway so not sure its necessary
    end)

	GameSession.OnPause(function()
		isPaused = true
	end)

	GameSession.OnResume(function()
		isPaused = false

        if NEED_TO_REFRESH then
        	switchLocationsFile(MOD_SETTINGS.MapFile)
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


		ImGui.Text("Collected: " .. tostring(countCollected()) .. "/" .. tostring(LEX.tableLen(LOADED_PACKAGES)))
		
		if MOD_SETTINGS.RandomizerShown then
			ImGui.Text("Randomizer:")
			MOD_SETTINGS.RandomizerAmount = ImGui.InputInt("Packages", MOD_SETTINGS.RandomizerAmount, 100)
			if ImGui.Button("Generate") then
				switchLocationsFile(generateRandomPackages(MOD_SETTINGS.RandomizerAmount))
				debugMsg("HP Randomizer done")
				saveSettings()
			end
			ImGui.Separator()
		end



		if MOD_SETTINGS.DebugMode then
			ImGui.Text("isInGame: " .. tostring(isInGame))
			ImGui.Text("isPaused: " .. tostring(isPaused))
			ImGui.Text("NEED_TO_REFRESH: " .. tostring(NEED_TO_REFRESH))
			ImGui.Text("LOADED_PACKAGES: " .. tostring(LEX.tableLen(LOADED_PACKAGES)))
			ImGui.Text("Map filename: " .. tostring(MOD_SETTINGS.MapFile))
			--ImGui.Text("Map identifier: " .. getMapProperty(MOD_SETTINGS.MapFile, "identifier"))
			--ImGui.Text("Map display name: " .. getMapProperty(MOD_SETTINGS.MapFile, "displayname"))
			ImGui.Text("userData collected: " .. tostring(LEX.tableLen(userData.collectedPackageIDs)))
			ImGui.Text("countCollected(): " .. tostring(countCollected()))
			ImGui.Text("checkThrottle: " .. tostring(checkThrottle))

			-- if isInGame then
			-- 	local NP = findNearestPackage(false) -- false to ignore if its collected or not
			-- 	if NP then
			-- 		ImGui.Text("Nearest Package: " .. string.format("%.f", distanceToPackage(NP)) .. "M away")
			-- 	end
			-- end

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

			-- if ImGui.Button("reset()") then
			-- 	reset()
			-- end
		end

		-- if isInGame then

		-- 	if ImGui.Button("Show/hide Scary Buttons") then
		-- 		showScaryButtons = not showScaryButtons
		-- 	end

		-- 	if showScaryButtons then

		-- 		ImGui.Separator()
		-- 		ImGui.Text("Warning: One click is all you need.\nNo confirmations!")

		-- 		if ImGui.Button("Load default packages\n(" .. defaultLocationsFile .. ")") then
		-- 			switchLocationsFile(defaultLocationsFile)
		-- 		end

		-- 		--if ImGui.Button("Reload current packages\n(" .. userData.locFile .. ")") then
		-- 		--	LOADED_PACKAGES = readHPLocations(userData.locFile)
		-- 		--end

		-- 		--if countCollected() > 0 then
		-- 		--	if ImGui.Button("Reset progress\n(" .. userData.locFile .. ")") then
		-- 		--		reset()
		-- 		--		clearProgress(userData.locFile)
		-- 		--		checkIfPlayerNearAnyPackage()
		-- 		--	end
		-- 		--	ImGui.SameLine()
		-- 		--end

		-- 		if LEX.tableLen(userData.collectedPackageIDs) > 0 then
		-- 			if ImGui.Button("Reset progress\n(all location files)") then
		-- 				reset()
		-- 				userData.collectedPackageIDs = {}
		-- 				checkIfPlayerNearAnyPackage()
		-- 			end
		-- 		end

		-- 	end

		-- end

		ImGui.End()
	end




	if showCreationWindow then
		ImGui.Begin("Hidden Packages: Creation Mode")

		ImGui.Text("Status: " .. Create_Message) -- status message

		if isInGame then
			checkIfPlayerNearAnyPackage()
			ImGui.Text("Player Position:")
			local position = Game.GetPlayer():GetWorldPosition()
			ImGui.Text("X: " .. string.format("%.3f", position["x"]))
			ImGui.SameLine()
			ImGui.Text("\tY: " .. string.format("%.3f", position["y"]))

			ImGui.Text("Z: " .. string.format("%.3f", position["z"]))
			ImGui.SameLine()
			ImGui.Text("\tW: " .. tostring(position["w"]))

			ImGui.Separator()
			ImGui.Text("(" .. tostring(LEX.tableLen(LOADED_PACKAGES)) .. " packages)")

			local NP = findNearestPackage(false) -- false to ignore if its collected or not
			if NP then
				ImGui.Text("Nearest Package: " .. string.format("%.f", distanceToPackage(NP)) .. "M away")
			end

			ImGui.Separator()
			Create_NewCreationFile = ImGui.InputText("File", Create_NewCreationFile, 50)
			Create_NewLocationComment = ImGui.InputText("Comment", Create_NewLocationComment, 50)
			if ImGui.Button("Save This Location") then

				local position = Game.GetPlayer():GetWorldPosition()
				if appendLocationToFile(Create_NewCreationFile, position["x"], position["y"], position["z"], position["w"], Create_NewLocationComment) then
					HUDMessage("Location saved!")
					Create_Message = "Location saved!"
					Create_NewLocationComment = ""
					MOD_SETTINGS.CreationModeFile = Create_NewCreationFile
				else
					Create_Message = "Error saving location :("
				end
			
			end

			if ImGui.Button("Apply & Test") then
				switchLocationsFile(Create_NewCreationFile)
				Create_Message = tostring(LEX.tableLen(LOADED_PACKAGES)) .. " packages applied & loaded"
			end
			ImGui.Separator()

			if ImGui.Button("Mark ALL packages on map") then
				removeAllMappins()
				for k,v in pairs(LOADED_PACKAGES) do
					markPackage(k)
				end
			end

			if ImGui.Button("Remove all map pins") then
				removeAllMappins()
			end

		else
			Create_Message = "Not in-game"
		end

		ImGui.Separator()
		ImGui.Text("Note: Packages aren\'t collected when you have this window open")
		if ImGui.Button("Close") then
			showCreationWindow = false
			switchLocationsFile(MOD_SETTINGS.MapFile) -- restore
			checkIfPlayerNearAnyPackage() -- cleans up any leftover packages
		end

		ImGui.End()
	end

end)

function spawnPackage(i)
	if activePackages[i] then
		debugMsg("spawnPackage(" .. tostring(i) .. ") = package already spawned")
		return false
	end

	local pkg = LOADED_PACKAGES[i]
	local entity = spawnObjectAtPos(pkg["x"], pkg["y"], pkg["z"]+PACKAGE_PROP_Z_BOOST, pkg["w"], PACKAGE_PROP)
	if entity then
		activePackages[i] = entity
		debugMsg("spawnPackage(" .. tostring(i) .. ") = OK")
		return entity
	else
		debugMsg("spawnPackage(" .. tostring(i) .. ") = error with spawn")
		return false
	end
end

function spawnObjectAtPos(x,y,z,w, prop)
	if not isInGame then
		return
	end

    local transform = Game.GetPlayer():GetWorldTransform()
    local pos = ToVector4{x=x, y=y, z=z, w=w}
    transform:SetPosition(pos)

    return WorldFunctionalTests.SpawnEntity(prop, transform, '') -- returns ID
end

function despawnPackage(i) -- i = package index
	if activePackages[i] then
		if destroyObject(activePackages[i]) then
			activePackages[i] = nil
			debugMsg("despawnPackage(" .. tostring(i) .. ") = OK")
			return true
		else
			debugMsg("despawnPackage(" .. tostring(i) .. ") = ERROR destroyObject()")
			return false
		end
	end
	debugMsg("despawnPackage(" .. tostring(i) .. ") = package not active")
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
	debugMsg("collectHP(" .. tostring(packageIndex) .. ")")

	local pkg = LOADED_PACKAGES[packageIndex]

	if not LEX.tableHasValue(userData.collectedPackageIDs, pkg["identifier"]) then
		table.insert(userData.collectedPackageIDs, pkg["identifier"])
	else
		debugMsg("HMM, this package seems to already be collected???")
	end

	unmarkPackage(packageIndex)
	despawnPackage(packageIndex)

    if (countCollected() == LEX.tableLen(LOADED_PACKAGES)) and (LEX.tableLen(LOADED_PACKAGES) > 0) then
    	-- got em all
    	debugMsg("Got all packages")
    	GameHUD.ShowWarning("All Hidden Packages collected!")
    	rewardAllPackages()
    else
    	local msg = "Hidden Package " .. tostring(countCollected()) .. " of " .. tostring(LEX.tableLen(LOADED_PACKAGES))
    	GameHUD.ShowWarning(msg)
    	--Game.GetAudioSystem():Play('ui_loot_rarity_legendary')
    	--HUDMessage(msg)

    end

   	debugMsg("collectHP(" .. tostring(packageIndex) .. ") OK")
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
	debugMsg("destroyAll() OK")
end

function readHPLocations(filename)
	if filename == "NONE" then
		return {}
	end

	local mapIdentifier = getMapProperty(filename, "identifier")
	filename = "Maps/" .. filename -- ugly hack again
	
	if not LEX.fileExists(filename) or LEX.tableHasValue(reservedFilenames, filename) then
		debugMsg("readHPLocations() not a valid file")
		return false
	else
		debugMsg("readHPLocations(): " .. filename)
	end

	local lines = {}
	for line in io.lines(filename) do
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

function generateRandomPackages(n)
	debugMsg("generating " .. n .. " random packages...")

	local filename = tostring(n) .. " random packages (" .. os.date("%Y%m%d-%H%M%S") .. ")"
	LOADED_PACKAGES = {}
	local i = 1
	local content = ""
	while (i <= n) do
		x = math.random(-2623, 3598)
		y = math.random(-4011, 3640)
		z = math.random(1, 120)
		w = 1

		content = content .. string.format("%.3f", x) .. " " .. string.format("%.3f", y) .. " " .. string.format("%.3f", z) .. " " .. tostring(w) .. "\n"

		i = i + 1
	end

	local file = io.open(filename, "w")
	file:write(content)
	file:close()

	-- save to file and return filename
	return filename

end

function appendLocationToFile(filename, x, y, z, w, comment)
	if filename == "" or LEX.tableHasValue(reservedFilenames, filename) then
		debugMsg("appendLocationToFile: not a valid filename")
		return false
	end

	local content = ""

	-- first check if file already exists and read it if so
	if LEX.fileExists(filename) then
		local file = io.open(filename,"r")
		content = file:read("*a")
		content = content .. "\n"
		file:close()
	end

	-- append new data
	-- 3 decimals should be plenty
	content = content .. string.format("%.3f", x) .. " " .. string.format("%.3f", y) .. " " .. string.format("%.3f", z) .. " " .. tostring(w)

	if comment ~= "" then -- only append comment if there is one
		content = content .. " // " .. comment
	end

	local file = io.open(filename, "w")
	file:write(content)
	file:close()
	debugMsg("Appended", filename, x, y, z, w, comment)
	return true
end

function placeMapPin(x,y,z,w) -- from CET Snippets discord
	debugMsg("placing map pin at " ..  x .. " " .. y .. " " .. z .. " " ..w)
	local mappinData = MappinData.new()
	mappinData.mappinType = TweakDBID.new('Mappins.DefaultStaticMappin')
	mappinData.variant = gamedataMappinVariant.CustomPositionVariant -- see more types: https://github.com/WolvenKit/CyberCAT/blob/main/CyberCAT.Core/Enums/Dumped%20Enums/gamedataMappinVariant.cs
	mappinData.visibleThroughWalls = true   

	local position = ToVector4{x=x, y=y, z=z, w=w}
	return Game.GetMappinSystem():RegisterMappin(mappinData, position) -- returns ID
end

function markPackage(i) -- i = package index
	if activeMappins[i] then
		debugMsg("markPackage(" .. tostring(i) .. ") = package already marked")
		return false
	end

	local pkg = LOADED_PACKAGES[i]
	local mappin_id = placeMapPin(pkg["x"], pkg["y"], pkg["z"], pkg["w"])
	if mappin_id then
		activeMappins[i] = mappin_id
		debugMsg("markPackage(" .. tostring(i) .. ") = OK")
		return mappin_id
	else
		debugMsg("markPackage(" .. tostring(i) .. ") = error")
		return false
	end

end

function unmarkPackage(i)
	if activeMappins[i] then
        Game.GetMappinSystem():UnregisterMappin(activeMappins[i])
      	activeMappins[i] = nil
        debugMsg("unmarkPackage(" .. tostring(i) .. ") = OK")
        return true
    else
    	debugMsg("unmarkPackage(" .. tostring(i) .. ") = marker not active")
    	return false
    end
    debugMsg("unmarkPackage(" .. tostring(i) .. ") = error?")
    return false
end	

function removeAllMappins()
	for k,v in pairs(LOADED_PACKAGES) do
		if activeMappins[k] then
			unmarkPackage(k)
		end
	end
	debugMsg("removeAllMappins() OK")
end

function findNearestPackage(ignoreFound)
	local lowest = nil
	local nearestPackage = false
	local playerPos = Game.GetPlayer():GetWorldPosition()

	for k,v in pairs(LOADED_PACKAGES) do
		if (LEX.tableHasValue(userData.collectedPackageIDs, v["identifier"]) == false) or (ignoreFound == false) then
			
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
	if not isInGame then
		return
	end

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

function switchLocationsFile(newFile)
	if newFile == "NONE" then
		reset()
		LOADED_PACKAGES = {}
		debugMsg("switchLocationsFile(" .. newFile .. ") = mod disabled")
		return true
	end

	local path = "Maps/" .. newFile

	if LEX.fileExists(path) and not LEX.tableHasValue(reservedFilenames, newFile) then
		debugMsg("switchLocationsFile(" .. newFile .. ")")

		if isInGame and not showCreationWindow then
			-- regular switch
			reset()
			MOD_SETTINGS.MapFile = newFile
			LOADED_PACKAGES = readHPLocations(newFile)
			
			debugMsg("switchLocationsFile(" .. newFile .. ") = OK (ingame)")
			checkIfPlayerNearAnyPackage()
		elseif isInGame and showCreationWindow then
			-- creation mode = bascially same as not creation mode but dont change MOD_SETTINGS.MapFile
			reset()
			LOADED_PACKAGES = readHPLocations(newFile)

			debugMsg("switchLocationsFile(" .. newFile .. ") = OK (ingame creation mode)")
			checkIfPlayerNearAnyPackage()
		else
			-- in main menu or something
			MOD_SETTINGS.MapFile = newFile
			LOADED_PACKAGES = readHPLocations(newFile)
			debugMsg("switchLocationsFile(" .. newFile .. ") = OK (not ingame)")
		end

		return true
	else
		debugMsg("switchLocationsFile(" .. newFile .. ") = error (file not exist or reserved)")
		return false
	end
end

function checkIfPlayerNearAnyPackage()
	local loopStarted = os.clock()

	if MOD_SETTINGS.MapFile == "NONE" then -- mod disabled more or less
		return
	end

	if isInGame == false then
		return
	end

	if (loopStarted - lastCheck) < checkThrottle then
		return
	else
		lastCheck = loopStarted
		debugMsg("check at " .. tostring(lastCheck))
	end

	local checkRange = MOD_SETTINGS.NearPackageRange
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

		if MOD_SETTINGS.HintAudioEnabled and d ~= nil and d <= MOD_SETTINGS.HintAudioRange and (LEX.tableHasValue(userData.collectedPackageIDs, v["identifier"]) == false) then
			audioHint(k)
		end

		if d ~= nil and d <= MOD_SETTINGS.NearPackageRange then -- player is in spawning range of package

			if (LEX.tableHasValue(userData.collectedPackageIDs, v["identifier"]) == false) or showCreationWindow then
				-- player has not collected package OR is in creation mode = should spawn the package

				if not activePackages[k] then -- package is not already spawned
					spawnPackage(k)
				end

				if (d <= 0.75) and (inVehicle() == false) then -- player is at package and is not in a vehicle, package should be collected?

					if showCreationWindow then -- no dont collect it because creation mode is active
						GameHUD.ShowWarning("Simulated Package Collection (Package " .. tostring(k) .. ")")
					else
						-- yes, player is actually playing, lets get it 
						collectHP(k)
					end

				end

			else
				-- package is collected or creation mode is not enabled
				if activePackages[k] then -- package can be active here if player collected package and then opened and closed creation window
					despawnPackage(k)
				end

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
		if LEX.tableLen(loopTimesAvg) > 100 then
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
	debugMsg("clearProgress(" .. LocFile .. ") - before: " .. tostring(LEX.tableLen(userData.collectedPackageIDs)))
	for k,v in pairs(userData.collectedPackageIDs) do
		if not LEX.stringStarts(v, LocFile .. ":") then
			-- package is not from LocFile, add it to the new (cleared) table
			table.insert(clearedTable, v)
		else
			c = c + 1 -- package is from LocFile and we DO NOT want it back = count it
		end
	end
	userData.collectedPackageIDs = clearedTable
	debugMsg("clearProgress(" .. LocFile .. ") - after: " .. tostring(LEX.tableLen(userData.collectedPackageIDs)) .. " (uncollected: " .. tostring(c) .. ")")
	--debugMsg("clearProgress(" .. LocFile .. ") - uncollected " .. tostring(c) .. " pkgs")
end

function countCollected()
	-- cant just check length of collectedPackageIDs as it may include packages from other location files
	local c = 0
	for k,v in pairs(LOADED_PACKAGES) do
		if LEX.tableHasValue(userData.collectedPackageIDs, v["identifier"]) then
			c = c + 1
		end
	end
	return c
end

function rewardAllPackages()
	-- TODO something more fun
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
	if (os.clock() - lastAudioHint) < 0.1 or showCreationWindow or isPaused then
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

function getMapProperty(mapfile, what)
	local path = "Maps/" .. mapfile

	--print(LEX.fileExists(path))
	
	-- TODO optimize

	if what == "identifier" then
		local lines = {}
		for line in io.lines(path) do
			if LEX.stringStarts(line, "IDENTIFIER:") then
				 return string.match(line, ":(.*)") -- https://stackoverflow.com/a/50398252
			end
		end
		return mapfile

	elseif what == "displayname" then
		local lines = {}
		for line in io.lines(path) do
			if LEX.stringStarts(line, "DISPLAY_NAME:") then
				 return string.match(line, ":(.*)") -- https://stackoverflow.com/a/50398252
			end
		end
		return mapfile
	end

	return false

end