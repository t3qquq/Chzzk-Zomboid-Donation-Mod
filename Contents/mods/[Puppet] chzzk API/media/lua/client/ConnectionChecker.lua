------------------------------------------------------------
-- ConnectionChecker.lua
-- Writes the current multiplayer connection state for
-- the external Puppet launcher.
------------------------------------------------------------

local function WritePuppetStatus(state)
    local writer = getFileWriter("pz_status.txt", false, false)
    if not writer then
        return
    end
    writer:write(state)
    writer:close()
end

local _tickCount = 0
local TICK_INTERVAL = 150  -- OnTick 약 150회 ≈ 5초

-- 게임 시작 시: 멀티/싱글 모두 인게임이면 CONNECTED + 타임스탬프
Events.OnGameStart.Add(function()
    WritePuppetStatus("CONNECTED|" .. tostring(os.time()))
end)

-- 5초마다 타임스탬프 갱신 (Python이 heartbeat로 생존 확인)
Events.OnTick.Add(function()
    _tickCount = _tickCount + 1
    if _tickCount >= TICK_INTERVAL then
        _tickCount = 0
        if isClient() or not isServer() then
            WritePuppetStatus("CONNECTED|" .. tostring(os.time()))
        end
    end
end)

-- 메인메뉴 복귀 시 명시적으로 DISCONNECTED
Events.OnMainMenuEnter.Add(function()
    WritePuppetStatus("DISCONNECTED")
end)
