--!strict
-- Domination: three flags. Stand in a flag alone to capture it; every held flag scores one point
-- for its team every `scoreInterval` seconds.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Objectives = require(ReplicatedStorage.Shared.Pure.Objectives)
local MatchRules = require(ReplicatedStorage.Shared.Pure.MatchRules)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)
local Types = require(ReplicatedStorage.Shared.Types)
local ModeTypes = require(script.Parent.ModeTypes)
local Zones = require(script.Parent.Zones)

local Domination = {}

function Domination.new(): ModeTypes.Impl
	local zones: { Zones.Zone } = {}
	local flags: { [string]: Objectives.Flag } = {}
	local scoreClock = 0
	-- last broadcast snapshot, so the payload is only re-sent when something visible changed
	local lastSent: { [string]: string } = {}

	local function snapshot(zone: Zones.Zone): string
		local f = flags[zone.id]
		return ("%s|%s|%d|%s"):format(tostring(f.owner), tostring(f.capturingTeam), math.floor(f.progress * 50), tostring(f.contested))
	end

	local impl: ModeTypes.Impl
	impl = {
		kind = "Domination",

		prepare = function(ctx)
			zones = Zones.collect(ctx.map, "Flag")
			if #zones == 0 then
				warn("[Domination] map has no Flag objectives")
			end
			for _, z in zones do
				flags[z.id] = { owner = nil, capturingTeam = nil, progress = 0, contested = false }
			end
			ctx.changed()
		end,

		start = function(_ctx)
			scoreClock = 0
		end,

		step = function(ctx, dt)
			local captureTime = ctx.mode.captureTime or 10
			for _, z in zones do
				local f = flags[z.id]
				local counts, who = Zones.occupants(ctx, z)
				local captured = Objectives.stepFlag(f, counts, dt, captureTime)
				if captured then
					ctx.event("ZoneCaptured", { id = z.id, team = captured })
					local capturers = who[captured]
					if capturers then
						for _, player in capturers do
							ctx.award(player, MatchRules.POINTS.Capture, "Capture", Progression.AccountXP.Capture)
						end
					end
				end
				local snap = snapshot(z)
				if snap ~= lastSent[z.id] then
					lastSent[z.id] = snap
					ctx.changed()
				end
			end
			scoreClock += dt
			local interval = ctx.mode.scoreInterval or 5
			while scoreClock >= interval do
				scoreClock -= interval
				for _, z in zones do
					local owner = flags[z.id].owner
					if owner then
						ctx.addTeamScore(owner, 1)
					end
				end
			end
		end,

		payload = function(_ctx): Types.ObjectivePayload
			local list = {}
			for _, z in zones do
				local s = Zones.state(z)
				local f = flags[z.id]
				s.owner = f.owner
				s.capturingTeam = f.capturingTeam
				s.progress = f.progress
				s.contested = f.contested
				table.insert(list, s)
			end
			return { kind = "Domination", zones = list }
		end,

		stop = function(_ctx)
			table.clear(flags)
			table.clear(lastSent)
		end,
	}
	return impl
end

return Domination
