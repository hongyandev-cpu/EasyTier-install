#!/bin/bash
# EasyTier Linux 安装脚本（五种模式定制版）
# 下载源可选：GitHub 官方 / 作者自用仓库 / GH-Proxy 加速

RED_COLOR='\e[1;31m'
GREEN_COLOR='\e[1;32m'
YELLOW_COLOR='\e[1;33m'
RES='\e[0m'

REPO_BASE=""
API_BASE=""
SOURCE_NAME=""
PROXY_PREFIX=""

TMP_DIR=""
BACKUP_DIR=""
CURL_AUTH=()

die() {
  echo -e "\r\n${RED_COLOR}错误: $*${RES}\r\n" 1>&2
  exit 1
}

SET_SOURCE() {
  case "$SOURCE" in
    github)
      REPO_BASE="https://github.com/EasyTier/EasyTier"
      API_BASE="https://api.github.com/repos/EasyTier/EasyTier"
      SOURCE_NAME="GitHub 官方源"
      PROXY_PREFIX=""
      ;;
    self)
      REPO_BASE="https://git.rao.jx.cn/hongyan/EasyTier"
      API_BASE="https://git.rao.jx.cn/api/v1/repos/hongyan/EasyTier"
      SOURCE_NAME="作者自用仓库源"
      PROXY_PREFIX=""
      ;;
    proxy)
      # 按官方文档：把原始 GitHub URL（含 API）完整拼在代理前缀后
      PROXY_PREFIX="https://gh-proxy.org/"
      REPO_BASE="${PROXY_PREFIX}https://github.com/EasyTier/EasyTier"
      API_BASE="${PROXY_PREFIX}https://api.github.com/repos/EasyTier/EasyTier"
      SOURCE_NAME="GH-Proxy 加速源"
      ;;
    *) die "--source 只能是 github（官方源）、self（自用源）或 proxy（加速源）" ;;
  esac
}

ENSURE_SOURCE() {
  if [ -n "$SOURCE" ]; then
    SET_SOURCE
    return
  fi
  # 本地包安装不需要联网，不询问下载源
  [ -n "$LOCAL_FILE" ] && return

  if [ -t 0 ]; then
    echo -e "\r\n${GREEN_COLOR}选择安装包下载源${RES}"
    echo "  1) 官方源 — 官方仓库，版本最全"
    echo "  2) 自用源 — 作者备份仓库，官方源网络不通时可尝试"
    echo "  3) 加速源 — 走代理访问官方仓库，下载慢时可尝试"
    while true; do
      read -r -p "请输入 1-3: " choice
      case "$choice" in
        1 | github) SOURCE="github"; break ;;
        2 | self) SOURCE="self"; break ;;
        3 | proxy) SOURCE="proxy"; break ;;
        *) echo "请只输入 1 到 3" ;;
      esac
    done
  else
    SOURCE="github"
    echo -e "${YELLOW_COLOR}未指定下载源，非交互环境默认使用官方源${RES}"
  fi
  SET_SOURCE
}

