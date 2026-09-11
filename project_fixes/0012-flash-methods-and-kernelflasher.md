# 记录 0012: 刷写方式 + KernelFlasher 不兼容根因

## 现象
用户用 KernelFlasher 刷 OrangeFox-pudding-recovery.img 报 `index0 out of bounds for length 0`。

## 根因 (源码级)
- 应用: capntrips/KernelFlasher, `SlotViewModel.kt`:
  `magiskboot unpack` 后 `strings kernel | grep 'Linux version'` 取 `.out[0]` —— 空列表取 0 抛
  `Index 0 out of bounds for length 0` (旧发布版未判空; master 已加 isNotEmpty 守卫)。
  `PartitionUtil` 亦有多处 `wc -c <$node>.out[0]` 未判空 (root 未授权/节点错 → 同样报错)。
- 镜像无问题: v4 头 + kernel_size=0, 与原厂 `device_probe/stock_recovery_a.img` 完全同构
  (原厂 kernel_size 也是 0; 内核在 vendor_boot v4, dtb 6.5MB, vendor ramdisk 22MB)。

## 分区映射 (device_probe/by_name.txt)
recovery_a -> /dev/block/sde28 ; recovery_b -> /dev/block/sde70 ; 无普通 recovery 链接 (A/B)
分区大小 104857600 = 镜像大小

## 交付镜像哈希 (可回读校验)
img: da9c9839fd19bcf8c26f43e3c52dff39b863bd63b8ec655ee418dd8f (dd 回读同哈希)
zip: afffcb6418fd413865bf76b6f750065dda59bb65ff556df5799551879379bb3c
