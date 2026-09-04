--[[ NONTK Direct Loader v1
  โหลดสคริปหลัก (NONTK_Clone_Thai.lua) จาก GitHub repo ของมึงเอง
  ใช้เมื่อมึงอยากได้ URL สั้นๆ 1 บรรทัดแทนการแจกไฟล์ให้เพื่อน
  แก้ REPO ด้านล่างให้ตรงกับที่มึงอัพ (เช่น "yourname/nontk-sae")
]]
local REPO = "ชื่อผู้ใช้/ชื่อrepo"  -- แก้ตรงนี้
local FILE = "NONTK_Clone_Thai.lua"
local URL  = ("https://raw.githubusercontent.com/%s/main/%s"):format(REPO, FILE)

local ok, src = pcall(function() return game:HttpGet(URL) end)
if not ok or type(src) ~= "string" or #src < 10000 then
  warn("[nontk] โหลดไฟล์ไม่สำเร็จ: " .. URL)
  return
end

local fn, err = loadstring(src, FILE)
if not fn then
  warn("[nontk] loadstring พัง: " .. tostring(err))
  return
end

local okRun, errRun = pcall(fn)
print("[nontk] " .. (okRun and "โหลดสำเร็จ" or ("พัง: " .. tostring(errRun))))