# Godot雷

Godot 4 扫雷类小游戏，源码托管于 GitHub，**网页版**通过 GitHub Actions 自动构建并发布到 GitHub Pages。

## 在线游玩

推送 `main`（或 `master`）分支且 Pages 配置完成后，访问：

**https://wxc-hub.github.io/GoDotSolei/**

（若仓库名或用户名不同，请把路径改成你的 `https://<用户>.github.io/<仓库名>/`。）

## 首次启用 Pages

1. 打开仓库 **Settings → Pages**。
2. **Build and deployment** 里 **Source** 选 **GitHub Actions**（不要选 Deploy from a branch）。
3. 将本仓库推送到 GitHub 后，在 **Actions** 里等待 **Deploy Web to GitHub Pages** 跑完；再回到 Settings → Pages 查看站点地址。

## 本地开发与导出

- CI 使用 **Godot 4.3.0** 无头导出；本机可用更高版本（如 4.6.x）开发，一般兼容。
- **本机 Godot 路径**：可在本地创建 `tools/EDITOR_PATHS.txt`（已 `.gitignore`，勿提交）；PowerShell 自检导入：  
  `powershell -NoProfile -File tools/run_godot_import.ps1`
- **字体**：`fonts/` 下需提交 **阿里巴巴普惠体** `ALIBABAPUHUITI-3-105-HEAVY.TTF` 与 `ALIBABAPUHUITI-3-115-BLACK.TTF`；主题与 `RunConfig` 使用打包 `FontFile`，**勿改回仅 SystemFont**（Web 无系统中文会乱码）。说明见 `fonts/README.txt`。
- 本地 Web 导出：编辑器 **项目 → 导出**，使用预设 **Web**，导出到任意目录即可调试。

## Web 导出说明

CI 里关闭了 **多线程 Web 导出**（`variant/thread_support=false`），以便在 GitHub Pages 默认环境下无需额外 COOP/COEP 响应头即可运行。若你自行托管并配置了跨源隔离头，可在 `export_presets.cfg` 中改回 `thread_support=true` 以提升性能。
