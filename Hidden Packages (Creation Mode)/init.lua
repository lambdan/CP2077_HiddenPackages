local MOD_METADATA = {
	title = "Hidden Packages (Creation Mode)",
	version = "1.0.0"
}

local GameUI = require('Modules/GameUI.lua')
local GameHUD = require("Modules/GameHUD.lua")
local LEX = require("Modules/LuaEX.lua")

local showCreationWindow = false
local isInGame = false

local statusMsg = "Hello, I am statusMsg."

local MAP_FOLDER = "Created Maps/"

local MOD_SETTINGS = {
	Filepath = ""
}

local activePackages = {}
local activeMappins = {}
local LOADED_PACKAGES = {}
local WORKING_MAP = nil

local PACKAGE_SELECTED = 0
local PACKAGE_LIST = {}

local MAPS_AVAILABLE_SELECTED = 0
local MAPS_AVAILABLE = {}
local LAST_MAPFILE_SCAN = 0
local DELETE_WARNING = 0

local NewMap_Filename = ""
local NewMap_DisplayName = ""
local Create_NewLocationComment = ""

local PACKAGE_PROP = "base/quest/main_quests/prologue/q005/afterlife/entities/q005_hologram_cube.ent"
local PACKAGE_PROP_Z_BOOST = 0.25

local lastCheck = 0
local checkThrottle = 1
local distanceToNearestPackage = nil
local nearestPackage = nil

local inGame = false
local isPaused = false


registerHotkey("hp_toggle_create_window", "Toggle creation window", function()
	showCreationWindow = not showCreationWindow
	if showCreationWindow == false then
		reset()
	end
end)

registerForEvent('onInit', function()
	loadSettings()
	if LEX.fileExists(MOD_SETTINGS.Filepath) then
		WORKING_MAP = MOD_SETTINGS.Filepath
		switchLocationsFile(MOD_SETTINGS.Filepath)
		statusMsg = "Loaded last used map: " .. MOD_SETTINGS.Filepath
	else
		statusMsg = "Create or load a map to get started"
	end
end)

registerForEvent('onShutdown', function() -- mod reload, game shutdown etc
    reset()
end)

