# 记录 0022: 冷启动 eSE 自初始化 —— 探究过程与结论

## 目标
掉电后直接进 recovery 也能解密 (无需先开一次 Android)。

## 已确认的机制
1. ST54 eSE 的"已初始化"状态**跨重启保留**(芯片不断电), 但**丢失后 recovery 无法自行恢复**
2. Android 侧初始化链: com.android.nfc → NFC HAL(`android.hardware.nfc-service-st`) → 
   `hal_wrapper_open()` → 打开 /dev/st21nfc + 复位脉冲 + NCI bring-up + **固件下载**
   (Android 侧 fd 取证: HAL 持有 /dev/st21nfc + /odm/firmware/st54l_fw.bin + /odm/etc/st54l_conf.txt)
3. recovery 内 NFC HAL 不能注册: `registerLazyService`(lazy API) 与 ramdisk 的 A16 servicemanager
   不兼容(BAD_TYPE); 且该 HAL 是**客户端驱动初始化**(无客户端则空转, 不碰芯片)
4. 换设备原生 servicemanager(方案A)已双向证伪: 我方旧客户端 getDeclaredInstances 反向 BAD_TYPE

## 绕开 HAL 的尝试(PoC: project_fixes/st54init-poc.so + st54init3.c)
直接 dlopen `/odm/lib64/nfc_nci.st21nfc.st.so` (ST 官方 NCI 库, 内含 FwUpdateHandler/mFwUpdateTask/
CNfcConfig 等) 并调用其导出入口:
- `CNfcConfig::GetInstance()` + `readConfig("/odm/etc/libnfc-hal-st.conf"|"libnfc-nci.conf")` ✓ 成功
- `hal_wrapper_open(st21nfc_dev_t*, cb1(u8,u8), cb2(u16,u8*), void**)` ✓ 返回成功
- 结果: 打开 /dev/st21nfc ✓、`i2cResetPulse result=0` ✓、`message_pump_thr` 启动 ✓,
  但 `i2cRead returns -1 errno 107 (ENOTCONN)` → **芯片不应答** → 固件下载未触发 → eSE 仍为 0 ✗
- 注意: hal_wrapper_open 内部会调 hal_fd_init, 不能重复调用(会 Device busy)

## 结论
冷启动自初始化需要复刻 ST 的完整 bring-up(上电/使能时序 + NCI 序列 + 固件传输),
属研究级工作量, 成功率不确定。
=> **保留已验证工作流**: 掉电后先正常开机 Android 一次(NFC 栈完成 ST54 初始化), 再进 recovery 即解密。
## 其它发现
- `failed to unmount /vendor`: 12+ 个解密/安全链 HAL 映射了 /vendor 的库 => 必然 busy;
  纯提示, 不影响解密/UI。需要卸载时用 system/bin/release_vendor.sh (停服务后 umount -l)
