请将「已获授权、可再分发」的 UI 字体放入本目录并提交到 Git。

当前工程约定：
- ALIBABAPUHUITI-3-105-HEAVY.TTF — 正文 / 按钮（themes/app_theme.tres、autoload/run_config.gd）
- ALIBABAPUHUITI-3-115-BLACK.TTF — 主菜单与选关页标题（见 scenes/MainMenu.tscn、LevelSelect.tscn）

切勿只用 SystemFont 做 Web 主题：浏览器里没有「微软雅黑」等系统字体时中文会乱码。若 .TTF 从仓库里消失，请从本机字体目录拷回或重新下载后再提交。
