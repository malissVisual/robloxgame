--!strict
-- 3.7: the first-day tutorial (contract stub; the stream that owns it fills it in). The dispatcher at the depot
-- (Config.Tutorial) greets a new player (profile.tutorial false), gives them the first job (Jobs.startTutorialJob) and
-- explains every step until it is delivered; then profile.tutorial = true. Remote: "Tutorial" (shared/Net.luau).

local Tutorial = {}

function Tutorial.start() end

return Tutorial
