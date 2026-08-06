--!nonstrict

-- 새 Script로 ServerScriptService에 넣는다.
-- 기존 Server 메인 스크립트를 건드리지 않고 연출 서비스를 시작한다.
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("RadRemotes", 30)

local server = ServerScriptService:WaitForChild("Server")
local services = server:WaitForChild("Services")
local ShowService = require(services:WaitForChild("ShowService"))

local ok, err = pcall(ShowService.start)
if not ok then
	warn("[ShowBootstrap] 연출 시작 실패: " .. tostring(err))
end