cleanup() {
  [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"
  [ -n "$BACKUP_DIR" ] && rm -rf "$BACKUP_DIR"
  return 0
}
trap cleanup EXIT

HELP() {
  echo -e "\r\n${GREEN_COLOR}EasyTier 安装脚本（Linux / 多模式定制版）${RES}\r\n"
  echo "用法: ./install.sh [命令] [选项] [安装路径]"
  echo
  echo "命令:"
  echo "  install    安装 EasyTier（引导选择: 中继 / 客户端 / 混合 / 端口转发 / 单向客户端）"
  echo "  download   只下载安装包到本地，不安装"
  echo "  update     从所选下载源更新"
  echo "  uninstall  一键卸载（独立命令，不经过安装流程）"
  echo "  help       显示帮助"
  echo
  echo "安装模式:"
  echo "  relay   中继服务器: 放在公网把大家连起来，不建虚拟网卡，权限最小"
  echo "  client  客户端: 建虚拟网卡，主动连接中继，适合普通机器"
  echo "  hybrid  混合节点: 既建虚拟网卡，又允许别人连进来"
  echo "  forward 端口转发: 不建虚拟网卡，把公网端口转到虚拟网里的服务，如 80 → 内网网站"
  echo "  oneway  单向客户端: 不建虚拟网卡，别人能访问它；它主动访问别人要配端口转发"
  echo
  echo "选项（不提供时全部交互式输入，没有默认值）:"
  echo "  --mode relay|client|hybrid|forward|oneway   安装模式"
  echo "  --source github|self|proxy   下载源：github=官方源，self=自用源，proxy=加速源"
  echo "  --local-file FILE            用本地已下载的安装包安装（跳过联网下载）"
  echo "  --output DIR                 download 命令的保存目录（默认当前目录）"
  echo "  --version TAG                指定 release 标签（默认取所选源的最新 release）"
  echo "  --hostname NAME              设备名称（可选，留空默认用系统设备名）"
  echo "  --network-name NAME          网络名"
  echo "  --network-secret SECRET      网络密钥（客户端/混合/端口转发/单向客户端）"
  echo "  --relay-host HOST            要连接的中继域名/IP（客户端/混合/端口转发/单向客户端）"
  echo "  --relay-port PORT            中继/监听端口，TCP+UDP 同端口"
  echo "  --ipv4 IP                    使用静态虚拟 IP（客户端/混合/端口转发/单向客户端）"
  echo "  --dhcp                       使用 DHCP 分配虚拟 IP（客户端/混合/端口转发/单向客户端）"
  echo "  --token TOKEN                token（可选，用于 API 限流；代理源也会透传）"
  echo "  --skip-folder-verify         安装目录非空时也继续"
  echo "  --skip-folder-fix            不自动在安装路径后追加 /easytier"
  echo "  --remove-user                卸载时删除 easytier 系统用户"
  echo "  --keep-user                  卸载时保留 easytier 系统用户（默认）"
  echo
  echo "示例:"
  echo "  ./install.sh install"
  echo "  ./install.sh install --mode relay"
  echo "  ./install.sh install --mode hybrid --version v2.6.4"
  echo "  ./install.sh install --mode client --hostname my-nas"
  echo "  ./install.sh install --mode forward"
  echo "  ./install.sh install --mode oneway"
  echo "  ./install.sh download --source self"
  echo "  ./install.sh download --source proxy --output /tmp/easytier-pkg"
  echo "  ./install.sh install --local-file ./easytier-linux-x86_64-v2.6.4.zip"
  echo "  ./install.sh update --version v2.6.4"
  echo "  ./install.sh uninstall"
  echo
  echo "下载源: 官方 GitHub 源 / 作者自用仓库源 / GH-Proxy 加速源（安装时选择，或用 --source 指定）"
}

if [ $# -eq 0 ] || [ "$1" = "help" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  HELP
  exit 0
fi

COMMAND="$1"
shift

INSTALL_PATH=""
MODE=""
VERSION=""
NETWORK_NAME=""
NETWORK_SECRET=""
RELAY_HOST=""
RELAY_PORT=""
IPV4=""
DHCP_MODE=""
INSTANCE_NAME=""
NODE_HOSTNAME=""
HOSTNAME_INPUT=""
MACHINE_ID=""
DEV_NAME="tun0"
TOKEN=""
SOURCE=""
SOURCE_SET=false
LOCAL_FILE=""
DOWNLOAD_DIR=""
DOWNLOAD_ONLY=false
SKIP_FOLDER_VERIFY=false
SKIP_FOLDER_FIX=false
REMOVE_USER=""

# 第一个非选项参数视为安装路径
if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
  INSTALL_PATH="$1"
  shift
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)
      [ -n "${2:-}" ] || die "--mode 需要参数: relay、client、hybrid、forward 或 oneway"
      MODE="$2"; shift ;;
    --version)
      [ -n "${2:-}" ] || die "--version 需要参数"
      VERSION="$2"; shift ;;
    --source)
      [ -n "${2:-}" ] || die "--source 需要参数: github、self 或 proxy"
      SOURCE="$2"; SOURCE_SET=true; shift ;;
    --local-file)
      [ -n "${2:-}" ] || die "--local-file 需要参数（本地 zip 路径）"
      LOCAL_FILE="$2"; shift ;;
    --output)
      [ -n "${2:-}" ] || die "--output 需要参数（下载目录）"
      DOWNLOAD_DIR="$2"; shift ;;
    --hostname)
      [ $# -ge 2 ] || die "--hostname 需要参数（留空则用系统设备名）"
      HOSTNAME_INPUT="$2"; shift ;;
    --network-name)
      [ -n "${2:-}" ] || die "--network-name 需要参数"
      NETWORK_NAME="$2"; shift ;;
    --network-secret)
      [ -n "${2:-}" ] || die "--network-secret 需要参数"
      NETWORK_SECRET="$2"; shift ;;
    --relay-host)
      [ -n "${2:-}" ] || die "--relay-host 需要参数"
      RELAY_HOST="$2"; shift ;;
    --relay-port)
      [ -n "${2:-}" ] || die "--relay-port 需要参数"
      RELAY_PORT="$2"; shift ;;
    --ipv4)
      [ -n "${2:-}" ] || die "--ipv4 需要参数"
      IPV4="$2"; shift ;;
    --dhcp) DHCP_MODE="true" ;;
    --token)
      [ -n "${2:-}" ] || die "--token 需要参数"
      TOKEN="$2"; shift ;;
    --skip-folder-verify) SKIP_FOLDER_VERIFY=true ;;
    --skip-folder-fix) SKIP_FOLDER_FIX=true ;;
    --remove-user) REMOVE_USER="true" ;;
    --keep-user) REMOVE_USER="false" ;;
    *) die "未知选项: $1（用 help 查看用法）" ;;
  esac
  shift
done

if [ "$SOURCE_SET" = true ]; then SET_SOURCE; fi

[ -z "$INSTALL_PATH" ] && INSTALL_PATH="/opt/easytier"
[[ "$INSTALL_PATH" == */ ]] && INSTALL_PATH="${INSTALL_PATH%/}"
if ! $SKIP_FOLDER_FIX && [[ "$INSTALL_PATH" != */easytier ]]; then
  INSTALL_PATH="$INSTALL_PATH/easytier"
fi
case "$INSTALL_PATH" in
  / | /etc | /usr | /opt | /var | /home | /root | "$HOME") die "拒绝在系统目录安装: $INSTALL_PATH" ;;
esac

if [ -n "$TOKEN" ]; then
  CURL_AUTH=(-H "Authorization: token ${TOKEN}")
fi

[ "$(uname -s)" = "Linux" ] || die "本脚本仅支持 Linux 部署"
command -v curl >/dev/null 2>&1 || die "缺少依赖: curl"

# 只有安装/更新/卸载才需要解压、服务管理和 root 权限；download 只下载，不要求这些
if [ "$COMMAND" != "download" ]; then
  command -v unzip >/dev/null 2>&1 || die "缺少依赖: unzip"
  if command -v systemctl >/dev/null 2>&1; then
    INIT_SYSTEM="systemd"
  elif command -v rc-service >/dev/null 2>&1; then
    INIT_SYSTEM="openrc"
  else
    die "未找到 systemd 或 OpenRC，无法确定服务管理方式"
  fi
  [ "$(id -u)" = "0" ] || die "请以 root 身份运行本脚本"
fi

if command -v arch >/dev/null 2>&1; then
  platform=$(arch)
else
  platform=$(uname -m)
