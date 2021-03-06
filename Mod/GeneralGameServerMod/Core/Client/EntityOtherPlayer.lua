--[[
Title: entity player multiplayer client
Author(s): wxa
Date: 2020/6/15
Desc: the other player entity on the client side. 
use the lib:
------------------------------------------------------------
NPL.load("Mod/GeneralGameServerMod/Core/Client/EntityOtherPlayer.lua");
local EntityOtherPlayer = commonlib.gettable("Mod.GeneralGameServerMod.Core.Client.EntityOtherPlayer");
-------------------------------------------------------
]]
NPL.load("(gl)script/apps/Aries/Creator/Game/Entity/EntityPlayerMPOther.lua");
NPL.load("(gl)script/apps/Aries/Creator/Game/Common/DataWatcher.lua");
NPL.load("Mod/GeneralGameServerMod/Core/Client/AssetsWhiteList.lua");
local AssetsWhiteList = commonlib.gettable("Mod.GeneralGameServerMod.Core.Client.AssetsWhiteList");
local DataWatcher = commonlib.gettable("MyCompany.Aries.Game.Common.DataWatcher");
local Packets = commonlib.gettable("Mod.GeneralGameServerMod.Core.Common.Packets");
local EntityOtherPlayer = commonlib.inherit(commonlib.gettable("MyCompany.Aries.Game.EntityManager.EntityPlayerMPOther"), commonlib.gettable("Mod.GeneralGameServerMod.Core.Client.EntityOtherPlayer"));

local moduleName = "Mod.GeneralGameServerMod.Core.Client.EntityOtherPlayer";

EntityOtherPlayer:Property("World");

function EntityOtherPlayer:ctor()
    self.playerInfo = {};
    self.packetPlayerEntityInfoQueue = commonlib.Queue:new();  -- 移动队列
end

function EntityOtherPlayer:init(world, username, entityId)
    EntityOtherPlayer._super.init(self, world, username, entityId);

    self:SetWorld(world);
    self:SetSkipPicking(not self:IsCanClick());

    return self;
end

-- 是否可以被点击
function EntityOtherPlayer:IsCanClick() 
    return true;
end

-- 设置玩家信息
function EntityOtherPlayer:SetPlayerInfo(playerInfo)
    commonlib.partialcopy(self.playerInfo, playerInfo);
end

-- 获取玩家信息
function EntityOtherPlayer:GetPlayerInfo()
    return self.playerInfo;
end

-- 实体玩家是否在家
function EntityOtherPlayer:IsOnline()
    return self.playerInfo.state == "online";
end

-- virtual function:
function EntityOtherPlayer:OnClick(x,y,z, mouse_button,entity,side)
-- 返回真 取消默认事件处理程序
    return true;
end

-- 是否可以被其它实体推动
function EntityOtherPlayer:CanBePushedBy(entity)
    return not self:IsOnline();
end

-- 是否存在target
function EntityOtherPlayer:HasTarget()
    -- 在线用户使用 target 移动
    if (self:IsOnline()) then
        return EntityOtherPlayer._super.HasTarget(self);
    end
    -- 离线用户使用 montion 避让
    return false;
end

-- 动画帧
function EntityOtherPlayer:FrameMove(deltaTime)
    if (not self:IsOnline()) then
        EntityOtherPlayer._super.MoveEntity(self, deltaTime);	
    else
        self:CheckCollision(deltaTime);
    end

    self:OnUpdate();
end

-- -- 离线人物位置调整
-- function EntityOtherPlayer:AdjustOfflinePlayerPosition()
--     if (self:IsOnline()) then return end

--     local players = self:GetWorld():GetPlayerManager():GetPlayers();
--     local bx, by, bz = self:GetBlockPos();
--     local areaSize, playerCount, maxPlayerCount = 5, 0, 5;
--     for key, player in pairs(players) do 
--         if (player.IsOnline and not player:IsOnline() and player ~= self) then 
--             local pbx, pby, pbz = player:GetBlockPos();
--             local isInnerAreaSize = math.abs(bx - pbx) <= areaSize and math.abs(bz - pbz) <= areaSize;
--             if (isInnerAreaSize) then playerCount = playerCount + 1 end
--             if (playerCount > maxPlayerCount) then

--             end
--         end
--     end
-- end

