local HiddenPackagesMetadata = {
	title = "Hidden Packages",
	version = "1.0.0"
}

local GameSession = require("Modules/GameSession.lua")
local GameUI = require("Modules/GameUI.lua")
local GameHUD = require("Modules/GameHUD.lua")
local LEX = require("Modules/LuaEX.lua")

local debugMode = false
local HUDMessage_Current = ""
local HUDMessage_Last = 0

local showWindow = false
local alwaysShowWindow = false
local showCreationWindow = false
local showScaryButtons = false

local LocationsFile = "packages1.locations" -- used as fallback also

local Create_CreationFile = "created.locations"
local Create_NewCreationFile = Create_CreationFile
local Create_LocationComment = ""
local Create_NewLocationComment = Create_LocationComment
local Create_Message = "Lets go place packages!!!"

local randomAmount = 100

local nearPackageRange = 100

--local propPath = "base/environment/architecture/common/int/int_mlt_jp_arasaka_a/arasaka_logo_tree.ent" -- spinning red arasaka logo... propzboost = 0.5 recommended
local propPath = "base/quest/main_quests/prologue/q005/afterlife/entities/q005_hologram_cube.ent" -- blue hologram cubes
local propZboost = 0.25 -- lifts prop a bit above ground


-- inits
local collectedNames = {} -- names of collected packages
local activeMappins = {} -- object ids for map pins
local activePackages = {}
local HiddenPackagesLocations = {} -- locations loaded from file

local isLoaded = false
local newLocationsFile = LocationsFile -- used for text field in regular window

local userData = {
	locFile = LocationsFile,
	collectedPackageIDs = {}
}

registerHotkey("hp_nearest_pkg", "Mark nearest package", function()
	markNearestPackage()
end)

registerHotkey("hp_toggle_create_window", "Toggle creation window", function()
	showCreationWindow = not showCreationWindow
end)

registerForEvent("onOverlayOpen", function()
	showWindow = true
end)

registerForEvent("onOverlayClose", function()
	showWindow = false
end)

registerForEvent('onInit', function()

	GameSession.StoreInDir('Sessions')
	GameSession.Persist(userData)
	LocationsFile = userData.locFile

	isLoaded = Game.GetPlayer() and Game.GetPlayer():IsAttached() and not Game.GetSystemRequestsHandler():IsPreGame()

	--readHPLocations(LocationsFile)
	--switchLocationsFile(LocationsFile)

	GameSession.OnSave(function()
		userData.locFile = LocationsFile
		userData.collectedPackageIDs = collectedNames
	end)

	GameSession.OnLoad(function()
		reset()
		LocationsFile = userData.locFile
		collectedNames = userData.collectedPackageIDs
		switchLocationsFile(LocationsFile)
	end)

    GameSession.OnStart(function()
        -- Triggered once the load is complete and the player is in the game
        -- (after the loading screen for "Load Game" or "New Game")
        debugMsg('Game Session Started')
        isLoaded = true
        Create_Message = "Lets go place some packages"
        checkIfPlayerNearAnyPackage()
    end)

    GameSession.OnEnd(function()
        -- Triggered once the current game session has ended
        -- (when "Load Game" or "Exit to Main Menu" selected)
        debugMsg('Game Session Ended')
        isLoaded = false
        reset() -- destory all objects and reset tables etc
    end)

    Observe('PlayerPuppet', 'OnAction', function(action) -- any player action
        checkIfPlayerNearAnyPackage()
    end)

end)

