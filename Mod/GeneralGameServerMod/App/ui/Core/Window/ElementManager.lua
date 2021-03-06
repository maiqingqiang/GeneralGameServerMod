--[[
Title: ElementManager
Author(s): wxa
Date: 2020/6/30
Desc: 元素管理器
use the lib:
-------------------------------------------------------
local ElementManager = NPL.load("Mod/GeneralGameServerMod/App/ui/Core/Window/ElementManager.lua");
-------------------------------------------------------
]]
-- NPL.load("(gl)script/ide/System/Windows/mcml/mcml.lua");
-- local mcml = commonlib.gettable("System.Windows.mcml");
-- -- 初始化基本元素
-- mcml:StaticInit();

local Element = NPL.load("./Element.lua", IsDevEnv);
local Html = NPL.load("./Elements/Html.lua", IsDevEnv);
local Style = NPL.load("./Elements/Style.lua", IsDevEnv);
local Script = NPL.load("./Elements/Script.lua", IsDevEnv);
local Div = NPL.load("./Elements/Div.lua", IsDevEnv);
local Button = NPL.load("./Elements/Button.lua", IsDevEnv);
local Label = NPL.load("./Elements/Label.lua", IsDevEnv);
local Radio = NPL.load("./Elements/Radio.lua", IsDevEnv);
local RadioGroup = NPL.load("./Elements/RadioGroup.lua", IsDevEnv);
local CheckBox = NPL.load("./Elements/CheckBox.lua", IsDevEnv);
local CheckBoxGroup = NPL.load("./Elements/CheckBoxGroup.lua", IsDevEnv);
local Select = NPL.load("./Elements/Select.lua", IsDevEnv);
local Input = NPL.load("./Elements/Input.lua", IsDevEnv);
local TextArea = NPL.load("./Elements/TextArea.lua", IsDevEnv);
local Canvas = NPL.load("./Elements/Canvas.lua", IsDevEnv);

local Component = NPL.load("../Vue/Component.lua", IsDevEnv);
local Slot = NPL.load("../Vue/Slot.lua", IsDevEnv);

local Blockly = NPL.load("../Blockly/Blockly.lua", IsDevEnv);

local ElementManager = commonlib.inherit(commonlib.gettable("System.Core.ToolBase"), NPL.export());
local ElementManagerDebug = GGS.Debug.GetModuleDebug("ElementManagerDebug").Enable();   --Enable  Disable

ElementManager.ScrollBar = NPL.load("./Controls/ScrollBar.lua", IsDevEnv);
ElementManager.Text = NPL.load("./Controls/Text.lua", IsDevEnv);

local ElementClassMap = {};

function ElementManager:ctor()
    -- 注册元素
    ElementManager:RegisterByTagName("Html", Html);
    ElementManager:RegisterByTagName("Style", Style);
    ElementManager:RegisterByTagName("Script", Script);
    ElementManager:RegisterByTagName("Div", Div);
    ElementManager:RegisterByTagName("Button", Button);    
    ElementManager:RegisterByTagName("Label", Label);    
    ElementManager:RegisterByTagName("Radio", Radio);
    ElementManager:RegisterByTagName("RadioGroup", RadioGroup);
    ElementManager:RegisterByTagName("CheckBox", CheckBox);
    ElementManager:RegisterByTagName("CheckBoxGroup", CheckBoxGroup);
    ElementManager:RegisterByTagName("Select", Select);
    ElementManager:RegisterByTagName("Input", Input);
    ElementManager:RegisterByTagName("TextArea", TextArea);
    ElementManager:RegisterByTagName("Canvas", Canvas);

    ElementManager:RegisterByTagName("Component", Component);
    ElementManager:RegisterByTagName("Slot", Slot);

    ElementManager:RegisterByTagName("Blockly", Blockly);
end

function ElementManager:RegisterByTagName(tagname, class)
    ElementClassMap[string.lower(tagname)] = class;
    -- ElementManagerDebug.Format("Register TagElement %s", tagname);
end

function ElementManager:GetElementByTagName(tagname)
    local TagElement = ElementClassMap[string.lower(tagname)];
    -- ElementManagerDebug.Format("GetElementByTagName TagName = %s", tagname);
    if (not TagElement) then ElementManagerDebug.Format("TagElement Not Exist, TagName = %s", tagname) end
    return TagElement or Element;
end

function ElementManager:GetTextElement()
    return self.Text;
end

-- 初始化成单列模式
ElementManager:InitSingleton();
