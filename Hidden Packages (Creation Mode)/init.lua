local MOD_METADATA = {
	title = "Hidden Packages (Creation Mode)",
	version = "1.0.0"
}


local GameHUD = require("Modules/GameHUD.lua")
local LEX = require("Modules/LuaEX.lua")

local showCreationWindow = false
local isInGame = false

local HUDMessage_Current = ""
local HUDMessage_Last = 0
local statusMsg = "Hello, I am statusMsg."


local MOD_SETTINGS = {
	DebugMode = false,
	Filename = "CREATE.map",
	NearPackageRange = 100
}

local activePackages = {}
local activeMappins = {}
local LOADED_PACKAGES = {}

local Create_NewCreationFile = MOD_SETTINGS.Filename
local Create_NewLocationComment = ""

local PACKAGE_PROP = "base/quest/main_quests/prologue/q005/afterlife/entities/q005_hologram_cube.ent"
local PACKAGE_PROP_Z_BOOST = 0.25

local lastCheck = 0
local checkThrottle = 1
local distanceToNearestPackage = nil

registerHotkey("hp_toggle_create_window", "Toggle creation window", function()
	showCreationWindow = not showCreationWindow
	if showCreationWindow == false then
		reset()
	end
end)

registerForEvent('onInit', function()
	loadSettings()
	switchLocationsFile(MOD_SETTINGS.Filename)
end)

registerForEvent('onDraw', function()
	if showCreationWindow then
		checkIfPlayerNearAnyPackage()

		ImGui.Begin("Hidden Packages - Creation Mode")
		ImGui.Text(statusMsg) -- status message
		ImGui.Separator()
		
		local position = Game.GetPlayer():GetWorldPosition()
		ImGui.Text("Player Position:")
		ImGui.Text("X: " .. string.format("%.3f", position["x"]))
		ImGui.SameLine()
		ImGui.Text("\tY: " .. string.format("%.3f", position["y"]))

		ImGui.Text("Z: " .. string.format("%.3f", position["z"]))
		ImGui.SameLine()
		ImGui.Text("\tW: " .. tostring(position["w"]))

		if LEX.tableLen(LOADED_PACKAGES) > 0 then
			ImGui.Text("Nearest package: " .. string.format("%.1f", distanceToNearestPackage) .. "M away")
		end

		ImGui.Separator()
		Create_NewCreationFile = ImGui.InputText("File", Create_NewCreationFile, 50)
		Create_NewLocationComment = ImGui.InputText("Comment", Create_NewLocationComment, 50)
		if ImGui.Button("Save This Location ") then
			if appendLocationToFile(Create_NewCreationFile, position["x"], position["y"], position["z"], position["w"], Create_NewLocationComment) then
				HUDMessage("Location saved!")
				statusMsg = "Location saved. Apply to test it."
				Create_NewLocationComment = ""
				MOD_SETTINGS.Filename = Create_NewCreationFile
				saveSettings()
			else
				statusMsg = "Error saving location :("
			end
		end

		if ImGui.Button("Apply/Test") then
			switchLocationsFile(Create_NewCreationFile)
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

		ImGui.Separator()
		ImGui.Text("* Created Maps are stored in:\n\t\'.../mods/Hidden Packages (Creation Mode)/Created Maps\'")
		if ImGui.Button("Close") then
			showCreationWindow = false
			reset()
		end

		ImGui.End()
	end

end)

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

function HUDMessage(msg)
	if os:clock() - HUDMessage_Last <= 1 then
		HUDMessage_Current = msg .. "\n" .. HUDMessage_Current
	else
		HUDMessage_Current = msg
	end

	GameHUD.ShowMessage(HUDMessage_Current)
	HUDMessage_Last = os:clock()
end

function removeAllMappins()
	for k,v in pairs(LOADED_PACKAGES) do
		if activeMappins[k] then
			unmarkPackage(k)
		end
	end
end