registerForEvent('onDraw', function()

	if showWindow then
		ImGui.Begin("Hidden Packages")

		if isLoaded then

			ImGui.Text("Collected: " .. tostring(countCollected()) .. "/" .. tostring(LEX.tableLen(HiddenPackagesLocations)) .. " (" .. LocationsFile .. ")")

			if LEX.tableLen(collectedNames) < LEX.tableLen(HiddenPackagesLocations) then
				if ImGui.Button("Mark nearest package")  then
					markNearestPackage()
				end
			else
				ImGui.Text("You got them all!")
			end
			ImGui.Separator()
		end

		ImGui.Text("Current Locations File: " .. LocationsFile)
		ImGui.Text("Load new:")
		newLocationsFile = ImGui.InputText("", newLocationsFile, 50)
		if ImGui.Button("Load") then
			switchLocationsFile(newLocationsFile)
			checkIfPlayerNearAnyPackage()
		end
		ImGui.Separator()
		
		if isLoaded then
			ImGui.Text(" - Very Dumb Randomizer - ")
			ImGui.Text("Randomized packages will very likely appear out of reach.\nOnly useful for testing, for now.")
			randomAmount = ImGui.InputInt("Random packages", randomAmount, 100)
			if ImGui.Button("Generate") then
				-- todo save these to file
				switchLocationsFile(generateRandomPackages(randomAmount))
				debugMsg("HP Randomizer done")
			end
			ImGui.Separator()
		end

		if ImGui.Button("Show/hide creation window") then
			showCreationWindow = not showCreationWindow
		end

		if ImGui.Button("Show/hide scary buttons") then
			showScaryButtons = not showScaryButtons
		end

		if showScaryButtons then
			if ImGui.Button("Reset progress\n(" .. LocationsFile .. ")") then
				clearProgress(LocationsFile)
				reset()
			end

			if ImGui.Button("Toggle Debug Mode") then
				debugMode = not debugMode
			end
			ImGui.SameLine()
			ImGui.Text("Debug Mode: " .. tostring(debugMode))

		end

		ImGui.Text("collectedNames: " .. tostring(LEX.tableLen(collectedNames)))
		ImGui.Text("userData: " .. tostring(LEX.tableLen(userData.collectedPackageIDs)))

		ImGui.End()
	end




	if showCreationWindow then
		ImGui.Begin("Package placing")

		ImGui.Text("Status: " .. Create_Message) -- status message

		if isLoaded then
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

			local NP = HiddenPackagesLocations[findNearestPackage(false)] -- false to ignore if its collected or not
			if NP then
				ImGui.Text("Distance to nearest package: " .. string.format("%.2f", distanceToCoordinates(NP["x"],NP["y"],NP["z"],NP["w"])))
			end

			ImGui.Separator()
			Create_NewCreationFile = ImGui.InputText("File", Create_NewCreationFile, 50)
			Create_NewLocationComment = ImGui.InputText("Comment (optional)", Create_NewLocationComment, 50)
			if ImGui.Button("Save This Location") then

				Create_CreationFile = Create_NewCreationFile
				Create_LocationComment = Create_NewLocationComment

				local gps = Game.GetPlayer():GetWorldPosition()
				local position = {}
				position["x"] = gps["x"]
				position["y"] = gps["y"]
				position["z"] = gps["z"]
				position["w"] = gps["w"]
				if appendLocationToFile(Create_NewCreationFile, position["x"], position["y"], position["z"], position["w"], Create_NewLocationComment) then
					Create_Message = "Location saved!"
				else
					Create_Message = "ERROR saving location :("
				end
			
			end

			if ImGui.Button("Apply & Test") then
				switchLocationsFile(Create_NewCreationFile)
				checkIfPlayerNearAnyPackage()
				Create_Message = tostring(LEX.tableLen(HiddenPackagesLocations)) .. " packages applied & loaded"
			end
			ImGui.Separator()
			if ImGui.Button("Mark ALL packages on map") then
				removeAllMappins()
				for k,v in ipairs(HiddenPackagesLocations) do
					if LEX.tableHasValue(collectedNames, v["id"]) == false then -- check if package is in collectedNames, if so we already got it
						activeMappins[k] = placeMapPin(v["x"], v["y"], v["z"], v["w"])
					end
				end
			end

			if ImGui.Button("Remove all map pins") then
				removeAllMappins()
			end

		else
			Create_Message = "Not in-game"
		end

		ImGui.Separator()
		if ImGui.Button("Close") then
			showCreationWindow = false
		end

		ImGui.End()
	end

end)

function printAllHPs()
	for k,v in ipairs(HiddenPackagesLocations) do
		print("Package" .. k)
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

function collectHP(packageIndex) -- name is more like packageID
	debugMsg("collecting package " .. packageIndex)

	local pkg = HiddenPackagesLocations[packageIndex]
	table.insert(collectedNames, pkg["id"])

	-- destroy package object
	destroyObject(activePackages[k])
		
	if activeMappins[packageIndex] then
		Game.GetMappinSystem():UnregisterMappin(activeMappins[packageIndex])
		activeMappins[packageIndex] = false
	end

    if LEX.tableLen(collectedNames) == LEX.tableLen(HiddenPackagesLocations) then
    	-- got em all
    	debugMsg("Got all packages")
    	local msg = "All Hidden Packages collected!"
    	GameHUD.ShowWarning(msg)
    	-- TODO give some kind of reward here
    else
    	local msg = "Hidden Package " .. tostring(countCollected()) .. " of " .. tostring(LEX.tableLen(HiddenPackagesLocations))
    	GameHUD.ShowWarning(msg)
    end

