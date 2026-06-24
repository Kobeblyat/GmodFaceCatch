TOOL.Category = "FaceCatch"
TOOL.Name = "#tool.facecatch.name"
TOOL.Command = nil
TOOL.ConfigName = ""

if CLIENT then
    language.Add("tool.facecatch.name", "FaceCatch 面捕")
    language.Add("tool.facecatch.desc", "同步面部表情到玩家、NPC 或模型实体。")
    language.Add("tool.facecatch.0", "左键：把你的面捕绑定到目标。右键：回到自己。R：清除目标。")
end

function TOOL:LeftClick(trace)
    if CLIENT then return true end
    if not trace or not IsValid(trace.Entity) then return false end
    if not FaceCatch_SetTarget then return false end
    return FaceCatch_SetTarget(self:GetOwner(), trace.Entity)
end

function TOOL:RightClick(trace)
    if CLIENT then return true end
    if not FaceCatch_SetTarget then return false end
    return FaceCatch_SetTarget(self:GetOwner(), self:GetOwner())
end

function TOOL:Reload(trace)
    if CLIENT then return true end
    if not FaceCatch_ClearTarget then return false end
    return FaceCatch_ClearTarget(self:GetOwner())
end

local function addCollapsible(panel, title, expanded)
    local category = vgui.Create("DCollapsibleCategory", panel)
    category:SetLabel(title)
    category:SetExpanded(expanded or false)
    category:Dock(TOP)

    local form = vgui.Create("DForm", category)
    form:SetName("")
    if form.SetPadding then form:SetPadding(6) end
    if form.SetSpacing then form:SetSpacing(4) end
    category:SetContents(form)

    panel:AddItem(category)
    return form
end

function TOOL.BuildCPanel(panel)
    panel:AddControl("Header", {
        Description = "FaceCatch by Kobeblyat - 多人面捕、观看设置和目标绑定。"
    })

    panel:Help("工具枪：左键绑定 NPC/模型/布娃娃，右键回到自己，R 清除目标。")

    panel:Help("连接 / 本地采集")
    panel:Button("连接面捕 / 重新连接", "facecatch_connect")
    panel:Button("断开面捕", "facecatch_disconnect")
    panel:Button("只看别人，不采集自己", "facecatch_viewer_only")
    panel:Button("本地模式：不发也不看别人", "facecatch_local_only")
    panel:CheckBox("启用 FaceCatch 插件", "facecatch_enabled")
    panel:CheckBox("启用本机摄像头采集", "facecatch_capture_enabled")

    panel:Help("多人观看")
    panel:CheckBox("把我的表情同步给服务器", "facecatch_multiplayer")
    panel:CheckBox("观看别人 / NPC 的同步表情", "facecatch_apply_remote")
    panel:CheckBox("观看其他玩家模型的表情", "facecatch_apply_remote_players")
    panel:CheckBox("进服自动开启观看别人表情", "facecatch_auto_view")
    panel:CheckBox("多人绘制前强制刷新表情", "facecatch_render_override")
    panel:CheckBox("NPC/模型绘制前强制刷新表情", "facecatch_entity_render_override")

    panel:Help("表情灵敏度")
    panel:NumSlider("整体表情强度", "facecatch_flex_scale", 0, 2, 2)
    panel:NumSlider("眨眼灵敏度", "facecatch_eye_sensitivity", 0.2, 2.5, 2)
    panel:NumSlider("嘴巴开合灵敏度", "facecatch_mouth_sensitivity", 0.2, 2.5, 2)
    panel:NumSlider("平滑度 / 越高越跟手", "facecatch_smoothing", 1, 40, 0)

    local head = addCollapsible(panel, "高级：头部动作 / 轴向校准", false)
    head:Help("默认收起。只有头部方向不对、上下看不动、或者歪脖子时再打开这里。")
    head:CheckBox("启用头部转动", "facecatch_head_enabled")
    head:Button("Tomorin/PM 安全预设", "facecatch_head_preset_tomorin")
    head:Button("上下点头备用轴", "facecatch_head_preset_pitch_alt")
    head:Button("Source 通用预设", "facecatch_head_preset_source")
    head:Button("左右转反了就点这个", "facecatch_head_preset_invert_yaw")
    head:Button("关闭头部转动", "facecatch_head_off")
    head:NumSlider("头部总强度", "facecatch_head_scale", 0, 2, 2)
    head:NumSlider("上下点头强度", "facecatch_head_pitch_scale", -2, 2, 2)
    head:NumSlider("左右转头强度", "facecatch_head_yaw_scale", -2, 2, 2)
    head:NumSlider("歪头强度", "facecatch_head_roll_scale", -2, 2, 2)
    head:NumSlider("点头轴 0/1/2/3关", "facecatch_head_pitch_axis", 0, 3, 0)
    head:NumSlider("左右轴 0/1/2/3关", "facecatch_head_yaw_axis", 0, 3, 0)
    head:NumSlider("歪头轴 0/1/2/3关", "facecatch_head_roll_axis", 0, 3, 0)
    head:Help("轴说明：0=Pitch，1=Yaw，2=Roll，3=关闭。Tomorin 默认把上下点头放到 1 轴；如果上下仍不动，点“上下点头备用轴”。")

    local advanced = addCollapsible(panel, "高级：网络 / 调试", false)
    advanced:NumSlider("同步帧率", "facecatch_network_rate", 1, 30, 0)
    advanced:Button("打印 FaceCatch 状态", "facecatch_status")
    advanced:Button("打印当前目标信息", "facecatch_target_info")
    advanced:Button("打印当前模型 Flex", "facecatch_dump_flexes")
    advanced:Button("打印当前映射", "facecatch_dump_mappings")
end
