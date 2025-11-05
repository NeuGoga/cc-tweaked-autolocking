-- =================================================================
-- Updater Bootstrap
-- =================================================================

local function ensureUpdater()
    local updater_name = "updater"
    local final_program_name = "entity_turret" 
    local startup_name = "startup"
    
    local updater_url = "https://raw.githubusercontent.com/NeuGoga/cc-tweaked-autolocking/main/updater.lua"

    local needs_install = false
    if not fs.exists(updater_name) then
        print("Updater not found. Downloading...")
        local response = http.get(updater_url)
        if not response then print("Error: Could not download updater."); return false end
        local content = response.readAll(); response.close()
        local file = fs.open(updater_name, "w"); file.write(content); file.close()
        print("Updater downloaded successfully.")
        needs_install = true
    end

    local expected_startup_content = 'shell.run("'..updater_name..'", "'..final_program_name..'")'
    local startup_content = ""
    if fs.exists(startup_name) then
        local file = fs.open(startup_name, "r"); startup_content = file.readAll(); file.close()
    end
    
    if startup_content ~= expected_startup_content then
        print("Configuring startup file for updates...")
        local file = fs.open(startup_name, "w")
        file.write(expected_startup_content)
        file.close()
        needs_install = true
    end
    
    if needs_install then
        print("Bootstrap complete. Rebooting to initialize updater...")
        sleep(1)
        os.reboot()
        return false
    end
    
    return true
end

if not ensureUpdater() then
    return
end

local config = {}
local CONFIG_FILE = "turret_config.json"

local function saveConfig()
    local file = fs.open(CONFIG_FILE, "w")
    file.write(textutils.serializeJSON(config, { pretty = true }))
    file.close()
end

local function loadConfig()
    if fs.exists(CONFIG_FILE) then
        local file = fs.open(CONFIG_FILE, "r")
        local content = file.readAll()
        file.close()
        config = textutils.unserializeJSON(content)
        if config then return true end
    end
    return false
end

local function runSetupWizard()
    local term = term.current()
    term.clear(); term.setCursorPos(1, 1)
    local function prompt(message)
        term.write(message .. ": ")
        return read()
    end
    print("--- Turret First-Time Setup ---")
    
    local compX = tonumber(prompt("Enter the Computer's X coordinate"))
    local compY = tonumber(prompt("Enter the Computer's Y coordinate"))
    local compZ = tonumber(prompt("Enter the Computer's Z coordinate"))

    local facing
    while not facing do
        local dir = string.lower(prompt("Which way is the computer screen facing? (N/S/E/W)"))
        if dir == "n" then facing = "north" elseif dir == "s" then facing = "south" elseif dir == "e" then facing = "east" elseif dir == "w" then facing = "west" else print("Invalid direction.") end
    end
    config.facing = facing

    local offset_vertical = 4.5; local offset_forward = 3; local offset_right = 1;
    config.cannon = { y = compY + offset_vertical }
    if facing == "south" then config.cannon.x = compX + offset_right; config.cannon.z = compZ + offset_forward
    elseif facing == "north" then config.cannon.x = compX - offset_right; config.cannon.z = compZ - offset_forward
    elseif facing == "east" then config.cannon.x = compX + offset_forward; config.cannon.z = compZ - offset_right
    elseif facing == "west" then config.cannon.x = compX - offset_forward; config.cannon.z = compZ + offset_right
    end
    print("Calculated Cannon Position: " .. config.cannon.x .. ", " .. config.cannon.y .. ", " .. config.cannon.z)

    config.detector = { y = compY - 1 }
    if facing == "south" then config.detector.x = compX + offset_right; config.detector.z = compZ + offset_forward
    elseif facing == "north" then config.detector.x = compX - offset_right; config.detector.z = compZ - offset_forward
    elseif facing == "east" then config.detector.x = compX + offset_forward; config.detector.z = compZ - offset_right
    elseif facing == "west" then config.detector.x = compX - offset_forward; config.detector.z = compZ + offset_right
    end
    print("Calculated Detector Position: " .. config.detector.x .. ", " .. config.detector.y .. ", " .. config.detector.z)

    config.secretKey = prompt("Enter a secret key for network security")
    config.networkChannel = tonumber(prompt("Enter network channel (e.g., 10)"))
    
    config.barrelLength = 0
    while config.barrelLength <= 0 do
        config.barrelLength = tonumber(prompt("Enter number of barrel blocks (e.g., 2)"))
        if not config.barrelLength or config.barrelLength <= 0 then print("Invalid number.") end
    end

    config.detectionRange = 0
    while config.detectionRange <= 0 or config.detectionRange > 64 do
        config.detectionRange = tonumber(prompt("Enter detection range (1-64)"))
        if not config.detectionRange or config.detectionRange <= 0 or config.detectionRange > 64 then print("Invalid number. Must be between 1 and 64.") end
    end

    config.scanCooldown = 0
    while config.scanCooldown <= 0 do
        config.scanCooldown = tonumber(prompt("Enter scan cooldown in seconds (e.g., 1.0)"))
        if not config.scanCooldown or config.scanCooldown <= 0 then print("Invalid number.") end
    end

    saveConfig()
    print("Configuration saved!")

    local progPath = shell.getRunningProgram()
    local startupFile = fs.open("startup", "w")
    startupFile.write('shell.run("' .. progPath .. '")')
    startupFile.close()
    print("Created 'startup' file to run on reboot.")

    print("Rebooting in 3 seconds...")
    sleep(3)
    os.reboot()
