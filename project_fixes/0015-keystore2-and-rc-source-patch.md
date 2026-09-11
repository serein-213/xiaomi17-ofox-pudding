# 修复记录 0015: keystore2 在 recovery 中启动 + rc 源文件优先级

## 现象 (用户真机, 第三层)
fscrypt_mount_metadata_encrypted -> "Retrieving key from keymaster"
-> "Timed out waiting for android.system.keystore2.IKeystoreService/default" (30s, 我方 waitForService 轮询)
-> "Vold unable to connect to keystore2." -> "read_key failed in mountFstab"
-> 之后 GetBatteryInfo 路径 SIGSEGV (NULL+0x50)

## 根因
1. keystore2 服务定义 (system/etc/init/keystore2.rc) 在 ramdisk 中是 AOSP 库存版:
   `user keystore`(recovery 无 passwd 该用户) + 工作目录 /data/misc/keystore(未解密不可用)
   + `critical window=0`(崩溃会触发重启) -> 从未启动
2. 设备树 recovery/root 里的适配版(作者已写: /tmp/misc/keystore + user root + on late-init start)
   **未进包** —— 构建模块安装会覆盖 overlay 同名文件 (仅 root 级 overlay 如 init.recovery.qcom.rc 生效)
   证据: ramdisk 的 servicemanager.rc md5 == frameworks/native/cmds/servicemanager/servicemanager.rc(系统版);
   TWRP 自带适配版 bootable/recovery/etc/init/servicemanager.rc 从未进包。

## 修复 (改真正进包的源)
1. frameworks/native/cmds/servicemanager/servicemanager.rc <- TWRP 适配版
   (user root + disabled + seclabel u:r:recovery:s0 + on init start)
2. system/security/keystore2/keystore2.rc <- recovery 适配版
   (/tmp/misc/keystore, user root, group root, seclabel recovery, on late-init start, 去掉 critical)
3. init.recovery.qcom.rc: on init 预建 /tmp/misc 与 /tmp/misc/keystore
4. 双树 overlay 副本同步保持(文档/保险)

## 审计结论 (overlay 有效性)
- root 级 overlay(init.recovery.qcom.rc 等) 生效 ✓
- system/ 下由构建模块安装的文件: overlay 被覆盖 -> 必须改源
- 全量审计: overlay 5223 same / 114 diff(多为源码构建的 system/bin 二进制, 预期) / 17 missing(目录符号链接)

## 覆盖失效的最终解法 (force 钩子)
现象: 设备树 recovery/root overlay 对 system/etc/init/*.rc 无效 —— out 里该文件 mtime 停在旧时间;
      我们自己的 [ABI修复] 步骤会把 $(PRODUCT_OUT)/system/... 的(陈旧)副本回拷覆盖 overlay。
解法: 新增 device/xiaomi/sm8750_thales/recovery_root_force/ (存放必须最后落盘的文件),
      build/make/core/Makefile recovery recipe 尾部(ramdisk-files.txt 生成之前)追加:
      $(if $(wildcard $(TARGET_DEVICE_DIR)/recovery_root_force), cp -rf .../recovery_root_force/. $(TARGET_RECOVERY_ROOT_OUT)/, true)
内容: system/etc/init/servicemanager.rc (user root/disabled/seclabel),
      system/etc/init/keystore2.rc (on late-init start + /tmp/misc/keystore + user root)

## 交付 (build 18)
- 取件码 85800 (img, sha256 f3e76723...b581d) / 73765 (zip, sha256 b7b20471...7def9)
- 落包验证: servicemanager.rc == force 版(md5 5d083ed2); keystore2.rc adapted;
  init.recovery.qcom.rc: start servicemanager + mkdir /tmp/misc (+0010/0013 全部保留); keymint=2; zh_CN fox=74
