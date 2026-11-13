-- Additive, in-memory controller for the pinned official Rojo 7.7.0 plugin modules.
-- Place this ModuleScript beside the inert `Rojo` folder under CoreGui.__CodexRojoBridge.

local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local EncodingService = game:GetService("EncodingService")

local bridgeRoot = script.Parent
local rojoRoot = bridgeRoot:FindFirstChild("Rojo")
assert(rojoRoot, "Expected sibling Rojo 7.7.0 module tree")

local PluginModules = rojoRoot:WaitForChild("Plugin")
local ApiContext = require(PluginModules:WaitForChild("ApiContext"))
local ServeSession = require(PluginModules:WaitForChild("ServeSession"))
local PatchSet = require(PluginModules:WaitForChild("PatchSet"))

local decisionEvent = Instance.new("BindableEvent")
local session = nil
local pendingReview = nil
local socketConnections = {}
local state = {
    status = "Disconnected",
    detail = nil,
    projectName = nil,
    address = nil,
    preview = nil,
    patchFailures = nil,
    reviewToken = nil,
    error = nil,
    expectedPlaceId = nil,
    expectedGameId = nil,
    twoWaySync = false,
    apiSessionId = nil,
    socketStatus = "Closed",
}

local Controller = {}

local function copySerializable(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, item in pairs(value) do
        copy[key] = copySerializable(item)
    end
    return copy
end

local function safePath(instance)
    if typeof(instance) ~= "Instance" then
        return nil
    end
    local ok, result = pcall(function()
        return instance:GetFullName()
    end)
    return if ok then result else "<unavailable>"
end

local function rejectIdentityChanges(instanceMap, patch, serverInfo, options)
    if type(serverInfo.projectName) ~= "string" or serverInfo.projectName ~= options.expectedProjectName then
        return "Rojo project name does not match the requested project"
    end
    if serverInfo.placeId ~= nil and serverInfo.placeId ~= options.expectedPlaceId then
        return "Rojo session would change the current PlaceId"
    end
    if serverInfo.gameId ~= nil and serverInfo.gameId ~= options.expectedGameId then
        return "Rojo session would change the current GameId"
    end
    if game.GameId ~= options.expectedGameId then
        return "GameId changed before initial patch review"
    end

    local identityProperties = {
        PlaceId = true,
        GameId = true,
        UniverseId = true,
    }
    for _, update in ipairs(patch.updated) do
        for propertyName in pairs(update.changedProperties) do
            if identityProperties[propertyName] then
                return "Initial patch includes an identity property: " .. propertyName
            end
        end
    end
    for _, added in pairs(patch.added) do
        for propertyName in pairs(added.Properties) do
            if identityProperties[propertyName] then
                return "Initial patch includes an identity property: " .. propertyName
            end
        end
    end

    local gameId = instanceMap.fromInstances[game]
    if gameId ~= nil then
        for _, update in ipairs(patch.updated) do
            if update.id == gameId and update.changedClassName ~= nil then
                return "Initial patch would change the DataModel class"
            end
        end
    end
    return nil
end

local MAX_PREVIEW_STRING_BYTES = 160
local MAX_PREVIEW_TABLE_ITEMS = 16
local MAX_PREVIEW_TABLE_DEPTH = 2

local function sha256Hex(value)
    local digest = EncodingService:ComputeStringHash(value, Enum.HashAlgorithm.Sha256)
    local output = table.create(#digest)
    for index = 1, #digest do
        output[index] = string.format("%02x", string.byte(digest, index))
    end
    return table.concat(output)
end

local function summarizeValue(value, propertyName, depth)
    if propertyName == "Source" then
        local source = if type(value) == "string" then value
            elseif type(value) == "table" then value.String else nil
        if type(source) ~= "string" then
            return { type = typeof(value), redacted = true }
        end
        return {
            type = "string",
            bytes = #source,
            sha256 = sha256Hex(source),
        }
    end

    local valueType = typeof(value)
    if valueType == "nil" or valueType == "boolean" then
        return value
    elseif valueType == "number" then
        if value == value and value ~= math.huge and value ~= -math.huge then
            return value
        end
        return tostring(value)
    elseif valueType == "string" then
        if #value <= MAX_PREVIEW_STRING_BYTES then
            return value
        end
        return { type = "string", bytes = #value, truncated = true }
    elseif valueType == "Instance" then
        return { type = "Instance", path = safePath(value) }
    elseif valueType == "EnumItem" then
        return tostring(value)
    elseif valueType == "table" and depth < MAX_PREVIEW_TABLE_DEPTH then
        local result = {}
        local keys = {}
        for key in pairs(value) do
            if type(key) == "string" or type(key) == "number" then
                table.insert(keys, key)
            end
        end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for index, key in ipairs(keys) do
            if index > MAX_PREVIEW_TABLE_ITEMS then
                result._truncated = true
                break
            end
            result[tostring(key)] = summarizeValue(value[key], nil, depth + 1)
        end
        return result
    end

    local text = tostring(value)
    if #text > MAX_PREVIEW_STRING_BYTES then
        text = string.sub(text, 1, MAX_PREVIEW_STRING_BYTES)
    end
    return { type = valueType, value = text }
end

local function propertySummaries(properties)
    local summaries = {}
    for propertyName, value in pairs(properties) do
        summaries[propertyName] = summarizeValue(value, propertyName, 0)
    end
    return summaries
end

local function buildPreview(instanceMap, patch)
    local preview = {
        added = {},
        removed = {},
        updated = {},
    }

    for id, instance in pairs(patch.added) do
        local parentId = instance.Parent
        local parentPath = nil
        if parentId ~= nil then
            local parent = instanceMap.fromIds[parentId] or patch.added[parentId]
            parentPath = safePath(parent)
        end
        table.insert(preview.added, {
            id = id,
            className = instance.ClassName,
            name = instance.Name,
            parentId = parentId,
            parentPath = parentPath,
            properties = propertySummaries(instance.Properties),
        })
    end

    for _, removed in ipairs(patch.removed) do
        local instance = if typeof(removed) == "Instance" then removed else instanceMap.fromIds[removed]
        table.insert(preview.removed, {
            id = if typeof(removed) == "Instance" then instanceMap.fromInstances[removed] else removed,
            path = safePath(instance),
            name = if instance then instance.Name else nil,
            className = if instance then instance.ClassName else nil,
        })
    end

    for _, update in ipairs(patch.updated) do
        local instance = instanceMap.fromIds[update.id]
        local properties = {}
        for propertyName in pairs(update.changedProperties) do
            table.insert(properties, propertyName)
        end
        table.sort(properties)
        table.insert(preview.updated, {
            id = update.id,
            path = safePath(instance),
            properties = properties,
            propertySummaries = propertySummaries(update.changedProperties),
            changedName = update.changedName,
            changedClassName = update.changedClassName,
        })
    end

    table.sort(preview.added, function(a, b) return a.id < b.id end)
    table.sort(preview.removed, function(a, b) return tostring(a.path) < tostring(b.path) end)
    table.sort(preview.updated, function(a, b) return a.id < b.id end)
    return preview
end

local function clearSocketConnections()
    for _, connection in ipairs(socketConnections) do
        connection:Disconnect()
    end
    table.clear(socketConnections)
end

local function watchSocket(newSession, apiContext)
    task.spawn(function()
        while session == newSession and apiContext.__wsClient == nil do
            task.wait()
        end
        if session ~= newSession then
            return
        end
        local socket = apiContext.__wsClient
        if socket == nil then
            return
        end

        local function setSocketStatus(status)
            if session == newSession and apiContext.__wsClient == socket then
                state.socketStatus = status
            end
        end
        table.insert(socketConnections, socket.Opened:Connect(function()
            setSocketStatus("Open")
        end))
        table.insert(socketConnections, socket.Closed:Connect(function()
            setSocketStatus("Closed")
        end))
        table.insert(socketConnections, socket.Error:Connect(function(_, message)
            setSocketStatus("Error")
            if session == newSession then
                state.error = tostring(message)
            end
        end))
        local ok, connectionState = pcall(function() return socket.ConnectionState end)
        if ok and connectionState == Enum.WebStreamClientState.Open then
            setSocketStatus("Open")
        elseif ok and connectionState == Enum.WebStreamClientState.Connecting then
            setSocketStatus("Connecting")
        elseif ok then
            setSocketStatus(connectionState.Name)
        else
            setSocketStatus("Unknown")
        end
    end)
end

local function normalizeTimeout(value)
    if value == nil then
        return 120
    end
    assert(type(value) == "number" and value % 1 == 0, "confirmationTimeoutSeconds must be an integer")
    assert(value >= 1 and value <= 300, "confirmationTimeoutSeconds must be between 1 and 300")
    return value
end

function Controller.status()
    return copySerializable(state)
end

function Controller.prepare(options)
    assert(type(options) == "table", "prepare expects an options table")
    options = table.clone(options)
    assert(RunService:IsStudio(), "Rojo headless sync requires Roblox Studio")
    assert(not RunService:IsRunning(), "Rojo headless sync is only allowed in Studio Edit mode")
    assert(type(options.port) == "number" and options.port % 1 == 0 and options.port >= 1 and options.port <= 65535,
        "port must be an integer from 1 through 65535")
    assert(type(options.expectedPlaceId) == "number" and options.expectedPlaceId % 1 == 0,
        "expectedPlaceId must be an integer")
    assert(options.expectedPlaceId == game.PlaceId, "expectedPlaceId must match the open place")
    local expectedGameId = game.GameId
    options.expectedGameId = expectedGameId
    assert(type(options.expectedProjectName) == "string" and #options.expectedProjectName > 0
        and string.match(options.expectedProjectName, "%S"), "expectedProjectName must be non-empty")
    assert(session == nil and pendingReview == nil and state.status ~= "Connecting" and state.status ~= "Review"
        and state.status ~= "Connected", "A Rojo session is already pending or active")

    local timeoutSeconds = normalizeTimeout(options.confirmationTimeoutSeconds)
    local endpoint = "http://127.0.0.1:" .. tostring(options.port)
    local apiContext = ApiContext.new(endpoint)
    local newSession = ServeSession.new({
        apiContext = apiContext,
        twoWaySync = false,
    })
    session = newSession
    state = {
        status = "Connecting",
        detail = "Connecting to pinned Rojo 7.7.0 server",
        projectName = nil,
        address = endpoint,
        preview = nil,
        patchFailures = nil,
        reviewToken = nil,
        error = nil,
        expectedPlaceId = options.expectedPlaceId,
        expectedGameId = expectedGameId,
        twoWaySync = false,
        apiSessionId = nil,
        socketStatus = "Connecting",
    }

    newSession:hookPostcommit(function(patch, instanceMap, unappliedPatch)
        if session ~= newSession then
            return
        end
        if not PatchSet.isEmpty(unappliedPatch) then
            state.patchFailures = buildPreview(instanceMap, unappliedPatch)
        end
    end)

    newSession:setConfirmCallback(function(instanceMap, patch, serverInfo)
        if session ~= newSession then
            return "Abort"
        end
        state.apiSessionId = newSession.__apiContext.__sessionId
        local identityError = rejectIdentityChanges(instanceMap, patch, serverInfo, options)
        if identityError then
            state.error = identityError
            state.detail = identityError
            return "Abort"
        end

        local token = HttpService:GenerateGUID(false)
        pendingReview = { token = token, decisionIssued = false }
        state.status = "Review"
        state.detail = "Initial Rojo patch awaits approval"
        state.projectName = serverInfo.projectName
        state.preview = buildPreview(instanceMap, patch)
        state.reviewToken = token

        task.delay(timeoutSeconds, function()
            if pendingReview and pendingReview.token == token and not pendingReview.decisionIssued then
                pendingReview.decisionIssued = true
                state.error = "Initial patch review timed out"
                decisionEvent:Fire("Abort")
            end
        end)

        local decision = decisionEvent.Event:Wait()
        if session ~= newSession then
            return "Abort"
        end
        if pendingReview and pendingReview.token == token then
            pendingReview = nil
        end
        state.reviewToken = nil
        if decision == "Accept" then
            if session ~= newSession then
                state.error = "Session was disconnected before approval completed"
                return "Abort"
            end
            if RunService:IsRunning() then
                state.error = "Studio entered Play mode before initial patch approval completed"
                return "Abort"
            end
            if game.PlaceId ~= options.expectedPlaceId then
                state.error = "PlaceId changed before initial patch approval completed"
                return "Abort"
            end
            if game.GameId ~= expectedGameId then
                state.error = "GameId changed before initial patch approval completed"
                return "Abort"
            end
            state.detail = "Initial patch approved; applying"
            return "Accept"
        end
        state.detail = state.error or "Initial patch rejected"
        return "Abort"
    end)

    newSession:onStatusChanged(function(status, detail)
        if session ~= newSession then
            return
        end
        if status == ServeSession.Status.Connecting then
            state.status = "Connecting"
            state.detail = detail or "Connecting"
        elseif status == ServeSession.Status.Connected then
            state.status = "Connected"
            state.projectName = detail
            state.detail = "Rojo initial sync applied"
            state.apiSessionId = newSession.__apiContext.__sessionId
            state.socketStatus = "Connecting"
            pendingReview = nil
            watchSocket(newSession, newSession.__apiContext)
        elseif status == ServeSession.Status.Disconnected then
            state.status = "Disconnected"
            state.socketStatus = "Closed"
            clearSocketConnections()
            state.error = state.error or (if detail ~= nil then tostring(detail) else nil)
            state.detail = state.error or "Disconnected"
            pendingReview = nil
            session = nil
        end
    end)

    local ok, err = pcall(function()
        newSession:start()
    end)
    if not ok then
        pcall(function() newSession:stop() end)
        if session == newSession then session = nil end
        pendingReview = nil
        state.status = "Disconnected"
        state.error = tostring(err)
        state.detail = state.error
        return false, state.error
    end
    return true
end

local function decide(token, decision)
    if type(token) ~= "string" or not pendingReview or pendingReview.token ~= token
        or pendingReview.decisionIssued then
        return false, "No matching pending review"
    end
    pendingReview.decisionIssued = true
    if decision == "Abort" then
        state.error = state.error or "Initial patch rejected"
    end
    decisionEvent:Fire(decision)
    return true
end

function Controller.accept(token)
    if not pendingReview or pendingReview.token ~= token then
        return false, "No matching pending review"
    end
    if RunService:IsRunning() then
        state.error = "Studio entered Play mode before initial patch approval"
        return decide(token, "Abort")
    end
    if game.PlaceId ~= state.expectedPlaceId then
        state.error = "PlaceId changed before initial patch approval"
        return decide(token, "Abort")
    end
    if game.GameId ~= state.expectedGameId then
        state.error = "GameId changed before initial patch approval"
        return decide(token, "Abort")
    end
    return decide(token, "Accept")
end

function Controller.abort(token)
    return decide(token, "Abort")
end

function Controller.disconnect()
    clearSocketConnections()
    if pendingReview and not pendingReview.decisionIssued then
        pendingReview.decisionIssued = true
        state.error = "Disconnected before initial patch approval"
        decisionEvent:Fire("Abort")
    end
    local current = session
    if current ~= nil then
        pcall(function() current:stop() end)
        if session == current then session = nil end
    end
    pendingReview = nil
    state.status = "Disconnected"
    state.detail = "Disconnected"
    state.reviewToken = nil
    state.socketStatus = "Closed"
    return true
end

function Controller.destroy()
    Controller.disconnect()
    decisionEvent:Destroy()
end

bridgeRoot.Destroying:Connect(function()
    Controller.destroy()
end)

return Controller
