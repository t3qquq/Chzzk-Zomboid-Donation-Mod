ZombieActions = ZombieActions or {}

ZombieActions.Zombify = {}
ZombieActions.Zombify.onStart = function(zombie, task)
    zombie:clearAttachedItems()
    return true
end

ZombieActions.Zombify.onWorking = function(zombie, task)
    if zombie:getBumpType() ~= task.anim then return true end
    return false
end

ZombieActions.Zombify.onComplete = function(zombie, task)
    zombie:changeState(ZombieOnGroundState.instance())
    local id = HitmanUtils.GetCharacterID(zombie)
    local args = {}
    args.id = id
    if isClient() then
        sendClientCommand(getSpecificPlayer(0), 'Commands', 'HitmanRemove', args)
    else
        HitmanServer.Commands.HitmanRemove(getSpecificPlayer(0), args)
    end
    return true
end