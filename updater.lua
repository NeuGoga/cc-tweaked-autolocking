local args = { ... }
if #args < 1 then
    print("Usage: updater <main_program_to_run>")
    return
end

local main_program_to_run = args[1]
local MANIFEST_URL = "https://raw.githubusercontent.com/NeuGoga/cc-tweaked-autolocking/main/manifest.json"
local LOCAL_MANIFEST_FILE = ".manifest"
local UPDATER_STUB_FILE = ".updater_stub"

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

term.clear(); term.setCursorPos(1, 1); print("Checking for updates...")

if not download(MANIFEST_URL, ".manifest.temp") then print("FATAL: Could not download manifest."); return end
local f = fs.open(".manifest.temp", "r"); local content = f.readAll(); f.close(); fs.delete(".manifest.temp")
local remoteManifest = textutils.unserializeJSON(content)
local localManifest = {}; if fs.exists(LOCAL_MANIFEST_FILE) then 
    local f = fs.open(LOCAL_MANIFEST_FILE, "r"); content = f.readAll(); f.close();
    localManifest = textutils.unserializeJSON(content) or {}
end
if not remoteManifest or not remoteManifest.files then print("FATAL: Invalid remote manifest."); return end

local remoteUpdaterData = remoteManifest.files.updater
local localUpdaterVersion = (localManifest.files and localManifest.files.updater) and localManifest.files.updater.version or "0.0"
if remoteUpdaterData and compareVersions(remoteUpdaterData.version, localUpdaterVersion) then
    print("Updater is outdated. Performing self-update...")
    local stub = fs.open(UPDATER_STUB_FILE, "w"); stub.write([[print("Finalizing update..."); local url, path = ...; local r = http.get(url); local c = r.readAll(); r.close(); fs.delete(path); local f = fs.open(path, "w"); f.write(c); f.close(); print("Updater updated. Restarting..."); sleep(2); shell.run("startup")]]); stub.close()
    shell.run(UPDATER_STUB_FILE, remoteUpdaterData.source, "updater")
    return
end

local files_to_check = {}
local mainProgramData = remoteManifest.files[main_program_to_run]
if not mainProgramData then
    print("FATAL: Program '" .. main_program_to_run .. "' not found in manifest.")
    return
end
table.insert(files_to_check, main_program_to_run)
if mainProgramData.dependencies then
    for _, dep in ipairs(mainProgramData.dependencies) do
        table.insert(files_to_check, dep)
    end
end

for _, filename in ipairs(files_to_check) do
    local remoteData = remoteManifest.files[filename]
    if remoteData then
        local localVersion = (localManifest.files and localManifest.files[filename]) and localManifest.files[filename].version or "0.0"
        if compareVersions(remoteData.version, localVersion) then
            print(string.format("Updating %s (v%s -> v%s)...", filename, localVersion, remoteData.version))
            download(remoteData.source, filename)
        else
            print(string.format("%s is up to date (v%s)", filename, localVersion))
        end
    else
        print("Warning: Dependency '" .. filename .. "' not found in manifest.")
    end
end

local finalManifestFile = fs.open(LOCAL_MANIFEST_FILE, "w"); 
finalManifestFile.write(textutils.serializeJSON(remoteManifest, { pretty = true })); 
finalManifestFile.close()

print("Update check complete.")

print("\nStarting " .. main_program_to_run .. "...")
sleep(1)
shell.run(main_program_to_run)