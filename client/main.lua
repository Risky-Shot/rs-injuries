healthManager = nil -- Global Variable
local devMode = true
stamina = 100.0

local PlayerPedId = PlayerPedId
local GetEntityCoords = GetEntityCoords
local GetTemperatureAtCoords = GetTemperatureAtCoords

function Log(msg)
    if devMode then
        print(msg)
    end
end

CreateThread(function()
    healthManager = HealthManager()
    healthManager.init()
	while true do
		Citizen.Wait(0)
		local size = GetNumberOfEvents(0) -- get number of events for EVENT GROUP 0 (SCRIPT_EVENT_QUEUE_AI). Check table below.
		if size > 0 then
			for i = 0, size - 1 do
				local eventAtIndex = GetEventAtIndex(0, i)

				if eventAtIndex == `EVENT_ENTITY_DAMAGED` then      
					local eventDataSize = 9  

					local eventDataStruct = DataView.ArrayBuffer(128) -- buffer must be 8*eventDataSize or bigger
					eventDataStruct:SetInt32(0, 0)     -- 8*0 offset for 0 element of eventData
					eventDataStruct:SetInt32(8, 0)     -- 8*1 offset for 1 element of eventData
					eventDataStruct:SetInt32(16, 0)    -- 8*2 offset for 2 element of eventData
					eventDataStruct:SetInt32(24, 0)    -- 8*3 offset for 3 element of eventData
					eventDataStruct:SetInt32(32, 0)    -- 8*4 offset for 4 element of eventData
					eventDataStruct:SetInt32(40, 0)    -- 8*4 offset for 5 element of eventData
					eventDataStruct:SetInt32(48, 0)    -- 8*4 offset for 6 element of eventData
					eventDataStruct:SetInt32(56, 0)    -- 8*4 offset for 7 element of eventData
					eventDataStruct:SetInt32(64, 0)    -- 8*4 offset for 8 element of eventData

					-- etc +8 offset for each next element (if data size is bigger then 5)

					local is_data_exists = Citizen.InvokeNative(0x57EC5FA4D4D6AFCA, 0, i, eventDataStruct:Buffer(), eventDataSize)          -- GET_EVENT_DATA
                    if is_data_exists then
                        local attacked = eventDataStruct:GetInt32(0) -- 8*1 offset for 1 element of eventData
                        local attacker = eventDataStruct:GetInt32(8)
                        local weaponHash = eventDataStruct:GetInt32(16)
                        local ammoHash = eventDataStruct:GetInt32(24)
                        local damage = eventDataStruct:GetInt32(32)
                        local unknown = eventDataStruct:GetInt32(40)
                        local x = eventDataStruct:GetInt32(48)
                        local y = eventDataStruct:GetInt32(56)
                        local z = eventDataStruct:GetInt32(64)

                        print('Weapon',WeaponsInfo[tostring(weaponHash)].name)
                        healthManager.handleDamageEvent(attacker, attacked, weaponHash, ammoHash, x, y, z)
                    end
				end
			end
		end
	end
end)






--[[
  _____  ______ ____  _    _  _____ 
 |  __ \|  ____|  _ \| |  | |/ ____|
 | |  | | |__  | |_) | |  | | |  __ 
 | |  | |  __| |  _ <| |  | | | |_ |
 | |__| | |____| |_) | |__| | |__| |
 |_____/|______|____/ \____/ \_____|    

]]--
local function DrawTxt(str, x, y, w, h, enableShadow, col1, col2, col3, a, centre)
    local str = CreateVarString(10, "LITERAL_STRING", str)
    SetTextScale(w, h)
    SetTextColor(math.floor(col1), math.floor(col2), math.floor(col3), math.floor(a))
	SetTextCentre(centre)
    if enableShadow then SetTextDropshadow(1, 0, 0, 0, 255) end
	Citizen.InvokeNative(0xADA9255D, 1);
    DisplayText(str, x, y)
end