fi
case "$platform" in
  amd64 | x86_64) ARCH="x86_64" ;;
  arm64 | aarch64 | *armv8*) ARCH="aarch64" ;;
  *armv7*) ARCH="armv7" ;;
  *arm*) ARCH="arm" ;;
  mips) ARCH="mips" ;;
  mipsel) ARCH="mipsel" ;;
  ppc64le | powerpc64le) ARCH="ppc64le" ;;
  *) die "不支持的 CPU 架构: $platform" ;;
esac
if [[ "$ARCH" == "armv7" || "$ARCH" == "arm" ]]; then
  if grep -i 'half' /proc/cpuinfo 2>/dev/null | grep -i 'Features' >/dev/null 2>&1; then
    ARCH="${ARCH}hf"
  fi
fi

CURL_BAR=""
if curl --help 2>/dev/null | grep -q progress-bar; then
  CURL_BAR="--progress-bar"
fi

echo -e "${GREEN_COLOR}平台: ${ARCH} (${platform}) | 初始化系统: ${INIT_SYSTEM} | 安装路径: ${INSTALL_PATH}${RES}"

validate_value() {
  case "$1" in
    *'"'* | *'\'* | *$'\n'* | *$'\r'*)
      die "$2 不能包含引号、反斜杠或换行" ;;
  esac
}

# 所有用户值都必须显式输入，不提供默认值
ask_required() {
  local prompt="$1" answer=""
  [ -t 0 ] || die "非交互环境请用命令行参数提供: $prompt（用 help 查看参数）"
  while [ -z "$answer" ]; do
    read -r -p "$prompt: " answer
    [ -z "$answer" ] && echo "这一项不能为空，请重新输入"
  done
  printf '%s' "$answer"
}

