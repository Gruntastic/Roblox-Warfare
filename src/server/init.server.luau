--!strict
-- Server bootstrap. Services are plain ModuleScripts with init() then start().
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)

Net.init()

local Services = script.Services
local order: { any } = {
	require(Services.DataService),
	require(Services.ProgressionService),
	require(Services.CombatService),
	require(Services.MatchService),
	require(Services.MovementGuard),
}

for _, service in order do
	(service :: any).init()
end
for _, service in order do
	task.spawn((service :: any).start)
end
print("[CallOfRoblox] server started")
