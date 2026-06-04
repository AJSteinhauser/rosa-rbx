local ReplicatedStorage = game:GetService("ReplicatedStorage")
local setupSocialEvents = require(ReplicatedStorage.RosaRbxPipeline.ingestion["default-metrics"]["social-events"])

local function makeSignal()
	local cbs = {}
	return {
		Connect = function(_, fn) table.insert(cbs, fn) end,
		Fire    = function(_, ...) for _, fn in cbs do fn(...) end end,
	}
end

local function makeHandler()
	local calls = {}
	return {
		calls = calls,
		addClientEvent = function(_, event)
			table.insert(calls, event)
		end,
	}
end

local function makePlayer(name, rootPos)
	local root = rootPos and { Position = rootPos } or nil
	return {
		Name      = name or "TestPlayer",
		Character = root and {
			FindFirstChild = function(_, name_)
				if name_ == "HumanoidRootPart" then return root end
			end,
		} or nil,
	}
end

local function makeLocalPlayer(rootPos)
	local friendStatusChanged = makeSignal()
	local root = rootPos and { Position = rootPos } or nil
	return {
		Name                 = "LocalPlayer",
		Character            = root and {
			FindFirstChild = function(_, name_)
				if name_ == "HumanoidRootPart" then return root end
			end,
		} or nil,
		FriendStatusChanged  = friendStatusChanged,
		_friendStatusChanged = friendStatusChanged,
	}
end

local function makeServices(localPlayer, allPlayers)
	return {
		Players = {
			LocalPlayer = localPlayer,
			GetPlayers  = function() return allPlayers or {} end,
		},
	}
end

return function()
	describe("SocialEvents", function()

		it("fires FriendRequestSent when status changes to FriendRequestSent", function()
			local local_ = makeLocalPlayer(nil)
			local other  = makePlayer("Other")
			local handler = makeHandler()

			setupSocialEvents(handler, makeServices(local_, { local_, other }))
			local_._friendStatusChanged:Fire(other, Enum.FriendStatus.FriendRequestSent)

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].tag).to.equal("FriendRequestSent")
		end)

		it("includes serverOccupancy in FriendRequestSent", function()
			local local_ = makeLocalPlayer(nil)
			local other  = makePlayer("Other")
			local handler = makeHandler()

			setupSocialEvents(handler, makeServices(local_, { local_, other, makePlayer("Third") }))
			local_._friendStatusChanged:Fire(other, Enum.FriendStatus.FriendRequestSent)

			expect(handler.calls[1].custom.serverOccupancy).to.equal(3)
		end)

		it("includes distanceStuds when both characters have roots", function()
			local local_ = makeLocalPlayer(Vector3.new(0, 0, 0))
			local other  = makePlayer("Other", Vector3.new(10, 0, 0))
			local handler = makeHandler()

			setupSocialEvents(handler, makeServices(local_, { local_, other }))
			local_._friendStatusChanged:Fire(other, Enum.FriendStatus.FriendRequestSent)

			expect(handler.calls[1].custom.distanceStuds).to.equal(10)
		end)

		it("distanceStuds is nil when characters lack roots", function()
			local local_ = makeLocalPlayer(nil)
			local other  = makePlayer("Other", nil)
			local handler = makeHandler()

			setupSocialEvents(handler, makeServices(local_, { local_, other }))
			local_._friendStatusChanged:Fire(other, Enum.FriendStatus.FriendRequestSent)

			expect(handler.calls[1].custom.distanceStuds).to.equal(nil)
		end)

		it("fires FriendRequestReceived when status changes to FriendRequestReceived", function()
			local local_ = makeLocalPlayer(nil)
			local other  = makePlayer("Other")
			local handler = makeHandler()

			setupSocialEvents(handler, makeServices(local_, {}))
			local_._friendStatusChanged:Fire(other, Enum.FriendStatus.FriendRequestReceived)

			expect(#handler.calls).to.equal(1)
			expect(handler.calls[1].tag).to.equal("FriendRequestReceived")
		end)

		it("does not fire for other status changes", function()
			local local_ = makeLocalPlayer(nil)
			local other  = makePlayer("Other")
			local handler = makeHandler()

			setupSocialEvents(handler, makeServices(local_, {}))
			local_._friendStatusChanged:Fire(other, Enum.FriendStatus.Friend)
			local_._friendStatusChanged:Fire(other, Enum.FriendStatus.NotFriend)

			expect(#handler.calls).to.equal(0)
		end)

		it("does nothing when LocalPlayer is nil", function()
			local handler = makeHandler()

			expect(function()
				setupSocialEvents(handler, makeServices(nil, {}))
			end).never.to.throw()
			expect(#handler.calls).to.equal(0)
		end)

		it("fires independently for requests to different players", function()
			local local_  = makeLocalPlayer(nil)
			local otherA  = makePlayer("PlayerA")
			local otherB  = makePlayer("PlayerB")
			local handler = makeHandler()

			setupSocialEvents(handler, makeServices(local_, { local_, otherA, otherB }))
			local_._friendStatusChanged:Fire(otherA, Enum.FriendStatus.FriendRequestSent)
			local_._friendStatusChanged:Fire(otherB, Enum.FriendStatus.FriendRequestSent)

			expect(#handler.calls).to.equal(2)
		end)

		it("fires FriendRequestSent again to same player on repeated status change", function()
			local local_ = makeLocalPlayer(nil)
			local other  = makePlayer("Other")
			local handler = makeHandler()

			setupSocialEvents(handler, makeServices(local_, { local_, other }))
			local_._friendStatusChanged:Fire(other, Enum.FriendStatus.FriendRequestSent)
			local_._friendStatusChanged:Fire(other, Enum.FriendStatus.FriendRequestSent)

			expect(#handler.calls).to.equal(2)
		end)

	end)
end