# 从所选源的 API 获取 release tag 与资产地址，并下载 zip 到 $TMP_DIR/release.zip
# 不指定 --version 时取 API 第一个 release（通常是最新构建）
FETCH_RELEASE() {
  local response tags
  TMP_DIR=$(mktemp -d /tmp/easytier-install-XXXXXX)

  if [ -n "$VERSION" ]; then
    response=$(curl -fsSL "${CURL_AUTH[@]}" "${API_BASE}/releases/tags/${VERSION}") \
      || die "无法从${SOURCE_NAME}获取版本 ${VERSION}，请确认 tag 存在"
    TAG="$VERSION"
  else
    response=$(curl -fsSL "${CURL_AUTH[@]}" "${API_BASE}/releases") \
      || die "无法访问 ${API_BASE}/releases，请检查网络；如触发 API 限流可用 --token"
    tags=$(printf '%s' "$response" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
      | sed -E 's/.*"([^"]+)"$/\1/')
    TAG=$(printf '%s\n' "$tags" | head -n 1)
    [ -n "$TAG" ] || die "${SOURCE_NAME} ${REPO_BASE}/releases 没有可用 Release"
  fi

  ASSET_URL=$(printf '%s' "$response" \
    | grep -o '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | sed -E 's/.*"([^"]+)"$/\1/' \
    | grep -E "easytier-linux-${ARCH}-.*\.zip$" | head -n 1)
  if [ -z "$ASSET_URL" ]; then
    if [[ "$TAG" == v* ]]; then
      ASSET_URL="${REPO_BASE}/releases/download/${TAG}/easytier-linux-${ARCH}-${TAG}.zip"
    else
      die "无法从 ${API_BASE}/releases 找到 easytier-linux-${ARCH}-*.zip 资产"
    fi
  elif [ -n "$PROXY_PREFIX" ] && [[ "$ASSET_URL" == https://github.com/* ]]; then
    # API 返回的是原始 GitHub 地址，按 gh-proxy 文档拼接代理前缀
    ASSET_URL="${PROXY_PREFIX}${ASSET_URL}"
  fi

  echo -e "${GREEN_COLOR}下载源: ${SOURCE_NAME}${RES}"
  echo -e "${GREEN_COLOR}版本: ${TAG}${RES}"
  echo -e "${GREEN_COLOR}下载地址: ${ASSET_URL}${RES}"

  curl -fL "${CURL_AUTH[@]}" "$ASSET_URL" -o "$TMP_DIR/release.zip" $CURL_BAR \
    || die "下载失败，请检查 ${REPO_BASE}/releases 中 ${TAG} 对应的 easytier-linux-${ARCH}-*.zip 资产"
}

# 解压 release.zip 并定位二进制目录
EXTRACT_RELEASE() {
  [ -f "$TMP_DIR/release.zip" ] || die "找不到安装包"
  unzip -q -o "$TMP_DIR/release.zip" -d "$TMP_DIR" || die "解压失败: $TMP_DIR/release.zip"

  SRC_DIR="$TMP_DIR"
  for d in "$TMP_DIR"/easytier-linux-*; do
    if [ -d "$d" ]; then SRC_DIR="$d"; break; fi
  done
  [ -f "$SRC_DIR/easytier-core" ] && [ -f "$SRC_DIR/easytier-cli" ] \
    || die "安装包中缺少 easytier-core / easytier-cli"
}

# 使用本地已下载的安装包，跳过联网
USE_LOCAL_FILE() {
  [ -f "$LOCAL_FILE" ] || die "本地安装包不存在: $LOCAL_FILE"
  TMP_DIR=$(mktemp -d /tmp/easytier-install-XXXXXX)
  cp -f "$LOCAL_FILE" "$TMP_DIR/release.zip" || die "复制本地安装包失败"
  local name
  name=$(basename "$LOCAL_FILE")
  TAG=$(printf '%s' "$name" | grep -oE 'v[0-9]+(\.[0-9]+)*' | head -n 1)
  TAG=${TAG:-local}
  echo -e "${GREEN_COLOR}使用本地安装包: ${name}（版本: ${TAG}）${RES}"
  EXTRACT_RELEASE
}

# 统一入口：本地包优先，否则按所选源联网下载
PREPARE_BINARY() {
  ENSURE_SOURCE
  if [ -n "$LOCAL_FILE" ]; then
    USE_LOCAL_FILE
  else
    FETCH_RELEASE
    EXTRACT_RELEASE
  fi
}

# 只下载安装包，不安装、不改动系统
DOWNLOAD() {
  [ -n "$LOCAL_FILE" ] && die "download 命令不能与 --local-file 同时使用"
  DOWNLOAD_ONLY=true
  ENSURE_SOURCE
  FETCH_RELEASE

  local dir="${DOWNLOAD_DIR:-.}"
  mkdir -p "$dir" || die "无法创建下载目录: $dir"
  local file="${ASSET_URL##*/}"
  file="${file%%\?*}"
  cp -f "$TMP_DIR/release.zip" "$dir/$file" || die "保存安装包失败: $dir/$file"

  echo -e "\r\n${GREEN_COLOR}安装包已保存: ${dir}/${file}${RES}"
  echo "之后可用本地包安装（会再引导填写配置）："
  echo "  ./install.sh install --local-file \"${dir}/${file}\""
}

CHECK() {
  if [ -f "$INSTALL_PATH/easytier-core" ] && ! $SKIP_FOLDER_VERIFY; then
    die "$INSTALL_PATH 已安装 EasyTier，请使用 update 或添加 --skip-folder-verify"
  fi
  if [ -d "$INSTALL_PATH" ] && ! $SKIP_FOLDER_VERIFY && [ -n "$(ls -A "$INSTALL_PATH")" ]; then
    die "$INSTALL_PATH 非空，EasyTier 需要独立空目录（可用 --skip-folder-verify 跳过）"
  fi
  mkdir -p "$INSTALL_PATH/config" "$INSTALL_PATH/logs" || die "无法创建安装目录"
}

COLLECT_INPUT() {
  if [ "$MODE" = "uninstall" ]; then
    die "卸载请使用独立命令: ./install.sh uninstall（不经过安装流程）"
  fi

  if [ -z "$MODE" ]; then
    [ -t 0 ] || die "非交互环境请用 --mode relay、client、hybrid、forward 或 oneway 指定模式"
    echo -e "\r\n${GREEN_COLOR}第 1 步：选择这台机器扮演什么角色${RES}"
    echo "  1) 中继服务器 (relay)    — 放在公网，负责把其他机器连起来；不建虚拟网卡，权限最小"
    echo "  2) 客户端 (client)       — 普通机器，建虚拟网卡，主动连接中继"
    echo "  3) 混合节点 (hybrid)     — 既建虚拟网卡，又允许别人连进来"
    echo "  4) 端口转发 (forward)    — 不建虚拟网卡，把公网端口转到虚拟网里的服务（如 80 → 内网网站）"
    echo "  5) 单向客户端 (oneway)   — 不建虚拟网卡，别人能访问它；它主动访问别人需要配端口转发"
    while true; do
      read -r -p "请输入数字 1-5: " choice
      case "$choice" in
        1 | relay) MODE="relay"; break ;;
        2 | client) MODE="client"; break ;;
        3 | hybrid) MODE="hybrid"; break ;;
        4 | forward) MODE="forward"; break ;;
        5 | oneway) MODE="oneway"; break ;;
        *) echo "请只输入 1 到 5 的数字" ;;
      esac
    done
  fi
  case "$MODE" in
    relay | client | hybrid | forward | oneway) ;;
    *) die "模式只能是 relay、client、hybrid、forward 或 oneway（交互安装时先选 1-5）" ;;
  esac

  echo -e "\r\n${GREEN_COLOR}第 2 步：填写组网信息（同一网络的所有机器要写一致）${RES}"
  NETWORK_NAME=${NETWORK_NAME:-$(ask_required "网络名称（同一网络的所有机器必须写成一样）")}
  validate_value "$NETWORK_NAME" "网络名称"

  if [ "$MODE" = "relay" ]; then
    # 中继不加入虚拟网络，不需要密钥、中继地址和虚拟 IP
    NETWORK_SECRET=""
    RELAY_HOST=""
    IPV4=""
    DHCP_MODE=""
    CONFIG_NAME="default"
    RELAY_PORT=${RELAY_PORT:-$(ask_required "监听端口（其他机器连你时用的端口；TCP 和 UDP 都要放行）")}
  else
    # 客户端/混合/端口转发/单向客户端都要加入虚拟网络，需要密钥和中继地址
    NETWORK_SECRET=${NETWORK_SECRET:-$(ask_required "网络密钥（同一网络必须一致；可用命令 openssl rand -base64 16 生成）")}
    RELAY_HOST=${RELAY_HOST:-$(ask_required "中继地址（填中继服务器的域名或公网 IP，不要填本机地址）")}
    RELAY_PORT=${RELAY_PORT:-$(ask_required "中继端口（填中继服务器上设置的端口）")}
    validate_value "$NETWORK_SECRET" "网络密钥"
    validate_value "$RELAY_HOST" "中继地址"

    if [ -n "$IPV4" ] && [ "$DHCP_MODE" = "true" ]; then
      die "--ipv4 与 --dhcp 不能同时使用"
    fi

    if [ -z "$IPV4" ] && [ "$DHCP_MODE" != "true" ]; then
      [ -t 0 ] || die "非交互环境请用 --ipv4 或 --dhcp 指定 IP 方式"
      echo
      echo "虚拟 IP 获取方式："
      echo "  1) DHCP     — 自动分配，省事；重启后可能变化"
      echo "  2) 静态 IP  — 自己指定固定地址，适合服务器；必须全网唯一"
      while true; do
        read -r -p "请输入 1 或 2: " ip_choice
        case "$ip_choice" in
          1 | dhcp) DHCP_MODE="true"; IPV4=""; break ;;
          2 | static) DHCP_MODE="false"; IPV4=$(ask_required "静态虚拟 IP（填一个未被占用的地址）"); break ;;
          *) echo "请只输入 1 或 2" ;;
        esac
      done
    fi

    if [ -n "$IPV4" ]; then
      DHCP_MODE="false"
      if ! [[ "$IPV4" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        die "虚拟 IP 要写成四段数字（你填的是: $IPV4）"
      fi
      IFS='.' read -r o1 o2 o3 o4 <<< "$IPV4"
      for o in "$o1" "$o2" "$o3" "$o4"; do
        [ "$o" -le 255 ] 2>/dev/null || die "虚拟 IP 每一段只能是 0 到 255（你填的是: $IPV4）"
      done
    else
      DHCP_MODE="true"
    fi

    case "$MODE" in
      hybrid) CONFIG_NAME="hybrid" ;;
      forward) CONFIG_NAME="forward" ;;
      oneway) CONFIG_NAME="oneway" ;;
      *) CONFIG_NAME="client" ;;
    esac
  fi

  case "$RELAY_PORT" in
    '' | *[!0-9]*) die "端口要填数字（你填的是: $RELAY_PORT）" ;;
  esac
  if [ "$RELAY_PORT" -lt 1 ] || [ "$RELAY_PORT" -gt 65535 ]; then
    die "端口要在 1 到 65535 之间（你填的是: $RELAY_PORT）"
  fi

  # 实例名、machine_id、TUN 设备名按模式自动生成，设备名称可自定义
  case "$MODE" in
    relay) INSTANCE_NAME="easytier-relay" ;;
    client) INSTANCE_NAME="easytier-client" ;;
    hybrid) INSTANCE_NAME="easytier-hybrid" ;;
    forward) INSTANCE_NAME="easytier-forward" ;;
    oneway) INSTANCE_NAME="easytier-oneway" ;;
  esac
  # 设备名称：命令行 --hostname 优先，否则交互询问；直接回车用系统名称
  local sys_hostname custom
  sys_hostname=$(hostname 2>/dev/null | tr -c 'A-Za-z0-9_-' '-')
  sys_hostname=${sys_hostname%-}
  sys_hostname=${sys_hostname:-easytier-node}

  custom="$HOSTNAME_INPUT"
  if [ -z "$custom" ] && [ -t 0 ]; then
    echo
    echo "设备名称（在虚拟网里显示，同一网络不要重名）"
    echo "  直接回车就使用本机名称: $sys_hostname"
    read -r -p "设备名称（可留空）: " custom
  fi
  if [ -n "$custom" ]; then
    validate_value "$custom" "设备名称"
    NODE_HOSTNAME=$(printf '%s' "$custom" | tr -c 'A-Za-z0-9_-' '-')
    NODE_HOSTNAME=${NODE_HOSTNAME%-}
  fi
  NODE_HOSTNAME=${NODE_HOSTNAME:-$sys_hostname}
  MACHINE_ID="${NODE_HOSTNAME}-${MODE}"
  DEV_NAME="tun0"

  CONFIG_FILE="$INSTALL_PATH/config/${CONFIG_NAME}.conf"
  SERVICE="easytier@${CONFIG_NAME}"
}

