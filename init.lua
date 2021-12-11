-- Sessions Folder must exist or saving will fail

local HiddenPackagesMetadata = {
	title = "Hidden Packages",
	version = "1.0.0"
}

local GameSession = require("Modules/GameSession.lua")
local GameUI = require("Modules/GameUI.lua")
local GameHUD = require("Modules/GameHUD.lua")
local LEX = require("Modules/LuaEX.lua")

local reservedFilenames = {"DEBUG", "RANDOMIZER", "DEFAULT", "init.lua", "db.sqlite3", "Hidden Packages.log"}

local locationsFile = "packages1" -- default/fallback packages file, will be overriden by packages file named in DEFAULT
local overrideLocations = false

local userData = {
	locFile = "",
	packages = {},
	collectedPackageIDs = {}
}

local debugMode = false
local showRandomizer = false

local HUDMessage_Current = ""
local HUDMessage_Last = 0

local statusMsg = ""
local showWindow = false
local showCreationWindow = false
local showScaryButtons = false

local Create_NewCreationFile = "created"
local Create_NewLocationComment = ""
local Create_Message = ""

local randomizerAmount = 100
local nearPackageRange = 100 -- if player this near to package then spawn it (and despawn when outside)

--local propPath = "base/environment/architecture/common/int/int_mlt_jp_arasaka_a/arasaka_logo_tree.ent" -- spinning red arasaka logo... propzboost = 0.5 recommended
local propPath = "base/quest/main_quests/prologue/q005/afterlife/entities/q005_hologram_cube.ent" -- blue hologram cubes
--local propPath = "base/environment/ld_kit/marker_blue_small.ent" -- lol
local propZboost = 0.25 -- lifts prop a bit above ground


-- inits
local activeMappins = {} -- object ids for map pins
local activePackages = {}
local isInGame = false
local newLocationsFile = userData.locFile -- used for text field in regular window

registerHotkey("hp_nearest_pkg", "Mark nearest package", function()
	markNearestPackage()
end)

registerHotkey("hp_toggle_create_window", "Toggle creation window", function()
	showCreationWindow = not showCreationWindow
end)

registerForEvent("onOverlayOpen", function()

	if LEX.fileExists("DEBUG") then
		debugMode = true
	else
		debugMode = false
	end

	if LEX.fileExists("RANDOMIZER") or debugMode then
		showRandomizer = true
	else
		showRandomizer = false
	end

	showWindow = true
end)

registerForEvent("onOverlayClose", function()
	showWindow = false
	showScaryButtons = false
end)

registerForEvent('onInit', function()
	GameSession.StoreInDir('Sessions')
	GameSession.Persist(userData)
	isInGame = Game.GetPlayer() and Game.GetPlayer():IsAttached() and not Game.GetSystemRequestsHandler():IsPreGame()

	-- check if file DEFAULT exists and if so load default packages file from there
	if LEX.fileExists("DEFAULT") then
		local file = io.open("DEFAULT", "r")
		local overrideFile = LEX.trim(file:read("*a"))
		file:close()
		if LEX.fileExists(overrideFile) and not LEX.tableHasValue(reservedFilenames, overrideFile) then
			locationsFile = overrideFile
			print("Loaded hidden packages file from DEFAULT: " .. locationsFile)
		end
	end

    GameSession.OnStart(function()
        -- Triggered once the load is complete and the player is in the game
        -- (after the loading screen for "Load Game" or "New Game")
        debugMsg('Game Session Started')
        isInGame = true
        Create_Message = "Lets go place some packages"
        checkIfPlayerNearAnyPackage() -- otherwise if you made a save near a package and just stand still it wont spawn until you move
    end)

	--GameSession.OnSave(function()
	--end)

	GameSession.OnLoad(function()
		if overrideLocations or LEX.tableLen(userData.packages) == 0 then
			userData.locFile = locationsFile
			userData.packages = readHPLocations(locationsFile)
			overrideLocations = false -- only load these new packages once. if user loads another save file where it already had packages loaded, use that.
		end

	end)

    GameSession.OnEnd(function()
        -- Triggered once the current game session has ended
        -- (when "Load Game" or "Exit to Main Menu" selected)
        debugMsg('Game Session Ended')
        isInGame = false
        reset() -- destroy all objects and reset tables etc
        -- should maybe wipe userData here but it gets properly set when starting a new game or loading a game anyway so not sure its necessary
    end)

    Observe('PlayerPuppet', 'OnAction', function(action) -- any player action
        checkIfPlayerNearAnyPackage()
    end)

end)

