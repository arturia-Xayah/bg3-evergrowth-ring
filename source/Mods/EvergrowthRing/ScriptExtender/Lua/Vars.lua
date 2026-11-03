local C = Ext.Require("Config.lua")
local options = {Server = true, Client = false, WriteableOnServer = true,
    Persistent = true, SyncToClient = false}
Ext.Vars.RegisterUserVariable(C.StateVar, options)
Ext.Vars.RegisterUserVariable(C.AppliedVar, options)
Ext.Vars.RegisterUserVariable(C.DeathVar, options)
Ext.Vars.RegisterModVariable(C.ModuleUUID, "DeliveryAttempted", options)
Ext.Vars.RegisterModVariable(C.ModuleUUID, "KnownRings", options)
return C
