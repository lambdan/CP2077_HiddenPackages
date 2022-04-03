local HiddenPackagesMetadata = {
	title = "Hidden Packages",
	version = "2.4.1"
}

local GameSession = require("Modules/GameSession.lua")
local GameHUD = require("Modules/GameHUD.lua")
local GameUI = require("Modules/GameUI.lua")
local LEX = require("Modules/LuaEX.lua")

local DEBUG_MODE = false -- set to true to be more verbose and log things

local MAPS_FOLDER = "Maps/" -- should end with a /
local MAP_DEFAULT = "Maps/packages1.map" -- full path to default map
local SONAR_DEFAULT_SOUND = "ui_elevator_select"

local SONAR_SOUNDS = {
	"ui_character_customization_navigate",
	"ui_elevator_select",
	"ui_focus_mode_zooming_in_step_change",
	"ui_gui_tab_change",
	"ui_hacking_access_granted",
	"ui_hacking_access_panel_close",
	"ui_hacking_hover",
	"ui_hacking_press",
	"ui_hacking_press_fail",
	"ui_hacking_qh_hover",
	"ui_menu_attributes_fail",
	"ui_menu_hover",
	"ui_menu_item_bought",
	"ui_menu_map_pin_created",
	"ui_menu_mouse_click",
	"ui_scanning_Done",
	"ui_scanning_Stop"
}

local SETTINGS_FILE = "SETTINGS.v2.4.1.json"
local MOD_SETTINGS = { -- saved in SETTINGS_FILE (separate from game save)
	SonarEnabled = false,
	SonarRange = 125,
	SonarSound = SONAR_DEFAULT_SOUND,
	SonarMinimumDelay = 0.0,
	MoneyPerPackage = 1000,
	StreetcredPerPackage = 100,
	ExpPerPackage = 100,
	PackageMultiply = false,
	MapPath = MAP_DEFAULT,
	ScannerEnabled = false,
	StickyMarkers = 0,
	ScannerImmersive = true,
	RandomRewardItemList = false
}

local SESSION_DATA = { -- will persist with game saves
	collectedPackageIDs = {}
}

local LOADED_MAP = nil

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
local modActive = true
local NEED_TO_REFRESH = false

local nextCheck = 0

local SONAR_NEXT = 0
local SONAR_LAST = 0
local SCANNER_MARKERS = {}
local SCANNER_OPENED = nil
local SCANNER_NEAREST_PKG = nil
local SCANNER_SOUND_TICK = 0.0

local RANDOM_ITEMS_POOL = {}
local ITEM_LIST_FOLDER = "ItemLists/" -- end with a /

registerHotkey("hp_nearest_pkg", "Mark nearest package", function()
	markNearestPackage()
end)

registerHotkey("hp_whereami", "Where Am I?", function()
	local pos = Game.GetPlayer():GetWorldPosition()
	showCustomShardPopup("Where Am I?", "You are standing here:\nX:  " .. string.format("%.3f",pos["x"]) .. "\nY:  " .. string.format("%.3f",pos["y"]) .. "\nZ:  " .. string.format("%.3f",pos["z"]) .. "\nW:  " .. pos["w"])
end)

registerHotkey("hp_toggle_mod", "Sonar/Scanner Active Quick Toggle", function() 
	modActive = not modActive
	if modActive then
		HUDMessage("Sonar/Scanner enabled")
	else
		HUDMessage("Sonar/Scanner disabled")
	end
end)

registerForEvent('onShutdown', function() -- mod reload, game shutdown etc
    GameSession.TrySave()
    reset()
end)

