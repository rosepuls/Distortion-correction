SEU IP v1.4规避DDR问题修改说明

1. 通过IPC生成用户指定的SEU IP，以下说明以instance name为user_seu为例
2. 如用户需要屏蔽DDR相关帧，则不需做任何修改，SEU工作时将不对这几帧进行操作
3. 如用户不需要屏蔽DDR相关帧，则在IP生成目录找到user_seu.v，打开该文件，搜索名为“FULL_SCAN”的localparam参数
4. 手动将localparam FULL_SCAN = "FALSE";改为localparam FULL_SCAN = "TRUE";
5. 编译PDS工程，SEU将会对片上所有帧进行操作
