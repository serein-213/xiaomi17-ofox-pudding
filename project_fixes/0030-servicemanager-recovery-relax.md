# 修复记录 0030: recovery 版 servicemanager 放宽注册/查找门控 (冷启动 eSE 前置)

## 背景 (冷启动 eSE 攻克链)
设备原生 NFC HAL 是 eSE(ST54) 的唯一初始化者; recovery 冷启动时它注册失败 (rc=-3) =>
芯片无人初始化 => weaver 无密钥 => 解密失败。

## 根因 (源码)
frameworks/native/cmds/servicemanager/ServiceManager.cpp:
- canAddService()/canFindService(): `mAccess->canAdd/canFind()` (SELinux service_contexts 等) 在
  recovery 上下文 (u:r:recovery:s0) 下拒绝 -> "SELinux denied for service" (实测 rc=-3)
- meetsDeclarationRequirements(): 要求 VINTF 声明; ramdisk 清单不含 nfc/strongbox/vibratorfeature 等
## 修复 (recovery 专属 servicemanager, 仅存于 ramdisk)
1. canAddService: 拒绝时仅告警, 继续放行
2. canFindService: 同上
3. meetsDeclarationRequirements: 未声明时告警并放行
另: odm/etc/vintf/manifest/{nfc-service-st.xml, keymint strongbox-thales, vibratorfeature} 已加入
    force 目录 (权威声明取自真机 /odm 分区)
## 后续
- 真注册后, 需由客户端调用 INfc::open() 触发芯片初始化(shim v7 已内置进程内调用尝试)

## 冷启动 eSE 攻克进度 (2026-09-10 深夜)
1. ✅ NFC HAL 真注册 (servicemanager 放行 + shim 转发 addService)
2. ✅ 调用 INfc::open() 成功: 修正 AIBinder_transact 参数顺序为 (binder, code, in, out, flags)
   -> HAL 打开 /dev/st21nfc + /odm/firmware/st54l_fw.bin + st54l_conf.txt (芯片上电+固件下载)
3. ✅ weaver 初始化成功 (weaver-impl Init Exit : SUCCESS, 此前 -129)
4. ⏳ QTI SE HAL 的 GPQeSE TA: qseecomd 报 fail to open /vendor/firmware_mnt/image/*.b00
   根因: (a) recovery 里 /vendor/firmware_mnt 被 TWRP 挂载成"空视图"(重新挂 sde7 后可见 458 个 TA ✓);
        (b) SE HAL 的 rc 是 `on init: start vendor.secure_element` -> 比挂载还早
   修复: files_copied 触发块内 umount+重新挂载 modem_a 到 /vendor/firmware_mnt 与 /vendor/firmware,
       然后才 start vendor.secure_element

## 冷启动 eSE 全线打通 (2026-09-10 深夜, 实测)
1. ✅ 真注册: servicemanager 放行 + shim 拦截 addService/registerLazyService 转发真实实现 (rc=0)
2. ✅ NFC HAL: shim 内调用 INfc::open() -> 芯片上电 + 固件下载 (持有 st21nfc/st54l_fw.bin)
3. ✅ 修正 AIBinder_transact 参数顺序 (binder, code, in, out, flags)
4. ✅ SE HAL: 重挂 modem 分区(TA 可见) + shim 预载 -> GPQeSE-HAL TEEC_OpenSession 成功,
   与 eSE 真实 APDU 交互 (rApdu: C8008131FE008066D0026A15E0012C), 不再 abort
5. ✅ weaver: shim 预载 -> 存活 (init 未预载的实例仍 -129 abort)
=> 下一版(构建 32)把 shim v11 预载接入 weaver/SE HAL/strongbox/vibratorfeature, 冷启动解密应全通
