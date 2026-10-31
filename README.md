# dynamic_vision_720p 工程说明

## 1. 工程简介（开发环境为vivado 2022.1）

`dynamic_vision_720p` 是一套基于 Xilinx Kintex-7（器件型号 `xc7k325tffg900-2`）的 720P 三模式实时动态视觉系统。系统通过 OV5640 摄像头采集 720P 画面，经中值降噪后，在 DDR3 帧缓存支撑下提供三种可一键切换的工作模式：

1. **原始高清显示**：常规实时监控画面；
2. **动态目标提取**：识别并高亮运动物体，屏蔽静止背景，量化运动剧烈程度并可超限告警，可用于入侵检测、生产线异物判别、运动强度量化与位移测量；
3. **动态增强（欧拉视频放大）**：放大肉眼不可见的微弱变化（机械振动、呼吸、结构震颤等）。

延迟帧数、检测阈值、放大灵敏度等参数通过电容触摸屏与 LCD 液晶屏现场调节，处理结果经 HDMI 实时输出。

本目录是**自包含、可重建**的成品交付包，原 Vivado 工程及其源工程文件保持不动，本包内所有内容均为独立副本。


## 2. 目录结构

```
dynamic_vision_720p_20261029/
├─ rtl/            31 个 Verilog 源文件（全英文注释、纯 ASCII）
│  ├─ top/         系统顶层
│  ├─ camera/      OV5640 采集与 SCCB 配置
│  ├─ vip/         中值滤波视频图像管线
│  ├─ ddr3/        DDR3 MIG + 环形调度 + 跨时钟域 FIFO
│  ├─ hdmi/        HDMI 发送驱动与配置
│  ├─ algorithm/   动态提取、欧拉放大等算法
│  └─ touch_lcd/   LCD 显示与电容触摸交互（含 lcd_rgb_char、touch）
├─ constraints/    3 个 XDC 约束文件（全英文注释、纯 ASCII）
├─ ip/             6 个打包 IP（.xcix）+ MIG 目录式 IP
├─ bitstream/      成品比特流 dynamic_vision_720p.bit
├─ build/          一键重建脚本 rebuild_project.tcl
└─ doc/            本说明文档
```

## 3. 源码清单（共 31 个 Verilog 文件，module 名全局唯一）

### 3.1 顶层（1）

| 文件 | module | 作用 |
| --- | --- | --- |
| rtl/top/dynamic_vision_720p.v | dynamic_vision_720p | 系统顶层，连接摄像头采集、视频图像处理、DDR3 帧缓存、HDMI 输出与 LCD 触摸交互 |

### 3.2 摄像头采集 camera（3）

| 文件 | module | 作用 |
| --- | --- | --- |
| cmos_capture_data.v | cmos_capture_data | OV5640 像素数据采集，解析行/帧同步并输出像素流 |
| i2c_ov5640_rgb565_cfg.v | i2c_ov5640_rgb565_cfg | 经 SCCB(I2C) 初始化 OV5640 寄存器，配置 720P、RGB565 等参数 |
| ov5640_dri.v | ov5640_dri | OV5640 驱动时序与配置流程启动控制 |

### 3.3 视频图像管线 vip（6）

| 文件 | module | 作用 |
| --- | --- | --- |
| line_shift_ram_16bit.v | line_shift_ram_16bit | 基于 BRAM 的行缓存/行移位，为开窗提供相邻行数据 |
| matrix_generate_3x3_16bit.v | matrix_generate_3x3_16bit | 生成 3×3 像素窗口矩阵 |
| sort3_n.v | sort3_n | 三值排序基本单元 |
| median_chan.v | median_chan | 单通道中值排序计算 |
| median_color_rgb565.v | median_color_rgb565 | RGB565 分通道彩色中值滤波 |
| vip_color_median.v | vip_color_median | 彩色中值/色度降噪管线封装 |

### 3.4 DDR3 帧缓存 ddr3（3）

| 文件 | module | 作用 |
| --- | --- | --- |
| ddr3_fifo_ctrl.v | ddr3_fifo_ctrl | 跨时钟域打包/解包 FIFO，一路写入、当前帧与延迟帧两路读出 |
| ddr3_ring_rw.v | ddr3_ring_rw | 64 槽位环形读写调度控制器，产生 MIG 地址/命令 |
| ddr3_top.v | ddr3_top | MIG IP、环形调度与 FIFO 的整体封装 |

### 3.5 HDMI 输出 hdmi（4）