WRITE_CONFIG() {
  IP_LINES="dhcp = true"
  if [ "$DHCP_MODE" != "true" ]; then
    IP_LINES="ipv4 = \"$IPV4\"
dhcp = false"
  fi

  case "$MODE" in
    relay)
      cat > "$CONFIG_FILE" <<EOF
instance_name = "$INSTANCE_NAME"
hostname = "$NODE_HOSTNAME"
machine_id = "$MACHINE_ID"

listeners = [
    "tcp://0.0.0.0:${RELAY_PORT}",
    "udp://0.0.0.0:${RELAY_PORT}",
]
exit_nodes = []
rpc_portal = "0.0.0.0:0"

[flags]
no_tun = true
relay_network_whitelist = "$NETWORK_NAME"
EOF
      ;;
    forward)
      cat > "$CONFIG_FILE" <<EOF
instance_name = "$INSTANCE_NAME"
hostname = "$NODE_HOSTNAME"
machine_id = "$MACHINE_ID"

$IP_LINES
listeners = [
    "tcp://0.0.0.0:${RELAY_PORT}",
    "udp://0.0.0.0:${RELAY_PORT}",
]
exit_nodes = []
rpc_portal = "0.0.0.0:0"

[network_identity]
network_name = "$NETWORK_NAME"
network_secret = "$NETWORK_SECRET"

[[peer]]
uri = "tcp://${RELAY_HOST}:${RELAY_PORT}"

[[peer]]
uri = "udp://${RELAY_HOST}:${RELAY_PORT}"

[flags]
no_tun = true
relay_network_whitelist = "$NETWORK_NAME"
EOF
      ;;
    oneway)
      cat > "$CONFIG_FILE" <<EOF
instance_name = "$INSTANCE_NAME"
hostname = "$NODE_HOSTNAME"
machine_id = "$MACHINE_ID"

$IP_LINES
listeners = []
exit_nodes = []
rpc_portal = "127.0.0.1:15888"

[network_identity]
network_name = "$NETWORK_NAME"
network_secret = "$NETWORK_SECRET"

[[peer]]
uri = "tcp://${RELAY_HOST}:${RELAY_PORT}"

[[peer]]
uri = "udp://${RELAY_HOST}:${RELAY_PORT}"

[flags]
no_tun = true
EOF
      ;;
    client)
      cat > "$CONFIG_FILE" <<EOF
instance_name = "$INSTANCE_NAME"
hostname = "$NODE_HOSTNAME"
machine_id = "$MACHINE_ID"

$IP_LINES
listeners = []
exit_nodes = []
rpc_portal = ""

