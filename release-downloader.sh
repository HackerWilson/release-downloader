#!/bin/bash
set -euo pipefail

# 语言检测：支持 --lang zh|en 参数，或通过 LANG 环境变量自动检测
SCRIPT_LANG=""
args=()
for arg in "$@"; do
  if [ "$SCRIPT_LANG" = "__next__" ]; then
    SCRIPT_LANG="$arg"
    continue
  fi
  if [ "$arg" = "--lang" ]; then
    SCRIPT_LANG="__next__"
    continue
  fi
  args+=("$arg")
done
[ "$SCRIPT_LANG" = "__next__" ] && SCRIPT_LANG=""
set -- "${args[@]+"${args[@]}"}"

if [ -z "$SCRIPT_LANG" ]; then
  case "${LANG:-}" in
    zh_*) SCRIPT_LANG="zh" ;;
    *)    SCRIPT_LANG="en" ;;
  esac
fi

# i18n 文案定义
if [ "$SCRIPT_LANG" = "zh" ]; then
  MSG_RESOLVED_REPO="已解析仓库"
  MSG_MULTI_MATCH="找到多个匹配仓库，请选择："
  MSG_ERR_RESOLVE="错误：无法解析仓库 '%s'，请使用 owner/repo 格式"
  MSG_INPUT_REPO="GitHub 仓库名称"
  MSG_ERR_REPO_REQUIRED="错误：仓库名称不能为空"
  MSG_FETCHING_RELEASES="获取版本列表..."
  MSG_ERR_NO_RELEASES="错误：未找到任何 Release 版本"
  MSG_SELECT_VERSION="按版本号或关键字筛选"
  MSG_ERR_NO_VERSION="错误：未选择版本"
  MSG_FETCHING_ASSETS="获取资源列表..."
  MSG_ERR_NO_ASSETS="错误：该版本没有可下载的资源文件"
  MSG_FILTER_HINT="Enter 选择 / Tab 多选 / 输入关键字过滤"
  MSG_ERR_NO_SELECTED="错误：未选择资源文件"
  MSG_SELECTED="已选择资源文件："
  MSG_INPUT_DIR="下载路径（回车默认当前目录）"
  MSG_ERR_MKDIR="错误：无法创建目录 '%s'"
  MSG_ERR_NOT_WRITABLE="错误：路径 '%s' 不可写"
  MSG_SKIPPED="跳过已存在且完整的文件："
  MSG_ALL_EXIST="所有文件已存在且完整，无需下载！"
  MSG_INTERRUPTED="检测到中断，正在清理..."
  MSG_DOWNLOADING="下载中..."
  MSG_DL_FAILED="下载失败！可能原因："
  MSG_DL_NETWORK="  - 网络连接失败"
  MSG_DL_NOT_FOUND="  - 资源文件不存在"
  MSG_DL_DISK="  - 磁盘空间不足（剩余：%s）"
  MSG_DIAG_API="网络诊断：GitHub API 访问失败"
  MSG_OK="[OK] 下载完成！共下载 %d 个文件到：%s"
  MSG_WARN_SIZE="[WARN] 文件大小校验失败："
  MSG_FAIL_SHA="[FAIL] SHA256 校验失败："
  MSG_SHA_OK="[SHA256] 校验通过：%d 个文件"
  MSG_SIZE_OK="[INFO] 文件大小校验通过（该 Release 未提供 checksums 文件，已跳过 SHA256 校验）"
  MSG_SKIP_COUNT="[SKIP] 跳过已存在文件：%d 个"
  MSG_EXPECTED="期望"
  MSG_ACTUAL="实际"
  MSG_FILE_MISSING="文件不存在"
