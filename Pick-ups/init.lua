local PickUpsMetadata = {
	title = "Pick-Ups",
	version = "0.1"
}

local DEBUG_MODE = true

local SETTINGS_FILE = "settings_1.0.json"

local GameSession = require("Modules/GameSession.lua")
local GameHUD = require("Modules/GameHUD.lua")
local GameUI = require("Modules/GameUI.lua")
local LEX = require("Modules/LuaEX.lua")

local PICKUPS_FOLDER = "Pickups/" -- should end with a /

local MOD_SETTINGS = {
	ShowMessage = true
}

local SESSION_DATA = { -- will persist
	pickedup = {}
}

local DISABLED_PICKUPS = {}

local LOADED_MAP = nil

local HUDMessage_Current = ""
local HUDMessage_Last = 0

-- defaults

local DEFAULT_PROP = "base/quest/main_quests/prologue/q005/afterlife/entities/q005_hologram_cube.ent"
local DEFAULT_PROP_Z_BOOST = 0.25

-- inits
local activePackages = {}
local isInGame = false
local isPaused = true
local NEED_TO_REFRESH = false

local lastCheck = 0
local checkThrottle = 1

registerHotkey("pup_whereami", "Where Am I?", function()
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
end)

registerForEvent('onInit', function()
	loadSettings()

	-- scan Maps folder and generate table suitable for nativeSettings
	local nsPickups = {}
	for k,v in pairs( listFilesInFolder(PICKUPS_FOLDER, ".json") ) do
		local map_path = PICKUPS_FOLDER .. v
		local read_pup = readPickup(map_path)

		if read_map ~= nil then
			table.insert(nsPickups, read_pup)
		end
	end

	-- generate NativeSettings (if available)
	nativeSettings = GetMod("nativeSettings")
	if nativeSettings ~= nil then

		nativeSettings.addTab("/Pick-Ups", "Pick-Ups")

		nativeSettings.addSubcategory("/Pick-Ups/ActivePickups", "Active Pick-Ups")

		for k,v in pairs(nsPickups) do
			nativeSettings.addSwitch("/Pick-Ups/ActivePickups", v["name"], v["filepath"], MOD_SETTINGS.SonarEnabled, true, function(state)
				print("toggled",v["name"])
			end)
		end

	end -- end NativeSettings
	

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
	return

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

function readPickup(path)
	debugMsg("read pickup: " .. path)
	if path == false or not LEX.fileExists(path) then
		return nil
	end

	local pickup = {
		id = "ididididid",
		name = "hello?",
		filepath = path,
		position = {
			x = 0,
			y = 0,
			z = 0,
			w = 1
		},
		vehicle_allowed  = false,
		pickup_msg = false,
		pickup_sound = false,
		shard_message = false,
		package_prop = DEFAULT_PROP,
		package_prop_z_boost = DEFAULT_PROP_Z_BOOST,
		respawn = false,
		money = false,
		xp = false,
		streetcred = false,
		items = false, 
		teleport = false
	}

	return pickup
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

function showCustomShardPopup(titel, text) -- from #cet-snippets @ discord
    shardUIevent = NotifyShardRead.new()
    shardUIevent.title = titel
    shardUIevent.text = text
    Game.GetUISystem():QueueEvent(shardUIevent)
end