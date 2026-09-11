# 修复记录 0013: AIDL servicemanager 未启动 -> recovery 卡 splash

## 现象 (用户真机 + adbd 取证)
- /tmp/recovery.log 停在 "Using additional fstab for decryption"; UI 永远 "Switching packages (splash)"
- logcat: `E recovery: Waited for servicemanager.ready for a second, waiting another...` (连 recovery 自己都在等)
- 11 个 AIDL 服务(HAL/keystore 链) 同卡; init.svc.recovery=running (非崩溃)
- init 从未 "starting service 'servicemanager'"

## 根因 (与原厂 recovery 对比)
- 原厂 system/etc/init/hw/init.rc 的 on init: `start servicemanager`; 且原厂**只提供**
  `servicemanager.recovery.rc` (disabled + user root + seclabel + onrestart setprop ready false)
- 本 ramdisk (TWRP/OF 源) 的 init.rc 无 start servicemanager; 仅有系统版
  `servicemanager.rc` (user system + class core animation, 无 disabled) —— recovery 中
  无 passwd 用户 system 且无 class_start core => 从未启动

## 修复 (mirror 原厂)
1. overlay 覆盖 system/etc/init/servicemanager.rc 为 recovery 适配版
   (disabled, user root, group system readproc, onrestart setprop servicemanager.ready false,
    seclabel u:r:servicemanager:s0 —— 我方 sepolicy 已定义该域, strings sepolicy 8 处)
2. init.recovery.qcom.rc 的 on init 增加 `start servicemanager` (原厂同位置)
预期: servicemanager 起 -> servicemanager.ready=true -> (我方 rc 已 setprop sys.boot_completed)
      -> 11 个 HAL 注册 -> UI 越过 splash。
