FaceCatch GMod addon
====================

Created by Kobeblyat
Bilibili: https://space.bilibili.com/3546897006463032

Connects to ws://127.0.0.1:8667 and applies MediaPipe face data to flex
controllers and head bones.

Multiplayer:
  Players run FaceCatch.exe locally.
  The client sends expression frames to the server.
  The server relays them to other players.
  Players without GWSockets or without FaceCatch.exe running are put into
  viewer-only mode automatically.

Toolgun:
  Category: FaceCatch
  Tool: FaceCatch Target
  Left click an NPC/ragdoll/model to drive it with your face.
  Right click to use your own player model.
  Reload clears the target.

Commands:
  facecatch_connect
  facecatch_disconnect
  facecatch_status
  facecatch_dump_flexes
  facecatch_dump_mappings
  facecatch_target_info
  facecatch_target_self
  facecatch_target_clear
  facecatch_local_only
  facecatch_viewer_only

ConVars:
  facecatch_enabled 1
  facecatch_url ws://127.0.0.1:8667
  facecatch_smoothing 14
  facecatch_flex_scale 1
  facecatch_eye_sensitivity 1
  facecatch_mouth_sensitivity 1
  facecatch_head_enabled 1
  facecatch_head_scale 0.65
  facecatch_head_axis_preset 5
  facecatch_head_pitch_scale 1
  facecatch_head_yaw_scale 1
  facecatch_head_roll_scale 0
  facecatch_head_pitch_axis 1
  facecatch_head_yaw_axis 2
  facecatch_head_roll_axis 3
  facecatch_capture_enabled 1
  facecatch_multiplayer 1
  facecatch_apply_remote 1
  facecatch_apply_remote_players 1
  facecatch_network_rate 20
  facecatch_render_override 1
  facecatch_entity_render_override 1
  facecatch_auto_view 1

Notes:
  If a player starts FaceCatch.exe after joining a server, run:
    facecatch_connect

Server ConVars:
  facecatch_allow_tool 1
  facecatch_admin_only_tool 0
  facecatch_allow_player_targets 0
  facecatch_sv_max_rate 30

Models use different flex names. Use facecatch_dump_flexes in the developer
console when a model needs custom mappings.
