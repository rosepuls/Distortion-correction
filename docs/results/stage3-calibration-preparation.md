# 阶段 3：真实相机标定准备

日期：2026-10-19。用户尚未拍摄标定照片，因此目前没有真实内参、畸变系数、重投影误差或 FPGA 矫正对比图。

已备好 `host/calibration/calibrate.py`、`host/reference/render_reference.py`、`host/calibration/export_fixed_parameters.py`、`host/calibration/make_checkerboard_svg.py` 和 A4 9×6 / 25 mm 棋盘格 SVG。工具要求原始 1280×720 图像、至少 20 张成功检测的不同棋盘格姿态；自动记录被拒收图像原因、每张图的重投影误差以及完整的 `k1,k2,p1,p2,k3`。软件参考图使用完整系数，保存四邻域有效掩码和所用输出相机矩阵；不会把 `k3` 静默删除。定点导出只有在 `k3` 对源坐标的最大影响不超过 0.5 像素时才允许继续。

下一步由现场采集真实工业相机照片并提供棋盘格实测格距。操作命令见 `host/README.md`。收到图像后才运行标定、分析 `k3` 的像素影响，并确定四系数 FPGA 核心是否必须增加 `k3`。目前 RGBX8888 位流只报告“用户反馈画面正常”，长时间稳定性和纯色图仍待记录。
