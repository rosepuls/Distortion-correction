%% 高斯滤波
clc;clear all;
%% 读取图像
originalImage = imread('noise.png');
figure;
%% 定义高斯核
gaussianKernel = [1, 2, 1; 2, 4, 2; 1, 2, 1];%和为16
%% 显示原图
subplot(1, 3, 1);
imshow(originalImage);
title('原图像');
%% 灰度化 
grayImage = rgb2gray(originalImage);
%% 图像尺寸
[img_height, img_width] = size(grayImage); 
medianImage = zeros(img_height, img_width);
%% 定义参数
windowSize = 4;  % 窗口大小 实际大小
%% 遍历像素 计算窗口均值
halfWindowSize = floor(windowSize / 2);
for i = 1:img_height
    for j = 1:img_width
        % 窗口边界
        r1 = max(i - halfWindowSize, 1);    %窗口上边界
        r2 = min(i + halfWindowSize, img_height);%窗口下边界
        c1 = max(j - halfWindowSize, 1);%窗口左边界
        c2 = min(j + halfWindowSize, img_width);%窗口右边界
        
        % 提取窗口
        window = double(grayImage(r1:r2, c1:c2));
        
        % 计算窗口内的卷积
        sum_gauss = window(1,1)*gaussianKernel(1,1)+window(1,2)*gaussianKernel(1,2)+window(1,3)*gaussianKernel(1,3)+...
                    window(2,1)*gaussianKernel(2,1)+window(2,2)*gaussianKernel(2,2)+window(2,3)*gaussianKernel(2,3)+...
                    window(3,1)*gaussianKernel(3,1)+window(3,2)*gaussianKernel(3,2)+window(3,3)*gaussianKernel(3,3);
        medianImage(i,j) = sum_gauss/16;
    end
end
%% 无符号8bit
medianImage = uint8(medianImage);   
%% 将原图像转换为二值图像
binarizedImage = imbinarize(grayImage);

% 显示原图和处理后的图像
subplot(1, 3, 2);
imshow(grayImage);
imwrite(grayImage,'gray.png')
title('灰度化图像');

subplot(1, 3, 3);
imshow(medianImage);
imwrite(medianImage,'matlab_gauss.png')
title('高斯滤波图像');
