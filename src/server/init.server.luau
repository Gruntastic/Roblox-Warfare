--!strict
-- Server bootstrap. Services are plain ModuleScripts with init() then start().
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Net)

Net.init()

local Services = script.Services
local order: { any } = {
	require(Services.DataService),
	require(Services.ProgressionService),
	require(Services.ChallengeService),
	require(Services.StoreService),
	require(Services.CombatService),
	require(Services.KillstreakService),
	require(Services.MatchService),
	require(Services.MovementGuard),
}

for _, service in order do
	(service :: any).init()
end
for _, service in order do
	task.spawn((service :: any).start)
end
print("[BloxOps] server started")
