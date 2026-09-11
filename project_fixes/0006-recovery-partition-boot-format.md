# 真机核查修正: recovery 走独立分区 (boot-format, ramdisk-only)

依据 (2026-09-10 真机只读探查, device_probe/):
- 设备存在 recovery_a/recovery_b 分区, 各 104,857,600 B (100MB)
- 原厂 recovery_a 镜像 = `ANDROID!` boot header v4, kernel_size=0, LZ4 ramdisk (27MB) —— ramdisk-only
- 作者发布版同为该格式; 原厂 vendor_boot 为 VNDRBOOT (仅 vendor ramdisk, 不含 recovery)

## BoardConfig.mk 变更 (device/xiaomi/sm8750_thales/BoardConfig.mk)
- 移除: `TARGET_NO_RECOVERY := true`
- 移除: `BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT` / `BOARD_INCLUDE_RECOVERY_RAMDISK_IN_VENDOR_BOOT`
- 新增: `BOARD_RECOVERYIMAGE_PARTITION_SIZE := 104857600`
- 新增: `BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE := true`

## 构建目标
- `mka adbd recoveryimage` → out/target/product/sm8750_thales/recovery.img (ANDROID! v4, kernel 空, LZ4)

## 刷入 (务必)
- `fastboot --slot=<a|b> flash recovery recovery.img`
- **不要刷 vendor_boot** (原厂 vendor_boot 承载 vendor 模块; 本项目早期 VNDRBOOT 产物已弃用)

## 回退
- 原厂 recovery_a 已完整备份: `device_probe/stock_recovery_a.img`
  SHA256 `af47e407311d4d7598739452...` (104,857,600 B) → 回刷即可恢复原厂 recovery
