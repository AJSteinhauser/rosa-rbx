-- TestEZ runner. Build test.project.json and run this script in a Roblox session.
-- Install packages first: wally install

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TestEZ = require(ReplicatedStorage.Packages.testez)

print("\n========== Rosa RBX Pipeline Tests ==========\n")

local results = TestEZ.TestBootstrap:run({
	ServerScriptService.Tests,
})

-- Surface a clear failure signal for CI environments
if results.failureCount > 0 then
	error(string.format("[Rosa Tests] %d test(s) failed.", results.failureCount), 0)
end
