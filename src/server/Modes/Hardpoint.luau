--!strict
-- Hardpoint: one live zone at a time, rotating in map order every `hardpointDuration` seconds.
-- A team alone in the live zone scores one point per second.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Objectives = require(ReplicatedStorage.Shared.Pure.Objectives)
local MatchRules = require(ReplicatedStorage.Shared.Pure.MatchRules)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)
local Types = require(ReplicatedStorage.Shared.Types)
local ModeTypes = require(script.Parent.ModeTypes)
local Zones = require(script.Parent.Zones)

local HOLD_AWARD_SECONDS = 5

local Hardpoint = {}

function Hardpoint.new(): ModeTypes.Impl
	local zones: { Zones.Zone } = {}
	local startedAt = 0
	local live: number? = nil -- index into zones
	local movesAt = 0 -- server time
	local holder: string? = nil
	local contested = false
	local teamClock: { [string]: number } = {}
	local playerClock: { [Player]: number } = {}

	local impl: ModeTypes.Impl
	impl = {
		kind = "Hardpoint",

		prepare = function(ctx)
			zones = Zones.collect(ctx.map, "Hardpoint")
			if #zones == 0 then
				warn("[Hardpoint] map has no Hardpoint objectives")
			end
			startedAt = ctx.now() + 1e9 -- not started yet: no zone is live
			movesAt = 0
			ctx.changed()
		end,

		start = function(ctx)
			startedAt = ctx.now()
			movesAt = startedAt + (ctx.mode.hardpointFirstDelay or 10)
			ctx.changed()
		end,

		step = function(ctx, dt)
			if #zones == 0 then
				return
			end
			local elapsed = ctx.now() - startedAt
			local index, endsAfter = Objectives.hardpointAt(elapsed, ctx.mode.hardpointFirstDelay or 10, ctx.mode.hardpointDuration or 60, #zones)
			if index ~= live then
				live = index
				holder, contested = nil, false
				table.clear(teamClock)
				table.clear(playerClock)
				if index then
					ctx.event("HardpointMoved", { id = zones[index].id })
				end
			end
			local newMovesAt = startedAt + endsAfter
			if newMovesAt ~= movesAt then
				movesAt = newMovesAt
				ctx.changed()
			end
			if not index then
				return
			end
			local counts, who = Zones.occupants(ctx, zones[index])
			local only, isContested = Objectives.presence(counts)
			if only ~= holder or isContested ~= contested then
				holder, contested = only, isContested
				ctx.changed()
			end
			if not only then
				return
			end
			local t = (teamClock[only] or 0) + dt
			while t >= 1 do
				t -= 1
				ctx.addTeamScore(only, 1)
			end
			teamClock[only] = t
			local holders = who[only]
			if holders then
				for _, player in holders do
					local c = (playerClock[player] or 0) + dt
					if c >= HOLD_AWARD_SECONDS then
						c -= HOLD_AWARD_SECONDS
						ctx.award(player, MatchRules.POINTS.HardpointHold, "Hardpoint", Progression.AccountXP.HardpointHold)
					end
					playerClock[player] = c
				end
			end
		end,

		payload = function(_ctx): Types.ObjectivePayload
			local list = {}
			for i, z in zones do
				local s = Zones.state(z)
				s.active = i == live
				if s.active then
					s.owner = holder
					s.contested = contested
				end
				table.insert(list, s)
			end
			return { kind = "Hardpoint", zones = list, hardpointMovesAt = if movesAt > 0 then movesAt else nil }
		end,

		onPlayerRemoving = function(_ctx, player)
			playerClock[player] = nil
		end,

		stop = function(_ctx)
			live = nil
			table.clear(teamClock)
			table.clear(playerClock)
		end,
	}
	return impl
end

return Hardpoint
