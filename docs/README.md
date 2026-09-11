# 小米17 (pudding) OrangeFox Recovery 构建项目

> ## ✅ 构建成功 — 最终交付 (真机核查修正版 2026-09-10 14:01)
>
> **产物 (`BUILDS/`)**:
> - `OrangeFox-pudding-recovery.img` (= `OrangeFox-R11.3-Unofficial-sm8750.img`) — `ANDROID!` v4, ramdisk-only, 104,857,600 B
>   SHA256 `86ac82d56a80f3aca7b4243af6d2ea1e93dbd38fbf93e2f5e1cde2de032b7b06`
> - `OrangeFox-R11.3-Unofficial-sm8750.zip` (75.6MB, SignApk 签名, 内含同一个 recovery.img)
>
> **刷入 (真机确认设备有独立 recovery_a/b 分区, 100MB, 官方即 boot-format ramdisk-only)**:
> ```bash
> fastboot getvar current-slot
> fastboot --slot=<a|b> flash recovery BUILDS/OrangeFox-pudding-recovery.img
> fastboot reboot recovery
> ```
> `fastboot --slot=<a|b> flash recovery BUILDS/OrangeFox-pudding-recovery.img` ← 就是这个
>
> **⚠️ 不要刷 vendor_boot** (`OrangeFox-pudding-vendor_boot-DO-NOT-FLASH.img.bak` 仅为构建过程产物, 已弃用;
> 原厂 vendor_boot 承载 vendor 模块, 覆盖会影响正常开机)。
> **回退**: 原厂 recovery 已备份 `device_probe/stock_recovery_a.img` → 同命令回刷即可。
>
> 详见 [构建报告.md](构建报告.md) 与 [device_probe/分区信息.md](device_probe/分区信息.md)。

为 **小米17 (Xiaomi 17, 代号 pudding, 平台 xiaomi_sm8750 / SM8750)** 构建 **OrangeFox 橙狐三方 Recovery** 的完整工程。

## ⚠️ 风险提示

- 刷入三方 Recovery 可能变砖、失去保修；已解锁 Bootloader 且全盘备份后再操作，风险自负。
- 本仓库仅组装社区开源代码: 基座 (OrangeFox16) + 设备树 (antocorvo3000) + 预编译内核, 不包含任何固件机密。

## 方案概述

