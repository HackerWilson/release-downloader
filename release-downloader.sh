#!/bin/bash
set -euo pipefail

# 参数模式快速启动
if [ $# -ge 1 ]; then
  repo="$1"
  [[ ! "$repo" =~ .*/.* ]] && { gum style --foreground 196 "错误：仓库格式应为 owner/repo"; exit 1; }
else
  repo=$(gum input --header "GitHub仓库名称" --placeholder "charmbracelet/gum")
  [ -z "$repo" ] && { gum style --foreground 196 "错误：仓库名称不能为空！"; exit 1; }
fi

# 版本选择
version=$(gum spin --spinner dot --title "获取版本列表..." -- \
    gh release list -R "$repo" --limit 50 --json tagName,name,isLatest,publishedAt --jq '.[] | "\(.tagName)  \(.publishedAt)  \(.name)  \(if .isLatest then "(Latest)" else "" end)"' | \
    gum filter --header "按版本号或关键字筛选" | awk '{print $1}')
[ -z "$version" ] && { gum style --foreground 196 "错误：未选择版本！"; exit 1; }

# 多选资源文件
declare -a assets
assets=$(gum spin --spinner monkey --title "获取资源列表..." -- \
    gh release view -R "$repo" "$version" --json assets --jq '.assets[].name' | \
    gum choose --no-limit --header "空格多选文件，回车确认") || {
    gum style --foreground 196 "错误：未选择资源文件！"
    exit 1
}

# 显示已选文件
gum style --foreground 87 --border rounded --padding "1 2" \
    $'✅ 已选择资源文件：\n'"$(echo "${assets:-}" | awk '{print "• "$0}')"

# 目录处理
dir=$(gum input --header "下载路径 (回车默认当前目录)" --placeholder "./")
[ -z "$dir" ] && dir="$(pwd)"
mkdir -p "$dir" 2>/dev/null || true
[ ! -w "$dir" ] && { gum style --foreground 196 "错误：路径 '$dir' 不可写！"; exit 1; }

# 文件差异检测
previous_files=$(ls -1q "$dir" 2>/dev/null | sort)

# 构建下载参数
download_args=("-R" "$repo" "-D" "$dir" "$version")
while IFS= read -r asset; do
    download_args+=("--pattern" "$asset")
done <<< "${assets:-}"  # 处理空值情况

# 执行下载并捕获错误
trap 'gum style --foreground 214 "检测到中断，正在清理临时文件..."' SIGINT
if ! gum spin --spinner globe --title "下载中..." -- \
    gh release download "${download_args[@]}"; then

    gum style --foreground 196 --border rounded --padding "1 2" \
        $'❌ 下载失败！可能原因：\n• 网络连接失败\n• 资源文件不存在\n• 磁盘空间不足（剩余：'$(df -h "$dir" | awk 'NR==2{print $4}')')'

    if ! curl -m 5 -sSf https://api.github.com >/dev/null; then
        echo -e "\n$(gum style --foreground 214 '网络诊断：GitHub API 访问失败')"
    fi
    exit 1
fi

# 精确统计下载数量
downloaded_files=$(comm -13 <(echo "${previous_files:-}") <(ls -1q "$dir" | sort) | wc -l | tr -d ' ')

# 结果输出美化
gum style --foreground 212 --border rounded --padding "1 2" \
    "✅ 下载完成！共下载 $downloaded_files 个文件到：$(realpath "$dir")"
