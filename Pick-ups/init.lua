local PickUpsMetadata = {
	title = "Pick-Ups",
	version = "0.1"
}

local DEBUG_MODE = true -- change to false before shipping!!!!!
local DEBUG_MSG = "debug_msg"

local GameSession = require("Modules/GameSession.lua")
local GameHUD = require("Modules/GameHUD.lua")
local GameUI = require("Modules/GameUI.lua")
local LEX = require("Modules/LuaEX.lua")

local MOD_SETTINGS = { -- saved to SETTINGS_FILE
	SpawnPackageRange = 100
}

local SESSION_DATA = { -- will persist thru GameSession
	collected = {}
}

-- paths
local PICKUPS_FOLDER = "Pickups/" -- folder with json files, should end with a /
local SETTINGS_FILE = "settings_1.0.json" -- change if MOD_SETTINGS gets new vars

-- defaults
local DEFAULT_PROP = "base/quest/main_quests/prologue/q005/afterlife/entities/q005_hologram_cube.ent"
local DEFAULT_PROP_Z_BOOST = 0.25
local DEFAULT_RESPAWN = 3
local DEFAULT_COLLECT_RANGE = 0.5

-- other vars
local LOADED_PICKUPS = {} -- all loaded jsons will be store in here as pickups
local activePackages = {} -- packages that are spawned
local isInGame = false
local isPaused = true
local lastCheck = 0 -- when checkifplayernearanypackage() was last run
local checkThrottle = 1 -- wait atleast this before checkifplayernearanypackage()
local HUDMessage_Current = "" -- if >1 hudmessage's are triggered in short succession the first one wont show...
local HUDMessage_Last = 0 --     so we store it and add another one to it

registerHotkey("pup_whereami", "Where Am I?", function()
	local pos = Game.GetPlayer():GetWorldPosition()
	showCustomShardPopup("Where Am I?", "You are standing here:\nX:  " .. string.format("%.3f",pos["x"]) .. "\nY:  " .. string.format("%.3f",pos["y"]) .. "\nZ:  " .. string.format("%.3f",pos["z"]) .. "\nW:  " .. pos["w"])
end)

registerForEvent("onDraw", function()
	if DEBUG_MODE then
		local w,h = GetDisplayResolution()
		ImGui.SetNextWindowPos(w/3, h-200)
		ImGui.Begin("pick-ups debug", true, ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoMove + ImGuiWindowFlags.NoScrollbar + ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoResize)
		ImGui.Text(DEBUG_MSG)
		ImGui.Text("LOADED_PICKUPS: " .. tostring(LEX.tableLen(LOADED_PICKUPS)))
		ImGui.Text("activePackages: " .. tostring(LEX.tableLen(activePackages)))
		ImGui.Text("SESSION_DATA.collected: [")
		for k,v in pairs(SESSION_DATA.collected) do
			ImGui.Text(tostring(v) .. " ")
			if k % 5 ~= 0 then
				ImGui.SameLine()
			end
		end
		ImGui.SameLine()
		ImGui.Text("]")
		--if ImGui.Button("reset session") then
		--	SESSION_DATA.collected = {}
		--end
		ImGui.End()

	end
end)

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

		nativeSettings.addSubcategory("/PickUps/Debug", "debug")

		nativeSettings.addButton("/PickUps/Debug", "Reset collected", "Reset SESSION_DATA.collected", "Reset", 45, function()
 			SESSION_DATA.collected = {}
 		end)

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

        -- since we just use onupdate for pick-ups we dont need this one
        --checkIfPlayerNearAnyPackage() -- otherwise if you made a save near a package and just stand still it wont spawn until you move
    end)

    GameSession.OnEnd(function()
        isInGame = false
        reset()
    end)

	GameSession.OnPause(function()
		isPaused = true
	end)

	GameSession.OnResume(function()
		isPaused = false
	end)

--[[	Observe('PlayerPuppet', 'OnAction', function(action)
		if LOADED_PICKUPS ~= nil and not isPaused and isInGame then
			checkIfPlayerNearAnyPackage()
		end
	end)--]]

	GameSession.TryLoad()

end)

