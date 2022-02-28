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
local LOADED_PICKUPS = {}

local MOD_SETTINGS = {
	ShowMessage = true,
	SpawnPackageRange = 100
}

local SESSION_DATA = { -- will persist
	pickedup = {}
}

local HUDMessage_Current = ""
local HUDMessage_Last = 0

-- defaults

local DEFAULT_PROP = "base/quest/main_quests/prologue/q005/afterlife/entities/q005_hologram_cube.ent"
local DEFAULT_PROP_Z_BOOST = 0.25
local DEFAULT_RESPAWN = 3
local DEFAULT_COLLECT_RANGE = 0.5

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

	-- load pickups
	local nsPickups = {}
	for k,v in pairs( listFilesInFolder(PICKUPS_FOLDER, ".json") ) do
		local map_path = PICKUPS_FOLDER .. v
		local read_pup = readPickup(map_path)

		if read_pup ~= nil then
			table.insert(LOADED_PICKUPS, read_pup)
		end
	end

	-- generate NativeSettings (if available)
	nativeSettings = GetMod("nativeSettings")
	if nativeSettings ~= nil then

		nativeSettings.addTab("/PickUps", "Pick-Ups")
		nativeSettings.addSubcategory("/PickUps/ActivePickups", "Loaded Pick-Ups:")

		for k,v in pairs(LOADED_PICKUPS) do
			nativeSettings.addSwitch("/PickUps/ActivePickups", v["name"], "(Note that toggling state here does nothing... for now)", LOADED_PICKUPS[k]["enabled"], false, function(state)
				-- do sometihng here...
			end)
		end

	end -- end NativeSettings


	

	GameSession.StoreInDir('Sessions')
	GameSession.Persist(SESSION_DATA)
	isInGame = Game.GetPlayer() and Game.GetPlayer():IsAttached() and not Game.GetSystemRequestsHandler():IsPreGame()

    GameSession.OnStart(function()
        isInGame = true
        isPaused = false

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
	end)

	Observe('PlayerPuppet', 'OnAction', function(action)
		if LOADED_PICKUPS ~= nil and not isPaused and isInGame then
			checkIfPlayerNearAnyPackage()
		end
	end)

	GameSession.TryLoad()

end)

function spawnPackage(i,prop,zboost)
	if activePackages[i] then
		return false
	end

	local pos = LOADED_PICKUPS[i].position
	local entity = spawnObjectAtPos(pos["x"], pos["y"], pos["z"]+zboost, pos["w"], prop)
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
	HUDMessage("picked up something")
	despawnPackage(packageIndex)
	print("collectHP", packageIndex)

end

function reset()
	destroyAllPackageObjects()
	activePackages = {}
	lastCheck = 0
	debugMsg("reset() OK")
	return true
end

function destroyAllPackageObjects()
	if LOADED_PICKUPS == nil then
		return
	end

	for k,v in pairs(LOADED_PICKUPS) do
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
	if not isInGame	or LOADED_PICKUPS == nil then
		return false
	end

	local nearest = nil
	local nearestPackage = false
	local playerPos = Game.GetPlayer():GetWorldPosition()

	for k,v in pairs(LOADED_PICKUPS) do
		if (LEX.tableHasValue(SESSION_DATA.pickedup, v["id"]) == false) then -- package not collected
			if range == 0 or math.abs(playerPos["x"] - v.position.x) <= range then
				if range == 0 or math.abs(playerPos["y"] - v.position.y) <= range then
					local d = Vector4.Distance(playerPos, ToVector4{x=v.position.x, y=v.position.y, z=v.position.z, w=v.position.w})
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