registerForEvent('onInit', function()
	loadSettings()

	LOADED_MAP = readMap(MOD_SETTINGS.MapPath)

	-- scan Maps folder and generate table suitable for nativeSettings
	local mapsPaths = {[1] = false}
	local nsMapsDisplayNames = {[1] = "None"}
	local nsDefaultMap = 1
	local nsCurrentMap = 1
	for k,v in pairs( listFilesInFolder(MAPS_FOLDER, ".map") ) do
		local map_path = MAPS_FOLDER .. v
		local read_map = readMap(map_path)

		if read_map ~= nil then
			local i = LEX.tableLen(mapsPaths) + 1
			nsMapsDisplayNames[i] = read_map["display_name"] .. " (" .. read_map["amount"] .. " pkgs)"
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

		-- maps

		nativeSettings.addSubcategory("/Hidden Packages/Maps", "Maps")

		nativeSettings.addSelectorString("/Hidden Packages/Maps", "Map", "Maps are stored in \'.../mods/Hidden Packages/Maps\''. If set to None the mod is disabled.", nsMapsDisplayNames, nsCurrentMap, nsDefaultMap, function(value)
			MOD_SETTINGS.MapPath = mapsPaths[value]
			saveSettings()
			NEED_TO_REFRESH = true
		end)

		-- sonar

		nativeSettings.addSubcategory("/Hidden Packages/Sonar", "Sonar")

		nativeSettings.addSwitch("/Hidden Packages/Sonar", "Sonar", "Play a sound when near a package in increasing frequency the closer you get to it", MOD_SETTINGS.SonarEnabled, false, function(state)
			MOD_SETTINGS.SonarEnabled = state
			saveSettings()
		end)

		nativeSettings.addRangeInt("/Hidden Packages/Sonar", "Range", "Sonar starts working when this close to a package", 50, 250, 25, MOD_SETTINGS.SonarRange, 125, function(value)
			MOD_SETTINGS.SonarRange = value
			saveSettings()
		end)

		-- cant be dragged by mouse?
		nativeSettings.addRangeFloat("/Hidden Packages/Sonar", "Minimum Interval", "Sonar will wait atleast this long before playing a sound again. Value is in seconds.", 0.0, 10.0, 0.5, "%.1f", MOD_SETTINGS.SonarMinimumDelay, 0.0, function(value)
 			MOD_SETTINGS.SonarMinimumDelay = value
 			saveSettings()
 		end)
		
		local sonarSoundsCurrent = 1
		local sonarSoundsDefault = 1
		local sonarDisplaySounds = {}
		for k,v in pairs(SONAR_SOUNDS) do
			sonarDisplaySounds[k] = v
			if v == MOD_SETTINGS.SonarSound then
				sonarSoundsCurrent = k
			end
			if v == SONAR_DEFAULT_SOUND then
				sonarSoundsDefault = k
			end
		end

		nativeSettings.addSelectorString("/Hidden Packages/Sonar", "Sound Effect", "Sonar ping sound (Some sounds will not be heard while in this menu and/or only works in-game)", sonarDisplaySounds, sonarSoundsCurrent, sonarSoundsDefault, function(value)
			MOD_SETTINGS.SonarSound = sonarDisplaySounds[value]
			saveSettings()
			Game.GetAudioSystem():Play(MOD_SETTINGS.SonarSound)
		end)

		-- disabled because not all sounds worked in the menu
		--nativeSettings.addButton("/Hidden Packages/Sonar", "Test Sound", "Play the sound effect to see if you like it. Some sounds only works if you're in-game.", "Test", 45, function()
 		--	Game.GetAudioSystem():Play(MOD_SETTINGS.SonarSound)
 		--end)

 		-- scanner

		nativeSettings.addSubcategory("/Hidden Packages/Scanner", "Scanner Marker")

		nativeSettings.addSwitch("/Hidden Packages/Scanner", "Scanner Marker", "Nearest package will be marked by using the scanner", MOD_SETTINGS.ScannerEnabled, false, function(state)
			MOD_SETTINGS.ScannerEnabled = state
			saveSettings()
		end)

		nativeSettings.addSwitch("/Hidden Packages/Scanner", "Immersive", "Make it more Immersive™", MOD_SETTINGS.ScannerImmersive, true, function(state)
			MOD_SETTINGS.ScannerImmersive = state
			saveSettings()
		end)

		nativeSettings.addRangeInt("/Hidden Packages/Scanner", "Sticky Markers", "Keep up to this many packages marked. Markers will disappear after closing the scanner if set to 0.", 0, 10, 1, MOD_SETTINGS.StickyMarkers, 0, function(value)
			MOD_SETTINGS.StickyMarkers = value
			saveSettings()
		end)



 		-- rewards

		nativeSettings.addSubcategory("/Hidden Packages/Rewards", "Rewards")

		nativeSettings.addRangeInt("/Hidden Packages/Rewards", "Money", "Collecting a package rewards you this much money", 0, 5000, 100, MOD_SETTINGS.MoneyPerPackage, 1000, function(value)
			MOD_SETTINGS.MoneyPerPackage = value
			saveSettings()
		end)

		nativeSettings.addRangeInt("/Hidden Packages/Rewards", "XP", "Collecting a package rewards you this much XP", 0, 300, 10, MOD_SETTINGS.ExpPerPackage, 100, function(value)
			MOD_SETTINGS.ExpPerPackage = value
			saveSettings()
		end)

		nativeSettings.addRangeInt("/Hidden Packages/Rewards", "Street Cred", "Collecting a package rewards you this much Street Cred", 0, 300, 10, MOD_SETTINGS.StreetcredPerPackage, 100, function(value)
			MOD_SETTINGS.StreetcredPerPackage = value
			saveSettings()
		end)

		nativeSettings.addSwitch("/Hidden Packages/Rewards", "Multiply by Packages Collected", "Multiply rewards by how many packages you have collected", MOD_SETTINGS.PackageMultiply, false, function(state)
			MOD_SETTINGS.PackageMultiply = state
			saveSettings()
		end)

		-- scan ItemList folder and generate table suitable for nativeSettings
		local itemlistPaths = {[1] = false}
		local itemlistDisplayNames = {[1] = "Disabled"}
		local nsItemListDefault = 1
		local nsItemListCurrent = 1
		for k,v in pairs( listFilesInFolder(ITEM_LIST_FOLDER, ".list") ) do
			local itemlist_path = ITEM_LIST_FOLDER .. v

			-- read how many lines to append it to display name
			local file = io.open(itemlist_path, "r")
			local lines = file:lines()
			local c = 0
			for line in lines do
				if (line ~= nil) and (line ~= "") and not (LEX.stringStarts(line, "#")) and not (LEX.stringStarts(line, "//")) then
					c = c + 1
				end
			end
			file:close()

			-- append count to filename
			local i = LEX.tableLen(itemlistPaths) + 1
			itemlistDisplayNames[i] = v:gsub(".list", "") .. " (" .. tostring(c) .. " items)"
			itemlistPaths[i] = itemlist_path
			if itemlist_path == MOD_SETTINGS.RandomRewardItemList then
				nsItemListCurrent = i
			end
		end
		nativeSettings.addSelectorString("/Hidden Packages/Rewards", "Random Item", "Get a random item from an ItemList. ItemLists are stored in \'.../mods/Hidden Packages/ItemLists\'.", itemlistDisplayNames, nsItemListCurrent, nsItemListDefault, function(value)
			MOD_SETTINGS.RandomRewardItemList = itemlistPaths[value]
			RANDOM_ITEMS_POOL = {}
			saveSettings()
			NEED_TO_REFRESH = true
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
        RESET_BUTTON_PRESSED = 0
        
        if NEED_TO_REFRESH then
        	switchLocationsFile(MOD_SETTINGS.MapPath)
        	NEED_TO_REFRESH = false
        end

        checkIfPlayerNearAnyPackage() -- otherwise if you made a save near a package and just stand still it wont spawn until you move
        readItemList(MOD_SETTINGS.RandomRewardItemList) -- need to read it here in case player just started the game without changing any setting
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
		RESET_BUTTON_PRESSED = 0

        if NEED_TO_REFRESH then
        	switchLocationsFile(MOD_SETTINGS.MapPath)
        	readItemList(MOD_SETTINGS.RandomRewardItemList)
        	NEED_TO_REFRESH = false
        end

        -- have to do this here in case user switched settings
		while LEX.tableLen(SCANNER_MARKERS) > MOD_SETTINGS.StickyMarkers do
			-- remove oldest marker (Lua starts at 1)
			unmarkPackage(SCANNER_MARKERS[1])
			table.remove(SCANNER_MARKERS, 1)
		end


	end)

	Observe('PlayerPuppet', 'OnAction', function(action)
		checkIfPlayerNearAnyPackage()
	end)

	GameUI.Listen('ScannerOpen', function()
		
		if MOD_SETTINGS.ScannerEnabled and modActive then
			SCANNER_OPENED = os.clock()
			SCANNER_NEAREST_PKG = findNearestPackageWithinRange(0)
		end

	end)

	GameUI.Listen('ScannerClose', function()
		
		if MOD_SETTINGS.ScannerEnabled then
			SCANNER_OPENED = nil
			SCANNER_NEAREST_PKG = nil
			SCANNER_SOUND_TICK = 0.0

			if MOD_SETTINGS.StickyMarkers == 0 then
				for k,v in pairs(SCANNER_MARKERS) do
					unmarkPackage(v)
					SCANNER_MARKERS[k] = nil
				end
			end
		end

	end)

	GameSession.TryLoad()

end)