else
  MSG_RESOLVED_REPO="Resolved repo"
  MSG_MULTI_MATCH="Multiple matches found, select one:"
  MSG_ERR_RESOLVE="Error: cannot resolve repo '%s', use owner/repo format"
  MSG_INPUT_REPO="GitHub Repository"
  MSG_ERR_REPO_REQUIRED="Error: repository name is required"
  MSG_FETCHING_RELEASES="Fetching releases..."
  MSG_ERR_NO_RELEASES="Error: no releases found"
  MSG_SELECT_VERSION="Select version:"
  MSG_ERR_NO_VERSION="Error: no version selected"
  MSG_FETCHING_ASSETS="Fetching assets..."
  MSG_ERR_NO_ASSETS="Error: no downloadable assets in this release"
  MSG_FILTER_HINT="Enter: select / Tab: multi-select / Type: filter"
  MSG_ERR_NO_SELECTED="Error: no assets selected"
  MSG_SELECTED="Selected assets:"
  MSG_INPUT_DIR="Download path (Enter for current dir)"
  MSG_ERR_MKDIR="Error: cannot create directory '%s'"
  MSG_ERR_NOT_WRITABLE="Error: '%s' is not writable"
  MSG_SKIPPED="Skipped (already complete):"
  MSG_ALL_EXIST="All files already exist and are complete."
  MSG_INTERRUPTED="Interrupted, cleaning up..."
  MSG_DOWNLOADING="Downloading..."
  MSG_DL_FAILED="Download failed. Possible causes:"
  MSG_DL_NETWORK="  - Network error"
  MSG_DL_NOT_FOUND="  - Asset not found"
  MSG_DL_DISK="  - Disk full (free: %s)"
  MSG_DIAG_API="Diagnostic: GitHub API unreachable"
  MSG_OK="[OK] Downloaded %d file(s) to: %s"
  MSG_WARN_SIZE="[WARN] Size verification failed:"
  MSG_FAIL_SHA="[FAIL] SHA256 verification failed:"
  MSG_SHA_OK="[SHA256] Verified: %d file(s)"
  MSG_SIZE_OK="[INFO] Size OK (no checksums file in release, SHA256 skipped)"
  MSG_SKIP_COUNT="[SKIP] Skipped %d existing file(s)"
  MSG_EXPECTED="expected"
  MSG_ACTUAL="actual"
  MSG_FILE_MISSING="file missing"
fi

# SHA256 计算
compute_sha256() {
  if command -v sha256sum &>/dev/null; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum &>/dev/null; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo ""
  fi
}

