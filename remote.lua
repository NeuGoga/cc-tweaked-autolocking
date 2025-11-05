-- =================================================================
-- Updater Bootstrap
-- =================================================================

local function ensureUpdater()
    local updater_name = "updater"
    local final_program_name = "remote" 
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
local CONFIG_FILE = "remote_config.json"

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
    term.clear(); term.setCursorPos(1, 1)
    
    local function prompt(message1, message2)
        print(message1)
        term.write((message2 or "") .. ": ")
        return read()
    end

    print("--- Remote Control First-Time Setup ---")
    
    config.networkChannel = tonumber(prompt("Enter Turret Network", "Channel"))
    config.secretKey = prompt("Enter Turret Secret", "Key")

    saveConfig()
    print("Configuration saved!")
    sleep(2)
end

if not loadConfig() then runSetupWizard() end

-- =================================================================
-- Core Logic
-- =================================================================

local modem = peripheral.find("modem")
if not modem then error("No modem found!") end

if not fs.exists("sha256") then
    error("sha256 library not found! Please ensure it is present.")
end

local sha256 = require("sha256")

local function generateSignature(message, key)
    return sha256.hex(message .. key)
end

local function sendToggleCommand()
    local message = {
        type = "request_toggle",
        timestamp = os.epoch("utc"),
    }
    
    local serializedMessage = textutils.serialize(message)
    local signature = generateSignature(serializedMessage, config.secretKey)
    
    modem.transmit(config.networkChannel, config.networkChannel, { message = serializedMessage, signature = signature })
end

-- =================================================================
-- Main Loop
-- =================================================================

local function main()
    term.clear()
    term.setCursorPos(1, 1)
    print("--- Turret Remote ---")
    print("Channel: " .. config.networkChannel)
    term.setCursorPos(1, 4)
    print("Press any key to toggle turrets.")
    
    while true do
        os.pullEvent("key")
        term.setCursorPos(1, 6); term.clearLine(); term.write("Sending command...")
        sendToggleCommand()
        sleep(0.5)
        term.setCursorPos(1, 6); term.clearLine(); term.write("Command sent!")
        sleep(1)
        term.setCursorPos(1, 6); term.clearLine()
    end
end

main()