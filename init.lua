local HiddenPackagesMetadata = {
	title = "Hidden Packages",
	version = "0.1"
}

local GameSession = require("Modules/GameSession.lua")
local GameUI = require("Modules/GameUI.lua")
local GameHUD = require("Modules/GameHUD.lua")
local LEX = require("Modules/LuaEX.lua")

local showWindow = false
local alwaysShowWindow = false
local showCreationWindow = false
local showScaryButtons = false

local LocationsFile = "packages1.txt" -- used as fallback also

local Create_CreationFile = "created.txt"
local Create_NewCreationFile = Create_CreationFile
local Create_LocationComment = ""
local Create_NewLocationComment = Create_LocationComment
local Create_Message = "Lets go place packages!!!"

local randomAmount = 100

local nearPackageRange = 10

local propPath = "base/environment/architecture/common/int/int_mlt_jp_arasaka_a/arasaka_logo_tree.ent" -- spinning red arasaka logo... propzboost = 0.5 
--local propPath = "base/quest/main_quests/prologue/q005/afterlife/entities/q005_hologram_cube.ent" -- blue hologram cubes
local propZboost = 0.5 -- lifts prop a bit above ground


-- inits
local collectedNames = {} -- names of collected packages
local activeMappins = {} -- object ids for map pins
local activePackages = {}
local HiddenPackagesLocations = {} -- locations loaded from file

local isLoaded = false
local newLocationsFile = LocationsFile -- used for text field in regular window


