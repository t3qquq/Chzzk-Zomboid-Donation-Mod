-- VehicleDropKeyGrant: MP에서 t3VehicleDrop이 스폰한 차량의 열쇠를
-- "요청한 본인"의 클라이언트가 직접 생성해서 자기 인벤토리에 넣는 리시버.
--
-- 서버(t3VehicleDropSpawner.lua)가 남의 인벤토리를 직접 AddItem하면
-- owning client에 반영이 안 되는 문제가 있어(검증된 동기화 API 부재),
-- 서버는 vehicleId만 그 플레이어에게 sendServerCommand로 전달하고
-- 실제 키 생성+지급은 여기서 owning client가 직접 수행한다
-- (이 모드의 bombard/mutant 알림과 동일한 "서버 판단 -> 특정 클라 실행" 패턴).

local function onServerCommand(module, command, args)
    if module ~= "PongDuVehicleDrop" then return end
    if command ~= "GrantKey" then return end

    local vehicleId = args and args.vehicleId
    if not vehicleId then return end

    local vehicle = getVehicleById(vehicleId)
    if not vehicle then
        print("[VehicleDropKeyGrant] vehicleId " .. tostring(vehicleId) .. " 로 차량을 찾을 수 없음")
        return
    end

    local player = getPlayer()
    if not player then return end

    local key = vehicle:createVehicleKey()
    if not key then
        print("[VehicleDropKeyGrant] 열쇠 생성 실패 (vehicleId " .. tostring(vehicleId) .. ")")
        return
    end

    local sender = args.sender
    local keyName = (sender and sender ~= "" and (sender .. "의 ") or "") .. key:getDisplayName()
    key:setName(keyName)

    player:getInventory():AddItem(key)
end

Events.OnServerCommand.Add(onServerCommand)