registerForEvent('onDraw', function()

	if showWindow then
		ImGui.Begin("Hidden Packages")

		if isInGame then

			ImGui.Text("Using locations from: " .. userData.locFile)
			ImGui.Text("Collected: " .. tostring(countCollected()) .. "/" .. tostring(LEX.tableLen(userData.packages)))

			if countCollected() < LEX.tableLen(userData.packages) then
				if ImGui.Button("Mark nearest package")  then
					markNearestPackage()
				
				end
			else
				ImGui.Text("You got them all!")
			end

		else
			ImGui.Text("Not in-game")
			ImGui.Text("DEFAULT packages: " .. locationsFile)
		end

		ImGui.Separator()

		newLocationsFile = ImGui.InputText("", newLocationsFile, 50)
		if ImGui.Button("Load New Locations File") then
			if switchLocationsFile(newLocationsFile) then
				statusMsg = "OK, loaded: " .. newLocationsFile
			else
				statusMsg = "Error loading: " .. newLocationsFile
			end
		end
		ImGui.Text(statusMsg)
		ImGui.Separator()
		
		if showRandomizer then
			ImGui.Text("Randomizer:")
			randomizerAmount = ImGui.InputInt("Packages", randomizerAmount, 100)
			if ImGui.Button("Generate") then
				switchLocationsFile(generateRandomPackages(randomizerAmount))
				debugMsg("HP Randomizer done")
			end
			ImGui.Separator()
		end

		if ImGui.Button("Package Placing Mode") then
			showCreationWindow = true
		end

		if debugMode then
			ImGui.Text(" *** DEBUG MODE ACTIVE ***")
			ImGui.Text("isInGame: " .. tostring(isInGame))
			ImGui.Text("overrideLocations: " .. tostring(overrideLocations))
			ImGui.Text("locationsFile: " .. locationsFile)
			ImGui.Text("userData locFile: " .. userData.locFile)
			ImGui.Text("userData packages: " .. tostring(LEX.tableLen(userData.packages)))
			ImGui.Text("userData collected: " .. tostring(LEX.tableLen(userData.collectedPackageIDs)))
			ImGui.Text("countCollected(): " .. tostring(countCollected()))
			if ImGui.Button("reset()") then
				reset()
			end
			ImGui.Separator()
		end

		if isInGame then

			if ImGui.Button("Show/hide Scary Buttons") then
				showScaryButtons = not showScaryButtons
			end

			if showScaryButtons then

				ImGui.Separator()
				ImGui.Text("Warning: One click is all you need.\nNo confirmations!")

				if ImGui.Button("Load DEFAULT packages\n(" .. locationsFile .. ")") then
					reset()
					switchLocationsFile(locationsFile)
				end

				if ImGui.Button("Reload packages\n(" .. userData.locFile .. ")") then
					userData.packages = readHPLocations(userData.locFile)
				end

				if countCollected() > 0 then
					if ImGui.Button("Reset progress\n(" .. userData.locFile .. ")") then
						clearProgress(userData.locFile)
						reset()
					end
				end

				if LEX.tableLen(userData.collectedPackageIDs) > 0 then
					if ImGui.Button("Reset ALL progress") then
						userData.collectedPackageIDs = {}
						reset()
					end
				end

			end

		end

		ImGui.End()
	end




	if showCreationWindow then
		ImGui.Begin("Package Placing")

		ImGui.Text("Status: " .. Create_Message) -- status message

		if isInGame then
			ImGui.Text("Player Position:")
			local gps = Game.GetPlayer():GetWorldPosition()
			local position = {} -- ... so we'll convert into a traditional table
			position["x"] = gps["x"]
			position["y"] = gps["y"]
			position["z"] = gps["z"]
			position["w"] = gps["w"]
			ImGui.Text("X: " .. string.format("%.3f", position["x"]))
			ImGui.SameLine()
			ImGui.Text("\tY: " .. string.format("%.3f", position["y"]))

			ImGui.Text("Z: " .. string.format("%.3f", position["z"]))
			ImGui.SameLine()
			ImGui.Text("\tW: " .. tostring(position["w"]))

			local NP = userData.packages[findNearestPackage(false)] -- false to ignore if its collected or not
			if NP then
				ImGui.Text("Nearest Package: " .. string.format("%.f", distanceToCoordinates(NP["x"],NP["y"],NP["z"],NP["w"])) .. "M away")
			end

			ImGui.Separator()
			Create_NewCreationFile = ImGui.InputText("File", Create_NewCreationFile, 50)
			Create_NewLocationComment = ImGui.InputText("Comment", Create_NewLocationComment, 50)
			if ImGui.Button("Save This Location") then

				local gps = Game.GetPlayer():GetWorldPosition()
				local position = {}
				position["x"] = gps["x"]
				position["y"] = gps["y"]
				position["z"] = gps["z"]
				position["w"] = gps["w"]
				if appendLocationToFile(Create_NewCreationFile, position["x"], position["y"], position["z"], position["w"], Create_NewLocationComment) then
					HUDMessage("Location saved!")
					Create_Message = "Location saved!"
					Create_NewLocationComment = ""
				else
					Create_Message = "Error saving location :("
				end
			
			end

			if ImGui.Button("Apply & Test") then
				switchLocationsFile(Create_NewCreationFile)
				checkIfPlayerNearAnyPackage()
				Create_Message = tostring(LEX.tableLen(userData.packages)) .. " packages applied & loaded"
			end
			ImGui.Separator()

			if ImGui.Button("Mark ALL packages on map") then
				removeAllMappins()
				for k,v in ipairs(userData.packages) do
					activeMappins[k] = placeMapPin(v["x"], v["y"], v["z"], v["w"])
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
		end

		ImGui.End()
	end

end)

