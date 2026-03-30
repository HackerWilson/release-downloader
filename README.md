# Release Downloader 🚀

**GitHub Release资源文件下载工具**  
支持多版本选择、批量下载、断点续传、文件校验，高效获取GitHub Release资源文件

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

# 也支持 owner_repo 格式（自动解析）：
./release-downloader.sh RSSNext_Folo
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

1. **智能仓库解析**
   - 支持 `owner/repo` 标准格式
   - 支持 `owner_repo` 下划线格式（自动将第一个 `_` 解析为 `/`，通过 API 验证）
   - 无法解析时自动搜索 GitHub 仓库，按 Star 数排序供选择

2. **智能版本列表**  
   - 自动获取最近50个Release版本
   - 支持关键字实时过滤（如输入"beta"筛选测试版）
   - 显示版本号、发布时间、名称及是否为最新版

3. **多选下载模式**  
   - 支持批量勾选资源文件
   - 自动识别不同平台包（*.dmg/*.exe/*.AppImage）

4. **断点续传**
   - 下载前自动检查目标目录中已存在的文件
   - 文件大小与 GitHub API 返回的一致时自动跳过
   - 所有文件已存在时直接退出，不发起下载请求

5. **文件校验系统**
   - 下载后自动进行文件大小校验
   - 自动查找 Release 中的 checksums 文件（支持 `checksums.txt`、`SHA256SUMS` 等常见命名）
   - 找到 checksums 文件时自动进行 SHA256 校验
   - 兼容 macOS (`shasum`) 和 Linux (`sha256sum`)

6. **精准统计系统**  
   ```bash
   ✅ 下载完成！共下载 3 个文件到：./downloads
   🔒 SHA256 校验通过：3 个文件
   ⏭️  跳过已存在文件：2 个
   ```

7. **错误诊断系统**  
   | 错误类型           | 自动检测项                     |
   |--------------------|------------------------------|
   | 网络异常          | GitHub API连通性测试          |
   | 磁盘空间          | 剩余容量实时监控              |
   | 权限问题          | 目录可写性预检                |
   | 中断处理          | Ctrl+C 信号捕获与安全退出     |

---

## 📜 开源协议

[MIT License](LICENSE)
