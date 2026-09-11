# 修复记录 0010: recovery 8-10s 重启循环真因 = charger 模式程序自动启动

## 真机现象 (用户, build 75640)
UI 起来后约 8 秒重启循环; 服务全 running; pstore 空; ro.boot.bootreason 空;
dmesg 被 `healthd: battery none chg=` 毫秒级刷屏。此前所有测试(插着 USB 抓 adb)均稳定。

## 根因 (代码级证据)
- `system/core/healthd/healthd_mode_charger.cpp`:
  `UNPLUGGED_SHUTDOWN_TIME = 10*1000 ms`; 属性 `ro.product.charger.unplugged_shutdown_time`
  **单位毫秒**; 未插电且无充电器 → `reboot(RB_POWER_OFF)` (软重启, 无 pstore/bootreason ✓)
  注意: 设 0 = 立即关机, 不可设 0。
- `/system/bin/charger` 服务 (system/etc/init/hw/init.rc, `critical`, 无 `disabled`, class default)
  被 `on boot: class_start default` 自动拉起 → 进入 charger 模式。
- 用户此前测试一直插 USB → `device plugged in: shutdown cancelled`; 本次拔线 → 倒计时触发。
=> 与 NFC 改动无关 (NFC 仍按用户要求改为手动门控以便二分)。

## 修复
1. `init.recovery.qcom.rc` 新增 `on init: stop charger / stop vendor.charger`
   (init 的 stop 置 SVC_DISABLED, 之后 class_start default 不再拉起)
2. `init.recovery.hlthchrg.rc` 的 `service charger /charger -r` 加 `disabled` (双保险 + 该二进制本就不存在)
3. `prop.default` 加 `ro.product.charger.unplugged_shutdown_time=86400000` (24h 冗余; 单位 ms)
4. NFC HAL 改为手动门控: `twrp.nfc=1` 启动 / `=2` 隐藏固件启动 / `=3` 恢复固件 / `=0` 停止;
   从 files_copied 自动启动中移除
5. NFC 存储路径去 /data 依赖: NFA_STORAGE -> /tmp/nfc, HAL_EVENT_LOG_STORAGE -> /tmp/nfc
6. 新增采集脚本: /system/bin/nfc_capture.sh, nfc_nofw_start.sh, nfc_fw_restore.sh

## 交付 (build 12)
- 取件码 66071 / SHA256 88a414be959a8d3afe543878c35942fa2767bf1c2c38dec24407412589b38acd (回下载一致)
- 终检: NFA_STORAGE/HAL_EVENT_LOG_STORAGE=/tmp/nfc 两 conf 均已改; stop charger/vendor.charger 就位;
  twrp.nfc 门控 4 条; hlthchrg rc disabled; prop 86400000ms; 3 个诊断脚本; NFC 件 4/4; keymint=2;
  ABI(recovery 4248272, libminuitwrp 333928) 不变
- 零刷机验证法(用 75640): 插 USB 启动应稳定/拔线后 ~10s 重启 => 确认 charger 真因
