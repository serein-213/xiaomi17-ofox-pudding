# 修复记录 0027: flashlight(闪光灯)不可用

## 根因
OFOX 的 flashlight 实现在 gui/action.cpp::flashlightImpl():
- 读 DataManager 变量 `of_fl_path_1` / `of_fl_path_2` 作为 LED 节点路径
- 两者都为空时回退到 `/sys/class/leds/flashlight/brightness` 或 `/sys/class/leds/led:torch_0`+`led:switch_0`
本机 LED 节点是 multi-flash 命名: `white:flash-1`(冷) / `yellow:flash-0`(暖) / `amber:flash-2`,
主题未设置 of_fl_path_* => 回退路径不存在 => "Flashlight file not found!" / 无反应。

## 实测
`echo 255 > /sys/class/leds/white:flash-1/brightness` -> readback 255 ✓ (root 可写 ✓, max_brightness=255 ✓)

## 修复
设备树 twres/themes/action.xml 的 <variables> 增加:
  <variable name="of_fl_path_1" value="/sys/class/leds/white:flash-1"/>
  <variable name="of_fl_path_2" value="/sys/class/leds/yellow:flash-0"/>
(OF_FLASHLIGHT_ENABLE 默认 "1" (orangefox.mk), 按钮本身存在 ✓)

## 修正 (真正生效的路径)
主题变量不够: data.cpp:858 用**编译宏** OF_FL_PATH1/2 (mConst 常量, 覆盖主题变量) 设置 of_fl_path_*;
orangefox.mk:269 支持 make 变量 OF_FL_PATH1/OF_FL_PATH2 (缺省为空串) => 必须在**设备树 BoardConfig.mk** 设置:
  OF_FL_PATH1 := /sys/class/leds/white:flash-1
  OF_FL_PATH2 := /sys/class/leds/yellow:flash-0
(主题变量保留作双保险; 真机实测: 主题变量未生效, 报 "Flashlight file not found!")
