==============================================================
   LAPTOP AUTO CHECKER v4  -  笔记本电脑自动检测工具
   Made by Mahdi
==============================================================

For checking a second-hand laptop before you buy it.
用于购买二手笔记本电脑之前进行检测。
Works on Windows 10 / 11. Changes nothing on the laptop.
支持 Windows 10 / 11，不会修改电脑上的任何东西。

--------------------------------------------------------------
 BEFORE YOU START  /  开始之前
--------------------------------------------------------------
 1. Right-click the ZIP file -> Properties -> tick "Unblock" -> OK.
    右键点击 ZIP 文件 -> 属性 -> 勾选“解除锁定” -> 确定。
 2. Right-click the ZIP -> "Extract All". Do NOT run it from inside the ZIP.
    右键点击 ZIP -> “全部解压缩”。不要在 ZIP 里面直接运行。
 3. Connect the charger and WiFi, turn Bluetooth on.
    插上充电器，连接 WiFi，打开蓝牙。

--------------------------------------------------------------
 RUN  /  运行
--------------------------------------------------------------
 Double-click   START-LAPTOP-CHECK.bat
 双击           START-LAPTOP-CHECK.bat

 - "Windows protected your PC"? Click "More info" -> "Run anyway".
   出现“Windows 已保护你的电脑”？点击“更多信息” -> “仍要运行”。
 - It asks for Administrator permission: click "Yes".
   要求管理员权限时，点击“是”。

 What happens  /  检测过程:
   1) Automatic checks, about 3 min - just wait.
      自动检测，约 3 分钟 – 等待即可。
   2) HAND CHECKS, about 5 min - the screen tells you exactly what to do:
      手动检查，约 5 分钟 – 屏幕会告诉你每一步怎么做：
        screen colour test, keyboard picture, USB ports, webcam.
        屏幕颜色测试、键盘图片、USB 接口、摄像头。
      Press ENTER to start a step, or S + ENTER to skip it.
      按 ENTER 开始，输入 S 再按 ENTER 跳过。
   3) Heat test, about 1 min - just wait.
      发热测试，约 1 分钟 – 等待即可。
   4) Battery test, 10-40 min: when the laptop BEEPS, unplug the charger.
      When it beeps again, plug it back in. (Q = stop the test early.)
      电池测试，10-40 分钟：电脑“嘀嘀”响时拔掉充电器，再次“嘀嘀”时插回。
      （按 Q 可提前结束。）
   5) The report opens in the browser (English + 中文) and is saved in
      the "Reports" folder.
      报告会在浏览器中打开（英文 + 中文），并保存在 "Reports" 文件夹。

 The % done is always shown in the window title.
 窗口标题栏会一直显示完成百分比 (% done)。

 To stop the battery test, press Q - do not close the window with X
 (the screen brightness would stay at 100%).
 要停止电池测试请按 Q，不要用 X 关闭窗口（否则屏幕亮度会停留在 100%）。

 Problem or strange result? Send the .log file from the "Reports" folder
 (it has the same name as the report).
 遇到问题或结果异常？请把 "Reports" 文件夹里的 .log 文件发过来（与报告同名）。

--------------------------------------------------------------
 RESULTS  /  结果说明
--------------------------------------------------------------
 FAIL (red)    = serious problem -> do NOT buy           严重问题 -> 不要买
 WARN (yellow) = small problem -> ask for a lower price  小问题 -> 砍价
 PASS (green)  = OK                                      正常
 INFO (grey)   = for your information                    仅供参考

 Never buy if these FAIL / 以下项目 FAIL 绝对不要买:
   Computrace, Autopilot (stolen or company-locked laptop / 赃物或公司锁),
   Serial blank (序列号为空), Crash Cause (死机原因), Disk Scan / SMART (硬盘坏道)

 The battery "health %" can be faked. The battery test measures the REAL
 battery life.
 电池“健康度 %”可能是假的。电池测试会测量真实续航。

 At the end of the report, "Still to check by hand" lists what only a
 person can check (serial sticker, BIOS password, body, fan noise).
 报告最后的“需要手动检查的项目”列出了只能人工检查的内容
 （序列号标签、BIOS 密码、外壳、风扇噪音）。

--------------------------------------------------------------
 EXTRA TOOLS (optional)  /  其他工具（可选）  - in the Tools folder
--------------------------------------------------------------
 Tools\CrystalDiskInfo\DiskInfo64.exe  SSD / HDD health        硬盘健康
 Tools\FurMark\FurMark_GUI.exe         GPU heat test, 5-10 min (above 90 C
                                       or flickering = problem)
                                       显卡烤机 5-10 分钟（超过 90°C 或花屏 = 有问题）

 Not bundled (download from the maker if you want them):
 未附带（如需要请从官网下载）:
   CPU-Z  (CPU / RAM / motherboard details  CPU / 内存 / 主板详细信息)
          https://www.cpuid.com/softwares/cpu-z.html
   HWMonitor (CPU temperature  CPU 温度)
          https://www.cpuid.com/softwares/hwmonitor.html

 Files: app\ = the program (do not delete)   Tools\ = extra tools
 文件：app\ = 程序（不要删除）   Tools\ = 其他工具

 If the seller does not let you test the laptop -> do not buy from them.
 如果卖家不让你检测 -> 不要在那里买。
