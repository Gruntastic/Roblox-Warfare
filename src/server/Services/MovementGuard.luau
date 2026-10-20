--!strict
-- Lightweight server movement sanity check. Roblox movement is client-simulated, so the
-- server samples positions and rubber-bands characters that sustain impossible speeds.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ModesConfig = require(ReplicatedStorage.Shared.Config.Modes)
local Perks = require(ReplicatedStorage.Shared.Config.Perks)

-- The fastest perk combination (one perk per tier), so Fleetfoot-style perks never trip the guard.
local function maxPerkSpeed(): number
	local best = { 1, 1, 1 }
	for _, def in Perks.list do
		best[def.tier] = math.max(best[def.tier], def.effects.moveSpeed or 1)
	end
	return best[1] * best[2] * best[3]
end

local SAMPLE_INTERVAL = 0.5
local MAX_HORIZONTAL_SPEED = ModesConfig.Match.SprintSpeed * maxPerkSpeed() * 1.6 + 4
local STRIKES_TO_CORRECT = 2

type Track = { character: Model, lastGood: CFrame, lastPos: Vector3, strikes: number, total: number }

local MovementGuard = { corrections = 0 }
local tracks: { [Player]: Track } = {}

function MovementGuard.reset(player: Player)
	tracks[player] = nil
end

local function sample()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not root then
			tracks[player] = nil
			continue
		end
		local t = tracks[player]
		if not t or t.character ~= character then
			tracks[player] = { character = character, lastGood = root.CFrame, lastPos = root.Position, strikes = 0, total = 0 }
			continue
		end
		local delta = root.Position - t.lastPos
		local speed = Vector3.new(delta.X, 0, delta.Z).Magnitude / SAMPLE_INTERVAL
		t.lastPos = root.Position
		if speed > MAX_HORIZONTAL_SPEED then
			t.strikes += 1
			if t.strikes >= STRIKES_TO_CORRECT then
				t.total += 1
				MovementGuard.corrections += 1
				warn(("[MovementGuard] %s moving %.0f studs/s; correcting (#%d)"):format(player.Name, speed, t.total))
				character:PivotTo(t.lastGood)
				t.lastPos = t.lastGood.Position
				t.strikes = 0
			end
		else
			t.strikes = 0
			t.lastGood = root.CFrame
		end
	end
end

function MovementGuard.init()
	Players.PlayerRemoving:Connect(function(p)
		tracks[p] = nil
	end)
end

function MovementGuard.start()
	while true do
		task.wait(SAMPLE_INTERVAL)
		sample()
	end
end

return MovementGuard