| 文件 | module | 作用 |
| --- | --- | --- |
| i2c_dri.v | i2c_dri | 配置 HDMI 芯片所用的 I2C 主控 |
| i2c_ms7210_cfg.v | i2c_ms7210_cfg | MS7210 HDMI 发送芯片寄存器配置表 |
| ms72xx_ctl.v | ms72xx_ctl | MS72xx 系列 HDMI 发送控制与配置启动 |
| video_driver.v | video_driver | HDMI 视频时序驱动，产生行/场同步与数据使能 |

### 3.6 算法 algorithm（4）

| 文件 | module | 作用 |
| --- | --- | --- |
| video_gen_720p.v | video_gen_720p | 720P 视频时序与模式视频生成 |
| dynamic_extract_565.v | dynamic_extract_565 | 帧差动态目标提取、二值化、运动强度/位移统计与超限告警 |
| dynamic_enhance_720p.v | dynamic_enhance_720p | 欧拉视频放大，时域 IIR/带通处理，状态全部存放于片上 BRAM |
| key_tick_debounce.v | key_tick_debounce | 按键消抖与单拍脉冲生成 |

### 3.7 LCD 与触摸 touch_lcd（10）

| 文件 | module | 作用 |
| --- | --- | --- |
| top_lcd_touch.v | top_lcd_touch | LCD 显示与电容触摸 UI 子系统顶层 |
| lcd_rgb_char/lcd_rgb_char.v | lcd_rgb_char | RGB LCD 显示子系统封装 |
| lcd_rgb_char/lcd_display.v | lcd_display | 绘制按钮/滑块/数值与视频叠加，并判定触摸热区 |
| lcd_rgb_char/lcd_driver.v | lcd_driver | RGB LCD 并行接口时序驱动 |
| lcd_rgb_char/clk_div.v | clk_div | LCD 像素时钟分频 |
| lcd_rgb_char/binary2bcd.v | binary2bcd | 二进制转 BCD，供参数十进制显示 |
| lcd_rgb_char/rd_id.v | rd_id | 上电读取 LCD 面板 ID 以选择时序 |
| touch/touch_top.v | touch_top | 电容触摸子系统封装 |
| touch/touch_dri.v | touch_dri | 电容触摸控制（GT9147 类），解析触点坐标与按压状态 |
| touch/i2c_dri.v | **touch_i2c_dri** | 触摸专用 I2C 主控（刻意区别于 HDMI 的 i2c_dri） |

## 4. IP 核（ip/）

| IP | 形式 | 作用 |
| --- | --- | --- |
| clk_wiz_0 | .xcix | 时钟向导，生成系统所需各时钟 |
| mig_7series_0 | 目录式（.xci + mig_a/mig_b.prj） | 7 系列 DDR3 MIG 内存控制器 |
| blk_mem_gen_0_1 | .xcix | 块存储器，用于算法行缓存与时域状态 |
| wr_fifo_1 | .xcix | DDR3 写入打包 FIFO |
| rd_fifo_1 | .xcix | 当前帧读出解包 FIFO |
| rd_fifo_dly | .xcix | 延迟帧读出解包 FIFO |

`.xcix` 为自包含打包 IP，重建时直接 `add_files` 即可；MIG 为目录式 IP，添加其 `mig_7series_0.xci`，同目录的 `.prj` 会被自动引用。

## 5. 约束文件（constraints/，加载顺序如下）

| 顺序 | 文件 | 作用 |
| --- | --- | --- |
| 1 | pin.xdc | 主引脚绑定与 `create_clock` 时钟约束 |
| 2 | timing_exceptions.xdc | 异步时钟分组等时序例外（`set_clock_groups`） |
| 3 | lcd_touch.xdc | LCD RGB888 并口与电容触摸（I2C）专用引脚 |

## 6. 比特流

`bitstream/dynamic_vision_720p.bit` 为已通过综合实现的成品比特流，可直接下载到 `xc7k325tffg900-2` 板卡验证。

## 7. 一键重建方法

环境：Vivado 2022.1，目标器件 `xc7k325tffg900-2`。

- 批处理方式：在 `build/` 目录执行
  `vivado -mode batch -source rebuild_project.tcl`
- GUI 方式：在 Vivado Tcl Console 中 `cd` 到 `build/` 目录后执行 `source rebuild_project.tcl`。

脚本使用相对脚本自身的路径定位资源，整个文件夹可整体移动。它会：创建名为 `dynamic_vision_720p` 的工程 → 添加 31 个 RTL → 按序添加 3 个约束 → 添加 6 个 `.xcix` 与 MIG → 生成 IP 输出产物 → 设置顶层 `dynamic_vision_720p` 并更新编译顺序。

**脚本只搭建工程，不自动运行综合/实现/生成比特流**。工程打开后可手动点击综合→实现→生成比特流，或在 Tcl Console 执行：

```tcl
launch_runs synth_1 -jobs 4
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
```

