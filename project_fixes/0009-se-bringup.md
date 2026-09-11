# 修复记录 0009: eSE (ST54L) 在 recovery 中拉起 — weaver-thales 解密前置

## 真机结论 (用户实测 + /vendor 取证)
- 解密失败链: weaver-service.thales → OmapiTransport → secure_element 查询 isSecureElementPresent: 0
- SE 服务链其实已启动 (qti SE 服务 + se_omapi)；断点在 **eSE 未上电/未初始化**
- 设备 Android 侧 SE 栈: secure_element.qti (1204) + weaver.thales (3636) + com.android.nfc (8072) + **odm nfc-service-st (8630)**
- /dev 存在 st21nfc、st54spi_gpio 节点；ramdisk 缺 NFC HAL 与其固件

## 从设备 /odm 拉取并集成 (两棵树同步)
- odm/bin/hw/android.hardware.nfc-service-st (86,400, NFC AIDL HAL)
- odm/etc/init/nfc-service-st.rc → recovery 适配版 (user root / seclabel recovery / LD_LIBRARY_PATH)
- odm/lib64/nfc_nci.st21nfc.st.so (HAL 的 NCI 实现库)
- odm/etc/libnfc-hal-st.conf, libnfc-nci.conf, st54l_conf.txt
- odm/firmware/st54l_fw.bin (260,157) + 96_nfcCard_P_RTP.bin + 98_nfcCardSlow_P_RTP.bin
  (conf 声明 STNFC_FW_PATH_STORAGE=/odm/firmware/, STNFC_FW_BIN_NAME=st54l_fw.bin)
- vendor/lib64/libnfc_vendor_extn.so

## init 接线
`init.recovery.qcom.rc` thales 触发块: 先 `start odm.nfc_hal_service` 再 weaver/strongbox，
使 NFC/SE 芯片在应用解密前完成初始化。

## 同批修复
- 0008: keymint AIDL 条目合并入 ramdisk 顶层 vendor/etc/vintf/manifest.xml

## 决定性证据 (Android 侧 fd 取证, 2026-09-10 15:02)
android.hardware.nfc-service-st (PID 8630) 持有:
  fd 11 -> /odm/firmware/st54l_fw.bin   (固件由 NFC HAL 加载)
  fd 12 -> /odm/etc/st54l_conf.txt
  fd  8 -> /dev/st21nfc
secure_element.qti (1204) / weaver.thales (3636) 均不持有 ST 节点
=> eSE 上电与固件下载完全由 NFC HAL 驱动; recovery 中必须 start odm.nfc_hal_service (已接线)
=> 镜像 82529 (SHA256 8c71ec91...) 交付, dd 后按 getprop init.svc.odm.nfc_hal_service + logcat 验证

## 10th build 补漏 (2026-09-10 15:06)
- 闭包审计发现 `nfc_nci.st21nfc.st.so` 会 **dlopen `libstnfc-auth.so`**
  (strings: "libstnfc-auth.so not loaded: %s"), ramdisk 缺 → 已从 /vendor/lib64 拉取 (135,080) 并入
- `odm.nfc_hal_service` rc: LD_LIBRARY_PATH 追加 /vendor/lib64/hw (对齐 secure_element rc, libEseUtils 位于 hw 子目录)
- 回归: keymint 条目=2, ABI 件源码构建不变, rc 触发=1
- 交付: 取件码 75640 / SHA256 ea2a4556be409269adcf0548a99ad23e819c561b9b9a69bcdad3c70e95a58edb (回下载哈希一致)