registerForEvent('onDraw', function()
	if showCreationWindow then
		checkIfPlayerNearAnyPackage()

		ImGui.Begin("Hidden Packages (Creation Mode)")
		ImGui.Text(statusMsg) -- status message
		ImGui.Separator()
		
		if WORKING_MAP == nil then
			ImGui.Text("Create New Map")
			ImGui.Indent()
			NewMap_Filename = ImGui.InputText("File Name", NewMap_Filename, 50)
			if ImGui.IsItemHovered() then
				ImGui.SetTooltip("File name of your map. \'.map\' extension will be added automatically if necessary.")
			end

			NewMap_DisplayName = ImGui.InputText("Name", NewMap_DisplayName, 50)
			if ImGui.IsItemHovered() then
				ImGui.SetTooltip("Name of your map. This is shown in the settings menu when players pick your map.\nCan be changed later by editting the .map file in a text editor.")
			end

			if ImGui.Button("Create Map") then
				local new_map = createNewMap(NewMap_Filename, NewMap_DisplayName)
				if new_map then
					statusMsg = "Created new map"
					
					MOD_SETTINGS.Filepath = new_map
					saveSettings()

					WORKING_MAP = new_map
					switchLocationsFile(WORKING_MAP)

					NewMap_Filename = ""
					NewMap_DisplayName = ""
				else
					statusMsg = "Error creating new map"
				end
			end
			ImGui.Unindent()

			if os.clock() > (LAST_MAPFILE_SCAN + 5) then -- so we dont spam a directory scan
				MAPS_AVAILABLE = listFilesInFolder(MAP_FOLDER, ".map")
				LAST_MAPFILE_SCAN = os.clock()
			end

			ImGui.Separator()
			ImGui.Text("Available Maps")
			ImGui.SameLine(ImGui.GetWindowWidth()-40)
			ImGui.Text("(" .. string.format("%.1f", ((LAST_MAPFILE_SCAN+5) - os.clock())) .. ")")
			ImGui.Indent()
			if LEX.tableLen(MAPS_AVAILABLE) > 0 then
				MAPS_AVAILABLE_SELECTED = ImGui.Combo(".map files", MAPS_AVAILABLE_SELECTED, MAPS_AVAILABLE, LEX.tableLen(MAPS_AVAILABLE), 5)
				if ImGui.Button("Load .map") then
					local path = MAP_FOLDER .. MAPS_AVAILABLE[MAPS_AVAILABLE_SELECTED+1]
					if switchLocationsFile(path) then
						statusMsg = "Loaded map " .. MAPS_AVAILABLE[MAPS_AVAILABLE_SELECTED+1]
						WORKING_MAP = path					
						MOD_SETTINGS.Filepath = WORKING_MAP
						saveSettings()
					end
				end
			else
				ImGui.Text("No .map\'s found")
			end
			ImGui.Unindent()

			ImGui.Separator()

			ImGui.Text("* Maps are stored in:\n  '.../mods/Hidden Packages (Creation Mode)/Created Maps\'")
			ImGui.Text("* They must have the .map file extension to be detected here")
			ImGui.Text("* To play them, copy the .map to the\n  regular Hidden Packages mods' Maps folder")

		else

			local position = Game.GetPlayer():GetWorldPosition()
			ImGui.Text("Player Position:")
			ImGui.Indent()
			ImGui.Text("X: " .. string.format("%.3f", position["x"]) .. "\tY: " .. string.format("%.3f", position["y"]) .. "\tZ: " .. string.format("%.3f", position["z"]) .. "\tW: " .. string.format("%.3f", position["w"]))
			if LEX.tableLen(LOADED_PACKAGES) > 0 then
				ImGui.Text("Nearest package: " .. string.format("%.1f", distanceToNearestPackage) .. " M away (package " .. tostring(nearestPackage) .. ")")
			end
			ImGui.Unindent()

			ImGui.Separator()
			ImGui.Text("Add package:")
			ImGui.Indent()
			Create_NewLocationComment = ImGui.InputText("Comment", Create_NewLocationComment, 50)

			if ImGui.Button("Add district to comment") then
				if Create_NewLocationComment ~= getLocationName() then
					if Create_NewLocationComment == "" then
						Create_NewLocationComment = getLocationName()
					else
						Create_NewLocationComment = Create_NewLocationComment .. " (" .. getLocationName() .. ")"
					end
				end
			end

			if ImGui.Button("+ Save") then
				if appendLocationToFile(WORKING_MAP, position["x"], position["y"], position["z"], position["w"], Create_NewLocationComment) then
					statusMsg = "Location saved"
					Create_NewLocationComment = ""
					MOD_SETTINGS.Filepath = WORKING_MAP
					saveSettings()
					switchLocationsFile(WORKING_MAP)
					Game.GetAudioSystem():Play('ui_menu_item_consumable_generic')
				else
					statusMsg = "Error saving location :("
				end
			end
			ImGui.Unindent()
			
			ImGui.Separator()
			ImGui.Text("Packages:")
			ImGui.Indent()
			if LEX.tableLen(LOADED_PACKAGES) == 0 then
				ImGui.Text("No packages placed")
			else
				PACKAGE_SELECTED = ImGui.Combo("Packages", PACKAGE_SELECTED, PACKAGE_LIST, LEX.tableLen(PACKAGE_LIST), 5)
				if ImGui.Button("Teleport") then
					local pkg = LOADED_PACKAGES[PACKAGE_SELECTED+1] -- +1 because imgui list index starts at 0, lua tables start at 1
					print("HP(CM): Teleport to:", pkg["x"], pkg["y"], pkg["z"])
					Game.TeleportPlayerToPosition(pkg["x"], pkg["y"], pkg["z"])
				end
				ImGui.SameLine()

				if ImGui.Button("Mark/Unmark on map") then
					if activeMappins[PACKAGE_SELECTED+1] then
						unmarkPackage(PACKAGE_SELECTED+1)
					else
						markPackage(PACKAGE_SELECTED+1)
					end

				end

				
				ImGui.PushStyleColor(ImGuiCol.Button, 0x882020ff)
				ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0xff0000ff)
				if ImGui.Button("Delete") then
					if DELETE_WARNING < os.clock() then
						DELETE_WARNING = os.clock() + 5
					elseif DELETE_WARNING > os.clock() then
						local pkg = LOADED_PACKAGES[PACKAGE_SELECTED+1]
						if deleteLocation(pkg["filepath"], pkg["line"]) then
							-- reload the file again
							print("HP(CM): deleted location")
							switchLocationsFile(pkg["filepath"])
						end
						DELETE_WARNING = 0
					end
				end
				ImGui.PopStyleColor(2)

				if DELETE_WARNING > os.clock() then
					ImGui.SameLine()
					ImGui.Text("Click again to confirm or wait " .. string.format("%.1f", (DELETE_WARNING - os.clock())) .. " to abort...")
				end

			end
			ImGui.Unindent()

			ImGui.Separator()
			ImGui.Text("Map Pins:")
			ImGui.Indent()
			if ImGui.Button("Mark all packages") then
				removeAllMappins()
				for k,v in pairs(LOADED_PACKAGES) do
					markPackage(k)
				end
			end
			ImGui.SameLine()
			if ImGui.Button("Remove all") then
				removeAllMappins()
			end
			ImGui.Unindent()

			ImGui.Separator()
			ImGui.Text("Current Map: " .. WORKING_MAP .. " (" .. tostring(LEX.tableLen(LOADED_PACKAGES)) .. " packages)")
			ImGui.Indent()
			if ImGui.Button("Unload Map") then
				reset()
				MOD_SETTINGS.Filepath = ""
				saveSettings()
				LOADED_PACKAGES = {}
				WORKING_MAP = nil
				statusMsg = "Create or load a map to get started!"
			end
			ImGui.Unindent()

		end
		
		ImGui.Separator()
		if ImGui.Button("Where Am I?") then
			statusMsg = "You are here: " .. getLocationName()
			--GameHUD.ShowWarning(statusMsg)
			GameHUD.ShowMessage(statusMsg)
		end		
		ImGui.SameLine()
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

