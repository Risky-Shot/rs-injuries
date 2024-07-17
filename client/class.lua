if not lib then 
    return
end

local moveSpeedSkels = {'SKEL_L_THIGH', 'SKEL_L_CALF', 'SKEL_L_FOOT', 'SKEL_R_THIGH', 'SKEL_R_CALF', 'SKEL_R_FOOT'}

local handShakeSkels = {
  'SKEL_L_HAND',
  'SKEL_R_HAND',
  'SKEL_L_FOREARM',
  'SKEL_R_FOREARM',
  'SKEL_L_UPPERARM',
  'SKEL_R_UPPERARM',
}

local lastHandShake = 0.0

local min, max, ceil, abs, floor = math.min, math.max, math.ceil, math.abs, math.floor

local function clamp(value, min, max)
    if value < min then
        return min
    elseif value > max then
        return max
    else
        return value
    end
end

local function VectorSub(u,v)
    return vector3(u.x - v.x, u.y - v.y, u.z - v.z)
end

local function lerp(a, b, t) return a * (1 - t) + b * t end

function string:startswith(start)
    return self:sub(1, #start) == start
end

function math:round(x, n)
    n = math.pow(10, n or 0)
    x = x * n
    if x >= 0 then x = math.floor(x + 0.5) else x = math.ceil(x - 0.5) end
    return x / n
end

local FoodLength = 60 * 60 * 2  -- 2 Hours
local WaterLength = 60 * 60 * 2  -- 2 Hours

local FoodPerSecond = 100 / FoodLength -- FoodLength
local WaterPerSecond = 100 / WaterLength -- WaterLength

local TempChangPerSecond = 1 / (60 * 0.1) -- 1 degree in 5 Minutes

LocalPlayer.state.boneSpeedLimit = 3 -- Max Speed

-- Default Data Set
function HealthManager()
    local self = {}
    self.initialized = false
    self.interval = nil

    self.playerPed = 0
    self.playerId = 0
    self.isRagdolling = false
    self.isBleeding = false
    self.hasBrokenBone = false
    self.lastCustomWalk = '__reset__'

    self.ragdollStart = nil
    self.ragdollLastDamagedBone = nil
    self.ragdollMaxZ = nil
    self.ragdollLastZ = 0
    self.ragdollDidDamage =false
    self.canRagdollWithKey = true

    self.bones = {}
    self.boneNames = {}

    self.burned = 0

    self.boneHealth = {}
    self.boneStatus = {}
    self.infectionStabilized = false

    self.recoveryMultiplier = 1.0

    self.lastGameTime = GetGameTimer()

    self.health = 100.0
    self.stamina = 100.0
    self.litersOfBlood = 5
    self.food = 100.0
    self.water = 100.0

    self.warmth = 0 -- TODO : Based On Clothes
    self.temperature = 37
    self.internalTemperature = 37

    self.isHot = false
    self.isCold = false

    self.getHealth = function()
        return self.health
    end

    self.getlitersOfBlood = function()
        return self.litersOfBlood
    end

    self.getBoneHealth = function()
        return self.boneHealth
    end

    self.getBoneStatus = function()
        return self.boneStatus
    end

    self.init = function()
        if self.initialized then return end

        self.initialized = true

        self.checkUpdatedPed() -- done
        self.resetHealth()

        self.interval = lib.timer(2500, function()
            local delta = (GetGameTimer() - self.lastGameTime) / 1000
            self.lastGameTime = GetGameTimer()
            self.checkUpdatedPed() --done
            self.screenFxTick() --done
            self.updateCurrentHealth() --done
            self.updateGameHealth() --done
            --self.checkPlayerStatus() -- Future Update
            self.foodWaterTick(delta)
            self.warmthTick(delta)
            self.checkMoveSpeedSkels()
            self.checkHandShakeSkels()
            self.handleBoneTick(delta)
            self.checkWalkCycle()

            self.interval:restart()
        end, true)
    end

    self.foodWaterTick = function(delta)
        self.food -= FoodPerSecond * delta
        self.water -=  WaterPerSecond * delta

        if self.isCold then
            self.food -= FoodPerSecond * delta * 2
        end

        if self.isHot then
            self.water -= WaterPerSecond * delta * 2
        end

        self.food = clamp(self.food, 0, 100.0)
        self.water = clamp(self.water, 0, 100.0)
    end

    self.warmthTick = function(delta)
        self.temperature = LocalPlayer.state.temperature
        local targetWarmthLevel = math.max(-1.0, lerp(10, 0, (self.temperature + 10) / 38))
        local warmthDelta = math.min(math.max(math.abs(self.warmth - targetWarmthLevel), 0), 10)
        local isHot = self.warmth > targetWarmthLevel and warmthDelta > 3
        local isCold = self.warmth < targetWarmthLevel and warmthDelta > 4

        local lowestTemp = 37 - warmthDelta
        local highestTemp = 37 + warmthDelta

        if (isCold and self.internalTemperature > lowestTemp) then
            self.internalTemperature = self.internalTemperature - warmthDelta * TempChangPerSecond * delta
        elseif (isHot and self.internalTemperature < highestTemp) then
            self.internalTemperature = self.internalTemperature + warmthDelta * TempChangPerSecond * delta
        elseif (not isCold and self.internalTemperature < 37 - warmthDelta / 5) then
            self.internalTemperature = self.internalTemperature + warmthDelta * TempChangPerSecond * delta
        elseif ( not isHot and self.internalTemperature > 37 + warmthDelta / 5) then
            self.internalTemperature = self.internalTemperature - warmthDelta * TempChangPerSecond * delta
        end

        -- if (!this.isCold && isCold) {
        --     emit('health:client:warmthSpeedLimit', 2);
        -- } else if (this.isCold && !isCold) {
        --     emit('health:client:warmthSpeedLimit', 3);
        -- }

        self.isHot = isHot
        self.isCold = isCold
    end

    self.updateCurrentHealth = function()
        local health = 100.0
        for name, bone in pairs(self.boneNames) do
            local boneHealth = self.boneHealth[tostring(bone.id)]
            if (not boneHealth and boneHealth ~= 0) then
                goto CONTINUE
            end

            local currentBoneStatus = self.boneStatus[tostring(bone.id)]
            if not currentBoneStatus then
                goto CONTINUE
            end

            if (name:startswith('SKEL_') and boneHealth < 100) then
                local boneHealthPercent = mpBoneHealth[name]?.percent
                --if boneHealthPercent ~= nil then -- make sure we have boneHealthPercent
                    if((currentBoneStatus.shot > 0 or currentBoneStatus.slash > 0) and currentBoneStatus.bandaged) then
                        Log('Bandaged Bone')
                        boneHealthPercent = boneHealthPercent - mpBoneHealth[name].percent * 0.25
                        if not currentBoneStatus.broken then
                            boneHealthPercent = boneHealthPercent - mpBoneHealth[name].percent * 0.25
                        end
                    elseif (currentBoneStatus.broken and currentBoneStatus.stabilized) then
                        Log('Stabalized Bone')
                        boneHealthPercent = boneHealthPercent - mpBoneHealth[name].percent * 0.25
                        if (currentBoneStatus.shot == 0 and currentBoneStatus.slash == 0) then
                            boneHealthPercent = boneHealthPercent - mpBoneHealth[name].percent * 0.25
                        end
                    end
                --end
                health = health - ((100.0 - boneHealth) / 100.0) * boneHealthPercent
                health = health - (currentBoneStatus.infection / 100.0) * (boneHealthPercent * 0.333)
            end

            ::CONTINUE::
        end
        self.health = health
    end

    self.updateGameHealth = function()
        if (DoesEntityExist(self.playerPed) and not GetPedResetFlag(self.playerPed, 139) and IsPedFatallyInjured(self.playerPed)) then
            local speed = GetEntitySpeed(self.playerPed)
            if (speed < 0.5 or IsEntityInWater(self.playerPed)) then
                local velocity = GetEntityVelocity(self.playerPed)
                local pCoords = GetEntityCoords(self.playerPed)
                local pHeading = GetEntityHeading(self.playerPed)
                NetworkResurrectLocalPlayer(pCoords.x, pCoords.y, pCoords.z, pHeading, 0, false, 0, true)
                SetPedToRagdoll(self.playerPed, speed * 100, speed * 100)
                SetEntityVelocity(self.playerPed, velocity.x, velocity.y, velocity.z)
                Log('Ragdolled Because of Speed < 0.5 or In water')
            end
        end
        if not IsPedFatallyInjured(self.playerPed) then
            SetEntityHealth(self.playerPed, GetEntityMaxHealth(self.playerPed))
            SetAttributeCoreValue(self.playerPed, 0, 100)
            SetAttributeCoreValue(self.playerPed, 1, 100)
            --Log('Reset Health and Stamina')
        end

        if (self.health <= 0 or self.litersOfBlood <= 3) then
            if (not GetPedConfigFlag(self.playerPed, 11) and not IsPedFatallyInjured(self.playerPed)) then -- not Knockedout
                SetCurrentPedWeapon(self.playerPed, `WEAPON_UNARMED`, true, 0, false, false ) --Main Hand
                SetCurrentPedWeapon(self.playerPed, `WEAPON_UNARMED`, true, 1, false, false ) --Off Hand
                ClearPedTasksImmediately(self.playerPed)
                SetPedConfigFlag(self.playerPed, 26, true)  --Disable Melee
                SetPedConfigFlag(self.playerPed, 170, true) --DisableGrappleByAi
                TaskKnockedOut(self.playerPed, 30.0, true)
                Log('Knockedout due to Fatal Injury')
            end
        elseif (GetPedConfigFlag(self.playerPed, 11)) then
            SetPedConfigFlag(self.playerPed, 26, false)     --Disable Melee
            SetPedConfigFlag(self.playerPed, 170, false)    --DisableGrappleByAi
            ClearPedTasks(self.playerPed)
            SetPedToRagdoll(self.playerPed, 0, 0, 1, false, true, false)
            Log('Stay Knocked Out')
        end
        
    end

    self.checkUpdatedPed = function()
        local playerPed = PlayerPedId()
        self.playerId = PlayerId()
        if(self.playerPed ~= playerPed) then
            self.playerPed = playerPed
            if IsPedMale(playerPed) then
                self.bones = mpMaleBones
                self.boneNames = mpMaleBoneNames
            else
                self.bone = mpFemaleBones
                self.boneNames = mpFemaleBoneNames
            end

            for boneName, boneInfo in pairs(self.boneNames) do
                boneInfo.index = GetEntityBoneIndexByName(self.playerPed, boneName);
            end
        end
    end

    self.resetHealth = function()
        self.stamina = 100.0

        for boneName, boneInfo in pairs(self.boneNames) do
            self.boneHealth[tostring(boneInfo.id)] = 100.0
            self.boneStatus[tostring(boneInfo.id)] = {
                index = boneInfo.index,
                bulletFragment = 0,
                shot = 0,
                burned = false,
                slash = 0,
                broken = false,
                bandaged = false,
                stabilized = false,
                infected = false,
                infectedBySelf = false,
                infectionMultiplier = 1.0,
                infection = 0.0,
                bleedingParticleId = false,
                bleedingParticleSize = 0.0,
            }
        end
    end

    self.screenFxTick = function()
        local doRagdoll = false
        local ragdollDuration = 0
        local doScreenFx = false

        for name, bone in pairs(self.boneNames) do
            local boneHealth = self.boneHealth[tostring(bone.id)]
            if type(boneHealth) == 'number' then
                if(name == 'SKEL_HEAD' and boneHealth < 50.0) then
                    if not AnimpostfxIsRunning('PlayerRPGCoreDeadEye') then
                        AnimpostfxPlay('PlayerRPGCoreDeadEye')
                    end
                    local strength = lerp(1.0, 0.0, boneHealth / 50.0)
                    AnimpostfxSetStrength('PlayerRPGCoreDeadEye', strength)
                    local chance = lerp(0.004, 0.0, boneHealth / 50.0)
                    if (math.random() < chance) then
                        doScreenFx = true
                        Log('doScreenFx '.. doScreenFx)
                    end
                    if (boneHealth < 10.0 and not IsPedRagdoll(self.playerPed) and math.random() < chance) then
                        ragdollDuration = lerp(5000, 2000, boneHealth / 10.0)
                        doRagdoll = true
                    end
                end
                if(name == 'SKEL_HEAD' and boneHealth > 50.0) then
                    if (AnimpostfxIsRunning('PlayerRPGCoreDeadEye') and self.litersOfBlood >= 4.75) then
                        AnimpostfxStop('PlayerRPGCoreDeadEye')
                    end
                end
            end
        end

        if (self.litersOfBlood < 4.75) then
            if not AnimpostfxIsRunning('PlayerRPGCoreDeadEye') then
                AnimpostfxPlay('PlayerRPGCoreDeadEye')
            end
            local strength = lerp(1.0, 0.0, (self.litersOfBlood - 4.0) / 0.75)
            AnimpostfxSetStrength('PlayerRPGCoreDeadEye', strength)
            local chance = lerp(0.004, 0.0, (self.litersOfBlood - 4.0) / 0.75)

            if (math.random() < chance) then
                if (self.litersOfBlood < 3.825 and not IsPedRagdoll(self.playerPed) and math.random() < chance * 25.0 ) then
                    ragdollDuration = lerp(5000, 2000, (self.litersOfBlood - 3.5) / 0.325);
                    doRagdoll = true
                end
                doScreenFx = true
            end
        end

        if doScreenFx then
            DoScreenFadeOut(375);
            Wait(500)
            DoScreenFadeIn(375);
            AnimpostfxPlay('RespawnMissionCheckpoint')
            Wait(5000)
        end
    end

    self.randomBone = function()
        local boneIds = {}
        for boneId, boneName in pairs(self.bones) do
            if boneName:startswith('SKEL_') then
                boneIds[#boneIds + 1] = boneId
            end
        end

        return boneIds[floor(math.random() * #boneIds)]
    end

    self.damageBone = function(boneId, damage)
        local boneHealth = self.boneHealth[tostring(boneId)]
        if not boneHealth then return end
        local damage = damage or 10 
        self.boneHealth[tostring(boneId)] = clamp(boneHealth - damage, 0, 100)
    end

    self.damageBoneByName = function(boneName, damage)
        local bone  = self.boneNames[tostring(boneName)]
        local damage = damage or 10
        self.damageBone(tostring(bone.id), damage)
    end

    self.shootBoneByName = function(boneName)
        local bone = self.boneNames[tostring(boneName)]
        local boneStatus = self.boneStatus[tostring(bone.id)]
        if not boneStatus then
            print('Invalid Bone Status')
            return 
        end

        boneStatus.shot = boneStatus.shot + 1
        Log('Shot Bone : '..boneName)
    end

    self.getBoneNameFromId = function(boneId)
        return self.bones[tostring(boneId)]
    end
    
    self.checkForBoneDamage = function(modifier, force, damageType, infect, infectionMultiplier, boneId)
        local hasBoneOverride = not(not boneId)
        local hasDamagedBone
        local damagedBoneId

        if hasBoneOverride then
            hasDamagedBone = true
            damagedBoneId = boneId
        else
            hasDamagedBone, damagedBoneId = GetPedLastDamageBone(self.playerPed)
        end

        if (not hasDamagedBone or not self.bones[tostring(damagedBoneId)]) then
            Log('Failed To Get Bone Damage : '..damagedBoneId)
            return
        end

        if damageType == 'FIRE' then
            damagedBoneId = self.randomBone()
        end

        local boneName = self.bones[tostring(damagedBoneId)]

        if not boneName then 
            Log('Invalid Bone Name '..boneName)
            return 
        end

        local redirectBone = boneRedirection[tostring(boneName)]

        if redirectBone then
            boneName = redirectBone
            damagedBoneId = self.boneNames[tostring(redirectBone)].id
        end

        local boneHealth = self.boneHealth[tostring(damagedBoneId)]
        if not boneHealth then 
            Log('Invalid Bone Health '..damagedBoneId)
            return 
        end

        local boneStatus = self.boneStatus[tostring(damagedBoneId)]
        if not boneStatus then 
            Log('Invalid Bone Status '..damagedBoneId)
            return 
        end

        local boneDamage = (1 + math.random() * 2) * mpBoneHealth[tostring(boneName)].multiplier * modifier
        local newBoneHealth = boneHealth - boneDamage

        if ((boneDamage > 20 or boneHealth < 25) and boneStatus.stabilized) then
            boneStatus.stabilized = false
        end

        self.boneHealth[tostring(damagedBoneId)] = clamp(newBoneHealth, 0, 100)

        if damageType == 'GUN' then
            boneStatus.shot = boneStatus.shot + 1
            boneStatus.bandaged = false
            if (math.random() < boneBulletFragmentChance[tostring(boneName)]) then
                boneStatus.bulletFragment = boneStatus.bulletFragment + 1
            end
        end

        if damageType == 'SHARP' then
            Log('SHARP damage Registered')
            boneStatus.slash = boneStatus.slash + 1
        end

        if damageType == 'EXPLOSIVE' then
            Log('EXPLOSIVE damage Registered')
            self.damageNearby(boneName, damagedBoneId, modifier)
        end

        if damageType == 'FIRE' then
            Log('FIRE damage Registered')
            boneStatus.burned = true
        end

        if damageType == 'FALL' then
            Log('Fall Damage Caused')
        end

        if (damageType == 'FALL' and modifier > 8 + math.random() * 3) then
            Log('FALL damage broken Bone')
            boneStatus.broken = true
        end

        if infect then
            boneStatus.infectedBySelf = false
            boneStatus.infected = true
            boneStatus.infectionMultiplier = infectionMultiplier
        end

        if boneName == 'SKEL_HEAD' then
            if math.random() < 0.3 then 
                AnimpostfxPlay('RespawnPulse01') 
            else 
                AnimpostfxPlay('MP_SuddenDeath') 
            end
            UseParticleFxAsset('scr_winter2')
            local x = (math.random() - 0.5) * 0.1
            local z = (math.random() - 0.5) * 0.2
            local particleFxId = StartNetworkedParticleFxLoopedOnEntityBone('scr_blood_drips', self.playerPed, x, 0.1, z, 0.0, 0.0, 0.0, tonumber(damagedBoneId), 0.5, false, false, false)
            SetTimeout(1500, function()
                if (DoesParticleFxLoopedExist(particleFxId)) then
                    StopParticleFxLooped(particleFxId, false)
                end
            end)
        elseif (boneDamage >  50) then
            AnimpostfxPlay('MP_HealthDrop')
        end

        if not hasBoneOverride then
            ClearPedLastDamageBone(self.playerPed)
        end
    end

    self.getRedirectBone = function(boneName, boneId)
        if boneRedirection[tostring(boneName)] then
            boneName = boneRedirection[tostring(boneName)]
            boneId = self.boneNames[tostring(boneName)].id
        end

        return {boneName, boneId}
    end

    self.damageNearby = function(boneName, boneId, damage)
        local boneData = self.getRedirectBone(boneName, tostring(boneId))
        local boneName, boneId = boneData[1], boneData[2]

        local currentDamaged = { [tostring(boneId)] = true }

        local bones = { [tostring(boneName)] = boneId }
        Log('Damaged Nearby : boneName :'..boneName)
        for n = 1, 10, 1 do
            damage = damage * 0.666
            if damage >= 0.5 then
                local newBones = {}
                for boneName, boneId in pairs(bones) do
                    local attachedTo = self.boneNames[tostring(boneName)]?.attachedTo
                    if attachedTo then 
                        for _, attachedBoneName in pairs(attachedTo) do
                            boneName = attachedBoneName
                            boneId = self.boneNames[attachedBoneName].id
                            if not currentDamaged[tostring(boneId)] then
                                currentDamaged[tostring(boneId)] = true
                                newBones[tostring(boneName)] = tostring(boneId)
                                Log('Also Damage '..n..". "..boneName..' for '..damage)
                                self.checkForBoneDamage(damage, nil, 'FALL', nil, nil, tostring(boneId))
                            end
                        end
                    end
                end
                bones = newBones
            end
        end
    end

    self.damageNearbyFromFall = function(boneName, boneId, fallHeight)
        local boneData = self.getRedirectBone(boneName, tostring(boneId))
        local boneName, boneId = boneData[1], boneData[2]

        local currentDamaged = { [tostring(boneId)] = true }

        local bones = { [tostring(boneName)] = boneId }

        for n = 1, 10, 1 do
            local damageModifier = fallHeight - n * 4
            if (damageModifier > 3) then
                local newBones = {}
                for boneName, boneId in pairs(bones) do
                    local attachedTo = self.boneNames[boneName]?.attachedTo
                    if attachedTo then
                        for _, attachedBoneName in pairs(attachedTo) do
                            boneName = attachedBoneName
                            boneId = self.boneNames[attachedBoneName].id
                            if not currentDamaged[tostring(boneId)] then
                                currentDamaged[tostring(boneId)] = true
                                newBones[tostring(boneName)] = tostring(boneId)
                                Log('Also Damage '..n..". "..boneName..' for '..damageModifier)
                                self.checkForBoneDamage(damageModifier, nil, 'FALL', nil, nil, tostring(boneId))
                            end
                        end
                    end
                end
                bones = newBones
            end
        end
    end

    self.damageNearbyFromFallBoneId = function(boneId, fallHeight)
        local boneName = self.getBoneNameFromId(tostring(boneId))
        self.damageNearbyFromFall(boneName or 'SKEL_SPINE4', boneId, fallHeight)
    end

    self.handleBoneTick = function(delta)
        local healthPercent = self.health / 100.0

        local currentlyBleeding = false
        local bloodRecoveryMultiplier = 1.0
        local bloodLossMultiplier = 0.25
        local hasBrokenBone = false

        for name, bone in pairs(self.boneNames) do
            if (not name:startswith('SKEL_') or not self.boneStatus[tostring(bone.id)]) then
                Log('Skipped Handle Bone Tick 1') 
                goto CONTINUEBONETICK
            end

            local currentLimboInfo = {}
            if lib.table.contains(injuryLimbBones, name) then
                currentLimbInfo = injuryLimbInfo
            elseif lib.table.contains(injuryBodyBones, name) then
                currentLimbInfo = injuryBodyInfo
            elseif lib.table.contains(injuryHeadBones, name) then
                currentLimbInfo = injuryHeadInfo
            elseif lib.table.contains(injuryOtherBones, name) then
                currentLimbInfo = injuryOtherInfo
            end

            local currentLimbBoneInfo = {recoveryMultiplier = 1.0}

            local currentBoneStatus = self.boneStatus[tostring(bone.id)]
            if not currentBoneStatus then
                Log('Skipped Handle Bone Tick 2') 
                goto CONTINUEBONETICK 
            end

            local boneHealth = self.boneHealth[tostring(bone.id)]
            if not boneHealth then 
                Log('Skipped Handle Bone Tick 3') 
                goto CONTINUEBONETICK 
            end

            for _, info in pairs(currentLimbInfo) do
                if boneHealth <= info.threshold then
                    currentLimbBoneInfo = info
                    if info.boneBroken then
                        Log('Broken Bone Registered')
                        currentBoneStatus.broken = true
                        hasBrokenBone = true
                    end
                    break
                end
            end

            if self.health <= 0 then
                currentLimbBoneInfo.recoveryMultiplier = 0
            end

            local baseMultiplier = 0.0
            if (currentBoneStatus.shot > 0 or currentBoneStatus.slash > 0) then
                bloodRecoveryMultiplier = 0.1
                if currentBoneStatus.bandaged then
                    baseMultiplier = baseMultiplier + 0.25
                    if (not currentBoneStatus.broken and (not currentBoneStatus.burned or boneHealth > 85)) then
                        baseMultiplier = baseMultiplier + 0.5
                    end
                else
                    local movementSpeed = GetEntitySpeed(self.playerPed)
                    bloodLossMultiplier = lerp(0.25, 1.0, movementSpeed / 7.5)
                    if IsPedInAnyTrain(self.playerPed) then
                        bloodLossMultiplier = 0.25
                    elseif IsPedOnFoot(self.playerPed) then
                        bloodLossMultiplier = bloodLossMultiplier * 0.333
                        bloodLossMultiplier = math.max(0.25, bloodLossMultiplier)
                    end

                    local bloodToRemove = (currentBoneStatus.shot + currentBoneStatus.slash) * (0.00125 * delta) * bloodLossMultiplier
                    self.litersOfBlood = self.litersOfBlood - bloodToRemove
                    --Log('Updated Blood '..bloodToRemove)

                    if (math.random() < math.min(bloodToRemove * 100, 0.1)) then
                        SetPedActivateWoundEffect(
                            self.playerPed,
                            2,
                            tonumber(bone.id),
                            0.0,
                            0.0,
                            0.0,
                            -1.0,
                            0.0,
                            0.0,
                            math.min(bloodToRemove * 500, 0.999)
                        )
                    end
                    if self.litersOfBlood < 0 then
                        self.litersOfBlood = 0
                    end
                    currentlyBleeding = true
                end
            else
                UpdatePedWoundEffect(self.playerPed, 0.0)
            end

            if (currentBoneStatus.broken and currentBoneStatus.stabilized) then
                baseMultiplier = baseMultiplier + 0.25

                if (currentBoneStatus.shot == 0 and currentBoneStatus.slash == 0 and (not currentBoneStatus.burned or boneHealth > 85)) then
                    baseMultiplier = baseMultiplier + 0.5
                end
            end

            if (currentBoneStatus.burned and currentBoneStatus.bandaged) then
                baseMultiplier = baseMultiplier + 0.25
                if (currentBoneStatus.shot == 0 and currentBoneStatus.slash == 0 and not currentBoneStatus.broken) then
                    baseMultiplier = baseMultiplier + 0.5
                end
            end

            if (currentBoneStatus.shot == 0 and currentBoneStatus.slash == 0 and not currentBoneStatus.broken and (not currentBoneStatus.burned or boneHealth > 85)) then
                baseMultiplier = baseMultiplier + 0.75
            end 

            if (currentBoneStatus.infected) then
                if(self.infectionStabilized) then
                    baseMultiplier = baseMultiplier * ((100.0 - currentBoneStatus.infection) / 100.0)
                    currentBoneStatus.infection = currentBoneStatus.infection - 0.175 * delta
                    if (currentBoneStatus.infection <= 0) then
                        currentBoneStatus.infection = 0
                        currentBoneStatus.infected = false
                    end
                else
                    baseMultiplier = 0.0
                    currentBoneStatus.infection = currentBoneStatus.infection + 0.25 * delta * currentBoneStatus.infectionMultiplier
                    if (math.random() < 0.01 * (currentBoneStatus.infection / 100.0)) then
                        local attachedBones = bone.attachedTo
                        if attachedBones then
                            local infectBoneName = attachedBones[floor(math.random() * #attachedBones)]
                            local infectBone = self.boneNames[tostring(infectBoneName)]
                            local infectBoneStatus = self.boneStatus[tostring(infectBone.id)]
                            if infectBoneStatus?.infected == false then
                                Log('Infect Nearby Bone '.. infectBoneName)
                                infectBoneStatus.infected = true
                            end
                        end
                    end
                end
                currentBoneStatus.infection = clamp(currentBoneStatus.infection, 0, 100)
                if (currentBoneStatus.stabilized and currentBoneStatus.infection <= 0.0) then
                    currentBoneStatus.infected = false
                    currentBoneStatus.infectionMultiplier = 1.0
                end
            end
            if (baseMultiplier > 0 and boneHealth < 100) then
                local boneHealthMultiplier = mpBoneHealth[tostring(name)].percent / 100
                -- Do Food and Thirst Here
                if (self.food > 0.0) then
                    baseMultiplier += 0.1
                    self.food -= 0.075 * delta * boneHealthMultiplier
                end
            end
            baseMultiplier = baseMultiplier * self.recoveryMultiplier

            local newBoneHealth = boneHealth + 0.25 * delta * baseMultiplier * currentLimbBoneInfo.recoveryMultiplier

            self.boneHealth[tostring(bone.id)] = clamp(newBoneHealth, 0, 100)

            if newBoneHealth >= 100.0 then
                local newBoneStatus = self.boneStatus[tostring(bone.id)] or currentBoneStatus
                newBoneStatus.bandaged = false
                newBoneStatus.stabilized = false
                newBoneStatus.broken = false
                newBoneStatus.burned = false
                newBoneStatus.shot = 0
                newBoneStatus.slash = 0

                self.boneStatus[tostring(bone.id)] = newBoneStatus
            end

            ::CONTINUEBONETICK::
        end

        self.hasBrokenBone = hasBrokenBone
        if (not currentlyBleeding and self.litersOfBlood < 5.0) then
            -- Add Water Recovery Here
            if (self.water > 0.0) then
                bloodRecoveryMultiplier += 0.2
                self.water -= 0.1 * delta
            end
            
            local newLitersOfBlood = self.litersOfBlood + healthPercent * 0.0125 * delta * bloodRecoveryMultiplier
            self.litersOfBlood = clamp(newLitersOfBlood, 0, 5)
        end

        self.isBleeding = currentlyBleeding
    end

    self.isBoneHealthUnderN = function(boneName, n)
        local boneInfo = self.boneNames[boneName]
        local boneHealth = self.boneHealth[tostring(boneInfo.id)]
        if type(boneHealth) == 'number' then
            if boneHealth < n then return true end
        end
        return false
    end

    self.isBonesHealthUnderN = function(boneNames, n)
        local healthAverage = 0
        for _, boneName in pairs(boneNames) do
            local boneInfo = self.boneNames[boneName]
            boneHealth = self.boneHealth[tostring(boneInfo.id)]
            if type(boneHealth) == 'number' then
                healthAverage = healthAverage + boneHealth
            end
        end

        healthAverage = healthAverage / #boneNames

        return healthAverage < n
    end

    self.checkWalkCycle = function()
    end

    self.handleDamageEvent = function(attacker, attacked, weaponHash, ammoHash, x, y, z)
        -- Damage Handler for Fist Fight
        if (attacker == self.playerPed and weaponHash == `WEAPON_UNARMED` and IsPedInMeleeCombat(self.playerPed)) then
            for _, name in pairs({'SKEL_R_HAND', 'SKEL_L_HAND'}) do
                local bone = self.boneNames[name]
                local boneHealth = self.boneHealth[tostring(bone.id)]
                if (not boneHealth and boneHealth ~= 0) then goto CONTINUE end

                if boneHealth > 0 then
                    self.damageBone(tostring(bone.id), math.random() * 4)
                elseif bone.attachedTo then
                    for _, attachedName in pairs(bone.attachedTo) do
                        self.damageBoneByName(attachedName, math.random() * 4)
                    end
                end
                ::CONTINUE::
            end
            return
        end

        if (attacked ~= self.playerPed or weaponHash == `WEAPON_FALL`) then return end

        local attackDistance = 0.0

        local weaponStats = WeaponsInfo[tostring(weaponHash)] or WeaponsInfo['DEFAULT']

        if weaponStats.effectiveRange then
            local attackerCoord = GetEntityCoords(attacker)
            local attackedCoord = GetEntityCoords(attacked)

            attackDistance = #(attackerCoord - attackedCoord)

            Log('Attack Distance '.. attackDistance)
        end

        local damageModifier = weaponStats.modifier
        local damageType = weaponStats.damageType

        Log(damageType)

        if (self.health <= 0 and damageType == 'GUN') then return end

        if (damageType == 'BLUNT' and damageModifier > 4.0) then
            AnimpostfxPlay('CamTransitionBlink')
        end

        local infect = false
        local infectionMultiplier = 0.0
        local attackerModel = GetEntityModel(attacker)

        if WildLifeInfo[tostring(attackerModel)] then
            Log('Attacked by Animal')
            damageModifier = WildLifeInfo[tostring(attackerModel)].modifier
            damageType = WildLifeInfo[tostring(attackerModel)].damageType
            if WildLifeInfo[tostring(attackerModel)].infectious then
                infect = true
                infectionMultiplier = WildLifeInfo[tostring(attackerModel)].infectionMultiplier or 0.75
            end
        elseif IsThisModelAHorse(attackerModel) == true then
            Log('Attacked by Horse')
            damageModifier = HorseInfo.modifier
            damageType = HorseInfo.damageType
        end

        if weaponStats.name == 'WEAPON_RUN_OVER_BY_CAR' then
            local velocity = GetEntitySpeed(attacker)
            local min, max = GetModelDimensions(attackerModel)
            local maxBounding = VectorSub(max,min)

            local cartVolume = maxBounding.x * maxBounding.y * maxBounding.z

            damageModifier = (cartVolume / 3) * lerp(0.25, 1, velocity / 20)
        end

        if attackDistance > 0.0 then
            local effectiveRange = weaponStats.effectiveRange
            if effectiveRange then
                local difference = 0
                if (attackDistance < effectiveRange.min) then
                        difference = math.abs(attackDistance - effectiveRange.min)
                    else if (attackDistance > effectiveRange.max) then
                        difference = math.abs(attackDistance - effectiveRange.max)
                    end
                    if (difference > 0) then
                        damageModifier = damageModifier - (difference * effectiveRange.falloff)
                        damageModifier = math.max(effectiveRange.minModifier or 0.1, damageModifier)
                    end
                end
            end
        end

        Log('Player '.. attacked ..' attack by '..attacker..' damageType : '..damageType..' modifier : '..damageModifier)

        self.checkForBoneDamage(damageModifier, false, damageType, infect, infectionMultiplier)
        ClearEntityLastDamageEntity(self.playerPed)
    end 

    self.checkMoveSpeedSkels = function()
        local boneSpeedLimit = 3
        for _, moveSpeedSkel in pairs(moveSpeedSkels) do
            local boneInfo = self.boneNames[moveSpeedSkel]
            local boneHealth = self.boneHealth[tostring(boneInfo.id)]
            if (not boneHealth and boneHealth ~= 0) then
                goto CONTINUE
            end
            boneSpeedLimit = boneSpeedLimit - lerp(0.25, 0.0, boneHealth / 100)

            ::CONTINUE::
        end

        if LocalPlayer.state.boneSpeedLimit ~= boneSpeedLimit then
            LocalPlayer.state.boneSpeedLimit = boneSpeedLimit
        end
    end

    self.checkHandShakeSkels = function()
        local handShake = 0
        if IsPlayerFreeAiming(self.playerId) then
            for _, handShakeSkel in pairs(handShakeSkels) do
                local boneInfo = self.boneNames[handShakeSkel]
                local boneHealth = self.boneHealth[tostring(boneInfo.id)]
                if (not boneHealth and boneHealth ~= 0) then
                    goto CONTINUE
                end
                handShake = handShake + lerp(0.2, 0.0, boneHealth / 100)

                ::CONTINUE::
            end

            handShake = math.floor(handShake * 100) / 100

        end

        if handShake ~= lastHandShake then
            ShakeGameplayCam('HAND_SHAKE', handShake)
            lastHandShake = handShake
        end
    end

    self.triggerFallDamage = function(fallHeight, damagedBoneId)
        if (damagedBoneId == 0 or damagedBoneId == 694201337) then
            damagedBoneId = self.randomBone()
        end

        local boneName = self.bones[tostring(damagedBoneId)]

        if (boneName) then
            Log('Player hit bone '..boneName..' for fall height of '..fallHeight)
            self.checkForBoneDamage(fallHeight, true, 'FALL')
            self.damageNearbyFromFall(boneName, damagedBoneId, fallHeight / 1.5);
        else 
            Log('Bone '..damagedBoneId..' not found in boneNames')
        end
    end

    -----------------------------------------------------------------
    -------------------HEALING SYSTEM--------------------------------
    -----------------------------------------------------------------
    -- Stabalize Specific Broken Bone
    self.splintBoneByName = function(boneName)

    end

    -- Stabalize First Broken Bone
    self.splintBone = function()

    end

    -- Badnage Specific Shot/Slash/Burn Bone with a mentioned chance of infection
    self.bandageBoneByName = function(boneName, infectionChance)

    end

    -- Badnage First Shot/Slash/Burn Bone with a mentioned chance of infection
    self.bandageBone = function(infectionChance)
        
    end

    -- FULL FIX FUNCTIONS --
    self.splintBoneAll = function()

    end

    self.bandageBoneAll = function()

    end

    -- Individual Damage Fix
    self.healShotBone = function(boneName)

    end

    self.healSlashBone = function(boneName)

    end

    self.healBurnBone = function(boneName)
        
    end





    self.stop = function()
        if self.interval then
            Log('Stopped Interval')
            self.interval:forceEnd()
            self.interval = nil
        end
    end

    return self
end