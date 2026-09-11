# 修复记录 0008: keymint AIDL 条目合并入 ramdisk 顶层 vintf manifest

## 症状 (真机)
TWRP: `Keymaster_Ver::Unable to find vendor manifest on the device, and no default value set. Checking the ramdisk manifest`
→ `Using keymaster version ''` (探测不到 HAL 版本)

## 根因
ramdisk 顶层 `vendor/etc/vintf/manifest.xml` (Xiaomi canoe 版) 不含 keymint；
条目在独立文件 `manifest/android.hardware.security.onekeymint-service-qti.xml` (AIDL keymint v4/v3)，TWRP 探测不读该目录。

## 修复
将 onekeymint 的 2 个 `<hal>` 条目合并进顶层 `vendor/etc/vintf/manifest.xml` (两棵树同步, 已通过 XML 校验)。

## 备注 (eSE / weaver 部分)
- SE 链路服务实际已启动: `vendor.secure_element`(qti, `on init`) + `se_omapi`(late-init) — 真机日志 pid 432/445 在跑。
- 失败点在 **eSE 硬件未上电/未枚举** (`isSecureElementPresent: 0`): ramdisk 缺 NFC 前端服务与 st21nfc 固件。
  需要设备 `/vendor` 侧文件: nfc service 二进制/rc、st21nfc 固件、相关 libs (清单见对话)。