registerForEvent('onUpdate', function(delta)
    if LOADED_PICKUPS ~= {} and not isPaused and isInGame then
    	checkIfPlayerNearAnyPackage()

        for k,v in pairs(LOADED_PICKUPS) do
			if v.rotating and v.spawned and (os.clock() > (v.spawned + (1/60))) then
				--print(activePackages[k])
				
				LOADED_PICKUPS[k].orientation.x = LOADED_PICKUPS[k].orientation.x + 1
				if LOADED_PICKUPS[k].orientation.x > 360 then
					LOADED_PICKUPS[k].orientation.x = 0
				end
				despawnPackage(k)
				spawnPackage(k)
			end
		end
    end
end)

function spawnPackage(i)
	local pkg = LOADED_PICKUPS[i]
	if activePackages[i] or pkg.spawned then
		return false
	end

	local entity = spawnObjectAtPos(pkg.position.x, pkg.position.y, pkg.position.z + pkg.prop_z_boost, pkg.position.w, pkg.prop, pkg.orientation)
	if entity then
		activePackages[i] = entity
		LOADED_PICKUPS[i].spawned = os.clock()
		return entity
	end
	return false
end

function spawnObjectAtPos(x,y,z,w, prop, ori)
    local transform = Game.GetPlayer():GetWorldTransform()
    local pos = ToVector4{x=x, y=y, z=z, w=w}
    transform:SetPosition(pos)
    transform:SetOrientation( EulerAngles.new(ori.z, ori.y, ori.x):ToQuat() )
    return WorldFunctionalTests.SpawnEntity(prop, transform, '') -- returns ID
end

function despawnPackage(i) -- i = package index
	if destroyObject(activePackages[i]) then
		activePackages[i] = nil
		LOADED_PICKUPS[i].spawned = false
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
	despawnPackage(packageIndex)
	local pkg = LOADED_PICKUPS[packageIndex]
	pkg.picked_up_time = os.clock()
	pkg.picked_up_pos = Game.GetPlayer():GetWorldPosition()

	if not LEX.tableHasValue(SESSION_DATA.collected, pkg["id"]) then
		-- add all packages (even the ones that arent permanent) to the table, it doesnt hurt + can use multiple packages for the prereq option
		table.insert(SESSION_DATA.collected, pkg["id"])
	end

	if pkg.pickup_msg then
		HUDMessage(pkg.pickup_msg)
	end

	if pkg.shard_message.title ~= nil and pkg.shard_message.body ~= nil then
		showCustomShardPopup(pkg.shard_message.title, pkg.shard_message.body)
	end

	if pkg.pickup_sound then
		Game.GetAudioSystem():Play(pkg.pickup_sound)
	end

	if pkg.teleport.x ~= nil and pkg.teleport.y ~= nil and pkg.teleport.z ~= nil then
		Game.TeleportPlayerToPosition(pkg.teleport.x, pkg.teleport.y, pkg.teleport.z)
	end

	LOADED_PICKUPS[packageIndex] = pkg

end

function reset()
	destroyAllPackageObjects()
	activePackages = {}
	lastCheck = 0
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
		if not (v.permanent and LEX.tableHasValue(SESSION_DATA.collected, v.id)) then -- no point in checking for collected permanents
			-- this looks 100% ridiculous but in my testing it is faster than always calculating the Vector4.Distance
			if math.abs(playerPos["x"] - v.position.x) <= MOD_SETTINGS.SpawnPackageRange and math.abs(playerPos["y"] - v.position.y) <= MOD_SETTINGS.SpawnPackageRange and math.abs(playerPos["z"] - v.position.z) <= MOD_SETTINGS.SpawnPackageRange then
				-- pkg is in range
				
				local pkg_allowed = true
				local d = Vector4.Distance(playerPos, ToVector4{x=v.position.x, y=v.position.y, z=v.position.z, w=v.position.w})

				-- (optimization: we use d (distance to specified package position) instead of the actual v.picked_up_pos)
				if v.picked_up_pos and d < (v.collect_range*4) then
					-- we are still standing too close to the package we just picked up
					pkg_allowed = false
					DEBUG_MSG = v.id .. " - too close"
				elseif v.picked_up_pos and d >= (v.collect_range*4) then
					-- we have moved far away enough from the package since we last picked it up
					LOADED_PICKUPS[k].picked_up_pos = false
					DEBUG_MSG = v.id .. " - reset picked_up_pos"
				end

				if v.picked_up_time and os.clock() < (v.picked_up_time + v.respawn) then
					-- package should not respawn yet
					pkg_allowed = false
					DEBUG_MSG = v.id .. " - not respawn yet"
				end

				if LEX.tableLen(v.prereq_pickups) > 0 then
					for a,b in pairs(v.prereq_pickups) do
						if not LEX.tableHasValue(SESSION_DATA.collected, b) then
							-- we are missing a prereq package
							pkg_allowed = false
							DEBUG_MSG = v.id .. " - missing prereq"
						end
					end
				end
				
				if pkg_allowed and not activePackages[k] then -- package is allowed and is not already spawned
					spawnPackage(k)
					DEBUG_MSG = v.id .. " - OK! spawn!"
				end

				if nearest == nil or d < nearest then -- dont use pkg_allowed here in case pkg suddenly becomes available when player is nearby
					nearest = d
				end

				if pkg_allowed and (d <= v.collect_range) and (v.vehicle_allowed or not inVehicle()) then
					-- pkg is allowed, we're in collect range, and vehicle is allowed or we're not in a vehicle: collect it
					despawnPackage(k)
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
	end

	if nearest == nil or nearest > 50 then
		checkThrottle = 1
	end

	lastCheck = os.clock()
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

