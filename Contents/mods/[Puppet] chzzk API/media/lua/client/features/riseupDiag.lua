-- ═══════════════════════════════════════════════════════════════════════════
--  '알몸 부활' 진단 로거 v3 (클라 전용)
--
--  v3 변경점: 일부 클라 환경(debuglog 설정)에서 Lua print()가 console.txt에
--  기록되지 않는 것이 확인됨(2026-07-14 재현 세션). print는 유지하되,
--  getFileWriter로 Zomboid/Lua/PongDuDiag.log 에 직접 기록하는 이중 출력.
--  → 로그 회수 시 console.txt 대신(또는 함께) Zomboid/Lua/PongDuDiag.log 수거.
--
--  v2와 동일: 트리거 없는 OnTick 상시 스윕(250ms).
--  바닐라 IsoDeadBody.reanimate()는 isFakeDead()==false인 모든 시체를
--  setReanimatedPlayer(true)+createPlayerZombieDescriptor 경로로 보내므로
--  RiseUp 대량부활/플레이어 좀비화 사망 모두 같은 원인으로 알몸이 난다.
--  클라의 ApplyReanimatedPlayerOutfit이 로컬 PlayerZombieDescriptors에서
--  디스크립터를 못 찾으면 조용히 아무것도 안 해서 알몸으로 굳는 구조.
--
--  riseupRedress.lua(패치)와 동시 적용 가능 — 원인은 이미 바닐라 소스로
--  확정됐으므로, 이제 이 로거의 역할은 '패치 효과 검증'이다:
--  NAKED-DETECT → NAKED-RESOLVED 간격이 곧 (디스크립터 도착 + 패치 스윕) 시간.
--
--  로그 태그: [PongDu][Diag] / 파일: Zomboid/Lua/PongDuDiag.log
-- ═══════════════════════════════════════════════════════════════════════════

local _tracked = {}                 -- [onlineID] = { firstMs, resolved, lastLogMs }
local PERMANENT_AFTER_MS = 20000    -- 이 시간까지 회복 없으면 영구 알몸 판정
local SCAN_INTERVAL_MS = 250
local _lastScan = 0

local LOG_FILE = "PongDuDiag.log"   -- Zomboid/Lua/ 하위에 생성됨

-- print + 파일 동시 기록. 파일은 라인마다 append로 열고 닫아 크래시에도 유실 최소화.
local function diagLog(msg)
    local line = "[PongDu][Diag] " .. msg
    print(line)
    pcall(function()
        local w = getFileWriter(LOG_FILE, true, true)
        if w then
            w:writeln(string.format("[%d] %s", getTimestampMs(), line))
            w:close()
        end
    end)
end

local function who()
    local ok, name = pcall(function() return getSpecificPlayer(0):getUsername() end)
    return (ok and name) or "?"
end

local function envTag()
    -- 협동서버는 호스트여도 서버가 별도 프로세스라 호스트 클라도 패킷 경로를
    -- 타므로(RequestDataPacket/ZombieDescriptors push) 호스트에서도 버그가 남.
    return (isClient() == false) and "HOST" or "REMOTE"
end

local function wornCount(z)
    local n = -1
    pcall(function() n = z:getWornItems():size() end)
    return n
end

local function invCount(z)
    local n = -1
    pcall(function()
        local inv = z:getInventory()
        if inv then n = inv:getItems():size() end
    end)
    return n
end

local function scan()
    local ok, err = pcall(function()
        local player = getSpecificPlayer(0)
        if not player then return end
        local cell = player:getCell()
        if not cell then return end

        local now = getTimestampMs()
        local zlist = cell:getZombieList()
        local seen = {}

        for i = 0, zlist:size() - 1 do
            local z = zlist:get(i)
            if z and z:isReanimatedPlayer() then
                local zid = z:getOnlineID()
                seen[zid] = true
                local worn = wornCount(z)
                local rec = _tracked[zid]

                if worn == 0 then
                    if not rec then
                        local inv = invCount(z)
                        _tracked[zid] = { firstMs = now, resolved = false, lastLogMs = now }
                        diagLog(string.format(
                            "NAKED-DETECT zid=%s env=%s user=%s worn=%d inv=%d pid=%s pos=%d,%d,%d",
                            tostring(zid), envTag(), who(), worn, inv,
                            tostring(z:getPersistentOutfitID()),
                            z:getX(), z:getY(), z:getZ()
                        ))
                    elseif not rec.resolved
                        and (now - rec.firstMs) >= PERMANENT_AFTER_MS
                        and (now - rec.lastLogMs) >= PERMANENT_AFTER_MS then
                        rec.lastLogMs = now
                        rec.resolved = true
                        diagLog(string.format(
                            "NAKED-PERMANENT zid=%s env=%s worn=0 inv=%d after=%dms",
                            tostring(zid), envTag(), invCount(z), now - rec.firstMs
                        ))
                    end
                elseif worn > 0 and rec and not rec.resolved then
                    rec.resolved = true
                    diagLog(string.format(
                        "NAKED-RESOLVED zid=%s env=%s worn=%d after=%dms",
                        tostring(zid), envTag(), worn, now - rec.firstMs
                    ))
                end
            end
        end

        for zid, rec in pairs(_tracked) do
            if not seen[zid] and rec.resolved then
                _tracked[zid] = nil
            end
        end
    end)
    if not ok then
        diagLog("scan error: " .. tostring(err))
    end
end

Events.OnTick.Add(function()
    local now = getTimestampMs()
    if now - _lastScan < SCAN_INTERVAL_MS then return end
    _lastScan = now
    scan()
end)

diagLog("riseupDiag v3 loaded (상시 스윕 + 파일기록: Lua/" .. LOG_FILE .. ") env=" .. envTag())