function spawnObjectAtPos(x,y,z,w)
	if not isInGame then
		return
	end

    local transform = Game.GetPlayer():GetWorldTransform()
    local pos = Game.GetPlayer():GetWorldPosition()
    pos.x = x
    pos.y = y
    pos.z = z
    pos.w = w
    transform:SetPosition(pos)

    return WorldFunctionalTests.SpawnEntity(propPath, transform, '') -- returns ID
end

function destroyObject(e)
	if Game.FindEntityByID(e) ~= nil then
        Game.FindEntityByID(e):GetEntity():Destroy()
    end
end

function collectHP(packageIndex)
	debugMsg("Collecting package " .. packageIndex)

	local pkg = userData.packages[packageIndex]
	table.insert(userData.collectedPackageIDs, pkg["identifier"])

	if activeMappins[packageIndex] then -- unregister map pin if any
		Game.GetMappinSystem():UnregisterMappin(activeMappins[packageIndex])
		activeMappins[packageIndex] = nil
	end

	destroyObject(activePackages[packageIndex]) -- despawn 

    if countCollected() == LEX.tableLen(userData.packages) then
    	-- got em all
    	debugMsg("Got all packages")
    	local msg = "All Hidden Packages collected!"
    	GameHUD.ShowWarning(msg)
    	rewardAllPackages()
    else
    	local msg = "Hidden Package " .. tostring(countCollected()) .. " of " .. tostring(LEX.tableLen(userData.packages))
    	GameHUD.ShowWarning(msg)
    end

    debugMsg("Collected package " .. packageIndex)
end

function reset()
	destroyAllPackageObjects()
	removeAllMappins()
	debugMsg("reset() OK")
end

function destroyAllPackageObjects()
	for k,v in ipairs(userData.packages) do
		if activePackages[k] then
			destroyObject(activePackages[k])
			activePackages[k] = nil
		end
	end
	debugMsg("destroyAll() OK")
end