[network_identity]
network_name = "$NETWORK_NAME"
network_secret = "$NETWORK_SECRET"

[[peer]]
uri = "tcp://${RELAY_HOST}:${RELAY_PORT}"

[[peer]]
uri = "udp://${RELAY_HOST}:${RELAY_PORT}"

[flags]
disable_p2p = false
dev_name = "$DEV_NAME"
EOF
      ;;
    hybrid)
      cat > "$CONFIG_FILE" <<EOF
instance_name = "$INSTANCE_NAME"
hostname = "$NODE_HOSTNAME"
machine_id = "$MACHINE_ID"

$IP_LINES
listeners = [
    "tcp://0.0.0.0:${RELAY_PORT}",
    "udp://0.0.0.0:${RELAY_PORT}",
]
exit_nodes = []
rpc_portal = ""

[network_identity]
network_name = "$NETWORK_NAME"
network_secret = "$NETWORK_SECRET"

[[peer]]
uri = "tcp://${RELAY_HOST}:${RELAY_PORT}"

[[peer]]
uri = "udp://${RELAY_HOST}:${RELAY_PORT}"

[flags]
no_tun = false
relay_network_whitelist = "$NETWORK_NAME"
disable_p2p = false
dev_name = "$DEV_NAME"
EOF
      ;;
  esac
  chown easytier:easytier "$CONFIG_FILE"
  chmod 640 "$CONFIG_FILE"
}

SETUP_USER_AND_PERMISSIONS() {
  if ! id easytier >/dev/null 2>&1; then
    useradd -r -s /usr/sbin/nologin -M easytier || die "创建 easytier 系统用户失败"
  fi
  chown -R root:root "$INSTALL_PATH"
  chmod 755 "$INSTALL_PATH" "$INSTALL_PATH/easytier-core" "$INSTALL_PATH/easytier-cli"
  mkdir -p "$INSTALL_PATH/config" "$INSTALL_PATH/logs"
  chown easytier:easytier "$INSTALL_PATH/config" "$INSTALL_PATH/logs"
  chmod 750 "$INSTALL_PATH/config" "$INSTALL_PATH/logs"
}

SETUP_SERVICE() {
  if [ "$INIT_SYSTEM" = "systemd" ]; then
    cat > /etc/systemd/system/easytier@.service <<EOF
[Unit]
Description=EasyTier Service (%i)
Wants=network-online.target
After=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
WorkingDirectory=$INSTALL_PATH
ExecStart=$INSTALL_PATH/easytier-core -c $INSTALL_PATH/config/%i.conf
Restart=always
RestartSec=1s

[Install]
WantedBy=multi-user.target
EOF

    CAP_LINES=""
    case "$MODE" in
      client | hybrid)
        CAP_LINES="AmbientCapabilities=CAP_NET_ADMIN
CapabilityBoundingSet=CAP_NET_ADMIN"
        ;;
      forward | oneway)
        # no_tun，只需绑定 1024 以下端口
        CAP_LINES="AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE"
        ;;
    esac
    mkdir -p /etc/systemd/system/easytier@.service.d
    cat > /etc/systemd/system/easytier@.service.d/override.conf <<EOF
[Service]
User=easytier
Group=easytier
NoNewPrivileges=true
ProtectSystem=full
ReadWritePaths=$INSTALL_PATH
PrivateTmp=true
ProtectHome=true
RestrictSUIDSGID=true
LockPersonality=true
LimitNOFILE=1048576
$CAP_LINES
EOF
  else
    cat > /etc/init.d/easytier <<EOF
#!/sbin/openrc-run
name="EasyTier"
description="EasyTier Service ($MODE)"
command="$INSTALL_PATH/easytier-core"
command_args="-c $CONFIG_FILE"
command_user="easytier:easytier"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
depend() {
  need net
}
EOF
    chmod +x /etc/init.d/easytier
  fi
}

SETUP_CAPABILITIES() {
  # 中继零 capability；客户端/混合要建 TUN；forward 是 no_tun，只需绑定低端口
  [ "$MODE" = "relay" ] && return
  if [ "$MODE" != "forward" ] && [ "$MODE" != "oneway" ]; then
    echo 'KERNEL=="tun", MODE="0666"' > /etc/udev/rules.d/99-tun.rules
    udevadm control --reload-rules >/dev/null 2>&1 || true
    udevadm trigger >/dev/null 2>&1 || true
  fi
  if command -v setcap >/dev/null 2>&1; then
    if [ "$MODE" = "forward" ] || [ "$MODE" = "oneway" ]; then
      CAPS='cap_net_bind_service+ep'
    else
      CAPS='cap_net_admin+ep'
    fi
    setcap "$CAPS" "$INSTALL_PATH/easytier-core" \
      || die "setcap 失败；请安装 libcap2-bin 后重试"
  else
    echo -e "${YELLOW_COLOR}警告: 未找到 setcap，systemd 的 AmbientCapabilities 仍会生效${RES}"
  fi
}

OPEN_FIREWALL() {
  if [ ! -t 0 ]; then
    echo -e "${YELLOW_COLOR}非交互环境：请手动在防火墙/安全组放行端口${RES}"
    return
  fi
  if [ "$MODE" = "relay" ] || [ "$MODE" = "hybrid" ] || [ "$MODE" = "forward" ]; then
    if command -v ufw >/dev/null 2>&1; then
      PORTS="$RELAY_PORT"
      read -r -p "检测到系统防火墙 ufw。要不要自动放行 ${PORTS} 的 TCP 和 UDP？不放行的话别的机器连不上 [y/N]: " answer
      case "$answer" in
        y | Y)
          for p in $PORTS; do
            ufw allow "${p}/tcp" >/dev/null && ufw allow "${p}/udp" >/dev/null
          done
          echo -e "${GREEN_COLOR}ufw 已放行 ${PORTS} 的 tcp 与 udp${RES}"
          ;;
        *) echo -e "${YELLOW_COLOR}未修改 ufw，请自行放行端口${RES}" ;;
      esac
    fi
  fi
}

