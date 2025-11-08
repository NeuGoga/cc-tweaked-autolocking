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

local function compareVersions(v1, v2)
    local parts1 = {}; for part in string.gmatch(v1, "[^.]+") do table.insert(parts1, tonumber(part)) end
    local parts2 = {}; for part in string.gmatch(v2, "[^.]+") do table.insert(parts2, tonumber(part)) end
    for i = 1, math.max(#parts1, #parts2) do
        local p1 = parts1[i] or 0
        local p2 = parts2[i] or 0
        if p1 > p2 then return true end
        if p1 < p2 then return false end
    end
    return false
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
    print("Updater is outdated. Staging self-update...")
    local stub = fs.open(UPDATER_STUB_FILE, "w")
    stub.write([[
        local url, updater_path, manifest_path, new_version = ...
        
        print("Finalizing update...")
        
        local temp_path = updater_path .. ".temp"
        local response = http.get(url)
        if not response then print("Self-update failed: Download error."); return end
        local content = response.readAll(); response.close()
        if not content or #content == 0 then print("Self-update failed: Empty file."); return end
        local temp_file = fs.open(temp_path, "w"); temp_file.write(content); temp_file.close()
        
        fs.delete(updater_path)
        fs.move(temp_path, updater_path)
        print("Updater file replaced.")
        
        local manifest = {}
        if fs.exists(manifest_path) then
            local mf = fs.open(manifest_path, "r")
            local m_content = mf.readAll(); mf.close()
            manifest = textutils.unserializeJSON(m_content) or {}
        end
        
        manifest.files = manifest.files or {}
        manifest.files.updater = manifest.files.updater or {}
        manifest.files.updater.version = new_version
        
        local mf_out = fs.open(manifest_path, "w")
        mf_out.write(textutils.serializeJSON(manifest, { pretty = true }))
        mf_out.close()
        print("Local manifest updated to version: " .. new_version)
        
        print("Updater has been updated. Rebooting to apply changes...")
        sleep(0.5)
        os.reboot()
    ]])
    stub.close()
    
    shell.run(UPDATER_STUB_FILE, remoteUpdaterData.source, "updater", LOCAL_MANIFEST_FILE, remoteUpdaterData.version)
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

table.insert(files_to_check, "updater")

local newLocalManifest = { project = remoteManifest.project, files = {} }

for _, filename in ipairs(files_to_check) do
    local remoteData = remoteManifest.files[filename]
    if remoteData then
        local localVersion = (localManifest.files and localManifest.files[filename]) and localManifest.files[filename].version or "0.0"
        if compareVersions(remoteData.version, localVersion) then
            print(string.format("Updating %s (v%s -> v%s)...", filename, localVersion, remoteData.version))
            if filename:match("%.mcanim$") then
                local folder_name = fs.getName(filename):gsub("%.mcanim", "")
                if not fs.exists(folder_name) then fs.makeDir(folder_name) end
                
                local master_path = fs.combine(folder_name, filename)
                if download(remoteData.source, master_path) then
                    local mf = fs.open(master_path, "r"); local mc = mf.readAll(); mf.close()
                    local master_anim = textutils.unserializeJSON(mc)
                    if master_anim and master_anim.chunks then
                        print("  -> Found " .. #master_anim.chunks .. " chunks. Downloading...")
                        local base_url = remoteData.source:gsub(filename, "")
                        for i, chunk_name in ipairs(master_anim.chunks) do
                            download(base_url .. chunk_name, fs.combine(folder_name, chunk_name))
                        end
                    end
                end
            else
                download(remoteData.source, filename)
            end
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