registerForEvent('onUpdate', function(delta)
    if LOADED_MAP ~= nil and not isPaused and isInGame and modActive then

    	if MOD_SETTINGS.SonarEnabled then
    		sonar()
    	end

    	if MOD_SETTINGS.ScannerEnabled and SCANNER_OPENED then
    		scanner()
    	end
    end

end)

function spawnPackage(i)
	if activePackages[i] then
		return false
	end

	local pkg = LOADED_MAP.packages[i]
	local vec = ToVector4{x=pkg.x, y=pkg.y, z=pkg.z + PACKAGE_PROP_Z_BOOST, w=pkg.w}
	local entity = spawnEntity(PACKAGE_PROP, vec)
	
	if entity then -- it got spawned
		activePackages[i] = entity
		return entity
	end
	return false
end

function spawnEntity(ent, vec)
    local transform = Game.GetPlayer():GetWorldTransform()
    transform:SetPosition(vec)
    transform:SetOrientation( EulerAngles.new(0,0,0):ToQuat() ) -- package angle/rotation always 0
    return WorldFunctionalTests.SpawnEntity(ent, transform, '') -- returns ID
end

function despawnPackage(i) -- i = package index
	if activePackages[i] then
		destroyEntity(activePackages[i])
		activePackages[i] = nil
		return true
	end
    return false