START_SERVICE() {
  if [ "$INIT_SYSTEM" = "systemd" ]; then
    systemctl daemon-reload
    # 同一台机器只保留一个实例，避免 RPC 端口冲突
    case "$MODE" in
      relay) OTHER_SERVICES="easytier@client easytier@hybrid easytier@forward easytier@oneway" ;;
      client) OTHER_SERVICES="easytier@default easytier@hybrid easytier@forward easytier@oneway" ;;
      hybrid) OTHER_SERVICES="easytier@default easytier@client easytier@forward easytier@oneway" ;;
      forward) OTHER_SERVICES="easytier@default easytier@client easytier@hybrid easytier@oneway" ;;
      oneway) OTHER_SERVICES="easytier@default easytier@client easytier@hybrid easytier@forward" ;;
    esac
    for other in $OTHER_SERVICES; do
      systemctl disable --now "$other" >/dev/null 2>&1 || true
    done
    systemctl enable --now "$SERVICE" || die "服务 $SERVICE 启动失败，请用 journalctl -u $SERVICE 查看原因"
  else
    rc-update add easytier default >/dev/null 2>&1 || true
    rc-service easytier restart || die "OpenRC 服务启动失败"
  fi
}

INSTALL() {
  CHECK
  COLLECT_INPUT
  PREPARE_BINARY

  cp -f "$SRC_DIR/easytier-core" "$SRC_DIR/easytier-cli" "$INSTALL_PATH/"
  SETUP_USER_AND_PERMISSIONS
  WRITE_CONFIG
  SETUP_SERVICE
  SETUP_CAPABILITIES
  OPEN_FIREWALL

  rm -f /usr/bin/easytier-core /usr/bin/easytier-cli /etc/systemd/system/easytier.service
  ln -sf "$INSTALL_PATH/easytier-core" /usr/sbin/easytier-core
  ln -sf "$INSTALL_PATH/easytier-cli" /usr/sbin/easytier-cli

  printf 'MODE=%s\nCONFIG=%s\nSERVICE=%s\nTAG=%s\n' \
    "$MODE" "$CONFIG_NAME" "$SERVICE" "$TAG" > "$INSTALL_PATH/.install-state"
  chown root:root "$INSTALL_PATH/.install-state"

  START_SERVICE
  SUCCESS
}

SUCCESS() {
  echo -e "\r\n${GREEN_COLOR}安装完成${RES}"
  echo "  模式    : $MODE"
  echo "  版本    : $TAG"
  echo "  配置    : $CONFIG_FILE"
  echo "  服务    : $SERVICE"
  echo "  网络名  : $NETWORK_NAME"
  if [ "$MODE" = "relay" ] || [ "$MODE" = "hybrid" ] || [ "$MODE" = "forward" ]; then
    echo "  监听    : tcp/udp ${RELAY_PORT}（防火墙/安全组需放行）"
  fi
  if [ "$MODE" = "client" ] || [ "$MODE" = "hybrid" ]; then
    echo "  中继    : tcp://${RELAY_HOST}:${RELAY_PORT}"
    if [ "$DHCP_MODE" = "true" ]; then
      echo "  IP 方式 : DHCP"
    else
      echo "  虚拟 IP : $IPV4"
    fi
    echo "  TUN     : $DEV_NAME"
  fi
  if [ "$MODE" = "forward" ] || [ "$MODE" = "oneway" ]; then
    echo "  中继    : tcp://${RELAY_HOST}:${RELAY_PORT}"
    if [ "$DHCP_MODE" = "true" ]; then
      echo "  IP 方式 : DHCP"
    else
      echo "  虚拟 IP : $IPV4"
    fi
    echo "  TUN     : 不建（no_tun，用户态协议栈）"
  fi
  echo
  echo "验证命令:"
  echo "  systemctl status $SERVICE"
  echo "  journalctl -u $SERVICE -n 50 --no-pager"
  if [ "$INIT_SYSTEM" = "systemd" ]; then
    echo "  ${INSTALL_PATH}/easytier-cli node config"
    echo "  ${INSTALL_PATH}/easytier-cli peer"
    echo "  ${INSTALL_PATH}/easytier-cli node"
  fi
  if [ "$MODE" = "oneway" ]; then
    echo "  ${INSTALL_PATH}/easytier-cli --rpc-portal 127.0.0.1:15888 peer"
    echo "  ${INSTALL_PATH}/easytier-cli --rpc-portal 127.0.0.1:15888 node"
  fi
  if [ "$MODE" = "client" ] || [ "$MODE" = "hybrid" ]; then
    echo "  ip a show ${DEV_NAME}"
    echo "  ping <对端虚拟IP>"
    echo -e "${YELLOW_COLOR}P2P 已默认开启；如打洞失败会自动回退到中继${RES}"
  fi
  if [ "$MODE" = "forward" ] || [ "$MODE" = "oneway" ]; then
    echo
    echo "端口转发配置模板（按需修改后追加到 ${CONFIG_FILE}）："
    cat <<'TPL'
[[port_forward]]
bind_addr = "0.0.0.0:80"
dst_addr = "10.126.126.2:2345"
proto = "tcp"
TPL
    echo
    echo "说明："
    echo "  bind_addr 必须写成完整 IP:端口（如 0.0.0.0:80），不能写成 :80；1024 以下端口已通过 CAP_NET_BIND_SERVICE 授权"
    echo "  dst_addr 必须是虚拟网 IPv4:端口，不能写域名或宿主网段地址"
    if [ "$MODE" = "forward" ]; then
      echo "  如果本机就是中继服务器，请删除配置中的 [[peer]] 段（tcp/udp 两段），否则会自连接报 peer id conflict"
    fi
    echo "  no_tun 节点不能主动访问虚拟网，主动访问靠这里的 [[port_forward]] 规则"
    echo "  可追加多条 [[port_forward]]，规则改完后执行："
    echo "  systemctl restart ${SERVICE}"
    echo "  防火墙/云安全组需放行对应监听端口"
  fi
  echo
}