-- 更改人物外观
function EntityOtherPlayer:UpdateEntityActionState()
    local curAnimId = self:GetAnimId();
    
	if(self.lastAnimId ~= curAnimId and curAnimId) then
		self.lastAnimId = curAnimId;
		local obj = self:GetInnerObject();
		if(obj) then
			obj:SetField("AnimID", curAnimId);
		end
    end
    
	local curSkinId = self:GetSkinId();
	if(self.lastSkinId ~= curSkinId and curSkinId) then
		self.lastSkinId = curSkinId;
		self:SetSkin(curSkinId, true);
    end
    
    local dataWatcher = self:GetDataWatcher();
    local curBlockIdInHand = dataWatcher:GetField(self.dataBlockInHand);
	if(curBlockIdInHand~=self:GetBlockInRightHand()) then
		self:SetBlockInRightHand(curBlockIdInHand);
		self:RefreshRightHand();
    end
    
    local curMainAsset = dataWatcher:GetField(self.dataMainAsset);
    if(curMainAsset~=self:GetMainAssetPath()) then
        if(not AssetsWhiteList.IsInWhiteList(curMainAsset)) then curMainAsset = AssetsWhiteList.GetDefaultFilename() end
        self:SetMainAssetPath(curMainAsset);
        dataWatcher:SetField(self.dataMainAsset, curMainAsset);
	end
    
    -- 改写大小同步规则
    local curScale = dataWatcher:GetField(self.dataFieldScale);
    if(curScale and curScale ~= self:GetScaling()) then
        local newScale = curScale > 1.2 and 1.2 or (curScale < 1 and 1 or curScale);
        self:SetScaling(newScale);
        dataWatcher:SetField(self.dataFieldScale, newScale);
    end
end

-- 帧函数
function EntityOtherPlayer:OnLivingUpdate()
    EntityOtherPlayer._super.OnLivingUpdate(self);
    if (self.smoothFrames > 0 or self.packetPlayerEntityInfoQueue:empty()) then return end
    local packetPlayerEntityInfo = self.packetPlayerEntityInfoQueue:pop();
    self:UpdatePlayerEntityInfo(packetPlayerEntityInfo);
end 

-- 添加移动帧
function EntityOtherPlayer:AddPlayerEntityInfo(packetPlayerEntityInfo)
    self.packetPlayerEntityInfoQueue:push(packetPlayerEntityInfo);
end

-- 更新玩家实体信息
function EntityOtherPlayer:UpdatePlayerEntityInfo(packetPlayerEntityInfo)
    local x, y, z, facing, pitch, tick = packetPlayerEntityInfo.x, packetPlayerEntityInfo.y, packetPlayerEntityInfo.z, packetPlayerEntityInfo.facing, packetPlayerEntityInfo.pitch, packetPlayerEntityInfo.tick or 5;
    -- 更新实体元数据
    local watcher = self:GetDataWatcher();
    local metadata = packetPlayerEntityInfo:GetMetadata();
    if (watcher and metadata) then 
        watcher:UpdateWatchedObjectsFromList(metadata); 
    end    

    -- 更新位置信息
    if (x or y or z or facing or pitch) then
        local oldpos = string.format("%.2f %.2f %.2f", self.x or 0, self.y or 0, self.z or 0);
        local newpos = string.format("%.2f %.2f %.2f", x or 0, y or 0, z or 0);
        if (oldpos == newpos) then 
            self:SetPositionAndRotation(x, y, z, facing, pitch);  -- 第一次需要用此函数避免飘逸
        else
            self:SetPositionAndRotation2(x, y, z, facing, pitch, tick);
        end
    end

    -- 头部信息
    local headYaw = packetPlayerEntityInfo.headYaw;
    local headPitch = packetPlayerEntityInfo.headPitch;
    if (self.SetTargetHeadRotation and headYaw ~= nil and headPitch ~= nil) then
        self:SetTargetHeadRotation(headYaw, headPitch, 3);
    end

    -- 设置玩家信息
    if (packetPlayerEntityInfo.playerInfo) then
        self:SetPlayerInfo(packetPlayerEntityInfo.playerInfo);
    end
end

-- 压力板同步触发
function EntityOtherPlayer:doesEntityTriggerPressurePlate()
    return true;
end