end

function destroyEntity(e)
	if Game.FindEntityByID(e) ~= nil then
        Game.FindEntityByID(e):GetEntity():Destroy()
        return true
    end
    return false
end

function collectHP(packageIndex)
	local pkg = LOADED_MAP.packages[packageIndex]

	if not LEX.tableHasValue(SESSION_DATA.collectedPackageIDs, pkg["identifier"]) then
		table.insert(SESSION_DATA.collectedPackageIDs, pkg["identifier"])
	end
	
	unmarkPackage(packageIndex)
	despawnPackage(packageIndex)

	local collected = countCollected(LOADED_MAP.filepath)
	
    if collected == LOADED_MAP.amount then
    	-- got all packages
    	Game.GetAudioSystem():Play('ui_jingle_quest_success')
    	HUDMessage("ALL HIDDEN PACKAGES COLLECTED!")
    	--showCustomShardPopup("All Hidden Packages collected!", "You have collected all " .. tostring(LOADED_MAP["amount"]) .. " packages from the map \"" .. LOADED_MAP["display_name"] .. "\"!")
    else
    	-- regular package pickup
    	Game.GetAudioSystem():Play('ui_loot_rarity_legendary')
    	local msg = "Hidden Package " .. tostring(collected) .. " of " .. tostring(LOADED_MAP.amount)
    	HUDMessage(msg)
    end	

	local multiplier = 1
	if MOD_SETTINGS.PackageMultiply then
		multiplier = collected
	end

	local money_reward = MOD_SETTINGS.MoneyPerPackage * multiplier
	if money_reward	> 0 then
		Game.AddToInventory("Items.money", money_reward)
	end

	local sc_reward = MOD_SETTINGS.StreetcredPerPackage * multiplier
	if sc_reward > 0 then
		Game.AddExp("StreetCred", sc_reward)
	end

	local xp_reward = MOD_SETTINGS.ExpPerPackage * multiplier
	if xp_reward > 0 then
		Game.AddExp("Level", xp_reward)
	end

	if MOD_SETTINGS.RandomRewardItemList then -- will be false if Disabled
		math.randomseed(os.time())
		local rng = RANDOM_ITEMS_POOL[math.random(1,#RANDOM_ITEMS_POOL)]
		local item = rng
		local amount = 1
		
		if string.find(rng, ",") then -- custom amount of item specified in ItemList
			item, amount = rng:match("([^,]+),([^,]+)") -- https://stackoverflow.com/a/19269176
			amount = tonumber(amount)
		end

		Game.AddToInventory(item, amount)
		if amount > 1 then
			HUDMessage("Got Item: " .. item .. " (" .. tostring(amount) .. ")")
		else
			HUDMessage("Got Item: " .. item)
		end
	end

end

function reset()
	destroyAllPackageObjects()
	removeAllMappins()
	activePackages = {}
	activeMappins = {}
	nextCheck = 0
	debugMsg("reset() OK")
	return true
end

function destroyAllPackageObjects()
	if LOADED_MAP == nil then
		return
	end

	for k,v in pairs(LOADED_MAP.packages) do
		despawnPackage(k)
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

function placeMapPin(x,y,z,w) -- from CET Snippets discord
	local mappinData = MappinData.new()
	mappinData.mappinType = TweakDBID.new('Mappins.DefaultStaticMappin')
	mappinData.variant = gamedataMappinVariant.CustomPositionVariant 
	-- more types: https://github.com/WolvenKit/CyberCAT/blob/main/CyberCAT.Core/Enums/Dumped%20Enums/gamedataMappinVariant.cs
	mappinData.visibleThroughWalls = true   

	return Game.GetMappinSystem():RegisterMappin(mappinData, ToVector4{x=x, y=y, z=z, w=w} ) -- returns ID
end

function markPackage(i) -- i = package index
	if activeMappins[i] then
		return false
	end

	local pkg = LOADED_MAP.packages[i]
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
	if LOADED_MAP == nil then
		return
	end
	for k,v in pairs(LOADED_MAP.packages) do
		unmarkPackage(k)
	end
end

function findPackagesWithinRange(range) -- 0 = any range
	if not isInGame	or LOADED_MAP == nil then
		return false
	end

	local pkgs = {}
	local distances = {}
	local playerPos = Game.GetPlayer():GetWorldPosition()

	for k,v in pairs(LOADED_MAP.packages) do
		if (LEX.tableHasValue(SESSION_DATA.collectedPackageIDs, v["identifier"]) == false) then -- package not collected
			if range == 0 or math.abs(playerPos["x"] - v["x"]) <= range then
				if range == 0 or math.abs(playerPos["y"] - v["y"]) <= range then
					local d = Vector4.Distance(playerPos, ToVector4{x=v["x"], y=v["y"], z=v["z"], w=v["w"]})
					if d <= range then
						table.insert(pkgs,k)
						table.insert(distances,d)
					end
				end
			end
		end
	end

	if LEX.tableLen(pkgs) == 0 then
		return false -- no packages in range
	else
		-- TODO sort them by closest to furthest before we return them (use the distances table!)
		return pkgs
	end
end



function findNearestPackageWithinRange(range) -- 0 = any range
	if not isInGame	or LOADED_MAP == nil then
		return false
	end

	local nearest = nil
	local nearestPackage = false
	local playerPos = Game.GetPlayer():GetWorldPosition()

	for k,v in pairs(LOADED_MAP.packages) do
		if (LEX.tableHasValue(SESSION_DATA.collectedPackageIDs, v["identifier"]) == false) then -- package not collected
			if range == 0 or math.abs(playerPos["x"] - v["x"]) <= range then
				if range == 0 or math.abs(playerPos["y"] - v["y"]) <= range then
					local d = Vector4.Distance(playerPos, ToVector4{x=v["x"], y=v["y"], z=v["z"], w=v["w"]})
					if nearest == nil or d < nearest then
						nearest = d
						nearestPackage = k
					end
				end
			end
		end
	end

	return nearestPackage -- returns package index or false
end

function markNearestPackage()
	local NP = findNearestPackageWithinRange(0)
	if NP then
		removeAllMappins()
		markPackage(NP)
		HUDMessage("Nearest Package Marked (" .. string.format("%.f", distanceToPackage(NP)) .. "M away)")
		Game.GetAudioSystem():Play('ui_jingle_car_call')
		return NP
	end
	HUDMessage("No packages available")
	return false
end

function switchLocationsFile(path)
	if path == false then -- false == mod disabled
		reset()
		LOADED_MAP = nil
		return true
	end

	if LEX.fileExists(path) then
		reset()
		LOADED_MAP = readMap(path)
		checkIfPlayerNearAnyPackage()
		return true
	end

	return false
end

function checkIfPlayerNearAnyPackage()
	if (LOADED_MAP == nil) or (isPaused == true) or (isInGame == false) or (os.clock() < nextCheck) then
		-- no map is loaded/game is paused/game has not loaded/not time to check yet: return and do nothing
		return
	end

	local nextDelay = 1.0 -- default check interval
	local playerPos = Game.GetPlayer():GetWorldPosition() -- get player coordinates

	for index,pkg in pairs(LOADED_MAP.packages) do -- iterate over packages in loaded map
		if not (LEX.tableHasValue(SESSION_DATA.collectedPackageIDs, pkg.identifier)) and (math.abs(playerPos.x - pkg.x) <= 100) and (math.abs(playerPos.y - pkg.y) <= 100) then
			-- package is not collected AND is in the neighborhood 
			if not activePackages[index] then -- package is not spawned
				spawnPackage(index)
			end

			if not inVehicle() then -- player not in vehicle = package can be collected
				-- finally calculate exact distance
				local d = Vector4.Distance(playerPos, ToVector4{x=pkg.x, y=pkg.y, z=pkg.z, w=pkg.w})

				if (d <= 0.5) then -- player is practically at the package = collect it
					collectHP(index) 
				elseif (d <= 10) then -- player is very close to package = check frequently
					nextDelay = 0.1 
				end
			end

		elseif activePackages[index] then -- package is spawned but we're not in its neighborhood or its been collected = despawn it
			despawnPackage(index)
		end
	end

	nextCheck = os.clock() + nextDelay
end


function debugMsg(msg)
	if not DEBUG_MODE then
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

function countCollected(MapPath)
	-- cant just check length of collectedPackageIDs as it may include packages from other location files
	local map
	if MapPath ~= LOADED_MAP.filepath then
		map = readMap(MapPath)
	else
		-- no nead to read the map file again if its already loaded
		map = LOADED_MAP
	end

	local c = 0
	for k,v in pairs(map.packages) do
		if LEX.tableHasValue(SESSION_DATA.collectedPackageIDs, v["identifier"]) then
			c = c + 1
		end
	end
	return c
end

function distanceToPackage(i)
	local pkg = LOADED_MAP.packages[i]
	return Vector4.Distance(Game.GetPlayer():GetWorldPosition(), ToVector4{x=pkg["x"], y=pkg["y"], z=pkg["z"], w=pkg["w"]})
end



function saveSettings()
	local file = io.open(SETTINGS_FILE, "w")
	local j = json.encode(MOD_SETTINGS)
	file:write(j)
	file:close()
end

function loadSettings()
	if not LEX.fileExists(SETTINGS_FILE) then
		return false
	end

	local file = io.open(SETTINGS_FILE, "r")
	local j = json.decode(file:read("*a"))
	file:close()

	MOD_SETTINGS = j

	return true
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

function readMap(path)
	--print("readMap", path)
	if path == false or not LEX.fileExists(path) then
		return nil
	end

	local map = {
		amount = 0,
		display_name = LEX.basename(path),
		display_name_amount = "",
		identifier = LEX.basename(path), 
		packages = {},
		filepath = path
	}

	for line in io.lines(path) do
		if (line ~= nil) and (line ~= "") and not (LEX.stringStarts(line, "#")) and not (LEX.stringStarts(line, "//")) then
			if LEX.stringStarts(line, "DISPLAY_NAME:") then
				map.display_name = LEX.trim(string.match(line, ":(.*)"))
			elseif LEX.stringStarts(line, "IDENTIFIER:") then
				map.identifier = LEX.trim(string.match(line, ":(.*)"))
			else
				-- regular coordinates
				local components = {}
				for c in string.gmatch(line, '([^ ]+)') do
					table.insert(components,c)
				end

				local pkg = {}
				pkg.x = tonumber(components[1])
				pkg.y = tonumber(components[2])
				pkg.z = tonumber(components[3])
				pkg.w = tonumber(components[4])
				pkg.identifier = map.identifier .. ": x=" .. tostring(pkg.x) .. " y=" .. tostring(pkg.y) .. " z=" .. tostring(pkg.z) .. " w=" .. tostring(pkg.w)
				table.insert(map.packages, pkg)
			end
		end
	end

	map.amount = LEX.tableLen(map.packages)
	if map.amount == 0 or map.display_name == nil or map.identifier == nil then
		return nil
	end

	map.display_name_amount = map.display_name .. " (" .. tostring(map.amount) .. ")"

	return map
end

function sonar()
    local NP = findNearestPackageWithinRange(MOD_SETTINGS.SonarRange)
    if NP then
        SONAR_NEXT = SONAR_LAST + math.max((MOD_SETTINGS.SonarRange - (MOD_SETTINGS.SonarRange - distanceToPackage(NP))) / 35, 0.1)
    --elseif MOD_SETTINGS.SonarIdlePing then --obviously this variable doesnt exist yet, so this will always evaluate to false
    --    SONAR_NEXT = SONAR_LAST + MOD_SETTINGS.SonarRange / 35 --added this bit in the edit, you could always tack a "+ 2" or w/e to the end of that, too
    else
        return
    end

    if os.clock() < (SONAR_NEXT + MOD_SETTINGS.SonarMinimumDelay) then
        return
    end

    Game.GetAudioSystem():Play(MOD_SETTINGS.SonarSound)

    SONAR_LAST = os.clock()
end

function scanner()
	if not MOD_SETTINGS.ScannerEnabled or SCANNER_OPENED == nil then
		return
	end

	local NP = SCANNER_NEAREST_PKG

	if NP and not LEX.tableHasValue(SCANNER_MARKERS, NP) then

		if not MOD_SETTINGS.ScannerImmersive then
			-- no BS, just mark the package instantly
			markPackage(NP)
			table.insert(SCANNER_MARKERS, NP)
		else
			-- "immersive": wait a while, especially if the package is far away
			-- TODO horribly inefficient to do these calculations every tick
			local distance = distanceToPackage(NP)
			local delay = (distance / 1000) + 1 -- 1 sec per km + 1 sec always
			if distance < 25 then
				delay = delay - 0.8
			end
			local wait = SCANNER_OPENED + delay
			if os.clock() >= wait then
				markPackage(NP)
				table.insert(SCANNER_MARKERS, NP)
				Game.GetAudioSystem():Play("ui_hacking_access_granted")

			elseif (os.clock() - SCANNER_OPENED) >= math.min(0.5,(distance/100)) and (os.clock() - SCANNER_SOUND_TICK) >= math.max((distance/2000), 0.5) then
					Game.GetAudioSystem():Play("ui_elevator_select")
					SCANNER_SOUND_TICK = os.clock()
			end
		end

		if MOD_SETTINGS.StickyMarkers > 0 then
			while LEX.tableLen(SCANNER_MARKERS) > MOD_SETTINGS.StickyMarkers do
				unmarkPackage(SCANNER_MARKERS[1])
				table.remove(SCANNER_MARKERS, 1)
			end
		end

	end
		
end

function showCustomShardPopup(titel, text) -- from #cet-snippets @ discord
    shardUIevent = NotifyShardRead.new()
    shardUIevent.title = titel
    shardUIevent.text = text
    Game.GetUISystem():QueueEvent(shardUIevent)
end

function readItemList(ItemListPath)
	RANDOM_ITEMS_POOL = {}
	if ItemListPath then -- will be false if Disabled
		local file = io.open(ItemListPath, "r")
		local lines = file:lines()
		for line in lines do
			if (line ~= nil) and (line ~= "") and not (LEX.stringStarts(line, "#")) and not (LEX.stringStarts(line, "//")) then
				table.insert(RANDOM_ITEMS_POOL, line)
			else
				--print("Not inserting line to item pool:", line)
			end
		end
		file:close()
		--print("RANDOM_ITEMS_POOL:", LEX.tableLen(RANDOM_ITEMS_POOL))
	end
end
