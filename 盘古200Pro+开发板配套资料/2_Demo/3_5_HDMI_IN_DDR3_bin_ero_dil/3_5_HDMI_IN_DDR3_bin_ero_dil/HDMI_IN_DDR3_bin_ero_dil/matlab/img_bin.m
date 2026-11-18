%% 结合AI工具生成
%% 读取图像  完成腐蚀膨胀
originalImage = imread('tttt.jpeg');
figure;
%% 显示原图
subplot(2, 3, 1);
imshow(originalImage);
title('原图像');
%% 灰度化 
grayImage = rgb2gray(originalImage);
%% 图像尺寸
[img_height, img_width] = size(grayImage); 
binaryImage = zeros(img_height, img_width);
%% 定义参数
windowSize = 27;  % 窗口大小，奇数
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
        
        % 计算窗口内的均值
        localMean = mean(window(:));
        
        % 计算阈值
        threshold = localMean*0.9;
        
        % 局部二值化处理
        if grayImage(i, j) < threshold
            binaryImage(i, j) = 0;
        else
            binaryImage(i, j) = 255;
        end
    end
end
%% 无符号8bit
binaryImage = uint8(binaryImage);
%% 将原图像转换为二值图像
binarizedImage = imbinarize(grayImage);


%% 腐蚀
%% 定义参数
windowSize = 5;  % 窗口大小，奇数
%% 遍历像素 计算窗口均值
halfWindowSize = floor(windowSize / 2);
erodedImage = zeros(img_height, img_width);
for i = 1:img_height
    for j = 1:img_width
        % 窗口边界
        r1 = max(i - halfWindowSize, 1);    %窗口上边界
        r2 = min(i + halfWindowSize, img_height); %窗口下边界
        c1 = max(j - halfWindowSize, 1);    %窗口左边界
        c2 = min(j + halfWindowSize, img_width); %窗口右边界
        
        % 提取窗口
        window = binaryImage(r1:r2, c1:c2);
        
        % 计算窗口内的最小值
        localMin = min(window(:)); 
        
        % 进行腐蚀操作
        erodedImage(i, j) = localMin;
    end
end


%% 膨胀
dilatedImage = zeros(img_height, img_width);
%% 定义参数
windowSize = 5;  % 窗口大小，奇数
%% 遍历像素 计算窗口均值
halfWindowSize = floor(windowSize / 2);
for i = 1:img_height
    for j = 1:img_width
        % 窗口边界
        r1 = max(i - halfWindowSize, 1);    %窗口上边界
        r2 = min(i + halfWindowSize, img_height); %窗口下边界
        c1 = max(j - halfWindowSize, 1);    %窗口左边界
        c2 = min(j + halfWindowSize, img_width); %窗口右边界
        
        % 提取窗口
        window = erodedImage(r1:r2, c1:c2);
        
        % 计算窗口内的最小值
        localmax = max(window(:));
        
        % 进行腐蚀操作
        dilatedImage(i, j) = localmax;
    end
end


% 显示原图和处理后的图像
subplot(2, 3, 2);
imshow(binarizedImage);
title('原二值图像');

subplot(2, 3, 3);
imshow(binaryImage);
title('局部二值化图像');


subplot(2, 3, 4);
imshow(erodedImage);
title('局部二值化腐蚀图像');


subplot(2, 3, 5);
imshow(dilatedImage);
title('局部二值化腐蚀、膨胀后的图像');