# RTL 分层说明

```text
rtl/
├── algorithm/          # 与 FPGA、开发板和存储控制器无关的图像算法
├── platform/common/    # 通用存储访问、缓存和跨模块接口
├── board/<board>/      # 某一块开发板的物理顶层与外设适配
└── vendor/<board>/     # 该板卡导入的供应商示例 RTL/IP 包装
```

## 换板卡规则

新增板卡时，禁止修改 `algorithm/` 中已经验证的模块。应新增：

1. `rtl/board/<board>/`：顶层、复位时钟、视频输入输出和 DDR 适配；
2. `rtl/vendor/<board>/`：供应商例程与自动生成的外设封装；
3. `boards/<board>/`：PDS 工程、约束、IP 生成参数和上板说明。

`platform/common/memory/` 的接口是算法和板级 DDR 控制器之间的边界。若新板的 DDR 控制器协议不同，应在新板目录增加适配器，不应把厂商端口带进算法模块。