UNINSTALL() {
  echo -e "${GREEN_COLOR}卸载 EasyTier ...${RES}"

  if [ "$REMOVE_USER" = "true" ]; then
    DELETE_USER=true
  elif [ "$REMOVE_USER" = "false" ]; then
    DELETE_USER=false
  elif [ -t 0 ]; then
    read -r -p "是否删除运行用的 easytier 系统用户？保留更安全、以后重装方便；删除则清理更彻底 [y/N]: " answer
    case "$answer" in
      y | Y | yes | YES) DELETE_USER=true ;;
      *) DELETE_USER=false ;;
    esac
  else
    DELETE_USER=false
    echo -e "${YELLOW_COLOR}非交互环境：默认保留 easytier 用户（如需删除请加 --remove-user）${RES}"
  fi

  if [ "$INIT_SYSTEM" = "systemd" ]; then
    mapfile -t UNITS < <(systemctl list-unit-files --type=service --no-legend 2>/dev/null \
      | awk '{print $1}' | grep '^easytier@' || true)
    if [ ${#UNITS[@]} -gt 0 ]; then
      systemctl disable --now "${UNITS[@]}" >/dev/null 2>&1 || true
    fi
    rm -f /etc/systemd/system/easytier@.service
    rm -rf /etc/systemd/system/easytier@.service.d
  else
    rc-update del easytier default >/dev/null 2>&1 || true
    rc-service easytier stop >/dev/null 2>&1 || true
    rm -f /etc/init.d/easytier
  fi
  rm -f /usr/bin/easytier-core /usr/bin/easytier-cli \
    /usr/sbin/easytier-core /usr/sbin/easytier-cli
  rm -f /etc/udev/rules.d/99-tun.rules
  rm -rf "$INSTALL_PATH"
  if [ "$INIT_SYSTEM" = "systemd" ]; then systemctl daemon-reload; fi

  USER_REMOVED=false
  if $DELETE_USER && id easytier >/dev/null 2>&1; then
    if userdel easytier; then
      groupdel easytier >/dev/null 2>&1 || true
      USER_REMOVED=true
    else
      echo -e "${YELLOW_COLOR}删除 easytier 用户失败，请手动处理${RES}"
    fi
  fi

  if $USER_REMOVED; then
    echo -e "${GREEN_COLOR}EasyTier 已卸载（easytier 系统用户已删除）${RES}"
  else
    echo -e "${GREEN_COLOR}EasyTier 已卸载（easytier 系统用户保留）${RES}"
  fi
}

UPDATE() {
  [ -f "$INSTALL_PATH/easytier-core" ] || die "$INSTALL_PATH 下未找到 EasyTier，无法更新"

  local state_file="$INSTALL_PATH/.install-state"
  local old_mode=""
  [ -f "$state_file" ] && old_mode=$(grep '^MODE=' "$state_file" | head -n 1 | cut -d= -f2)

  PREPARE_BINARY

  ACTIVE_SERVICES=()
  if [ "$INIT_SYSTEM" = "systemd" ]; then
    mapfile -t ACTIVE_SERVICES < <(systemctl list-units --type=service --state=active --no-legend 2>/dev/null \
      | awk '{print $1}' | grep '^easytier@' || true)
    if [ ${#ACTIVE_SERVICES[@]} -gt 0 ]; then
      echo "停止服务: ${ACTIVE_SERVICES[*]}"
      systemctl stop "${ACTIVE_SERVICES[@]}"
    fi
  else
    rc-service easytier stop >/dev/null 2>&1 || true
  fi

  BACKUP_DIR=$(mktemp -d /tmp/easytier-config-backup-XXXXXX)
  [ -d "$INSTALL_PATH/config" ] && cp -a "$INSTALL_PATH/config" "$BACKUP_DIR/"

  cp -f "$SRC_DIR/easytier-core" "$SRC_DIR/easytier-cli" "$INSTALL_PATH/"
  chmod 755 "$INSTALL_PATH/easytier-core" "$INSTALL_PATH/easytier-cli"
  chown root:root "$INSTALL_PATH/easytier-core" "$INSTALL_PATH/easytier-cli"
  if [ -d "$BACKUP_DIR/config" ]; then
    cp -af "$BACKUP_DIR/config/." "$INSTALL_PATH/config/"
  fi

  if command -v setcap >/dev/null 2>&1; then
    case "$old_mode" in
      client | hybrid) CAPS='cap_net_admin+ep' ;;
      forward | oneway) CAPS='cap_net_bind_service+ep' ;;
      *) CAPS="" ;;
    esac
    [ -n "$CAPS" ] && setcap "$CAPS" "$INSTALL_PATH/easytier-core" || true
  fi

  if [ "$INIT_SYSTEM" = "systemd" ]; then
    systemctl daemon-reload
    if [ ${#ACTIVE_SERVICES[@]} -gt 0 ]; then
      systemctl start "${ACTIVE_SERVICES[@]}"
    fi
  else
    rc-service easytier start || true
  fi

  [ -f "$state_file" ] && sed -i "s/^TAG=.*/TAG=${TAG}/" "$state_file"
  echo -e "\r\n${GREEN_COLOR}已更新到 ${TAG}（配置保持不变）${RES}"
}

case "$COMMAND" in
  install) INSTALL ;;
  download) DOWNLOAD ;;
  update) UPDATE ;;
  uninstall) UNINSTALL ;;
  *) die "未知命令: $COMMAND（可用: install, download, update, uninstall, help）" ;;
esac
