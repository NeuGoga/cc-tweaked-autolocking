local args = { ... }
if #args < 2 then
    print("Usage: updater <source_url> <target_filename>")
    return
end

local url = args[1]
local filename = args[2]
local temp_filename = "." .. filename .. ".temp"
local sha256_lib = "sha256"
local sha256_url = "https://raw.githubusercontent.com/NeuGoga/cc-tweaked-autolocking/main/sha256.lua" 

local function drawProgressBar(progress)
    local width = term.getSize() - 7
    local filled = math.floor(width * progress)
    local bar = "[" .. string.rep("=", filled) .. string.rep(" ", width - filled) .. "]"
    term.setCursorPos(1, 3); term.clearLine();
    term.write(bar .. string.format(" %d%%", math.floor(progress * 100)))
end

local function download(url_path, file_path)
    print("Downloading " .. file_path .. "...")
    local response, err = http.get(url_path, nil, true)
    if not response then print("Error: " .. tostring(err)); return false end
    
    local content = response.readAll(); response.close()
    if not content then print("Error: Downloaded file is empty."); return false end
    
    local file = fs.open(file_path, "w"); file.write(content); file.close()
    return true
end

term.clear(); term.setCursorPos(1, 1)
print("Checking for updates for '" .. filename .. "'...")

if not fs.exists(sha256_lib) then
    if not download(sha256_url, sha256_lib) then
        print("Could not download hashing library. Aborting update.")
        if fs.exists(filename) then shell.run(filename) end
        return
    end
    print("Hashing library downloaded.")
end
local sha256 = require(sha256_lib)

local function getFileHash(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "rb"); local c = f.readAll(); f.close();
    return sha256.hex(c)
end

if not download(url, temp_filename) then
    print("\nUpdate check failed. Running local version.")
    if fs.exists(filename) then shell.run(filename) end
    return
end

local remote_hash = getFileHash(temp_filename)
local local_hash = getFileHash(filename)

if remote_hash and remote_hash ~= local_hash then
    print("New version found! Updating...")
    drawProgressBar(0)
    fs.delete(filename); sleep(0.2)
    drawProgressBar(0.5)
    fs.move(temp_filename, filename); sleep(0.3)
    drawProgressBar(1.0)
    print("\nUpdate successful!")
    sleep(0.5)
else
    print("No updates found.")
    fs.delete(temp_filename)
end

print("\nStarting " .. filename .. "...")
sleep(1)
shell.run(filename)