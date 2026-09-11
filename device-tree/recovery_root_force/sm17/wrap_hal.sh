#!/system/bin/sh
# [0046] 给必要的 vendor HAL 套上 LD_PRELOAD shim.
#
# 背景: 设备自带的 vendor HAL 与 recovery 内置的 servicemanager/libbinder 属于不同
# 代次(A16 recovery vs 设备 QPR), 注册时 servicemanager 报:
#   "Parcel: Expecting header 0x53595354 but found 0x564e4452. Mixing copies of libbinder?"
# 导致 HAL 注册被拒 -> 服务自杀重启循环 -> keymint/keystore2 不可用 -> metadata 解密失败.
#
# 经验(今晚实测):
#   * vendor.keymint (onekeymint)  : 必须包装, 否则崩溃循环 ✗
#   * vendor.secure_element       : **不要包装**! 包装后反而崩溃; 原生启动是好的 ✓
#   * odm.weaver_hal_service      : 有 ramdisk rc 里的 setenv, 这里再包一次无害 ✓
#
# TWRP 后续 mount_all(挂真实 vendor/odm) 会覆盖这些 bind-mount, 因此需要多轮自愈.
L=/sm17/lib64/libfoxsvcfake.so
[ -f "$L" ] || echo "[WRAP] done: keymint=$(getprop init.svc.vendor.keymint) se=$(getprop init.svc.vendor.secure_element) weaver=$(getprop init.svc.odm.weaver_hal_service) keystore2=$(getprop init.svc.keystore2)"
exit 0
echo "[WRAP] start $(date) " 

wrap() {
    BIN="$1"; R="/tmp/.fw_real_$(basename "$BIN")"; W="/tmp/.fw_wrap_$(basename "$BIN")"
    [ -e "$BIN" ] || return 0
    # [0071] 不再做"已包装则跳过"的短路(它会误判导致漏包); 总是重包, 并记录结果
    printf '%s\n' '#!/system/bin/sh' "exec env LD_PRELOAD=$L $R \"\$@\"" > "$W"
    chmod 755 "$W"
    touch "$R" 2>/dev/null
    mount --bind "$BIN" "$R" 2>/dev/null
    if mount --bind "$W" "$BIN" 2>/dev/null; then
        echo "[WRAP] ok: $BIN" 
    else
        echo "[WRAP] FAIL: $BIN"
    fi
}
for round in $(seq 1 100); do   # [0077] 持续重包(约 5 分钟): 对抗 TWRP 后续 mount_all 覆盖 bind-mount
    wrap /vendor/bin/hw/android.hardware.security.onekeymint-service-qti
    # [0054] keystore2 同样需要: vold(TWRP 内) 用 NDK checkService 查
    # "android.system.keystore2.IKeystoreService/default" 会超时(见 Keystore.cpp
    #  "Timed out waiting"), 导致 metadata 解密报 "Vold unable to connect to keystore2."
    wrap /system/bin/keystore2
    if [ "$(getprop init.svc.vendor.keymint)" != "running" ]; then
        # 注意: 不要在这里再 bind 一次"真身" —— 此时 $BIN 已被 wrap() 覆盖成 wrapper,
        # 再 bind 会把 wrapper 绑成真身, 造成无限自我 exec. wrap() 内部已正确处理.
        setprop ctl.restart vendor.keymint
    fi
    if [ "$(getprop init.svc.odm.weaver_hal_service)" != "running" ]; then
        setprop ctl.restart odm.weaver_hal_service
    fi
    if [ "$(getprop init.svc.vendor.keymint)" = "running" ] && [ "$(getprop init.svc.keystore2)" = "running" ]; then
        break
    fi
    if [ "$(getprop init.svc.keystore2)" != "running" ]; then
        setprop ctl.restart keystore2
    fi
    sleep 3
done
echo "[WRAP] done: keymint=$(getprop init.svc.vendor.keymint) se=$(getprop init.svc.vendor.secure_element) weaver=$(getprop init.svc.odm.weaver_hal_service) keystore2=$(getprop init.svc.keystore2)"
exit 0
