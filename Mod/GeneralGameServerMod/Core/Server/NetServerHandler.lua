--[[
Title: NetServerHandler
Author(s): wxa
Date: 2020/6/10
Desc: 网络处理程序
use the lib:
-------------------------------------------------------
NPL.load("Mod/GeneralGameServerMod/Core/Server/NetServerHandler.lua");
local NetServerHandler = commonlib.gettable("GeneralGameServerMod.Core.Server.NetServerHandler");
-------------------------------------------------------
]]
NPL.load("(gl)script/apps/Aries/Creator/Game/Network/NetHandler.lua");
NPL.load("Mod/GeneralGameServerMod/Core/Common/Connection.lua");
NPL.load("Mod/GeneralGameServerMod/Core/Server/WorldManager.lua");
NPL.load("Mod/GeneralGameServerMod/Core/Common/Config.lua");
NPL.load("Mod/GeneralGameServerMod/Core/Server/WorkerServer.lua");
local WorkerServer = commonlib.gettable("Mod.GeneralGameServerMod.Core.Server.WorkerServer");
local Config = commonlib.gettable("Mod.GeneralGameServerMod.Core.Common.Config");
local Packets = commonlib.gettable("Mod.GeneralGameServerMod.Core.Common.Packets");
local Connection = commonlib.gettable("Mod.GeneralGameServerMod.Core.Common.Connection");
local WorldManager = commonlib.gettable("Mod.GeneralGameServerMod.Core.Server.WorldManager");
local NetServerHandler = commonlib.inherit(commonlib.gettable("System.Core.ToolBase"), commonlib.gettable("Mod.GeneralGameServerMod.Core.Server.NetServerHandler"));

NetServerHandler:Property("Authenticated", false, "IsAuthenticated");  -- 是否认证
NetServerHandler:Property("Player");                                   -- 当前玩家
NetServerHandler:Property("World");                                    -- 当前世界
NetServerHandler:Property("PlayerManager");                            -- 世界玩家管理器
NetServerHandler:Property("WorldManager");                             -- 世界管理器
NetServerHandler:Property("WorkerServer");                             -- 工作服务器
NetServerHandler:Property("PlayerConnection");                               -- 玩家链接

local PlayerLoginLogoutDebug = GGS.Debug.GetModuleDebug("PlayerLoginLogoutDebug");

function NetServerHandler:ctor() 
    self:SetWorkerServer(WorkerServer);
    self:SetWorldManager(WorldManager);
end

-- @param tid: this is temporary identifier of the socket connnection
function NetServerHandler:Init(tid)
	self:SetPlayerConnection(Connection:new():Init(tid, self));
	return self;
end

function NetServerHandler:SendPacketToPlayer(packet)
    if (not self:GetPlayerConnection()) then return end
    return self:GetPlayerConnection():AddPacketToSendQueue(packet);
end

-- 服务器是否已达到峰值
function NetServerHandler:IsAllowLoginWorld(worldId)
    local totalClientCount = self:GetWorldManager():GetOnlineClientCount();
    local worldClientCount = self:GetWorld() and self:GetWorld():GetOnlineClientCount() or 0;
    if (totalClientCount >= Config.Server.maxClientCount) then
        return false;
    end
    if (worldClientCount >= self:GetWorld():GetMaxClientCount()) then
        return false;
    end
    return true;
end