end

if not loadConfig() then runSetupWizard() end

-- =================================================================
-- Peripheral Assignment & Global State
-- =================================================================

local yaw, pitch, blockReader, entDet, mon, lever, modem

local function assignPeripherals()
    yaw = peripheral.wrap("left")
    pitch = peripheral.wrap("right")
    for _, name in ipairs(peripheral.getNames()) do
        local pType = peripheral.getType(name)
        if pType == "environmentDetector" and not entDet then entDet = peripheral.wrap(name); print("Environment Detector assigned.")
        elseif pType == "blockReader" and not blockReader then blockReader = peripheral.wrap(name); print("Block Reader assigned.")
        elseif pType == "monitor" and not mon then mon = peripheral.wrap(name)
        elseif pType == "redstoneIntegrator" and not lever then lever = peripheral.wrap(name); print("Redstone Integrator assigned.")
        elseif pType == "modem" and not modem then modem = peripheral.wrap(name)
        end
    end
end

assignPeripherals()

if not (yaw and pitch and blockReader and entDet and mon and lever and modem) then
    print("Error: Missing peripherals! Check: Speed Controllers, Block Reader, Environment Detector, Monitor, Relay, Modem."); return
end

print("All peripherals found.")
mon.clear(); mon.setCursorPos(1, 1); mon.write("System Ready. Made by NeuGoga."); sleep(2)

-- =================================================================
-- Constants and Globals
-- =================================================================

local RPM_STEPS = {256, 192, 128, 96, 64, 32, 16, 8}
local FINAL_APPROACH_RPM = 2
local MIN_PITCH = -45.0
local MAX_PITCH = 90.0
local STATIONARY_DRIFT_TOLERANCE = 0.1

local BRAKE_RPM = -1
local BRAKE_DURATION = 0.001
local BRAKE_EFFECT_DEGREES = 0.075

local OVERSHOOT_TOLERANCE = 0.04
local OVERSHOOT_PER_RPM = 0.0375

local FAST_TURN_THRESHOLD = 3

local GRAVITY = 10.0
local DRAG_MULTIPLIER = 0.99
local SIMULATION_TIME_STEP = 0.05
local MAX_SIMULATION_TICKS = 600
local AIM_ITERATIONS = 30
local MAX_POS_HISTORY = 5
local TIME_PER_SHOT = 0.05
local Y_OFFSET = 0.9

local isEngaged = false
local relYaw, relPitch = 0, 0
local entityData = {}
local targetList = {}
local displayedEntities = {}
local stationaryEntities = {}
local processedTimestamps = {}
local lastScanTime = 0
local cachedEntities = {}
local entitiesScrollOffset = 0
local targetListScrollOffset = 0
local shotFired = 0