registerHotkey("hp_nearest_pkg", "Mark nearest package", function()
	markNearestPackage()
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
        checkIfPlayerNearAnyPackage()
    end)

	Observe('QuestTrackerGameController', 'OnInitialize', function()
	    if not isLoaded then
	        --print('Game Session Started')
	        isLoaded = true

	        loadSaveData(LocationsFile .. ".save")
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

	if showWindow then
		ImGui.Begin("Hidden Packages")

		ImGui.Text("Collected: " .. tostring(LEX.tableLen(collectedNames)) .. "/" .. tostring(LEX.tableLen(HiddenPackagesLocations)) .. " (" .. LocationsFile .. ")")

		if LEX.tableLen(collectedNames) < LEX.tableLen(HiddenPackagesLocations) then
			if ImGui.Button("Mark nearest package")  then
				markNearestPackage()
			end
			if ImGui.Button("Mark ALL packages")  then
				for k,v in ipairs(HiddenPackagesLocations) do
					if LEX.tableHasValue(collectedNames, v["id"]) == false then -- check if package is in collectedNames, if so we already got it
						activeMappins[k] = placeMapPin(v["x"], v["y"], v["z"], v["w"])
					end
				end
			end

		else
			ImGui.Text("You got them all!")
		end

		ImGui.Separator()
		ImGui.Text("Load new locations file:")
		newLocationsFile = ImGui.InputText("", newLocationsFile, 50)
		if ImGui.Button("Load") then
			switchLocationsFile(newLocationsFile)
		end


		ImGui.Text("")
		if ImGui.Button("Create Package Locations") then
			showCreationWindow = not showCreationWindow
		end

		ImGui.Separator()
		ImGui.Text(" - Very Dumb Randomizer - ")
		ImGui.Text("Randomized packages can appear out of reach.\nOnly useful for testing for now...\n(...but feel free to try anyway)")
		randomAmount = ImGui.InputInt("Random packages", randomAmount, 10)
		if ImGui.Button("Generate") then
			-- todo save these to file
			switchLocationsFile(generateRandomPackages(randomAmount))
			print("HP Randomizer done")
		end
		ImGui.Separator()

		if ImGui.Button("Show/hide scary buttons") then
			showScaryButtons = not showScaryButtons
		end

		if showScaryButtons then
			if ImGui.Button("Reset progress\n(" .. LocationsFile .. ")") then
				deleteSave()
				reset()
			end

			if ImGui.Button("reset()\ndespawns packages and sets collected to 0\n(SHOULD ALWAYS BE DONE BEFORE RELOADING MOD!)") then
				reset()
			end
			if ImGui.Button("destroyAll()\ndespawns all packages") then
				destroyAll()
			end
			if ImGui.Button("printAllHPs()\nprints current loaded HPs to console") then
				printAllHPs()
			end

		end

		ImGui.End()
	end




	if showCreationWindow then
		ImGui.Begin("Hidden Package placin\'")

		ImGui.Text("Player Position:")
		if isLoaded then
			local gps = Game.GetPlayer():GetWorldPosition()
			local position = {} -- ... so we'll convert into a traditional table
			position["x"] = gps["x"]
			position["y"] = gps["y"]
			position["z"] = gps["z"]
			position["w"] = gps["w"]
			ImGui.Text("X: " .. string.format("%.2f", position["x"]))
			ImGui.SameLine()
			ImGui.Text("Y: " .. string.format("%.2f", position["y"]))

			ImGui.Text("Z: " .. string.format("%.2f", position["z"]))
			ImGui.SameLine()
			ImGui.Text("W: " .. tostring(position["w"]))
		else
			ImGui.Text("(Not in-game)")
		end

		local NP = HiddenPackagesLocations[findNearestPackage(false)]
		ImGui.Text("Distance to nearest package: " .. string.format("%.2f", distanceToCoordinates(NP["x"],NP["y"],NP["z"],NP["w"])))

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
		end

		ImGui.Text(Create_Message) -- status message

		if ImGui.Button("Close") then
			showCreationWindow = not showCreationWindow
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

    return WorldFunctionalTests.SpawnEntity(propPath, transform, '') -- returns ID
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
    end
end

function collectHP(packageIndex) -- name is more like packageID

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
    	local msg = "All Hidden Packages collected!"
    	GameHUD.ShowWarning(msg)
    	-- TODO give reward here
    else
    	local msg = "Hidden Package " .. tostring(LEX.tableLen(collectedNames)) .. " of " .. tostring(LEX.tableLen(HiddenPackagesLocations))
    	GameHUD.ShowWarning(msg)
    end

end


function saveData(filename)
	if LEX.tableLen(collectedNames) == 0 then
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
	if not LEX.fileExists(filename) then
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
	print("Hidden Packages: loaded " .. filename)
	return true
end

function reset()
	destroyAll()
	collectedNames = {}
	removeAllMappins()
	print("Hidden Packages: reset ok")
end

function destroyAll()
	for k,v in ipairs(activePackages) do
		if activePackages[k] then
			destroyObject(activePackages[k])
			activePackages[k] = false
		end
	end
end

function readHPLocations(filename)
	if not LEX.fileExists(filename) then
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
	if not LEX.fileExists("LAST_USED") then
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
	if not LEX.fileExists(filename) then
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
		print("HP Append: not a valid filename")
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
	-- rounding to 2 decimals... seems fine?
	content = content .. string.format("%.2f", x) .. " " .. string.format("%.2f", y) .. " " .. string.format("%.2f", z) .. " " .. tostring(w)

	if comment ~= "" then -- only append comment if there is one
		content = content .. " // " .. comment
	end

	local file = io.open(filename, "w")
	file:write(content)
	file:close()
	print("HP Appended", filename, x, y, z, w, comment)
	return true
end

function removeAllMappins()
	print("removeallmappins")
	for k,v in ipairs(activeMappins) do
		print(k,v)
		if activeMappins[k] then
			Game.GetMappinSystem():UnregisterMappin(activeMappins[k])
			activeMappins[k] = false
		end
	end
	print("removed all mappins")
end

function distanceToCoordinates(x,y,z,w)
	local playerPosition = Game.GetPlayer():GetWorldPosition()
	
	local x_distance = math.abs(playerPosition["x"] - x)
	local y_distance = math.abs(playerPosition["y"] - y)
	local z_distance = math.abs(playerPosition["z"] - z)
	-- ignore w for now, seems to always be 1
	
	return math.sqrt( (x_distance*x_distance) + (y_distance*y_distance) + (z_distance*z_distance) ) -- pythagorean shit
end

function findNearestPackage(ignoreFound)
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
	removeAllMappins()

	local NP = findNearestPackage(true) -- true to ignore found packages
	if NP then
		local pkg = HiddenPackagesLocations[NP]
		activeMappins[NP] = placeMapPin(pkg["x"], pkg["y"], pkg["z"], pkg["w"])
		GameHUD.ShowMessage("Nearest package marked")
		return true
	end
	return false
end

function switchLocationsFile(newFile)
	if LEX.fileExists(newFile) then
		LocationsFile = newFile
		reset()
		readHPLocations(LocationsFile)
		loadSaveData(LocationsFile .. ".save")
		saveLastUsed()
		return true
	else
		print("Hidden Packages ERROR: file " .. newFile .. " did not exist?")
		return false
	end
end

function checkIfPlayerNearAnyPackage()
	if not isLoaded then
		return
	end

	for k,v in ipairs(HiddenPackagesLocations) do

		if ( distanceToCoordinates(v["x"], v["y"], (v["z"] + propZboost), v["w"]) <= nearPackageRange ) and ( LEX.tableHasValue(collectedNames, v["id"]) == false ) then
			-- player is near a uncollected package. spawn it if it isnt already and start checking if at actual HP

			if not activePackages[k] then
				activePackages[k] = spawnObjectAtPos(v["x"], v["y"], v["z"], v["w"])
			end

			checkIfPlayerAtHP(k)

		else

			if activePackages[k] then
				destroyObject(activePackages[k])
				activePackages[k] = false
			end

		end
	end

end


function checkIfPlayerAtHP(packageIndex)

	local pkg = HiddenPackagesLocations[packageIndex]
	if isPlayerAtPos(pkg["x"], pkg["y"], (pkg["z"] + propZboost), pkg["w"]) then
		if not inVehicle() then -- only allow picking them up on foot (like in the GTA games)
			collectHP(packageIndex)
		end
	end

end