end

function reset()
	destroyAll()
	removeAllMappins()
	collectedNames = {}
	debugMsg("reset() OK")
end

function destroyAll()
	for k,v in ipairs(HiddenPackagesLocations) do
		if activePackages[k] then
			destroyObject(activePackages[k])
			activePackages[k] = nil
		end
	end
end

function readHPLocations(filename)
	if not LEX.fileExists(filename) then
		debugMsg("readHPLocations: failed to load " .. filename)
		return false
	end

	HiddenPackagesLocations = {}
	lines = {}
	for line in io.lines(filename) do
		if (line ~= nil) and (line ~= "") and not (LEX.stringStarts(line, "#")) then 
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
		hp["id"] = filename .. ": x=" .. tostring(vals[1]) .. " y=" .. tostring(vals[2]) .. " z=" .. tostring(vals[3]) .. " w=" .. tostring(vals[4])
		hp["x"] = tonumber(vals[1])
		hp["y"] = tonumber(vals[2])
		hp["z"] = tonumber(vals[3])
		hp["w"] = tonumber(vals[4])
		table.insert(HiddenPackagesLocations, hp)
	end

	debugMsg("read locations file " .. filename)
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

	local filename = "Random - " .. tostring(n) .. " packages (" .. os.date("%Y-%m-%d %H.%M.%S") .. ").rng"
	HiddenPackagesLocations = {}
	local i = 1
	while (i <= n) do
		x = math.random(-2623, 3598)
		y = math.random(-4011, 3640)
		z = math.random(1, 120)
		w = 1

		appendLocationToFile(filename, x,y,z,w, "") -- extremely inefficient btw

		i = i + 1
	end

	-- save to file and return filename
	return filename

end

function appendLocationToFile(filename, x, y, z, w, comment)
	if filename == "" then
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
		print(k,v)
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

	for k,v in ipairs(HiddenPackagesLocations) do
		if (LEX.tableHasValue(collectedNames, v["id"]) == false) or (ignoreFound == false) then
			
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
	if not isLoaded then
		return
	end

	removeAllMappins()

	local NP = findNearestPackage(true) -- true to ignore found packages
	if NP then
		local pkg = HiddenPackagesLocations[NP]
		activeMappins[NP] = placeMapPin(pkg["x"], pkg["y"], pkg["z"], pkg["w"])
		debugMsg("package #" .. NP .. " marked")
		HUDMessage("Nearest package marked")
		return true
	end
	HUDMessage("No packages available")
	return false
end

function switchLocationsFile(newFile)
	if LEX.fileExists(newFile) then
		LocationsFile = newFile
		reset()
		readHPLocations(LocationsFile)
		collectedNames = userData.collectedPackageIDs -- because reset clears collectedNames
		return true
	else
		debugMsg("switchLocationsFile() ERROR: " .. newFile .. " did not exist?")
		return false
	end
end

function checkIfPlayerNearAnyPackage()
	if not isLoaded then
		return
	end

	for k,v in ipairs(HiddenPackagesLocations) do

		local d = distanceToCoordinates(v["x"], v["y"], v["z"], v["w"])

		if ( d <= nearPackageRange ) and ( LEX.tableHasValue(collectedNames, v["id"]) == false ) then
			-- player is near a uncollected package. spawn it if it isnt already

			if not activePackages[k] then
				debugMsg("spawning package " .. k)
				activePackages[k] = spawnObjectAtPos(v["x"], v["y"], v["z"]+propZboost, v["w"])
			end

			if d <= 0.5 and not inVehicle() then 
				collectHP(k)
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
	if isLoaded then
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
	for k,v in ipairs(collectedNames) do
		if LEX.stringStarts(v,LocFile .. ":") then -- galaxy brain move to use a : as its not allowed in filenames
			debugMsg("uncollected " ..  k .. v)
			table.remove(collectedNames,k)
		end
	end
	--userData.collectedPackageIDs = collectedNames
end

function countCollected()
	local c = 0
	for k,v in ipairs(HiddenPackagesLocations) do
		if LEX.tableHasValue(collectedNames, v["id"]) then
			c = c + 1
		end
	end
	return c
end