-- =================================================================
-- Core Utility, Target List, & Rotation Functions
-- =================================================================

if not fs.exists("sha256") then
    error("sha256 library not found! Please ensure it is present.")
end

local sha256 = require("sha256")

local function generateSignature(message, key)
    return sha256.hex(message .. key)
end

local function loadTargetList()
    if fs.exists("targetlist.txt") then
        local file = fs.open("targetlist.txt", "r")
        targetList = textutils.unserialize(file.readAll()) or {}
        file.close()
    else
        fs.open("targetlist.txt", "w").close()
    end
end

local function saveTargetList()
    local file = fs.open("targetlist.txt", "w")
    file.write(textutils.serialize(targetList))
    file.close()
end
loadTargetList()

local function isEntityOnTargetList(entityName)
    for _, targetName in ipairs(targetList) do
        if entityName == targetName then return true end
    end
    return false
end

local function getMicroRPM(error)
    local x = math.abs(error)
    local ideal_rpm = math.min(math.max(1, 2.8 * x - 0.4), 8)
    -- print("Pitch speed " .. ideal_rpm)
    return ideal_rpm
end

local function setPitch()
    local targetAngle = math.max(MIN_PITCH, math.min(MAX_PITCH, relPitch))
    local blockData = blockReader.getBlockData()
    if not blockData or not blockData.CannonPitch then return end
    local canPitch = tonumber(blockData.CannonPitch)
    if not canPitch then return end

    local error = targetAngle - canPitch
    
    while math.abs(error) > OVERSHOOT_TOLERANCE do
        local motorDirection = (error > 0) and -1 or 1
        if config.facing == "north" or config.facing == "west" then
            motorDirection = -motorDirection
        end
        
        if math.abs(error) > FAST_TURN_THRESHOLD then
            local rpmToUse = FINAL_APPROACH_RPM
            for _, rpm in ipairs(RPM_STEPS) do
                local turnPerTick = (rpm * 6 / 8.0) * SIMULATION_TIME_STEP + rpm * OVERSHOOT_PER_RPM + BRAKE_EFFECT_DEGREES
                if turnPerTick < math.abs(error) then
                    rpmToUse = rpm
                    break
                end
            end

            local predictedOvershoot = rpmToUse * OVERSHOOT_PER_RPM
            local travelDistance = math.abs(error) - predictedOvershoot + BRAKE_EFFECT_DEGREES
            local theoreticalSpeed = (rpmToUse * 6) / 8.0
            
            if travelDistance > 0 and theoreticalSpeed > 0 then
                local duration = travelDistance / theoreticalSpeed
                
                pitch.setTargetSpeed(rpmToUse * motorDirection)
                sleep(duration)
                pitch.setTargetSpeed(BRAKE_RPM * motorDirection)
                sleep(BRAKE_DURATION)
                pitch.setTargetSpeed(0)
                sleep(0.1)
            end
        
        else
            local microRPM = getMicroRPM(error)
            pitch.setTargetSpeed(microRPM * motorDirection)
            sleep(0.05)
        end
        
        blockData = blockReader.getBlockData()
        if not blockData or not blockData.CannonPitch then break end
        canPitch = tonumber(blockData.CannonPitch)
        error = targetAngle - canPitch
        print("Pitch Error: " .. error)
    end
    pitch.setTargetSpeed(0)
end

local function calculateShortestYawError(target, current)
    local error = target - current
    if error > 180 then error = error - 360
    elseif error < -180 then error = error + 360 end
    return error
end