# 仓库名称解析
resolve_repo() {
  local input="$1"

  if [[ "$input" == */* ]]; then
    echo "$input"
    return 0
  fi

  if [[ "$input" == *_* ]]; then
    local candidate="${input/_//}"
    if gh api "repos/$candidate" --jq '.full_name' &>/dev/null; then
      gum style --foreground 87 "$MSG_RESOLVED_REPO: $candidate" >&2
      echo "$candidate"
      return 0
    fi
  fi

  local search_result
  search_result=$(gh api "search/repositories?q=${input}+in:name&sort=stars&order=desc&per_page=5" \
    --jq '.items[] | .full_name' 2>/dev/null)

  if [ -n "$search_result" ]; then
    local selected
    selected=$(echo "$search_result" | gum filter --header "$MSG_MULTI_MATCH")
    if [ -n "$selected" ]; then
      echo "$selected"
      return 0
    fi
  fi

  gum style --foreground 196 "$(printf "$MSG_ERR_RESOLVE" "$input")" >&2
  return 1
}

if [ $# -ge 1 ]; then
  repo=$(resolve_repo "$1") || exit 1
else
  repo_input=$(gum input --header "$MSG_INPUT_REPO" --placeholder "charmbracelet/gum")
  [ -z "$repo_input" ] && { gum style --foreground 196 "$MSG_ERR_REPO_REQUIRED"; exit 1; }
  repo=$(resolve_repo "$repo_input") || exit 1
fi

release_list=$(gum spin --spinner dot --title "$MSG_FETCHING_RELEASES" -- \
    gh release list -R "$repo" --limit 50 --json tagName,name,isLatest,publishedAt \
    --jq '.[] | "\(.tagName)  \(.publishedAt)  \(.name)  \(if .isLatest then "(Latest)" else "" end)"')

if [ -z "$release_list" ]; then
  gum style --foreground 196 "$MSG_ERR_NO_RELEASES: '$repo'"
  exit 1
fi

version=$(echo "$release_list" | gum filter --header "$MSG_SELECT_VERSION" | awk '{print $1}')
[ -z "$version" ] && { gum style --foreground 196 "$MSG_ERR_NO_VERSION"; exit 1; }

asset_info=$(gum spin --spinner monkey --title "$MSG_FETCHING_ASSETS" -- \
    gh release view -R "$repo" "$version" --json assets --jq '.assets[] | "\(.name)\t\(.size)"')

if [ -z "$asset_info" ]; then
  gum style --foreground 196 "$MSG_ERR_NO_ASSETS"
  exit 1
fi

# 选择资源文件
assets=$(echo "$asset_info" | awk -F'\t' '{print $1}' | \
    gum filter --no-limit --header "$MSG_FILTER_HINT") || true

if [ -z "${assets:-}" ]; then
  gum style --foreground 196 "$MSG_ERR_NO_SELECTED"
  exit 1
fi

selected_msg="$MSG_SELECTED"$'\n'"$(echo "${assets:-}" | awk '{print "  - "$0}')"
echo "$selected_msg" | gum style --foreground 87 --border rounded --padding "1 2"

dir=$(gum input --header "$MSG_INPUT_DIR" --placeholder "./")
[ -z "$dir" ] && dir="$(pwd)"
if ! mkdir -p "$dir" 2>/dev/null; then
  gum style --foreground 196 "$(printf "$MSG_ERR_MKDIR" "$dir")"
  exit 1
fi
[ ! -w "$dir" ] && { gum style --foreground 196 "$(printf "$MSG_ERR_NOT_WRITABLE" "$dir")"; exit 1; }

# 跳过已完整下载的文件
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

if [ ${#skip_list[@]} -gt 0 ]; then
  skip_msg="$MSG_SKIPPED"$'\n'"$(printf '  - %s\n' "${skip_list[@]}")"
  echo "$skip_msg" | gum style --foreground 214 --border rounded --padding "1 2"
fi

if [ ${#download_list[@]} -eq 0 ]; then
  echo "$MSG_ALL_EXIST" | gum style --foreground 212 --border rounded --padding "1 2"
  exit 0
fi

# 构建下载参数
download_args=("-R" "$repo" "-D" "$dir" "$version" "--clobber")
for asset in "${download_list[@]}"; do
  download_args+=("--pattern" "$asset")
done

trap 'gum style --foreground 214 "$MSG_INTERRUPTED"; exit 130' SIGINT
if ! gum spin --spinner globe --title "$MSG_DOWNLOADING" -- \
    gh release download "${download_args[@]}"; then

    disk_free=$(df -h "$dir" | awk 'NR==2{print $4}')
    printf '%s\n' "$MSG_DL_FAILED" "$MSG_DL_NETWORK" "$MSG_DL_NOT_FOUND" "$(printf "$MSG_DL_DISK" "$disk_free")" \
      | gum style --foreground 196 --border rounded --padding "1 2"

    if ! curl -m 5 -sSf https://api.github.com >/dev/null; then
        echo -e "\n$(gum style --foreground 214 "$MSG_DIAG_API")"
    fi
    exit 1
fi

# 校验文件大小
verify_failed=()
for asset in "${download_list[@]}"; do
  local_file="$dir/$asset"
  expected_size=$(echo "$asset_info" | awk -F'\t' -v name="$asset" '$1 == name {print $2}')

  if [ -f "$local_file" ] && [ -n "$expected_size" ]; then
    actual_size=$(wc -c < "$local_file" | tr -d ' ')
    if [ "$actual_size" != "$expected_size" ]; then
      verify_failed+=("$asset ($MSG_EXPECTED: ${expected_size}B, $MSG_ACTUAL: ${actual_size}B)")
    fi
  elif [ ! -f "$local_file" ]; then
    verify_failed+=("$asset ($MSG_FILE_MISSING)")
  fi
done

# SHA256 校验
checksums_file=""
all_asset_names=$(echo "$asset_info" | awk -F'\t' '{print $1}')
match=$(echo "$all_asset_names" | grep -iE '(checksum|sha256|sha512)' | head -1 || true)
if [ -n "$match" ]; then
  checksums_file="$match"
fi

sha256_verified=0
sha256_failed=()
if [ -n "$checksums_file" ]; then
  checksums_dir=$(mktemp -d)
  checksums_path="$checksums_dir/$checksums_file"
  if gh release download -R "$repo" "$version" --pattern "$checksums_file" -D "$checksums_dir" --clobber &>/dev/null; then
    for asset in "${download_list[@]}"; do
      local_file="$dir/$asset"
      expected_hash=$(grep -w "$asset" "$checksums_path" 2>/dev/null | awk '{print $1}')
      if [ -n "$expected_hash" ] && [ -f "$local_file" ]; then
        actual_hash=$(compute_sha256 "$local_file")
        if [ -n "$actual_hash" ] && [ "$actual_hash" = "$expected_hash" ]; then
          sha256_verified=$((sha256_verified + 1))
        elif [ -n "$actual_hash" ]; then
          sha256_failed+=("$asset")
        fi
      fi
    done
  fi
  rm -rf "$checksums_dir"
fi

downloaded_count=${#download_list[@]}

result_msg="$(printf "$MSG_OK" "$downloaded_count" "$(realpath "$dir")")"

if [ ${#verify_failed[@]} -gt 0 ]; then
  result_msg+="\n\n$MSG_WARN_SIZE"
  for item in "${verify_failed[@]}"; do
    result_msg+="\n  - $item"
  done
fi

if [ ${#sha256_failed[@]} -gt 0 ]; then
  result_msg+="\n\n$MSG_FAIL_SHA"
  for item in "${sha256_failed[@]}"; do
    result_msg+="\n  - $item"
  done
elif [ "$sha256_verified" -gt 0 ]; then
  result_msg+="\n\n$(printf "$MSG_SHA_OK" "$sha256_verified")"
elif [ -z "$checksums_file" ]; then
  result_msg+="\n\n$MSG_SIZE_OK"
fi

if [ ${#skip_list[@]} -gt 0 ]; then
  result_msg+="\n$(printf "$MSG_SKIP_COUNT" "${#skip_list[@]}")"
fi

echo -e "$result_msg" | gum style --foreground 212 --border rounded --padding "1 2"