function NetServerHandler:handlePlayerLogin(packetPlayerLogin)
    local username = packetPlayerLogin.username;
    local password = packetPlayerLogin.password;
    local worldId = tostring(packetPlayerLogin.worldId);
    local worldName = packetPlayerLogin.worldName or "";
    local worldType = packetPlayerLogin.worldType;
    local options = packetPlayerLogin.options;

    PlayerLoginLogoutDebug(string.format("player request login; username : %s, worldId: %s, worldName: %s, nid: %s", username, worldId, worldName, self:GetPlayerConnection():GetNid()));

    -- 获取并设置世界
    self:SetWorld(self:GetWorldManager():GetWorld(worldId, worldName, worldType, true));
    -- 设置玩家管理器
    self:SetPlayerManager(self:GetWorld():GetPlayerManager());
    -- 获取并设置玩家
    self:SetPlayer(self:GetPlayerManager():CreatePlayer(username, self));   -- 创建玩家
    -- 设置玩家选项
    if (options) then self:GetPlayer():SetOptions(options) end         

    -- TODO 认证逻辑
    -- 检测是否达到最大处理量
    if (not self:IsAllowLoginWorld(worldId)) then
        GGS.WARN("服务器连接数已到上限");
        packetPlayerLogin.result = "failed";
        packetPlayerLogin.errmsg = "服务器连接数已到上限";
        return self:SendPacketToPlayer(packetPlayerLogin);
    end

    -- 认证通过
    self:SetAuthenticated();
    -- 玩家登录
    self:GetPlayer():Login();
    -- 打印日志
    PlayerLoginLogoutDebug(string.format("player success login; username : %s, worldkey: %s, entityId: %s", self:GetPlayer():GetUserName(), self:GetWorld():GetWorldKey(), self:GetPlayer():GetEntityId()));
    -- 通知玩家登录
    packetPlayerLogin.entityId = self:GetPlayer().entityId;
    packetPlayerLogin.result = "ok";
    packetPlayerLogin.worldName = self:GetWorld():GetWorldName();
    packetPlayerLogin.username = self:GetPlayer().username;
    packetPlayerLogin.worldKey = self:GetWorld():GetWorldKey();
    self:SendPacketToPlayer(packetPlayerLogin);
end

-- 处理生成玩家包
function NetServerHandler:handlePlayerEntityInfo(packetPlayerEntityInfo)
    -- 用户不存在
    if (not self:GetPlayer()) then return self:handlePlayerRelogin() end

    -- 设置当前玩家实体信息
    local isNew = self:GetPlayer():SetPlayerEntityInfo(packetPlayerEntityInfo);
    local packet = (isNew or self:GetPlayer():IsEnableArea()) and self:GetPlayer():GetPlayerEntityInfo() or packetPlayerEntityInfo;
    -- 新玩家通知所有旧玩家
    self:GetPlayerManager():SendPacketToAllPlayers(packet, self:GetPlayer());
    -- self:GetPlayerManager():SendPacketToAreaPlayers(packet, self:GetPlayer());
    -- 所有旧玩家告知新玩家   最好只通知可视范围内的玩家信息
    if (not isNew) then return end

    -- 新玩家同步玩家列表
    self:handlePlayerEntityInfoList();
    -- 将玩家加入玩家管理器 有实体信息才加入玩家管理器
    self:GetPlayerManager():AddPlayer(self:GetPlayer());
    -- 开始块同步
    if (self:GetPlayer():IsSyncBlock()) then
        self:SendPacketToPlayer(Packets.PacketGeneral:new():Init({action = "SyncBlock", data = {state = "SyncBlock_Begin"}}));
    end
end

-- 同步玩家信息列表
function NetServerHandler:handlePlayerEntityInfoList()
    -- 用户不存在 重新登录
    if (not self:GetPlayer()) then return self:handlePlayerRelogin() end
    
    -- 更新玩家列表
    self:SendPacketToPlayer(Packets.PacketPlayerEntityInfoList:new():Init(self:GetPlayerManager():GetPlayerEntityInfoList(self:GetPlayer())));
end

-- 玩家重新登录, 当连接存在玩家丢失需要重新等陆, 这个问题与TCP自身自动重连有关(玩家第一次登录, 登录切后台, tcp自行断开, 程序恢复前台, tcp自行重连, 这样跳过了登录步骤,导致用户丢失, 这种发送客户端重连数据包)
function NetServerHandler:handlePlayerRelogin()
    PlayerLoginLogoutDebug("client relogin: " .. tostring(self:GetPlayerConnection():GetIPAddress()));
    self:SendPacketToPlayer(Packets.PacketGeneral:GetReloginPacket());
end

-- 链接出错 玩家退出
function NetServerHandler:handleErrorMessage(text, data)
    if (not self:GetPlayer()) then return end

    -- 下线走离线流程 登出直接踢出服务器
    self:GetPlayerManager():Offline(self:GetPlayer(), "连接断开, 玩家主动下线");
    
    -- 关闭连接
    self:GetPlayerConnection():CloseConnection();
    self:SetPlayerConnection(nil);
end