| 项目 | 内容 |
|---|---|
| 基座 | **OrangeFox 16.0** (社区新版, 基于 TWRP android-16 / twrp-16.0, 支持 Weaver + StrongBox + OMAPI 解密) |
| 设备树 | [antocorvo3000/twrp-xiaomi-17-series](https://github.com/antocorvo3000/twrp-xiaomi-17-series) (`twrp_device_xiaomi_pudding`) |
| 内核 | 设备树内置预编译 `Image` + `dtb.img` + `msm_drm.ko` (**免编译内核**, 大幅降低构建负载与温度) |
| 架构 | boot header v4, vendor_boot 内嵌 recovery ramdisk, 动态分区 + Virtual A/B, FBE 解密 |
| 产物 | `out/target/product/sm8750_thales/vendor_boot.img` (构建目标 `vendorbootimage`) |

> 官方 OrangeFox (GitLab, fox_12.1/fox_14.1) 只到 TWRP android-14 基座, 与本设备 (Android 16/17 时代, twrp-16 设备树) 不兼容;
> 故采用社区延续项目 **OrangeFox16** ([sync](https://github.com/OrangeFox16/sync) `--branch 16.0`)。

## 目录结构

```
OrangeFox-Xiaomi17/
├── README.md                # 本文档
├── build_pudding.sh         # 主构建脚本 (一键 all / 分步)
├── thermal_guard.sh         # 温度看门狗 (SIGSTOP/SIGCONT 节流编译)
├── orangefox16-sync/        # OrangeFox16 官方同步工具
├── device_tree/antocorvo/   # 设备树源 (pudding)
├── fox_16.0/                # 构建树 (repo 同步目标)
└── logs/                    # sync16.log / build.log / temp.log
```

## 构建

```bash
# 环境要求
# - Linux x86_64, ≥16GB 内存, ≥150GB 磁盘 (已含 30GB 交换更佳)
# - repo, git, make, python3, OpenJDK 17

# 一键 (同步 + 集成 + 编译 + 报告), 默认 -j3 + 温度看门狗
./build_pudding.sh

# 分步
./build_pudding.sh sync     # 同步 OrangeFox 16.0 源码 (40-80GB, 1-2h)
./build_pudding.sh device   # 集成 pudding 设备树
./build_pudding.sh patch    # 应用 vold GCM 解密补丁
./build_pudding.sh build    # 编译 vendor_boot
./build_pudding.sh report   # 打印产物与温度记录

# 常用参数
./build_pudding.sh --jobs 4 --stop-t 75 --resume-t 62   # 调低并行度/阈值
./build_pudding.sh --proxy http://127.0.0.1:7897        # 强制走代理
./build_pudding.sh --no-guard                           # 关闭看门狗 (不推荐)
```

## 温度监控设计

- 传感器: `k10temp` Tctl (AMD Zen), 回退 `x86_pkg_temp`/`cpu-thermal`, 再回退 `sensors` 输出。
- 机制: 编译运行在**独立进程组** (`setsid`); 看门狗对**整棵进程树** (组内 + 后代, 防 nsjail/setsid 逃逸) 发 `SIGSTOP`/`SIGCONT`;
  温度 ≥ 72°C → 全树暂停, 降温至 ≤ 58°C → 恢复; ≥ 85°C 持续 60s → 强制终止。
- 三层控温: `taskset` 限核 (默认 `0-3`, 4 逻辑核) + `-j2` 低并行 + 看门狗兜底。
  (soong bootstrap 内部并行度 = nproc, 不限制核数会直接打满 CPU; 本机实测六核满载 ~90°C。
   实测四核 + -j2 平台温度稳定 66-70°C, 看门狗几乎不介入, 净吞吐最优。)
- 日志: `logs/temp.log` 周期记录温度与 STOP/CONT/ALERT 事件; 无过温关机风险。

## 已知构建坑 (已修复, 固化于脚本)

1. **soong denylist Fatal**: OFOX16 manifest 带的 `external/magisk-prebuilt/Android.mk` 命中
   内置 denylist (`external/` 前缀), soong 每次启动即 Fatal 退出 (exit 1)。
   → 脚本自动创建 `vendor/google/build/androidmk/allowlist.txt` 加入白名单。
2. **lunch 格式**: Android 16 envsetup 用 `<product>-<release>-<variant>` 三段格式:
   `twrp_sm8750_thales-bp2a-eng` (bp2a = Android 16 release, board API 202504)。
3. **CrashRecovery APEX 校验**: soong 要求 `service-crashrecovery` 出现在
   `PRODUCT_APEX_SYSTEM_SERVER_JARS`; 已在设备树 `device.mk` 中添加该映射。
4. **构建目标**: soong 目标名为 `vendorbootimage` (无下划线)。
5. **mka**: 是 bash 函数, 子进程不可用; 脚本改用真实入口 `build/soong/bin/m`。


## 解密链修复 (pudding, 2026-09-10)

- **0008 keymint manifest**: AIDL keymint v4/v3 条目合并入 ramdisk 顶层
  `vendor/etc/vintf/manifest.xml` (TWRP 只读顶层文件, 不扫目录) → 消除 `Using keymaster version ''`。
- **0009 eSE (ST54L) bring-up**: 从设备 /odm 拉取 NFC HAL 与其依赖并集成:
  `android.hardware.nfc-service-st`、`nfc_nci.st21nfc.st.so`、`libnfc-{hal-st,nci}.conf`、
  `st54l_conf.txt`、`st54l_fw.bin` + `libnfc_vendor_extn.so`;
  recovery 适配 rc (root + seclabel recovery); `init.recovery.qcom.rc` 在 weaver 前
  `start odm.nfc_hal_service`。
  取证: Android 侧 nfc-service-st 持有 `/odm/firmware/st54l_fw.bin` + `/dev/st21nfc`,
  而 secure_element/weaver 均不持有 ST 节点 → eSE 上电与固件下载由 NFC HAL 驱动。
- 交付镜像: 取件码 **98648**(img)/**70530**(zip) —— build 22 基线 + eSE 自初始化方案B(shim)
  历史: 37466/23302 (CJK 字体+APEX), 25094/74012 (truetype 崩溃) —— 含 CJK 中文字体(DroidSansFallback) + APEX loop 挂载修复
  历史: 25094/74012 (truetype 空字体崩溃), 61248/89522 (FBE 判空) —— 修复 twrpTruetype 空字体指针崩溃(GUI 输入框资源失效)
  历史: 61248/89522 (FBE 4 处判空), 85800/73765 (服务链) —— 含 FBE 合成密码解包 4 处判空(修复 5 秒崩溃循环)
  历史: 85800/73765 (servicemanager+keystore2+VINTF) —— 含 servicemanager 启动、VINTF 去重、keystore2 recovery 适配
  历史: 66071 (charger 修复) / SHA256 `88a414be…8acd` (build 12: 修 charger 8-10s 重启循环 + NFC 手动门控)
  前一版: 75640 / `ea2a4556…8edb` (橙色狐 recovery.img, dd 写入 recovery 分区;
  含 `libstnfc-auth.so` 补漏, 取代 82529)。

## 刷入 (需已解锁 Bootloader; **务必先备份原厂 recovery/vendor_boot**)

设备为 A/B,分区节点 (来自 `device_probe/by_name.txt`): `recovery_a -> /dev/block/sde28`, `recovery_b -> /dev/block/sde70`
(无普通 `recovery` 链接, 需写当前活动槽)。镜像 SHA256: `9c6c04d9b4d9563bbf08435f91e78228add1cf46d5fe0a7c9fd39a31f413de54` (build 22)

### 方式 1: dd (Android 内, root)
```bash
adb push OrangeFox-pudding-recovery.img /sdcard/Download/
adb shell su -c 'getprop ro.boot.slot_suffix'          # 例: _a
adb shell su -c 'dd if=/sdcard/Download/OrangeFox-pudding-recovery.img of=/dev/block/by-name/recovery_a bs=1M'
# 回读校验 (期望与上面 SHA256 一致):
adb shell su -c 'dd if=/dev/block/by-name/recovery_a bs=1M 2>/dev/null | sha256sum'
```

### 方式 2: fastboot
```bash
adb reboot bootloader
fastboot flash recovery OrangeFox-pudding-recovery.img   # 自动写活动槽
fastboot reboot recovery
```

### 方式 3: 官方刷写包 (手机内, 无需 PC)
在**现有自定义 recovery** 中刷 `OrangeFox-R11.3-Unofficial-sm8750.zip` (Install -> 选 zip)。

### 已知不兼容工具
**KernelFlasher 等"内核类"App**: 本镜像与原厂一致为 v4 头 + `kernel_size=0` (内核在 `vendor_boot`),
此类 App 解析内核段时对空结果取 `[0]` 会抛 `Index 0 out of bounds for length 0` (应用侧缺陷)。
如需手机内刷写请用方式 3, 或纯 dd 类工具/终端。


> 若设备有独立 recovery 分区 (以 `fastboot getvar partition-type recovery` 为准):
> `fastboot flash recovery recovery.img`。

## 已知事项

- 设备树自带的 vold 补丁修复合成密码 GCM 认证标签切分/未初始化 bug (decrypt 关键); 若补丁上下文不匹配, 构建会跳过并告警。
- 预编译内核版本取决于设备树作者; 本机替换内核 = 替换 `device/xiaomi/sm8750_thales/prebuilt/` 下三个文件。
- 首次同步源码量大, 若中途失败请重跑 `./build_pudding.sh sync` (幂等)。

## 致谢与来源

- [OrangeFox16/sync](https://github.com/OrangeFox16/sync) - OrangeFox Android 16 基座同步工具
- [antocorvo3000/twrp-xiaomi-17-series](https://github.com/antocorvo3000/twrp-xiaomi-17-series) - 小米17 系列 TWRP 设备树 (pudding)
- [TWRP-Test](https://github.com/TWRP-Test) - twrp-16.0 基座 (bootable/recovery, system/vold, vendor/twrp)
- [MissMyTime/twrp_device_sm8850](https://github.com/MissMyTime/twrp_device_sm8850) - 同类新平台 TWRP 构建参考
- TeamWin / OrangeFox 社区

## 验收结论 (build 21, 2026-09-10)

真机 + 镜像侧双向复验通过:
- **稳定性**: 运行 93 秒 / recovery 进程 1:31 无重启; `logcat -b crash` 崩溃 0;
  界面实测切页 (`settings` -> `ext_general` -> `settings`) 稳定; 旧 `Fatal signal 11 fault addr 0x50` 不再出现
- **eSE + FBE 全链**: `isSecureElementPresent: 1` / `cardPresent: 1` -> `using weaver` -> `weaver key size is 16`
  -> `User 0 Decrypted Successfully!` -> `Data successfully decrypted`; `twrp.user.0.decrypt=1`;
  `/data/media/0` 25 项真实文件; `/data` Is_Decrypted/Is_Storage/Has_Data_Media
- **NFC 门控结论**: `twrp.nfc` 与 `odm.nfc_hal_service` 为空也能解密 —— QTI SE HAL + se_omapi 路径足够,
  门控 (`twrp.nfc`) 保持默认关闭
- **镜像侧**: sha256 3239195e...83fb 一致; ABI 闭包 MISSING=0; libminuitwrp.so md5 7c43d325...

遗留(可选, 非阻塞): 主题 `SelectPackage` 资源重建路径上字体资源会瞬时失效 (现已判空不再崩溃);
若用户反馈输入框显示异常可再追根因层。

交付: `25094` (img) / `74012` (zip)