local function setYaw()
    local blockData = blockReader.getBlockData()
    if not blockData or not blockData.CannonYaw then return end
    local canYaw = (tonumber(blockData.CannonYaw) + 360) % 360
    if not canYaw then return end

    local error = calculateShortestYawError(relYaw, canYaw)

    while math.abs(error) > OVERSHOOT_TOLERANCE do
        local motorDirection = (error > 0) and -1 or 1
        
        if math.abs(error) > FAST_TURN_THRESHOLD then
            local rpmToUse = FINAL_APPROACH_RPM
            for _, rpm in ipairs(RPM_STEPS) do
                local turnPerTick = (rpm * 6 / 8.0) * SIMULATION_TIME_STEP + rpm * OVERSHOOT_PER_RPM + BRAKE_EFFECT_DEGREES
                if turnPerTick < math.abs(error) then
                    rpmToUse = rpm
                    break
                end
            end

            local predictedOvershoot = rpmToUse * OVERSHOOT_PER_RPM
            local travelDistance = math.abs(error) - predictedOvershoot + BRAKE_EFFECT_DEGREES
            local theoreticalSpeed = (rpmToUse * 6) / 8.0
            
            if travelDistance > 0 and theoreticalSpeed > 0 then
                local duration = travelDistance / theoreticalSpeed
                
                yaw.setTargetSpeed(rpmToUse * motorDirection)
                sleep(duration)
                yaw.setTargetSpeed(BRAKE_RPM * motorDirection)
                sleep(BRAKE_DURATION)
                yaw.setTargetSpeed(0)
                sleep(0.2)
            end
        else
            local microRPM = getMicroRPM(error)
            yaw.setTargetSpeed(microRPM * motorDirection)
            sleep(0.05)
        end

        blockData = blockReader.getBlockData()
        if not blockData or not blockData.CannonYaw then break end
        canYaw = (tonumber(blockData.CannonYaw) + 360) % 360
        error = calculateShortestYawError(relYaw, canYaw)
        print("Yaw Error: " .. error)
    end
    yaw.setTargetSpeed(0)
end

-- =================================================================
-- Monitor, Network, and Targeting Logic
-- =================================================================

local function safeScanEntities(radius)
    local scanRadius = math.max(1, radius)
    local entities, err = entDet.scanEntities(scanRadius)
    if err then print("Peripheral Error: " .. tostring(err)) end
    
    entities = entities or {}
    for _, entity in pairs(entities) do
        entity.x = entity.x + config.detector.x
        entity.y = entity.y + config.detector.y
        entity.z = entity.z + config.detector.z
    end
    return entities
end

local function drawUI()
    mon.clear()
    mon.setCursorPos(1, 1)
    if isEngaged then mon.setBackgroundColor(colors.red); mon.write(" ENGAGED ")
    else mon.setBackgroundColor(colors.green); mon.write(" DISENGAGED ") end
    mon.setBackgroundColor(colors.orange); mon.setCursorPos(15, 1); mon.write(" RESET ")
    mon.setBackgroundColor(colors.black)
end

local function updateMonitor(target)
    drawUI()
    mon.setCursorPos(1, 2)
    if target then
        mon.write("Target: " .. target.name)
        mon.setCursorPos(1, 3); mon.write(string.format("Pos: %d, %d, %d", target.x, target.y, target.z))
    else
        mon.write("No Target in Range")
    end
    
    mon.setCursorPos(1, 5); mon.write("Entities:")
    mon.setCursorPos(15, 5); mon.write("Target List:")
    
    displayedEntities = {}
    local namesSeen = {}
    for _, entity in pairs(cachedEntities) do
        if not isEntityOnTargetList(entity.name) and not namesSeen[entity.name] then
            table.insert(displayedEntities, entity.name)
            namesSeen[entity.name] = true
        end
    end
    table.sort(displayedEntities)

    mon.setCursorPos(1, 6); mon.write("^")
    for i = 1, 5 do
        mon.setCursorPos(1, 6 + i); mon.write(displayedEntities[i + entitiesScrollOffset] or "")
    end
    mon.setCursorPos(1, 12); mon.write("v")

    mon.setCursorPos(15, 6); mon.write("^")
    for i = 1, 5 do
        mon.setCursorPos(15, 6 + i); mon.write(targetList[i + targetListScrollOffset] or "")
    end
    mon.setCursorPos(15, 12); mon.write("v")
end