-- 监听包处理后
function NetServerHandler:OnAfterProcessPacket(packet)
    -- 更新玩家心跳
    if (self:GetPlayer()) then 
        self:GetPlayer():UpdateTick();
    end
end

-- 转发聊天消息
function NetServerHandler:handleChat(packetChat)
    -- 用户不存在
    if (not self:GetPlayer()) then return self:handlePlayerRelogin() end

    self:GetPlayerManager():SendPacketToAllPlayers(packetChat, self:GetPlayer());
end

-- 处理方块同步
function NetServerHandler:handleGeneral_SyncBlock(packetGeneral)
    -- 用户不存在
    if (not self:GetPlayer()) then return self:handlePlayerRelogin() end

    local state = packetGeneral.data.state;       -- 同步状态
    local playerId = packetGeneral.data.playerId; -- 请求同步玩家ID
    local player = self:GetPlayerManager():GetPlayer(playerId);

    -- 请求的玩家不存在或同步完成直接跳出
    if (not player and player:IsSyncBlockFinish()) then return GGS.DEBUG.Format("请求同步世界方块信息的玩家不存在或已同步完成 playerId = %s", playerId) end

    -- 方块同步逻辑
    if (state == "SyncBlock_Finish") then
        self:GetPlayer():SetSyncBlockFinish();
    elseif (state == "SyncBlock_RequestBlockIndexList" or state == "SyncBlock_RequestSyncBlock") then
        local player = self:GetPlayerManager():GetSyncBlockOldestPlayer();
        if (not player or player == self:GetPlayer()) then
            return self:SendPacketToPlayer(Packets.PacketGeneral:new():Init({action = "SyncBlock", data = {state = "SyncBlock_Finish"}}));
        else
            self:GetPlayerManager():SendPacketToPlayer(packetGeneral, player);
        end
    elseif (state == "SyncBlock_ResponseBlockIndexList" or state == "SyncBlock_ResponseSyncBlock") then
        self:GetPlayerManager():SendPacketToPlayer(packetGeneral, player);
    else

    end
end

-- 处理调试信息
function NetServerHandler:handleGeneral_Debug(packetGeneral)
    -- 用户不存在
    if (not self:GetPlayer()) then return self:handlePlayerRelogin() end

    local cmd = packetGeneral.data.cmd;
    if (cmd == "WorldInfo") then
        packetGeneral.data.debug = self:GetWorld():GetDebugInfo();
        self:SendPacketToPlayer(packetGeneral);
    elseif (cmd == "ServerInfo") then
        packetGeneral.data.debug = self:GetWorkerServer():GetServerList();
        self:SendPacketToPlayer(packetGeneral);
    elseif (cmd == "ping") then
        local worldKey = self:GetWorld():GetWorldKey();
        packetGeneral.data.debug = self:GetWorld() == self:GetWorldManager():GetWorldByKey(worldKey);
        self:SendPacketToPlayer(packetGeneral);
    end
end

-- 通用数据包转发
function NetServerHandler:handleGeneral(packetGeneral)
    -- 用户不存在
    if (not self:GetPlayer()) then return self:handlePlayerRelogin() end

    if (packetGeneral.action == "PlayerOptions") then
        self:GetPlayer():SetOptions(packetGeneral.data);
    elseif (packetGeneral.action == "SyncCmd") then
        self:GetPlayerManager():SendPacketToSyncCmdPlayers(packetGeneral, self:GetPlayer());
    elseif (packetGeneral.action == "SyncBlock") then
        self:handleGeneral_SyncBlock(packetGeneral);
    elseif (packetGeneral.action == "Debug") then
        self:handleGeneral_Debug(packetGeneral);
    else
        self:GetPlayerManager():SendPacketToAllPlayers(packetGeneral, self:GetPlayer());
    end
end

-- 数据包列表转发
function NetServerHandler:handleMultiple(packetMultiple)
    -- 用户不存在
    if (not self:GetPlayer()) then return self:handlePlayerRelogin() end
    
    if (packetMultiple.action == "SyncBlock") then
        self:GetPlayerManager():SendPacketToSyncBlockPlayers(packetMultiple, self:GetPlayer());
    else
        self:GetPlayerManager():SendPacketToAllPlayers(packetMultiple, self:GetPlayer());
    end
end