function readHPLocations(filepath)
	if not LEX.fileExists(filepath) then
		return {}
	end
	
	local mapIdentifier = getMapProperty(filepath, "identifier")

	local lines = {}
	for line in io.lines(filepath) do
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
		hp["line"] = LEX.trim(v)
		hp["filepath"] = filepath
		table.insert(packages, hp)
	end
	return packages
end

function appendLocationToFile(filepath, x, y, z, w, comment)
	if filepath == "" then
		print("HP(CM): not a valid path")
		return false
	end

	local content = ""

	-- first check if file already exists and read it if so
	if LEX.fileExists(filepath) then
		local file = io.open(filepath,"r")
		content = file:read("*a")
		content = content .. "\n"
		file:close()
	else
		-- add IDENTIFIER and DISPLAY_NAME if file is new
		print("HP(CM): Creating new map file " .. filepath)
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

	local file = io.open(filepath, "w")
	file:write(content)
	file:close()
	print("HP(CM): Appended to", filepath, x, y, z, w, comment)
	return true
end

function checkIfPlayerNearAnyPackage()
	if not showCreationWindow then
		return -- basically disable the mod when window is not shown
	end

	distanceToNearestPackage = nil
	nearestPackage = nil
	local playerPos = Game.GetPlayer():GetWorldPosition()
	for k,v in pairs(LOADED_PACKAGES) do

		local d = Vector4.Distance(playerPos, ToVector4{x=v["x"], y=v["y"], z=v["z"], w=v["w"]})

		if distanceToNearestPackage == nil or d < distanceToNearestPackage then
			distanceToNearestPackage = d
			nearestPackage = k
		end

		if d ~= nil and d <= 100 then -- player is in spawning range of package

			if not activePackages[k] then -- package is not already spawned
				spawnPackage(k)
			end

			if (d <= 0.5) and (inVehicle() == false) then -- player is at package and is not in a vehicle, package should be collected?
				--GameHUD.ShowWarning("Touched package " .. tostring(k))
				GameHUD.ShowMessage("Touched package " .. tostring(k))
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