function unmarkPackage(i)
	if activeMappins[i] then
        Game.GetMappinSystem():UnregisterMappin(activeMappins[i])
      	activeMappins[i] = nil
      	return true
    end
    return false
end	

function readHPLocations(filename)
	if not LEX.fileExists(filename) then
		print("readHPLocations: file not found")
		return {}
	end
	
	local mapIdentifier = getMapProperty(filename, "identifier")

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

function appendLocationToFile(filename, x, y, z, w, comment)
	filename = "Created Maps/" .. filename

	if filename == "" then
		print("appendLocationToFile: not a valid filename")
		return false
	end

	local content = ""

	-- first check if file already exists and read it if so
	if LEX.fileExists(filename) then
		local file = io.open(filename,"r")
		content = file:read("*a")
		content = content .. "\n"
		file:close()
	else
		-- add IDENTIFIER and DISPLAY_NAME if file is new
		print("Creating new map file " .. filename)
		content = content .. "IDENTIFIER:created_" .. tostring(os.time()) .. "\n"
		content = content .. "DISPLAY_NAME:Creation Mode " .. datetimeNowString() .. "\n"
		content = content .. "\n"
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
	print("Appended to", filename, x, y, z, w, comment)
	return true
end

function checkIfPlayerNearAnyPackage()
	if not showCreationWindow then
		return -- basically disable the mod when window is not shown
	end

	distanceToNearestPackage = nil
	local playerPos = Game.GetPlayer():GetWorldPosition()
	for k,v in pairs(LOADED_PACKAGES) do

		local d = Vector4.Distance(playerPos, ToVector4{x=v["x"], y=v["y"], z=v["z"], w=v["w"]})

		if distanceToNearestPackage == nil or d < distanceToNearestPackage then
			distanceToNearestPackage = d
		end

		if d ~= nil and d <= MOD_SETTINGS.NearPackageRange then -- player is in spawning range of package

			if not activePackages[k] then -- package is not already spawned
				spawnPackage(k)
			end

			if (d <= 0.5) and (inVehicle() == false) then -- player is at package and is not in a vehicle, package should be collected?
				GameHUD.ShowWarning("Simulated Package Collection (Package " .. tostring(k) .. ")")
			end

		else -- player is outside of spawning range
			if activePackages[k] then -- out of range, despawn the package if its active
				despawnPackage(k)
			end
		end
	end
end

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

function switchLocationsFile(newFile)
	local path = "Created Maps/" .. newFile
	if LEX.fileExists(path) then

		reset()
		MOD_SETTINGS.Filename = newFile
		LOADED_PACKAGES = readHPLocations(path)
		checkIfPlayerNearAnyPackage()

		statusMsg = LEX.tableLen(LOADED_PACKAGES) .. " pkgs loaded from " .. newFile
		return true
	else
		statusMsg = "File " .. newFile .. " did not exist?"
		return false
	end
end

function datetimeNowString()
	return tostring(os.date("%Y-%m-%d %H:%M:%S"))
end

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

function reset()
	destroyAllPackageObjects()
	removeAllMappins()
	activePackages = {}
	activeMappins = {}
	lastCheck = 0
	return true
end

function destroyAllPackageObjects()
	for k,v in pairs(LOADED_PACKAGES) do
		if activePackages[k] then
			despawnPackage(k)
		end
	end
end

function getMapProperty(mapfile, what)
	local path = mapfile

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

function placeMapPin(x,y,z,w) -- from CET Snippets discord
	local mappinData = MappinData.new()
	mappinData.mappinType = TweakDBID.new('Mappins.DefaultStaticMappin')
	mappinData.variant = gamedataMappinVariant.CustomPositionVariant 
	-- more types: https://github.com/WolvenKit/CyberCAT/blob/main/CyberCAT.Core/Enums/Dumped%20Enums/gamedataMappinVariant.cs
	mappinData.visibleThroughWalls = true   

	return Game.GetMappinSystem():RegisterMappin(mappinData, ToVector4{x=x, y=y, z=z, w=w} ) -- returns ID
end