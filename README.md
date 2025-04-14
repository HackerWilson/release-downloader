# Release Downloader 🚀

**GitHub Release资源文件下载工具**  
支持多版本选择、批量下载、跨平台运行，高效获取GitHub Release资源文件

## 📦 依赖安装

- **Gum CLI** (终端交互框架)
  - 安装 [charmbracelet/gum](https://github.com/charmbracelet/gum?tab=readme-ov-file#installation) 

- **GitHub CLI** (API访问工具)
  - 安装 [cli/cli](https://github.com/cli/cli?tab=readme-ov-file#installation) 

  - 认证登录 (必做)
  ```
  gh auth login  # 选择HTTPS协议完成浏览器认证
  ```

---

## 🛠️ 使用说明

### 参数模式 (CLI)
```bash
./release-downloader.sh <owner/repo>
# 示例：
./release-downloader.sh charmbracelet/gum
```

### 交互模式 (TUI)
```bash
./release-downloader.sh
▸ 输入仓库：folo-project/releases
▸ 选择版本：v0.4.2
▸ 选择文件：空格多选 → 回车确认
▸ 下载路径：./downloads (支持自动创建目录)
```

---

## ✨ 核心功能

1. **智能版本列表**  
   - 自动获取最近50个Release版本
   - 支持关键字实时过滤（如输入"beta"筛选测试版）

2. **多选下载模式**  
   - 支持批量勾选资源文件
   - 自动识别不同平台包（*.dmg/*.exe/*.AppImage）

3. **精准统计系统**  
   ```bash
   ✅ 下载完成！共新增 3 个文件到：./downloads
   ```
   - 采用文件差异比对算法

4. **错误诊断系统**  
   | 错误类型           | 自动检测项                     |
   |--------------------|------------------------------|
   | 网络异常          | GitHub API连通性测试          |
   | 磁盘空间          | 剩余容量实时监控              |
   | 权限问题          | 目录可写性预检                |

---

## 📜 开源协议

[MIT License](LICENSE)