function switchLocationsFile(path)
	if LEX.fileExists(path) then

		reset()
		MOD_SETTINGS.Filepath = path
		LOADED_PACKAGES = readHPLocations(path)

		PACKAGE_LIST = {}
		for k,v in ipairs(LOADED_PACKAGES) do
			table.insert(PACKAGE_LIST, tostring(k) .. ": " .. v["line"])
		end
		PACKAGE_SELECTED = LEX.tableLen(PACKAGE_LIST) - 1 -- -1 because imgui starts index at 0...

		checkIfPlayerNearAnyPackage()

		WORKING_MAP = path
		return true
	else
		statusMsg = path .. " did not exist?"
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

function getLocationName()
	-- this but we dont care about gangs: https://github.com/psiberx/cp2077-cet-kit/blob/main/mods/GameUI-WhereAmI/init.lua
	-- <3 psiberx
	local preventionSystem = Game.GetScriptableSystemsContainer():Get('PreventionSystem')
	local districtManager = preventionSystem.districtManager

	if districtManager and districtManager:GetCurrentDistrict() then
		local t = {}
		local district_id = districtManager:GetCurrentDistrict():GetDistrictID()
		local tweakDb = GetSingleton('gamedataTweakDBInterface')
		local districtRecord = tweakDb:GetDistrictRecord(district_id)

		repeat
			local districtLabel = Game.GetLocalizedText(districtRecord:LocalizedName())
			table.insert(t, 1, districtLabel)
			districtRecord = districtRecord:ParentDistrict()
		until districtRecord == nil
		
		return table.concat(t, '/')
	end
	return "?"
end

function deleteLocation(filepath, line_to_delete)
	if not LEX.fileExists(filepath) then
		print("HP(CM) delete failed because file doesnt exist?")
		return false
	end

	local found_match = false

	local lines = {}
	for line in io.lines(filepath) do
		if LEX.trim(line) ~= LEX.trim(line_to_delete) then 
			-- only insert lines that arent the line we are looking for
			table.insert(lines, line)
		else
			found_match = true -- we found it 
		end
	end

	if found_match then
		-- now save the lines to the same file again
		local file = io.open(filepath, "w")
		file:write(table.concat(lines, "\n"))
		file:close()

		Game.GetAudioSystem():Play('g_sc_bd_rewind_restart')
		statusMsg = "Deleted location"
		return true
	else
		-- we didnt find it so theres nothing to do
		return false
	end

end

function createNewMap(filename, displayname)
	if filename == "" then
		print("HP(CM): no filename provided!")
		return false
	end

	local path = MAP_FOLDER .. filename

	if not LEX.stringEnds(path, ".map") then
		path = path .. ".map"
	end

	if LEX.fileExists(path) then
		print("HP(CM): cannot create new map because file already exists!")
		return false
	end

	local identifier = "CreationMode" .. tostring(math.random(0,1000000))

	if displayname == "" then
		print("HP(CM): no name provided, using random identifier instead")
		displayname = identifier
	end

	local content = {}
	-- also add some help lines
	table.insert(content, "# DISPLAY_NAME can safely be changed. It is shown in the settings menu when picking your map.")
	table.insert(content, "DISPLAY_NAME:" .. displayname)
	table.insert(content, "# IDENTIFIER however should not be changed if anyone has already played your .map because it is used to track internally what packages have been collected.")
	table.insert(content, "IDENTIFIER:" .. identifier)

	local file = io.open(path, "w")
	file:write(table.concat(content, "\n"))
	file:close()

	-- verify file now exists
	if LEX.fileExists(path) then
		print("HP(CM): Created new map file:", path)
		return path
	else
		print("HP(CM): something went wrong with saving the map")
		return false
	end
	return false
end

function listFilesInFolder(folder, ext)
	local files = {}
	for k,v in pairs(dir(folder)) do
		for a,b in pairs(v) do
			if a == "name" then
				if LEX.stringEnds(b, ext) then
					table.insert(files, b)
				end
			end
		end
	end
	return files
end