CreateThread(function()
    while true do
        Wait(1)
        DrawTxt('Health : '..tostring(healthManager.health), 0.02, 0.25, 0.5, 0.5, true, 255, 255, 255, 255, false)
        DrawTxt('Blood : '..tostring(healthManager.litersOfBlood), 0.02, 0.28, 0.5, 0.5, true, 255, 255, 255, 255, false)
        DrawTxt('Body Temp : '..tostring(healthManager.internalTemperature), 0.02, 0.31, 0.5, 0.5, true, 255, 255, 255, 255, false)
        DrawTxt('Food : '..tostring(healthManager.food), 0.02, 0.34, 0.5, 0.5, true, 255, 255, 255, 255, false)
        DrawTxt('Water : '..tostring(healthManager.water), 0.02, 0.37, 0.5, 0.5, true, 255, 255, 255, 255, false)
        DrawTxt('Hot ? : '..tostring(healthManager.isHot), 0.02, 0.41, 0.5, 0.5, true, 255, 255, 255, 255, false)
        DrawTxt('Cold ? : '..tostring(healthManager.isCold), 0.02, 0.44, 0.5, 0.5, true, 255, 255, 255, 255, false)
        DrawTxt('Move Speed : '..tostring(LocalPlayer.state.boneSpeedLimit), 0.02, 0.47, 0.5, 0.5, true, 255, 255, 255, 255, false)
        DrawTxt('Curr Move Speed : '..tostring(GetPedDesiredMoveBlendRatio(PlayerPedId())), 0.02, 0.51, 0.5, 0.5, true, 255, 255, 255, 255, false)
        DrawTxt('Stamina : '..tostring(stamina), 0.02, 0.54, 0.5, 0.5, true, 255, 255, 255, 255, false)

        DrawTxt('SKEL_HEAD', 0.5, 0.5, 0.4, 0.4, true, 255, 255, 255, 255, true)
        DrawTxt('SKEL_NECK1', 0.5, 0.53, 0.4, 0.4, true, 255, 255, 255, 255, true)
        DrawTxt('SKEL_L_CLAVICLE', 0.4, 0.56, 0.4, 0.4, true, 255, 255, 255, 255, true)
        DrawTxt('SKEL_R_CLAVICLE', 0.6, 0.56, 0.4, 0.4, true, 255, 255, 255, 255, true)
        DrawTxt('SKEL_L_UPPERARM', 0.35, 0.59, 0.4, 0.4, true, 255, 255, 255, 255, true)
        DrawTxt('SKEL_R_UPPERARM', 0.65, 0.59, 0.4, 0.4, true, 255, 255, 255, 255, true)
        DrawTxt('SKEL_SPINE4', 0.5, 0.62, 0.4, 0.4, true, 255, 255, 255, 255, true)
        DrawTxt('SKEL_L_FOREARM', 0.35, 0.65, 0.4, 0.4, true, 255, 255, 255, 255, true)
        DrawTxt('SKEL_R_FOREARM', 0.65, 0.65, 0.4, 0.4, true, 255, 255, 255, 255, true)
        DrawTxt('SKEL_L_HAND', 0.35, 0.68, 0.4, 0.4, true, 255, 255, 255, 255, true)
        DrawTxt('SKEL_R_HAND', 0.65, 0.68, 0.4, 0.4, true, 255, 255, 255, 255, true)
        DrawTxt('SKEL_PENIS00', 0.5, 0.70, 0.4, 0.4, true, 255, 255, 255, 255, true)
        DrawTxt('SKEL_L_THIGH', 0.45, 0.75, 0.4, 0.4, true, 255, 255, 255, 255, true)
        DrawTxt('SKEL_R_THIG', 0.55, 0.75, 0.4, 0.4, true, 255, 255, 255, 255, true)
        DrawTxt('SKEL_L_CALF', 0.45, 0.78, 0.4, 0.4, true, 255, 255, 255, 255, true)
        DrawTxt('SKEL_R_CALF', 0.55, 0.78, 0.4, 0.4, true, 255, 255, 255, 255, true)
        DrawTxt('SKEL_L_FOOT', 0.45, 0.81, 0.4, 0.4, true, 255, 255, 255, 255, true)
        DrawTxt('SKEL_R_FOOT', 0.55, 0.81, 0.4, 0.4, true, 255, 255, 255, 255, true)
    end
end)

RegisterCommand('shootBone', function(_, args)
    healthManager.damageBoneByName(args[1], tonumber(args[2]))
    healthManager.shootBoneByName(args[1])
end)

RegisterCommand('statusBone', function(_, args)
    for k, v in pairs(mpBoneHealth) do
        local bone = healthManager.boneNames[tostring(k)]
        if healthManager.boneStatus[tostring(bone.id)] ~= nil then
            print(k, json.encode(healthManager.boneStatus[tostring(bone.id)]))
        end
    end
end)

RegisterCommand('resetHealth', function(_, args)
    healthManager.resetHealth()
end)

RegisterCommand('fxTest', function(_, args)
    AnimpostfxPlay(args[1])
    AnimpostfxSetStrength(args[1], 1.0)

    Wait(5000)
    AnimpostfxStop(args[1])
end)

RegisterCommand('locoTest', function(_, args)
    local ped = PlayerPedId()
    ClearPedDesiredLocoForModel(ped)
    ClearPedDesiredLocoMotionType(ped)
    Wait(100)
    SetPedDesiredLocoForModel(ped, 'default')
    SetPedDesiredLocoMotionType(ped, args[1])

    Wait(10000)
    ClearPedDesiredLocoForModel(ped)
    ClearPedDesiredLocoMotionType(ped)
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName == GetCurrentResourceName() then
        healthManager.stop()
    end
end)