local function handleMonitorTouch()
    while true do
        local _, _, x, y = os.pullEvent("monitor_touch")
        if y == 1 then
            if x >= 1 and x <= 11 then broadcastEngagementState()
            elseif x >= 15 and x <= 21 then fs.delete(CONFIG_FILE); fs.delete("targetlist.txt"); os.reboot() end
         elseif x < 15 and y == 6 then
            entitiesScrollOffset = math.max(0, entitiesScrollOffset - 1)
        elseif x < 15 and y == 12 then
            entitiesScrollOffset = math.max(0, math.min(entitiesScrollOffset + 1, #displayedEntities - 5))
        elseif x >= 15 and y == 6 then
            targetListScrollOffset = math.max(0, targetListScrollOffset - 1)
        elseif x >= 15 and y == 12 then 
            targetListScrollOffset = math.max(0, math.min(targetListScrollOffset + 1, #targetList - 5))

        elseif y > 6 and y < 12 then
            local index
            if x < 15 then
                index = y - 6 + entitiesScrollOffset
                if displayedEntities[index] then
                    table.insert(targetList, displayedEntities[index]); saveTargetList()
                end
            else
                index = y - 6 + targetListScrollOffset
                if targetList[index] then
                    table.remove(targetList, index); saveTargetList()
                end
            end
        end
    end
end

function broadcastEngagementState()
    isEngaged = not isEngaged
    local msg = { type = "engagement", state = isEngaged, timestamp = os.epoch("utc") }
    local ser = textutils.serialize(msg)
    local sig = generateSignature(ser, config.secretKey)
    modem.transmit(config.networkChannel, config.networkChannel, { message = ser, signature = sig })
    drawUI()
end

local function listenForNetworkMessages()
    modem.open(config.networkChannel)
    while true do
        local _, _, _, _, rx = os.pullEvent("modem_message")
        local ok, err = pcall(function()
            if type(rx) == "table" and rx.message and rx.signature then
                if generateSignature(rx.message, config.secretKey) == rx.signature then
                    local msg = textutils.unserialize(rx.message)
                    if msg and msg.timestamp and not processedTimestamps[msg.timestamp] then
                        processedTimestamps[msg.timestamp] = true
                        if msg.type == "engagement" then
                            if msg.state ~= isEngaged then isEngaged = msg.state; drawUI() end
                        elseif msg.type == "request_toggle" then
                            print("Toggle request received, broadcasting new state.")
                            broadcastEngagementState()
                        end
                    end
                end
            end
        end)
        if not ok then
            printError("Network Error: " .. tostring(err))
            printError("Received problematic message: " .. textutils.serialize(rx))
        end
    end
end

local function updateStationaryStatus()
    local currentlyStationary = {}
    
    for _, entity in pairs(cachedEntities) do
        if isEntityOnTargetList(entity.name) then
            local uuid = entity.uuid
            local currentPos = { x = entity.x, y = entity.y, z = entity.z }

            if not entityData[uuid] then
                entityData[uuid] = { prevPos = currentPos }
            else
                local prevPos = entityData[uuid].prevPos
                
                local deltaX = math.abs(currentPos.x - prevPos.x)
                local deltaY = math.abs(currentPos.y - prevPos.y)
                local deltaZ = math.abs(currentPos.z - prevPos.z)

                if deltaX < STATIONARY_DRIFT_TOLERANCE and
                   deltaY < STATIONARY_DRIFT_TOLERANCE and
                   deltaZ < STATIONARY_DRIFT_TOLERANCE then
                    
                    entity.dist = math.sqrt((entity.x - config.cannon.x)^2 + (entity.z - config.cannon.z)^2)
                    table.insert(currentlyStationary, entity)
                end
                
                entityData[uuid].prevPos = currentPos
            end
        end
    end
    
    stationaryEntities = currentlyStationary
end

local function updateEntityCache()
    if os.clock() - lastScanTime > config.scanCooldown then
        cachedEntities = safeScanEntities(config.detectionRange)
        lastScanTime = os.clock()
        updateStationaryStatus()
    end
end

local function checkForNewTarget()
    if #stationaryEntities == 0 then return nil end

    table.sort(stationaryEntities, function(a, b) return a.dist < b.dist end)
    
    local closestTarget = stationaryEntities[1]
    return {
        name = closestTarget.name,
        x = closestTarget.x,
        y = closestTarget.y,
        z = closestTarget.z,
        velocity = { x = 0, y = 0, z = 0 }
    }
end

local function simulateFlight(pitch_deg, yaw_deg, target_pos, projectile_speed)
    local p_rad, y_rad = math.rad(pitch_deg), math.rad(yaw_deg)
    local vel = { x = math.cos(p_rad) * math.sin(y_rad) * projectile_speed, y = math.sin(p_rad) * projectile_speed, z = math.cos(p_rad) * math.cos(y_rad) * projectile_speed }
    local pos = { x = config.cannon.x, y = config.cannon.y, z = config.cannon.z }
    local h_dist_target = math.sqrt((target_pos.x - pos.x)^2 + (target_pos.z - pos.z)^2)
    
    for i = 1, MAX_SIMULATION_TICKS do
        pos.x = pos.x + vel.x * SIMULATION_TIME_STEP
        pos.y = pos.y + vel.y * SIMULATION_TIME_STEP
        pos.z = pos.z + vel.z * SIMULATION_TIME_STEP
        vel.y = (vel.y - GRAVITY * SIMULATION_TIME_STEP) * DRAG_MULTIPLIER
        vel.x = vel.x * DRAG_MULTIPLIER
        vel.z = vel.z * DRAG_MULTIPLIER
        
        local h_dist_curr = math.sqrt((pos.x - config.cannon.x)^2 + (pos.z - config.cannon.z)^2)
        if h_dist_curr >= h_dist_target then
            return pos.y - target_pos.y, i * SIMULATION_TIME_STEP
        end
    end
    return 9999, 20
end

local function calculateIterativeBallisticSolution(target)
    local barrelSpeeds = { [1] = 120.0, [2] = 150.0 }
    local projectileSpeed
    if config.barrelLength >= 3 then projectileSpeed = 180.0
    else projectileSpeed = barrelSpeeds[config.barrelLength] or 150.0 end

    local dx, dz = target.x - config.cannon.x, target.z - config.cannon.z
    local tof_guess = math.sqrt(dx^2 + dz^2) / projectileSpeed
    for _ = 1, 3 do
        local pred_target = { x = target.x + target.velocity.x * tof_guess, y = target.y + target.velocity.y * tof_guess, z = target.z + target.velocity.z * tof_guess }
        local pdx, pdz = pred_target.x - config.cannon.x, pred_target.z - config.cannon.z
        
        local rawYaw = math.deg(math.atan2(pdz, pdx))
        relYaw = (rawYaw - 90 + 720) % 360
        local lo_p, hi_p = -45.0, 90.0
        local actual_tof = tof_guess
        
        for _ = 1, AIM_ITERATIONS do
            local mid_p = (lo_p + hi_p) / 2
            local h_err, f_time = simulateFlight(mid_p, relYaw, pred_target, projectileSpeed)
            if h_err < 0 then lo_p = mid_p else hi_p = mid_p end
            actual_tof = f_time
        end
        relPitch = (lo_p + hi_p) / 2
        tof_guess = actual_tof
    end
end

local function fireBurst()
    lever.setOutput("back", false)
    sleep(0.1)
    lever.setOutput("back", true)
    sleep(0.5)
end

-- =================================================================
-- Main Loop
-- =================================================================
local function turretControl()
    while true do
        updateEntityCache()
        local target = checkForNewTarget()
        updateMonitor(target)
        if target and isEngaged then
            if (shotFired > 1) then 
                lever.setOutput("front", true)
                shotFired = 0
                target = nil
                sleep(0.1)
            else
                lever.setOutput("front", false)
                calculateIterativeBallisticSolution({ x = target.x, y = target.y - Y_OFFSET, z = target.z, velocity = target.velocity })
                print(string.format("New Target Solution -> Yaw: %.3f, Pitch: %.3f", relYaw, relPitch))
                parallel.waitForAll(setYaw, setPitch)
                fireBurst()
                shotFired = shotFired + 1
            end
        else
            lever.setOutput("front", true)
            lever.setOutput("back", true)
            shotFired = 0
            yaw.setTargetSpeed(0)
            pitch.setTargetSpeed(0)
        end
        sleep(0.1)
    end
end

parallel.waitForAll(turretControl, listenForNetworkMessages, handleMonitorTouch)