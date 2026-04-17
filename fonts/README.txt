本目录可放置「已获授权、可再分发」的 UI 字体文件（例如 .ttf / .otf），并在 autoload/run_config.gd 的 OPTIONAL_BUNDLED_UI_FONT 中填写 res://fonts/你的文件.ttf。

不放置任何文件时：项目使用 themes/app_theme.tres 内的 SystemFont（微软雅黑 / 苹方 / Noto CJK 等系统栈），适合本机与 Godot Web 导出；GitHub Actions 会在导出前安装 fonts-noto-cjk 以便 Linux 无头环境能解析中文轮廓。
