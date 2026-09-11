# 修复记录 0020: AIDL 补丁级漂移 -> BAD_TYPE 注册失败 -> eSE 不上电 -> 解密失败

## 真机证据 (build 22)
- `AidlLazyServiceRegistrar: Failed to register service android.hardware.nfc.INfc/default
   (Status(-129, EX_TRANSACTION_FAILED): 'BAD_TYPE: ')` -> `Check failed: status == STATUS_OK` -> SIGABRT
- 同症状: javacard.strongbox-service(odm.keymint-strongbox-thales), vendor.xiaomi.hardware.vibratorfeature.service
- 正常注册: vendor.keymint(onekeymint), gatekeeper, secure_element, weaver
- 后果: eSE 无初始化路径 -> isSecureElementPresent: 0 -> weaver key size 失败 -> twrp.user.0.decrypt=0
- build 21 能解密 = ST54 保留了上次 Android 启动的芯片状态; 多次重启后状态丢失 => 暴露既有缺陷
- 对照实验(用户): 卸载已挂载 APEX 后仍 BAD_TYPE => 与 APEX 无关

## 根因
设备原生 HAL 的 AIDL parcel 布局由**编译进 HAL 的生成代码**(设备 A16 QPR)决定;
服务端解析在我们 Fox A16 树构建的 servicemanager(旧) -> 读不了新 parcel -> BAD_TYPE。
证据: 原厂 recovery(设备原生) 与我们的 binder 栈**全部 DIFF**:
  servicemanager 9c09a287 vs 184d7d3d; libbinder 6d4d20d3 vs 87c307ce;
  libbinder_ndk d842b8c6 vs 969dbbfb; libbase/libutils/libcutils/libvintf/libselinux/liblog 均 DIFF (libc++ SAME)
AIDL 稳定性规则: 新服务端可读旧客户端, 反之不行 => 只换服务端即可, 既有旧客户端(TWRP 侧服务)不受影响。

## 修复
1. 从原厂 recovery dump 提取设备原生 servicemanager 与其依赖(libbinder/libbinder_ndk/libbase/libutils/
   libcutils/liblog/libvintf/libselinux) -> 私有目录 /sm17/{bin,lib64} (不动 TWRP 使用的全局库)
2. system/etc/init/servicemanager.rc: exec /sm17/bin/servicemanager + LD_LIBRARY_PATH=/sm17/lib64:/system/lib64
   (源文件 frameworks/native/cmds/servicemanager/servicemanager.rc 同步)
3. 恢复 NFC HAL 自动启动: files_copied(thales) 触发块内 `start odm.nfc_hal_service` (先于 weaver)
   —— 芯片状态不跨重启保留, 必须由 recovery 自行初始化 eSE

## 方案B备件 (0021): 伪造注册 shim (运行时可切换)
- 目标: 设备原生 HAL(新 AIDL) 与旧 servicemanager 不兼容时, 让 HAL 不 abort 而继续完成硬件初始化
  (recovery 内无人需要 lookup 这些服务)
- 实现: /sm17/lib64/libfoxsvcfake.so (aarch64, 带 bionic 符号版本 @@LIBBINDER_NDK/31/34)
  伪造 AServiceManager_addService / addServiceWithFlags / registerLazyService -> STATUS_OK
  源: project_fixes/foxsvcfake.c ; 取件码 66377 (sha256 862c5b27...)
- rc 接线:
  - odm/etc/init/nfc-service-st.rc: 新增 odm.nfc_hal_service_shim (同二进制 + LD_PRELOAD),
    触发器 `on property:twrp.nfc.shim=1` (自动停普通实例) / `=0` 停用
  - strongbox-thales / vibratorfeature: 直接加 LD_PRELOAD (消掉 5 秒 SIGABRT 崩溃循环, 二者 recovery 内非必需)
- foxstart.sh: 最小 stub 入 force 目录, 消除 /sbin/foxstart.sh 127 噪音
- 离线验证: shim 可在现有机型上直接 adb push 后 LD_PRELOAD 手动起 HAL 验证 (无需刷机)

