# 修复记录 0014: VINTF 重复声明 (0008 副作用) -> AIDL 服务发现失效

## 现象 (用户真机)
- servicemanager 报 `Conflicting FqInstance ... NULL VINTF MANIFEST!: device`;
  `VINTF parse error` 频发, AIDL 服务发现失效 (se_omapi 死循环找 ISecureElement/eSE1)
- 手动把 /vendor/etc/vintf/manifest/android.hardware.security.onekeymint-service-qti.xml
  移走后 parse error = 0, UI 进入主界面

## 根因
0008 把 keymint AIDL v4/v3 合并进 ramdisk 顶层 vendor/etc/vintf/manifest.xml,
但未撤掉同目录分文件 -> 同一 FQInstance 声明两次:
  android.hardware.security.keymint.IKeyMintDevice/default            (顶层 + 分文件)
  android.hardware.security.keymint.IRemotelyProvisionedComponent/default (顶层 + 分文件)

## 修复
保留顶层 (TWRP 只读顶层, keymaster 版本显示依赖它), 移除冲突分文件 (双树, 已归档
project_fixes/vintf-dup-keymint-fragment-removed-20260910.tar.gz)。
其余 9 个分文件与顶层无 fqname 重叠 (secure_element: 顶层 eSE1 vs 分文件 SIM1/SIM2) -> 保留。

## 同批 (0013)
- servicemanager: overlay 覆盖 system/etc/init/servicemanager.rc 为 recovery 适配版
  (disabled + user root + seclabel) + init.recovery.qcom.rc `on init: start servicemanager`