function readPickup(path) -- path=path to json file
	if path == false or not LEX.fileExists(path) then
		return nil
	end

	local file = io.open(path,"r")
	local j = json.decode(file:read("*a"))
	file:close()



	local pickup = {
		enabled = true, -- is the package enabled? (not user modified)
		filename = path:match("^.+/(.+)$"), -- name of the base .json (not including subfolder)
		filepath = path, -- full path to the .json (not user modified)
		picked_up_time = false, -- used for figuring out when to respawn. will be set to a os.clock() on pickup
		picked_up_pos = false, -- player pos when picked up stored here
		spawned = false,
		id = "", -- *required*. a unique id for the package, i.e. djs_package1. will be stored in SESSION_DATA.collected
		position = { -- *required*. position of the package.
			x = 0,
			y = 0,
			z = 0,
			w = 1 -- w seems to always be 1 but lets include just to be safe
		},
		orientation = {
			z = 0, -- TODO check if these are the proper names
			y = 0,
			x = 0
		},
		rotating = false, -- should it rotate (animate)
		collect_range = DEFAULT_COLLECT_RANGE, -- how close you need to be to a package to pick it up. HP used 0.5.
		name = "", -- a pretty display name of the package. might be used for a screen where you toggle packages, or on pick-up. will fallback to full filename.
		vehicle_allowed  = false, -- can package be collected while in a vehicle?
		pickup_msg = false, -- HUDMessage on pickup
		pickup_sound = false, -- play this sound (string) on pickup
		shard_message = {}, -- title,body (strings) of shard_message on pickup
		prop = DEFAULT_PROP, -- prop used
		prop_z_boost = DEFAULT_PROP_Z_BOOST, -- z boost (height) to prop
		respawn = DEFAULT_RESPAWN, -- how long to wait (secs) before respawning package. has no effect if permanent is activated.
		permanent = false, -- is package permanently collected? wont respawn if it is
		money = false, -- give this money on pickup
		xp = false, -- give this xp on pickup
		streetcred = false, -- give this streetcred xp on pickup
		items = {}, -- give these items on pickup
		teleport = {}, -- teleport here on pickup
		prereq_pickups = {} -- these package id's need to be in SESSION_DATA.collected before package will spawn
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

	if j["orientation"] ~= nil then
		pickup.orientation = j["orientation"]
	end

	if j["name"] ~= nil then
		pickup.name = j["name"]
	else
		pickup.name = pickup.filename
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

	if j["rotating"] ~= nil then
		pickup.rotating = j["rotating"]
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

	if j["permanent"] ~= nil then
		pickup.permanent = j["permanent"]
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

	if j["prereq_pickups"] ~= nil then
		pickup.prereq_pickups = j["prereq_pickups"]
	end


	if DEBUG_MODE then
		print("readPickup", path, ":")
		for k,v in pairs(pickup) do
			print(k..":", v)
		end
		print("---------END READMAP------------")
	end

	return pickup
end

function showCustomShardPopup(titel, text) -- from #cet-snippets @ discord
    shardUIevent = NotifyShardRead.new()
    shardUIevent.title = titel
    shardUIevent.text = text
    Game.GetUISystem():QueueEvent(shardUIevent)
end