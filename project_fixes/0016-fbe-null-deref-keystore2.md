# 修复记录 0016: FBE 合成密码解包空指针 (SIGSEGV NULL+0x50, 5 秒重启循环)

## 真机证据 (用户)
- 基础设施全绿: servicemanager/keystore2/weaver running, sys.boot_completed=1,
  keymaster '4.x', metadata 解密成功, twrp.user.0.decrypt=1, /data/media 可见
- 仍崩: SIGSEGV NULL+0x50 主线程, ~5s 一轮 (pids 917/991/1094/1186/1265/1360)
- 崩溃前: Writing BCB → DM_DEV_CREATE failed for [odm_a] → Clearing BCB → GetBatteryInfo()
  → W recovery: Thread Pool ... serviceName: android.system.keystore2.IKeystoreService/default → SIGSEGV
- 对比: keystore2 不可用时 30s 超时后 1-3s 崩; keystore2 可用后立刻崩

## 根因 (源码)
system/vold/Decrypt.cpp  unwrapSyntheticPasswordBlob():
  ::ndk::SpAIBinder keystoreBinder(AServiceManager_checkService("...IKeystoreService/default"));
  auto keystore = ks2::IKeystoreService::fromBinder(keystoreBinder);
  auto rc = keystore->getKeyEntry(...);        // <-- checkService 非阻塞; 空代理解引用
该文件上文 (470-530) 正是 TWRP 的 "停 keystore2 → 同步 db 到 tmpfs → 重启" 流程 =>
重启窗口内服务尚未注册, checkService 返回 null => 崩溃即刻发生 (与实测吻合)
同函数另有两处: keyResponse.iSecurityLevel->createOperation(...) / encOperationResponse.iOperation->finish(...)
authorization 分支: 空服务仅打印后仍调用 service->addAuthToken(...)

## 修复 (四处判空)
1. checkService -> 复用文件内已有的有界轮询 waitForService() + 判空返回
2. iSecurityLevel 判空
3. iOperation 判空
4. authorization: 空服务时跳过调用 (else 分支)

## 交付 (build 19)
- 取件码 61248 (img, sha256 12b8be8d...8220) / 89522 (zip, sha256 4406ef42...5c01); 回下载哈希一致
- 落包验证: recovery 内新增 3 条判空字符串 (unavailable; cannot unwrap / no security level / no operation) ✓
- 回归: servicemanager.rc(disabled/user root) ✓, keystore2.rc(on late-init) ✓, start servicemanager ✓,
  keymint=2 ✓, zh_CN fox=74 ✓, recovery 4,248,376 ✓

## 后续取证建议
/data 现已可解密 => /data/tombstones/tombstone_* 可直接读取, 若仍有崩溃优先用它 + logcat -b crash -d

## 第 5 处 (build 20 尝试)
用户实测: 4 处判空生效(解密全通: user 0 解密成功, /data/media/0 可见, weaver 16B, eSE present:1),
但仍有同一签名 NULL+0x50, 现在位于"启动挂载路径"(fstab 处理后 + keystore2 lookup 之后)。
已加固两处同类隐患:
  - bootable/recovery/twrp-functions.cpp: <hal> 无 <name> 时 nameNode->value() 空指针 ([0017-1])
  - system/vold/Weaver1.cpp: AIDL/HIDL weaver 均不可用时 mDevice->getConfig() 空指针 ([0017-2])
新增取证脚本: system/bin/twrp-crash-dump.sh (汇总 /data/tombstones + logcat -b crash -> /sdcard)
