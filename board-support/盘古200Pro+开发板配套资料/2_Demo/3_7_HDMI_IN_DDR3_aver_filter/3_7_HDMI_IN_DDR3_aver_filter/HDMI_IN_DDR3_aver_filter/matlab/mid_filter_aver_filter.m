%% 均值滤波和中值滤波都用该文件
%% 读取图像
originalImage = imread('noise.png');
figure;
%% 显示原图
subplot(1, 4, 1);
imshow(originalImage);
title('原图像');
%% 灰度化 
grayImage = rgb2gray(originalImage);
%% 图像尺寸
[img_height, img_width] = size(grayImage); 
medianImage = zeros(img_height, img_width);
%% 定义参数
windowSize = 3;  % 窗口大小，奇数
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
        window = grayImage(r1:r2, c1:c2);
        
        % 计算窗口内的均值  /9  =   (*228) >> 11 
        localmedian = sum(window(:))*228.0;
        
        medianImage(i,j) = localmedian/2048.0;
    end
end
%% 无符号8bit
medianImage = uint8(medianImage);   
%% 将原图像转换为二值图像
binarizedImage = imbinarize(grayImage);

% 显示原图和处理后的图像
subplot(1, 4, 2);
imshow(grayImage);
imwrite(grayImage,'gray.png')
title('灰度化图像');

subplot(1, 4, 3);
imshow(medianImage);
imwrite(medianImage,'matlab_aver.png')
title('均值滤波图像');

subplot(1, 4, 4);
medianImage = imread('matlab_median.png');
imshow(medianImage);
title('中值滤波图像');