function checkIfPlayerNearAnyPackage()
	if LOADED_PICKUPS == nil or (isPaused == true) or (isInGame == false) then
		return
	end

	if (os.clock() - lastCheck) < checkThrottle then
		return -- too soon
	end

	local nearest = nil
	local playerPos = Game.GetPlayer():GetWorldPosition()
	for k,v in pairs(LOADED_PICKUPS) do
		print(v.position.x)
		if not (LEX.tableHasValue(SESSION_DATA.pickedup, v.id)) then -- no point in checking for already collected packages
			-- this looks 100% ridiculous but in my testing it is faster than always calculating the Vector4.Distance
			if math.abs(playerPos["x"] - v.position.x) <= MOD_SETTINGS.SpawnPackageRange then
				if math.abs(playerPos["y"] - v.position.y) <= MOD_SETTINGS.SpawnPackageRange then
					if math.abs(playerPos["z"] - v.position.z) <= MOD_SETTINGS.SpawnPackageRange then
						print("in range of", v.id)

						if not activePackages[k] then -- package is not already spawned
							spawnPackage(k, v.prop, v.prop_z_boost)
						end

						local d = Vector4.Distance(playerPos, ToVector4{x=v.position.x, y=v.position.y, z=v.position.z, w=v.position.w})

						if nearest == nil or d < nearest then
							nearest = d
						end

						if (d <= v.collect_range) and (inVehicle() == false) then -- player is at package and is not in a vehicle, package should be collected
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
	local pkg = LOADED_PICKUPS[i].position
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
	print("readPickup",path)
	if path == false or not LEX.fileExists(path) then
		return nil
	end

	local file = io.open(path,"r")
	local j = json.decode(file:read("*a"))
	file:close()

	local pickup = {
		enabled = true, -- not modified
		filepath = path, -- not modified
		id = "", -- required
		position = { -- required
			x = 0,
			y = 0,
			z = 0,
			w = 1
		},
		collect_range = DEFAULT_COLLECT_RANGE,
		name = path,
		vehicle_allowed  = false,
		pickup_msg = false,
		pickup_sound = false,
		shard_message = {},
		prop = DEFAULT_PROP,
		prop_z_boost = DEFAULT_PROP_Z_BOOST,
		respawn = DEFAULT_RESPAWN,
		money = false,
		xp = false,
		streetcred = false,
		items = {}, 
		teleport = {}
	}


	-- first read required attributes, and return nil if they fail 

	if j["id"] ~= nil then
		pickup.id = j["id"]
	else
		print(path,"is missing id")
		return nil
	end

	if j["position"] ~= nil then
		if j["position"]["x"] ~= nil then
			pickup.position.x = j["position"]["x"]
		else
			print(path,"is missing x")
			return nil
		end
		if j["position"]["y"] ~= nil then
			pickup.position.y = j["position"]["y"]
		else
			print(path,"is missing y")
			return nil
		end
		if j["position"]["z"] ~= nil then
			pickup.position.z = j["position"]["z"]
		else
			print(path,"is missing z")
			return nil
		end
		-- w is not strictly necessary
	else
		print(path,"is missing position")
		return nil
	end

	-- now read optional attributes

	if j["name"] ~= nil then
		pickup.name = j["name"]
	end

	if j["vehicle_allowed"] ~= nil then
		pickup.vehicle_allowed = j["vehicle_allowed"]
	end

	if j["pickup_msg"] ~= nil then
		pickup.pickup_msg = j["pickup_msg"]
	end

	if j["pickup_sound"] ~= nil then
		pickup.pickup_sound = j["pickup_sound"]
	end

	if j["shard_message"] ~= nil then
		if j["shard_message"]["title"] ~= nil then
			pickup.shard_message.title = j["shard_message"]["title"]
		else
			pickup.shard_message.title = ""
		end

		if j["shard_message"]["body"] ~= nil then
			pickup.shard_message.body = j["shard_message"]["body"]
		else
			pickup.shard_message.body = ""
		end
	end

	if j["prop"] ~= nil then
		pickup.prop = j["prop"]
	end

	if j["prop_z_boost"] ~= nil then
		pickup.prop_z_boost = j["prop_z_boost"]
	end

	if j["respawn"] ~= nil then
		pickup.respawn = j["respawn"]
	end

	if j["money"] ~= nil then
		pickup.money = j["money"]
	end

	if j["exp"] ~= nil then
		pickup.exp = j["exp"]
	end

	if j["streetcred"] ~= nil then
		pickup.streetcred = j["streetcred"]
	end

	if j["items"] ~= nil then
		pickup.items = j["items"]
	end

	if j["teleport"] ~= nil then
		pickup.teleport = j["teleport"]
	end

	if j["collect_range"] ~= nil then
		pickup.collect_range = j["collect_range"]
	end

	print(path, "OK!")
	return pickup
end

function showCustomShardPopup(titel, text) -- from #cet-snippets @ discord
    shardUIevent = NotifyShardRead.new()
    shardUIevent.title = titel
    shardUIevent.text = text
    Game.GetUISystem():QueueEvent(shardUIevent)
end