function readHPLocations(filename)
	if not LEX.fileExists(filename) or LEX.tableHasValue(reservedFilenames, filename) then
		debugMsg("readHPLocations() not a valid file")
		return false
	end

	local lines = {}
	for line in io.lines(filename) do
		if (line ~= nil) and (line ~= "") and not (LEX.stringStarts(line, "#")) and not (LEX.stringStarts(line, "//")) then 
			lines[#lines + 1] = line
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
		hp["identifier"] = filename .. ": x=" .. tostring(vals[1]) .. " y=" .. tostring(vals[2]) .. " z=" .. tostring(vals[3]) .. " w=" .. tostring(vals[4])
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
	debugMsg("placing map pin at " ..  x .. " " .. y .. " " .. z .. " " ..w)
	local mappinData = MappinData.new()
	mappinData.mappinType = TweakDBID.new('Mappins.DefaultStaticMappin')
	mappinData.variant = gamedataMappinVariant.CustomPositionVariant -- see more types: https://github.com/WolvenKit/CyberCAT/blob/main/CyberCAT.Core/Enums/Dumped%20Enums/gamedataMappinVariant.cs
	mappinData.visibleThroughWalls = true   

	local position = Game.GetPlayer():GetWorldPosition()
	position.x = x
	position.y = y
	position.z = z -- dont add propZboost to map pin, otherwise the waypoint covers up the prop 
	position.w = w

	return Game.GetMappinSystem():RegisterMappin(mappinData, position) -- returns ID
end

function generateRandomPackages(n)
	debugMsg("generating " .. n .. " random packages...")

	local filename = tostring(n) .. " random packages (" .. os.date("%Y%m%d-%H%M%S") .. ")"
	userData.packages = {}
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

function removeAllMappins()
	for k,v in ipairs(activeMappins) do
		--print(k,v)
		if activeMappins[k] then
			Game.GetMappinSystem():UnregisterMappin(activeMappins[k])
			activeMappins[k] = nil
		end
	end
	debugMsg("removeAllMappins() OK")
end

function distanceToCoordinates(x,y,z,w)
	local playerPosition = Game.GetPlayer():GetWorldPosition()
	
	local x_distance = math.abs(playerPosition["x"] - x)
	local y_distance = math.abs(playerPosition["y"] - y)
	local z_distance = math.abs(playerPosition["z"] - z)
	-- ignore w for now, seems to always be 1
	
	return math.sqrt( (x_distance*x_distance) + (y_distance*y_distance) + (z_distance*z_distance) ) -- pythagorean shit
end

function findNearestPackage(ignoreFound) -- 
	local lowest = nil
	local nearestPackage = false

	for k,v in ipairs(userData.packages) do
		if (LEX.tableHasValue(userData.collectedPackageIDs, v["identifier"]) == false) or (ignoreFound == false) then
			
			local distance = distanceToCoordinates(v["x"], v["y"], v["z"], v["w"])
			
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
		local pkg = userData.packages[NP]
		activeMappins[NP] = placeMapPin(pkg["x"], pkg["y"], pkg["z"], pkg["w"])
		debugMsg("package #" .. NP .. " marked")
		HUDMessage("Nearest Package Marked (" .. string.format("%.f", distanceToCoordinates(pkg["x"],pkg["y"],pkg["z"],pkg["w"])) .. "M away)")
		return true
	end
	HUDMessage("No packages available")
	return false
end

function switchLocationsFile(newFile)
	if LEX.fileExists(newFile) and not LEX.tableHasValue(reservedFilenames, newFile) then
		debugMsg("switchLocationsFile() " .. newFile)

		if isInGame then 
			userData.locFile = newFile
			userData.packages = readHPLocations(newFile)
			reset()
			overrideLocations = false
			debugMsg("switchLocationsFile() " .. newFile .. "OK (in-game)")
		else
			locationsFile = newFile
			overrideLocations = true
			debugMsg("switchLocationsFile() " .. newFile .. "OK (NOT in game)")
		end

		return true
	else
		debugMsg("switchLocationsFile() ERROR: " .. newFile .. " did not exist or is reserved filename")
		return false
	end
end

function checkIfPlayerNearAnyPackage()
	if not isInGame then
		return
	end

	for k,v in ipairs(userData.packages) do

		local d = distanceToCoordinates(v["x"], v["y"], v["z"], v["w"])

		if ( d <= nearPackageRange ) then -- player is in spawning range of package

			if (LEX.tableHasValue(userData.collectedPackageIDs, v["identifier"]) == false) or showCreationWindow then
				-- player has not collected package OR is in creation mode = should spawn the package

				if not activePackages[k] then -- package is not already spawned
					debugMsg("spawning package " .. k)
					activePackages[k] = spawnObjectAtPos(v["x"], v["y"], v["z"]+propZboost, v["w"])
				end

				if d <= 0.5 and not inVehicle() then

					if showCreationWindow then
						-- creation mode, dont collect it (messes with userdata collected packages)
						GameHUD.ShowWarning("Simulated Package Collection")
					else
						-- player is actually playing, lets get it 
						collectHP(k)
					end

				end
			end

		else

			if activePackages[k] then
				debugMsg("DE-spawning package " .. k)
				destroyObject(activePackages[k])
				activePackages[k] = nil
			end

		end
	end

end


function debugMsg(msg)
	if not debugMode then
		return
	end

	print("HP debug: " .. msg)
	if isInGame then
		HUDMessage("DEBUG: " .. msg)
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
	for k,v in ipairs(userData.collectedPackageIDs) do
		if LEX.stringStarts(v,LocFile .. ":") then -- galaxy brain move to use a : as its not allowed in filenames
			debugMsg("uncollected " ..  k .. v)
			table.remove(userData.collectedPackageIDs,k)
		end
	end
end

function countCollected()
	-- cant just check length of collectedPackageIDs as it may include packages from other location files
	local c = 0
	for k,v in ipairs(userData.packages) do
		if LEX.tableHasValue(userData.collectedPackageIDs, v["identifier"]) then
			c = c + 1
		end
	end
	return c
end

function rewardAllPackages()
	-- TODO something more fun
	Game.AddToInventory("Items.money", 1000000)
	debugMsg("Reward!")
end