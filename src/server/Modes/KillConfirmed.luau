--!strict
-- Kill Confirmed: every death drops the victim's tag. An enemy collecting it scores a point for
-- their team (confirm); a teammate collecting it denies the point. Tags expire after a while.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MatchRules = require(ReplicatedStorage.Shared.Pure.MatchRules)
local Progression = require(ReplicatedStorage.Shared.Config.Progression)
local ModesConfig = require(ReplicatedStorage.Shared.Config.Modes)
local Types = require(ReplicatedStorage.Shared.Types)
local ModeTypes = require(script.Parent.ModeTypes)

local PICKUP_RADIUS = 4
local TAG_HEIGHT = 2.2 -- above the floor

local KillConfirmed = {}

type Tag = { part: BasePart, team: string, victimUserId: number, expiresAt: number }

local teamColor: { [string]: Color3 } = {}
for _, t in ModesConfig.Match.Teams do
	teamColor[t.id] = t.color
end

function KillConfirmed.new(): ModeTypes.Impl
	local tags: { Tag } = {}
	local folder: Folder? = nil
	local floorParams = RaycastParams.new()
	floorParams.FilterType = Enum.RaycastFilterType.Include

	local function removeTag(i: number)
		local tag = table.remove(tags, i)
		if tag then
			tag.part:Destroy()
		end
	end

	local impl: ModeTypes.Impl
	impl = {
		kind = "KillConfirmed",

		prepare = function(ctx)
			local f = Instance.new("Folder")
			f.Name = "DogTags"
			f.Parent = workspace
			folder = f
			local geometry = ctx.map:FindFirstChild("Geometry")
			floorParams.FilterDescendantsInstances = if geometry then { geometry } else { ctx.map }
			ctx.changed()
		end,

		start = function(_ctx) end,

		onKilled = function(ctx, info)
			local team = ctx.teamOf(info.victim)
			if not team or not info.position or not folder then
				return
			end
			-- Drop onto the floor under the victim (they may have died mid-air or on stairs).
			local origin = info.position
			local hit = workspace:Raycast(origin + Vector3.new(0, 1, 0), Vector3.new(0, -40, 0), floorParams)
			local floorY = if hit then hit.Position.Y else origin.Y - 3
			local part = Instance.new("Part")
			part.Name = "Tag"
			part.Size = Vector3.new(1.2, 1.6, 0.25)
			part.Material = Enum.Material.Metal
			part.Color = teamColor[team] or Color3.new(1, 1, 1)
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.CFrame = CFrame.new(origin.X, floorY + TAG_HEIGHT, origin.Z)
			part:SetAttribute("Team", team)
			part:SetAttribute("VictimUserId", info.victim.UserId)
			local light = Instance.new("PointLight")
			light.Color = part.Color
			light.Range = 6
			light.Brightness = 1.5
			light.Parent = part
			part.Parent = folder
			table.insert(tags, {
				part = part :: BasePart,
				team = team,
				victimUserId = info.victim.UserId,
				expiresAt = ctx.now() + (ctx.mode.tagLifetime or 30),
			})
		end,

		step = function(ctx, _dt)
			if #tags == 0 then
				return
			end
			local now = ctx.now()
			-- gather living collectors once per step
			local collectors: { { player: Player, team: string, pos: Vector3 } } = {}
			for _, player in ctx.participants() do
				local team = ctx.teamOf(player)
				local root = ctx.root(player)
				if team and root then
					table.insert(collectors, { player = player, team = team, pos = root.Position })
				end
			end
			for i = #tags, 1, -1 do
				local tag = tags[i]
				if now >= tag.expiresAt then
					removeTag(i)
				else
					local tagPos = tag.part.Position
					for _, c in collectors do
						local offset = c.pos - tagPos
						-- generous vertical tolerance: root is ~3 above the floor, the tag ~2.2
						if Vector3.new(offset.X, 0, offset.Z).Magnitude <= PICKUP_RADIUS and math.abs(offset.Y) <= 5 then
							if c.team ~= tag.team then
								ctx.addTeamScore(c.team, 1)
								ctx.award(c.player, MatchRules.POINTS.TagConfirm, "Kill Confirmed", Progression.AccountXP.TagConfirm)
								ctx.event("TagConfirmed", { userId = c.player.UserId, victimUserId = tag.victimUserId })
							else
								ctx.award(c.player, MatchRules.POINTS.TagDeny, "Kill Denied", Progression.AccountXP.TagDeny)
								ctx.event("TagDenied", { userId = c.player.UserId, victimUserId = tag.victimUserId })
							end
							removeTag(i)
							break
						end
					end
				end
			end
		end,

		payload = function(_ctx): Types.ObjectivePayload
			return { kind = "KillConfirmed", zones = {} }
		end,

		stop = function(_ctx)
			for i = #tags, 1, -1 do
				removeTag(i)
			end
			if folder then
				folder:Destroy()
				folder = nil
			end
		end,
	}
	return impl
end

return KillConfirmed
