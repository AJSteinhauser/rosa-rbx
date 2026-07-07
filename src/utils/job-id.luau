local HttpService = game:GetService("HttpService")

local function resolve(jobId: string, generateGuid: () -> string): string
	if jobId ~= "" then
		return jobId
	end
	return generateGuid()
end

local jobId = resolve(game.JobId, function()
	return HttpService:GenerateGUID(false)
end)

return {
	jobId = jobId,
	resolve = resolve,
}