## 实测结论 (build 23, 用户真机)
1. 打包 bug: force 钩子 `cp -rf` 丢失可执行位 -> /sm17/bin/servicemanager 无法执行(Permission denied, exit 127)
   -> init.svc.servicemanager=restarting -> 全线 AIDL 客户端卡 servicemanager.ready -> 卡首屏
   修复: 钩子改 `cp -a` (保留权限)
2. **方案A前提证伪**: 换用设备原生(新) servicemanager 后, 我方 A16 旧客户端反向失败:
   `ServiceManagerCppClient: Failed to getDeclaredInstances ... BAD_TYPE` (keymint/sharedsecret 同) ->
   SE HAL Check failed -> 死。=> 混代不可行(双向), 方案A作废, 保持 ramdisk 自带 A16 servicemanager。
3. 方案B确定可行: 实测这三个设备原生 HAL 的导入符号只有
   NFC: AServiceManager_registerLazyService ; strongbox/vibratorfeature: AServiceManager_addService
   (无 getService/getDeclaredInstances/waitForService 导入) => 现有 shim 3 符号已覆盖, 无需扩面。
4. 最终接线: NFC 默认走 shim 实例 (odm.nfc_hal_service_shim, 带 LD_PRELOAD),
   twrp.nfc.plain=1 可切回原始实例; strongbox/vibratorfeature 默认带预载(消 5s SIGABRT 循环)

## 交付 (build 26 = build 22 基线 + 方案B)
- 取件码 98648 (img, sha256 ba55de80...07f3) / 70530 (zip, sha256 216eb419...eb65); 回下载哈希一致
- 落包验证:
  - servicemanager = /system/bin/servicemanager (ramdisk 原生 A16 版; 方案A的 /sm17 stock 栈已删)
  - sm17/ 仅 libfoxsvcfake.so ; NFC 默认 odm.nfc_hal_service_shim (LD_PRELOAD shim)
  - sbin/foxstart.sh -> /system/bin/foxstart.sh (symlink, 755) => 消除 127 噪音
  - 钩子: cp -a (保留权限) + 拷贝前 rm -rf sm17 (防 out 残留)
  - 回归: CJK 字体 ✓ / keymint=2 ✓ / recovery 4248392 ✓

## 终局结论 (build 26 设备实测 + 深挖, 2026-09-10)
### 已定位
1. 我们的 HAL rc 里 `LD_LIBRARY_PATH` 把 /system/lib64(我方 A16 库) 排在厂商目录前 ->
   设备原生 HAL 改用我方 libbinder_ndk -> 注册 parcel 不匹配 (BAD_TYPE)
2. 设备原生 HAL 的注册 API 分两类:
   - `addService`(vibratorfeature/strongbox 等): 手动以默认库顺序启动可成功注册(实测 vibrator ✓)
   - `registerLazyService`(NFC HAL): 即使默认顺序也失败 => lazy 注册路径与 A16 servicemanager 不兼容
3. **NFC HAL 是"客户端驱动初始化"**: 无客户端(com.android.nfc)时进程空转(sleeping, 1 线程,
   不持有 /dev/st21nfc 与固件) => shim 让 HAL 存活也无法给 ST54 上电
### 结论
冷启动(彻底掉电后)自初始化 eSE = 需要 (a) NFC HAL 真注册 + (b) 自写客户端调 INfc::open()
两者都是研究级工作量; 且 lazy 注册 API 与 A16 servicemanager 不可调和(混代已双向证伪)。
=> 保留**已验证工作流**: 掉电后先进一次 Android(其 NFC 栈会初始化 ST54), 再进 recovery 即可解密。
### 本版清理
- strongbox/vibratorfeature: 撤掉预载(无为而治, 保持 build 22 行为)
- NFC: 保留 shim 实例为默认(仅消除 abort 噪音; 明确其**不会**给 eSE 上电) + twrp.nfc.plain=1 切回原实例
- foxstart symlink 保留(消除 127 噪音)
