#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
生成用于 OpenCV 相机标定的黑白棋盘格 PDF。

默认参数：
- 10 列 × 7 行方格
- 每格 25 mm × 25 mm
- 因此 OpenCV 内部角点数量为 9 × 6
- 输出为 A4 横向 PDF
- 打印时必须选择“实际大小 / 100%”，不要“适合页面”

安装依赖：
    pip install reportlab

运行：
    python generate_checkerboard.py

输出：
    checkerboard_10x7_25mm_A4_landscape.pdf
"""

from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.units import mm


# =========================
# 可修改参数
# =========================

COLS = 10                 # 方格列数
ROWS = 7                  # 方格行数
SQUARE_SIZE_MM = 25.0     # 每个方格边长，单位 mm

OUTPUT_FILE = "checkerboard_10x7_25mm_A4_landscape.pdf"

# True: 左上角为黑色
TOP_LEFT_BLACK = True


def generate_checkerboard_pdf():
    # A4 横向：297 mm × 210 mm
    page_width, page_height = landscape(A4)

    board_width = COLS * SQUARE_SIZE_MM * mm
    board_height = ROWS * SQUARE_SIZE_MM * mm

    # 检查是否能放入页面
    if board_width > page_width or board_height > page_height:
        raise ValueError(
            f"棋盘尺寸 {COLS * SQUARE_SIZE_MM:.1f} mm × "
            f"{ROWS * SQUARE_SIZE_MM:.1f} mm 超出 A4 横向页面。"
        )

    # 居中放置
    x0 = (page_width - board_width) / 2
    y0 = (page_height - board_height) / 2

    c = canvas.Canvas(OUTPUT_FILE, pagesize=landscape(A4))

    # 纯白背景
    c.setFillColorRGB(1, 1, 1)
    c.rect(0, 0, page_width, page_height, fill=1, stroke=0)

    square = SQUARE_SIZE_MM * mm

    # 画棋盘
    for row in range(ROWS):
        for col in range(COLS):
            is_black = ((row + col) % 2 == 0)

            if not TOP_LEFT_BLACK:
                is_black = not is_black

            # PDF 坐标原点在左下角，因此需要把 row 从“上往下”换算
            x = x0 + col * square
            y = y0 + (ROWS - 1 - row) * square

            if is_black:
                c.setFillColorRGB(0, 0, 0)
            else:
                c.setFillColorRGB(1, 1, 1)

            # 不画边框，避免额外线宽影响角点
            c.rect(x, y, square, square, fill=1, stroke=0)

    # 可选：打印少量说明文字，放在棋盘外，不影响标定
    c.setFillColorRGB(0, 0, 0)
    c.setFont("Helvetica", 9)

    inner_cols = COLS - 1
    inner_rows = ROWS - 1

    info = (
        f"Checkerboard: {COLS}x{ROWS} squares | "
        f"OpenCV inner corners: {inner_cols}x{inner_rows} | "
        f"Square: {SQUARE_SIZE_MM:.1f} mm"
    )

    c.drawCentredString(page_width / 2, 8 * mm, info)

    c.save()

    print(f"已生成: {OUTPUT_FILE}")
    print(f"棋盘实际尺寸: {COLS * SQUARE_SIZE_MM:.1f} mm × "
          f"{ROWS * SQUARE_SIZE_MM:.1f} mm")
    print(f"OpenCV pattern_size = ({inner_cols}, {inner_rows})")
    print(f"square_size = {SQUARE_SIZE_MM:.1f} mm")
    print("打印时请选择：实际大小 / 100%，不要选择“适合页面”。")


if __name__ == "__main__":
    generate_checkerboard_pdf()
