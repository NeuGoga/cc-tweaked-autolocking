-- =================================================================
-- Updater Bootstrap
-- =================================================================

local function ensureUpdater()
    local updater_name = "updater"
    local final_program_name = "player_turret" 
    local startup_name = "startup"
    
    local repo_base_url = "https://raw.githubusercontent.com/NeuGoga/cc-tweaked-autolocking/main/"
    local updater_url = repo_base_url .. updater_name .. ".lua"
    local this_program_url = repo_base_url .. final_program_name .. ".lua"

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

    local expected_startup_content = 'shell.run("'..updater_name..'", "'..this_program_url..'", "'..final_program_name..'")'
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
        sleep(3)
        os.reboot()
        return false
    end
    
    return true
end

if not ensureUpdater() then
    return
end

-- =================================================================
-- Configuration and Setup
-- =================================================================

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

    local offset_vertical = 4.5
    local offset_forward = 3
    local offset_right = 1
    config.cannon = { y = compY + offset_vertical }
    if facing == "south" then
        config.cannon.x = compX + offset_right
        config.cannon.z = compZ + offset_forward
    elseif facing == "north" then
        config.cannon.x = compX - offset_right
        config.cannon.z = compZ - offset_forward
    elseif facing == "east" then
        config.cannon.x = compX + offset_forward
        config.cannon.z = compZ - offset_right
    elseif facing == "west" then
        config.cannon.x = compX - offset_forward
        config.cannon.z = compZ + offset_right
    end
    print("Calculated Cannon Position: " .. config.cannon.x .. ", " .. config.cannon.y .. ", " .. config.cannon.z)

    config.secretKey = prompt("Enter a secret key for network security")
    config.networkChannel = tonumber(prompt("Enter network channel (e.g., 10)"))
    
    config.barrelLength = 0
    while config.barrelLength <= 0 do
        config.barrelLength = tonumber(prompt("Enter number of barrel blocks (e.g., 2)"))
        if not config.barrelLength or config.barrelLength <= 0 then
            print("Invalid number. Please enter a positive number.")
        end
    end

    config.detectionRange = 150

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
        if pType == "playerDetector" and not entDet then
            entDet = peripheral.wrap(name); print("Player Detector assigned.")
        elseif pType == "blockReader" and not blockReader then
            blockReader = peripheral.wrap(name); print("Block Reader assigned.")
        elseif pType == "monitor" and not mon then
            mon = peripheral.wrap(name)
        elseif pType == "redstone_relay" and not lever then
            lever = peripheral.wrap(name); print("Redstone Relay assigned.")
        elseif pType == "modem" and not modem then
            modem = peripheral.wrap(name)
        end
    end
end

assignPeripherals()

if not (yaw and pitch and blockReader and entDet and mon and lever and modem) then
    print("Error: Missing one or more required peripherals!"); return
end

print("All peripherals found.")
mon.clear(); mon.setCursorPos(1, 1); mon.write("System Ready. Made by NeuGoga."); sleep(2)

-- =================================================================
-- Constants and Globals
-- =================================================================

local RPM_STEPS = {128, 64, 32, 16, 8, 4, 2}
local OVERSHOOT_TOLERANCE = 0.5
local SAFETY_MARGIN = 0.3
local MIN_PITCH = -45.0
local MAX_PITCH = 90.0
local GRAVITY = 10.0
local DRAG_MULTIPLIER = 0.99
local SIMULATION_TIME_STEP = 0.05
local MAX_SIMULATION_TICKS = 400
local AIM_ITERATIONS = 15
local TARGET_Y_OFFSET = 0.9
local MAX_POS_HISTORY = 5

local availableRanges = {25, 50, 100, 150}
local currentRangeIndex = 4
for i, range in ipairs(availableRanges) do if range == config.detectionRange then currentRangeIndex = i; break end end

local isEngaged = false
local relYaw, relPitch = 0, 0
local playerData = {}
local whitelist = {}
local targets = {}
local whitelistPlayers = {}
local processed_timestamps = {}
local targetsScrollOffset = 0
local whitelistScrollOffset = 0

-- =================================================================
-- Core Utility & Rotation Functions
-- =================================================================

local function simpleHash(str)
    local hash = 5381
    for i = 1, #str do
        hash = (hash * 33) + string.byte(str, i)
        hash = bit.band(hash, 0xFFFFFFFF)
    end
    return tostring(hash)
