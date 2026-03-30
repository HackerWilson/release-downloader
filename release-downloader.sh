#!/bin/bash
set -euo pipefail

# 仓库名称解析：支持 owner/repo 和 owner_repo 两种格式
resolve_repo() {
  local input="$1"

  # 已经是 owner/repo 格式，直接返回
  if [[ "$input" == */* ]]; then
    echo "$input"
    return 0
  fi

  # 尝试将第一个 _ 替换为 /（GitHub 用户名不允许下划线）
  if [[ "$input" == *_* ]]; then
    local candidate="${input/_//}"
    # 通过 GitHub API 验证仓库是否存在
    if gh api "repos/$candidate" --jq '.full_name' &>/dev/null; then
      gum style --foreground 87 "📦 已解析仓库：$candidate"
      echo "$candidate"
      return 0
    fi
  fi

  # 尝试通过 GitHub 搜索 API 查找仓库
  local search_result
  search_result=$(gh api "search/repositories?q=${input}+in:name&per_page=5" \
    --jq '.items[] | .full_name' 2>/dev/null)

  if [ -n "$search_result" ]; then
    local selected
    selected=$(echo "$search_result" | gum filter --header "找到多个匹配仓库，请选择：")
    if [ -n "$selected" ]; then
      echo "$selected"
      return 0
    fi
  fi

  gum style --foreground 196 "错误：无法解析仓库 '$input'，请使用 owner/repo 格式"
  return 1
}

# 参数模式快速启动
if [ $# -ge 1 ]; then
  repo=$(resolve_repo "$1") || exit 1
else
  repo_input=$(gum input --header "GitHub仓库名称" --placeholder "charmbracelet/gum")
  [ -z "$repo_input" ] && { gum style --foreground 196 "错误：仓库名称不能为空！"; exit 1; }
  repo=$(resolve_repo "$repo_input") || exit 1
fi

# 版本选择
version=$(gum spin --spinner dot --title "获取版本列表..." -- \
    gh release list -R "$repo" --limit 50 --json tagName,name,isLatest,publishedAt --jq '.[] | "\(.tagName)  \(.publishedAt)  \(.name)  \(if .isLatest then "(Latest)" else "" end)"' | \
    gum filter --header "按版本号或关键字筛选" | awk '{print $1}')
[ -z "$version" ] && { gum style --foreground 196 "错误：未选择版本！"; exit 1; }

# 获取资源列表（含文件大小，用于校验和断点续传）
asset_info=$(gum spin --spinner monkey --title "获取资源列表..." -- \
    gh release view -R "$repo" "$version" --json assets --jq '.assets[] | "\(.name)\t\(.size)"')

# 多选资源文件
declare -a assets
assets=$(echo "$asset_info" | awk -F'\t' '{print $1}' | \
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

# 断点续传：检查已存在且大小一致的文件，跳过下载
skip_list=()
download_list=()
while IFS= read -r asset; do
  [ -z "$asset" ] && continue
  local_file="$dir/$asset"
  expected_size=$(echo "$asset_info" | awk -F'\t' -v name="$asset" '$1 == name {print $2}')

  if [ -f "$local_file" ] && [ -n "$expected_size" ]; then
    actual_size=$(wc -c < "$local_file" | tr -d ' ')
    if [ "$actual_size" = "$expected_size" ]; then
      skip_list+=("$asset")
      continue
    fi
  fi
  download_list+=("$asset")
done <<< "${assets:-}"

# 显示跳过的文件
if [ ${#skip_list[@]} -gt 0 ]; then
  gum style --foreground 214 --border rounded --padding "1 2" \
    $'⏭️  跳过已存在且完整的文件：\n'"$(printf '• %s\n' "${skip_list[@]}")"
fi

# 如果所有文件都已存在，直接退出
if [ ${#download_list[@]} -eq 0 ]; then
  gum style --foreground 212 --border rounded --padding "1 2" \
    "✅ 所有文件已存在且完整，无需下载！"
  exit 0
fi

# 文件差异检测
previous_files=$(ls -1q "$dir" 2>/dev/null | sort)

# 构建下载参数（仅下载需要的文件）
download_args=("-R" "$repo" "-D" "$dir" "$version" "--clobber")
for asset in "${download_list[@]}"; do
  download_args+=("--pattern" "$asset")
done

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

# 文件大小校验
verify_failed=()
for asset in "${download_list[@]}"; do
  local_file="$dir/$asset"
  expected_size=$(echo "$asset_info" | awk -F'\t' -v name="$asset" '$1 == name {print $2}')

  if [ -f "$local_file" ] && [ -n "$expected_size" ]; then
    actual_size=$(wc -c < "$local_file" | tr -d ' ')
    if [ "$actual_size" != "$expected_size" ]; then
      verify_failed+=("$asset (期望: ${expected_size}B, 实际: ${actual_size}B)")
    fi
  elif [ ! -f "$local_file" ]; then
    verify_failed+=("$asset (文件不存在)")
  fi
done

# SHA256 校验：查找 release 中的 checksums 文件
checksums_file=""
checksums_patterns=("checksums.txt" "SHA256SUMS" "sha256sums.txt" "CHECKSUMS" "checksums" "sha256sum.txt")
all_asset_names=$(echo "$asset_info" | awk -F'\t' '{print $1}')
for pattern in "${checksums_patterns[@]}"; do
  match=$(echo "$all_asset_names" | grep -i "$pattern" | head -1)
  if [ -n "$match" ]; then
    checksums_file="$match"
    break
  fi
done

sha256_verified=0
sha256_failed=()
if [ -n "$checksums_file" ]; then
  # 下载 checksums 文件
  checksums_path="$dir/.checksums_tmp"
  if gh release download -R "$repo" "$version" --pattern "$checksums_file" -D "$dir" --clobber &>/dev/null; then
    mv "$dir/$checksums_file" "$checksums_path" 2>/dev/null || true

    for asset in "${download_list[@]}"; do
      local_file="$dir/$asset"
      expected_hash=$(grep -w "$asset" "$checksums_path" 2>/dev/null | awk '{print $1}')
      if [ -n "$expected_hash" ] && [ -f "$local_file" ]; then
        actual_hash=$(shasum -a 256 "$local_file" | awk '{print $1}')
        if [ "$actual_hash" = "$expected_hash" ]; then
          sha256_verified=$((sha256_verified + 1))
        else
          sha256_failed+=("$asset")
        fi
      fi
    done
    rm -f "$checksums_path"
  fi
fi

# 精确统计下载数量
downloaded_files=$(comm -13 <(echo "${previous_files:-}") <(ls -1q "$dir" | sort) | wc -l | tr -d ' ')

# 结果输出美化
result_msg="✅ 下载完成！共下载 $downloaded_files 个文件到：$(realpath "$dir")"

# 显示校验结果
if [ ${#verify_failed[@]} -gt 0 ]; then
  result_msg+="\n\n⚠️  文件大小校验失败："
  for item in "${verify_failed[@]}"; do
    result_msg+="\n  • $item"
  done
fi

if [ ${#sha256_failed[@]} -gt 0 ]; then
  result_msg+="\n\n❌ SHA256 校验失败："
  for item in "${sha256_failed[@]}"; do
    result_msg+="\n  • $item"
  done
elif [ "$sha256_verified" -gt 0 ]; then
  result_msg+="\n\n🔒 SHA256 校验通过：$sha256_verified 个文件"
elif [ -z "$checksums_file" ]; then
  result_msg+="\n\n📎 文件大小校验通过（该 Release 未提供 checksums 文件，已跳过 SHA256 校验）"
fi

if [ ${#skip_list[@]} -gt 0 ]; then
  result_msg+="\n⏭️  跳过已存在文件：${#skip_list[@]} 个"
fi

gum style --foreground 212 --border rounded --padding "1 2" "$(echo -e "$result_msg")"
