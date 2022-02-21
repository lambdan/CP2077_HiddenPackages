local HiddenPackagesMetadata = {
	title = "Hidden Packages",
	version = "2.1"
}

local GameSession = require("Modules/GameSession.lua")
local GameHUD = require("Modules/GameHUD.lua")
local LEX = require("Modules/LuaEX.lua")

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

local SETTINGS_FILE = "SETTINGS.v2.1.json"
local MOD_SETTINGS = { -- defaults set here
	DebugMode = false,
	SpawnPackageRange = 100,
	SonarEnabled = false,
	SonarRange = 125,
	SonarSound = SONAR_DEFAULT_SOUND,
	SonarMinimumDelay = 0.0,
	MoneyPerPackage = 1000, -- these defaults should also be set in the nativesettings lines
	StreetcredPerPackage = 100,
	ExpPerPackage = 100,
	PackageMultiply = false,
	MapPath = MAP_DEFAULT
}

local SESSION_DATA = { -- will persist
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
local NEED_TO_REFRESH = false

local lastCheck = 0
local checkThrottle = 1

local SONAR_NEXT = 0

registerHotkey("hp_nearest_pkg", "Mark nearest package", function()
	markNearestPackage()
end)

registerHotkey("hp_whereami", "Where Am I?", function()
	local pos = Game.GetPlayer():GetWorldPosition()
	showCustomShardPopup("Where Am I?", "You are standing here:\nX:  " .. string.format("%.3f",pos["x"]) .. "\nY:  " .. string.format("%.3f",pos["y"]) .. "\nZ:  " .. string.format("%.3f",pos["z"]) .. "\nW:  " .. pos["w"])
end)

-- registerForEvent("onOverlayOpen", function()
-- 	print("HP SESSION DATA:")
-- 	--print(SESSION_DATA)
-- 	for k,v in pairs(SESSION_DATA) do
-- 		print(k,v)
-- 		for k2,v2 in pairs(v) do
-- 			print(k2,v2)
-- 		end
-- 	end
-- end)

registerForEvent('onShutdown', function() -- mod reload, game shutdown etc
    GameSession.TrySave()
    reset()
    --GameSession.TrySave()
end)

registerForEvent('onInit', function()
	loadSettings()

	if LEX.fileExists("DEBUG") then
		MOD_SETTINGS.DebugMode = true
	end

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

		nativeSettings.addSubcategory("/Hidden Packages/Maps", "Maps")

		nativeSettings.addSelectorString("/Hidden Packages/Maps", "Map", "Maps are stored in \'.../mods/Hidden Packages/Maps\''. If set to None the mod is disabled.", nsMapsDisplayNames, nsCurrentMap, nsDefaultMap, function(value)
			MOD_SETTINGS.MapPath = mapsPaths[value]
			saveSettings()
			NEED_TO_REFRESH = true
		end)

		nativeSettings.addSubcategory("/Hidden Packages/Sonar", "Sonar")

		nativeSettings.addSwitch("/Hidden Packages/Sonar", "Sonar Enabled", "Play a sound when near a package in increasing frequency the closer you get to it", MOD_SETTINGS.SonarEnabled, false, function(state)
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

	Observe('PlayerPuppet', 'OnAction', function(action)
		if LOADED_MAP ~= nil and not isPaused and isInGame then
			checkIfPlayerNearAnyPackage()
		end
	end)

	GameSession.TryLoad()



end)

registerForEvent('onUpdate', function(delta)
    if MOD_SETTINGS.SonarEnabled and LOADED_MAP ~= nil and not isPaused and isInGame then
    	sonar()
    end
end)

registerForEvent('onDraw', function()

	if MOD_SETTINGS.DebugMode then
		ImGui.Begin("Hidden Packages - Debug")
		--ImGui.Text("last check:" .. tostring(os.clock() - lastCheck))
		ImGui.Text("isInGame: " .. tostring(isInGame))
		ImGui.Text("isPaused: " .. tostring(isPaused))
		ImGui.Text("NEED_TO_REFRESH: " .. tostring(NEED_TO_REFRESH))
		ImGui.Text("checkThrottle: " .. tostring(checkThrottle))
		ImGui.Text("MOD_SETTINGS.MapPath: " .. tostring(MOD_SETTINGS.MapPath))
		ImGui.Text("SESSION_DATA.collected: " .. tostring(LEX.tableLen(SESSION_DATA.collectedPackageIDs)))

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

		if LOADED_MAP ~= nil then
			ImGui.Separator()
			ImGui.Text("Collected: " .. tostring(countCollected()) .. "/" .. tostring(LOADED_MAP.amount))
			ImGui.Text("countCollected(): " .. tostring(countCollected()))
		end
		
		-- showing NP at all times has a huge performance impact
		--local NP = findNearestPackageWithinRange(0)
		--if NP then
		--	ImGui.Text("Nearest package: " .. tostring(NP) .. " (" .. string.format("%.1f", distanceToPackage(NP)) .. "M)")
		--end


		ImGui.Separator()
		if ImGui.Button("Stop Debugging") then
			MOD_SETTINGS.DebugMode = false
		end

		ImGui.End()
	end

end)

function spawnPackage(i)
	if activePackages[i] then
		return false
	end

	local pkg = LOADED_MAP.packages[i]
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
	local pkg = LOADED_MAP.packages[packageIndex]

	if not LEX.tableHasValue(SESSION_DATA.collectedPackageIDs, pkg["identifier"]) then
		table.insert(SESSION_DATA.collectedPackageIDs, pkg["identifier"])
	end
	
	unmarkPackage(packageIndex)
	despawnPackage(packageIndex)

	local collected = countCollected()
	
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
		return true
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
	if LOADED_MAP == nil or (isPaused == true) or (isInGame == false) then
		return
	end

	if (os.clock() - lastCheck) < checkThrottle then
		return -- too soon
	end

	local nearest = nil
	local playerPos = Game.GetPlayer():GetWorldPosition()
	for k,v in pairs(LOADED_MAP.packages) do
		if not (LEX.tableHasValue(SESSION_DATA.collectedPackageIDs, v["identifier"])) then -- no point in checking for already collected packages
			-- this looks 100% ridiculous but in my testing it is faster than always calculating the Vector4.Distance
			if math.abs(playerPos["x"] - v["x"]) <= MOD_SETTINGS.SpawnPackageRange then
				if math.abs(playerPos["y"] - v["y"]) <= MOD_SETTINGS.SpawnPackageRange then
					if math.abs(playerPos["z"] - v["z"]) <= MOD_SETTINGS.SpawnPackageRange then

						if not activePackages[k] then -- package is not already spawned
							spawnPackage(k)
						end

						local d = Vector4.Distance(playerPos, ToVector4{x=v["x"], y=v["y"], z=v["z"], w=v["w"]})

						if nearest == nil or d < nearest then
							nearest = d
						end

						if (d <= 0.5) and (inVehicle() == false) then -- player is at package and is not in a vehicle, package should be collected
							collectHP(k)
							checkThrottle = 1
						elseif d < 10 then
							checkThrottle = 0.1
						elseif d < 50 then
							checkThrottle = 0.5
						end

					elseif activePackages[k] then
						despawnPackage(k)
					end
				elseif activePackages[k] then
					despawnPackage(k)
				end
			elseif activePackages[k] then
				despawnPackage(k)
			end
		elseif activePackages[k] then
			despawnPackage(k)
		end
	end

	if nearest == nil or nearest > 50 then
		checkThrottle = 1
	end

	lastCheck = os.clock()
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

function countCollected()
	-- cant just check length of collectedPackageIDs as it may include packages from other location files
	local c = 0
	for k,v in pairs(LOADED_MAP.packages) do
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
	if os.clock() < (SONAR_NEXT + MOD_SETTINGS.SonarMinimumDelay) then
		return
	end

	local NP = findNearestPackageWithinRange(MOD_SETTINGS.SonarRange)
	if not NP then
		SONAR_NEXT = os.clock() + 2
		return
	end

	Game.GetAudioSystem():Play(MOD_SETTINGS.SonarSound)

	local d = distanceToPackage(NP)
	local sonarThrottle = (MOD_SETTINGS.SonarRange - (MOD_SETTINGS.SonarRange - d)) / 35
	if sonarThrottle < 0.1 then
		sonarThrottle = 0.1
	end

	SONAR_NEXT = os.clock() + sonarThrottle
end

function showCustomShardPopup(titel, text) -- from #cet-snippets @ discord
    shardUIevent = NotifyShardRead.new()
    shardUIevent.title = titel
    shardUIevent.text = text
    Game.GetUISystem():QueueEvent(shardUIevent)
end