end

local function generateSignature(message, key)
    return simpleHash(message .. key)
end

local function loadWhitelist()
    if fs.exists("whitelist.txt") then
        local file = fs.open("whitelist.txt", "r")
        whitelist = textutils.unserialize(file.readAll()) or {}
        file.close()
    else
        fs.open("whitelist.txt", "w").close()
    end
end

local function saveWhitelist()
    local file = fs.open("whitelist.txt", "w")
    file.write(textutils.serialize(whitelist))
    file.close()
end
loadWhitelist()

local function isPlayerExcluded(name)
    for _, wName in ipairs(whitelist) do
        if name == wName then return true end
    end
    return false
end

local function setPitch()
    local targetAngle = math.max(MIN_PITCH, math.min(MAX_PITCH, relPitch))
    local blockData = blockReader.getBlockData()
    if not blockData or not blockData.CannonPitch then return end
    local canPitch = tonumber(blockData.CannonPitch)
    if not canPitch then return end
    
    local lastTime = os.clock()
    while math.abs(canPitch - targetAngle) > OVERSHOOT_TOLERANCE do
        local error = targetAngle - canPitch
        local currentTime = os.clock()
        local tickTime = currentTime - lastTime
        lastTime = currentTime
        
        local rpmToUse = RPM_STEPS[#RPM_STEPS]
        for i = 1, #RPM_STEPS do
            local rpmPerTick = RPM_STEPS[i] / 8 * 360 / 60 * tickTime
            if rpmPerTick < (math.abs(error) - SAFETY_MARGIN) then
                rpmToUse = RPM_STEPS[i]
                break
            end
        end
        
        local direction = (error > 0) and -1 or 1
        if config.facing == "north" or config.facing == "west" then
            direction = -direction
        end
        pitch.setTargetSpeed(rpmToUse * direction)
        sleep(0.05)
        
        blockData = blockReader.getBlockData()
        if not blockData or not blockData.CannonPitch then break end
        canPitch = tonumber(blockData.CannonPitch)
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
    
    local lastTime = os.clock()
    local error = calculateShortestYawError(relYaw, canYaw)
    while math.abs(error) > OVERSHOOT_TOLERANCE do
        local currentTime = os.clock()
        local tickTime = currentTime - lastTime
        lastTime = currentTime
        
        local rpmToUse = RPM_STEPS[#RPM_STEPS]
        for i = 1, #RPM_STEPS do
            local rpmPerTick = RPM_STEPS[i] / 8 * 360 / 60 * tickTime
            if rpmPerTick < (math.abs(error) - SAFETY_MARGIN) then
                rpmToUse = RPM_STEPS[i]
                break
            end
        end
        
        local direction = (error > 0) and -1 or 1
        if config.facing == "north" or config.facing == "west" then
            direction = -direction
        end
        yaw.setTargetSpeed(rpmToUse * direction)
        sleep(0.05)
        
        blockData = blockReader.getBlockData()
        if not blockData or not blockData.CannonYaw then break end
        canYaw = (tonumber(blockData.CannonYaw) + 360) % 360
        error = calculateShortestYawError(relYaw, canYaw)
    end
    yaw.setTargetSpeed(0)
end

-- =================================================================
-- Monitor, Network, and Targeting Logic
-- =================================================================
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
        mon.write(string.format("TGT: %s (%d,%d,%d)", target.name, target.x, target.y, target.z))
    else
        mon.write("No Target in Range")
    end
    
    mon.setCursorPos(1, 4); mon.write("Range: <- " .. config.detectionRange .. " ->")
    
    mon.setCursorPos(1, 6); mon.write("Targets:")
    mon.setCursorPos(15, 6); mon.write("Whitelist:")
    
    targets, whitelistPlayers = {}, {}
    for _, pName in ipairs(entDet.getPlayersInRange(config.detectionRange)) do
        if isPlayerExcluded(pName) then table.insert(whitelistPlayers, pName)
        else table.insert(targets, pName) end
    end
    
    mon.setCursorPos(1, 7); mon.write("^")
    for i = 1, 4 do
        mon.setCursorPos(1, 7 + i); mon.write(targets[i + targetsScrollOffset] or "")
    end
    mon.setCursorPos(1, 12); mon.write("v")

    mon.setCursorPos(15, 7); mon.write("^")
    for i = 1, 4 do
        mon.setCursorPos(15, 7 + i); mon.write(whitelist[i + whitelistScrollOffset] or "")
    end
    mon.setCursorPos(15, 12); mon.write("v")
end

local function handleMonitorTouch()
    while true do
        local _, _, x, y = os.pullEvent("monitor_touch")
        if y == 1 then
            if x >= 1 and x <= 11 then broadcastEngagementState()
            elseif x >= 15 and x <= 21 then fs.delete(CONFIG_FILE); fs.delete("whitelist.txt"); os.reboot() end
        
        elseif y == 4 then
            if x <= 8 then
                currentRangeIndex = currentRangeIndex - 1
                if currentRangeIndex < 1 then currentRangeIndex = #availableRanges end
            elseif x >= 13 then
                currentRangeIndex = currentRangeIndex + 1
                if currentRangeIndex > #availableRanges then currentRangeIndex = 1 end
            end
            config.detectionRange = availableRanges[currentRangeIndex]
            saveConfig()
        
        elseif x < 15 and y == 7 then targetsScrollOffset = math.max(0, targetsScrollOffset - 1)
        elseif x < 15 and y == 12 then targetsScrollOffset = math.max(0, math.min(targetsScrollOffset + 1, #targets - 4))
        elseif x >= 15 and y == 7 then whitelistScrollOffset = math.max(0, whitelistScrollOffset - 1)
        elseif x >= 15 and y == 12 then whitelistScrollOffset = math.max(0, math.min(whitelistScrollOffset + 1, #whitelist - 4))
        
        elseif y > 7 and y < 12 then
            local index
            if x < 15 then
                index = y - 7 + targetsScrollOffset
                if targets[index] then table.insert(whitelist, targets[index]); saveWhitelist() end
            else
                index = y - 7 + whitelistScrollOffset
                if whitelist[index] then table.remove(whitelist, index); saveWhitelist() end
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
                    if msg and msg.timestamp and not processed_timestamps[msg.timestamp] then
                        processed_timestamps[msg.timestamp] = true
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

local function checkForNewTarget()
    local playersInRange = entDet.getPlayersInRange(config.detectionRange) or {}
    for _, pName in ipairs(playersInRange) do
        if not isPlayerExcluded(pName) then
            local pos = entDet.getPlayerPos(pName)
            if pos then
                local time = os.clock()
                playerData[pName] = playerData[pName] or { positions = {} }
                local hist = playerData[pName].positions
                table.insert(hist, { pos = pos, time = time })
                if #hist > MAX_POS_HISTORY then table.remove(hist, 1) end
                local vel = { x = 0, y = 0, z = 0 }
                if #hist > 1 then
                    local o, n = hist[1], hist[#hist]
                    local SIMULATION_TIME_STEP = n.time - o.time
                    if SIMULATION_TIME_STEP > 0.1 then
                        vel.x = (n.pos.x - o.pos.x) / SIMULATION_TIME_STEP
                        vel.y = (n.pos.y - o.pos.y) / SIMULATION_TIME_STEP
                        vel.z = (n.pos.z - o.pos.z) / SIMULATION_TIME_STEP
                    end
                end
                return { name = pName, x = pos.x, y = pos.y, z = pos.z, velocity = vel }
            end
        end
    end
    return nil
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
        vel.x, vel.z = vel.x * DRAG_MULTIPLIER, vel.z * DRAG_MULTIPLIER
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
        local lo_p, hi_p = MIN_PITCH, MAX_PITCH
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

-- =================================================================
-- Main Loop
-- =================================================================
local function turretControl()
    while true do
        local target = checkForNewTarget()
        updateMonitor(target)
        if target and isEngaged then
            lever.setOutput("front", true)
            calculateIterativeBallisticSolution({ x = target.x, y = target.y + TARGET_Y_OFFSET, z = target.z, velocity = target.velocity })
            print(string.format("New Target Solution -> Yaw: %.2f, Pitch: %.2f", relYaw, relPitch))
            parallel.waitForAll(setYaw, setPitch)
        else
            lever.setOutput("front", false)
            yaw.setTargetSpeed(0)
            pitch.setTargetSpeed(0)
        end
        sleep(0.1)
    end
end

parallel.waitForAll(turretControl, listenForNetworkMessages, handleMonitorTouch)