#!/bin/bash
# EasyTier Linux 安装脚本（三种模式定制版）
# 软件源固定为 GitHub 官方 Releases，不使用第三方镜像

RED_COLOR='\e[1;31m'
GREEN_COLOR='\e[1;32m'
YELLOW_COLOR='\e[1;33m'
RES='\e[0m'

# ===== 软件源：GitHub 官方仓库 =====
REPO_BASE="https://github.com/EasyTier/EasyTier"
API_BASE="https://api.github.com/repos/EasyTier/EasyTier"

TMP_DIR=""
BACKUP_DIR=""
CURL_AUTH=()

die() {
  echo -e "\r\n${RED_COLOR}错误: $*${RES}\r\n" 1>&2
  exit 1
}

cleanup() {
  [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR"
  [ -n "$BACKUP_DIR" ] && rm -rf "$BACKUP_DIR"
  return 0
}
trap cleanup EXIT

HELP() {
  echo -e "\r\n${GREEN_COLOR}EasyTier 安装脚本（Linux / 官方源定制版）${RES}\r\n"
  echo "用法: ./install.sh [命令] [选项] [安装路径]"
  echo
  echo "命令:"
  echo "  install    安装 EasyTier（引导选择: 中继 / 客户端 / 混合）"
  echo "  update     从 GitHub 官方 Releases 更新"
  echo "  uninstall  卸载 EasyTier"
  echo "  help       显示帮助"
  echo
  echo "安装模式:"
  echo "  relay   中继: 不建 TUN，监听端口为其他节点转发，零特权"
  echo "  client  客户端: 建 TUN 加入网络，连接中继，不监听端口"
  echo "  hybrid  混合: 建 TUN 加入网络，同时监听端口为其他节点中继"
  echo
  echo "选项（不提供时全部交互式输入，没有默认值）:"
  echo "  --mode relay|client|hybrid   安装模式"
  echo "  --version TAG                指定 release 标签（默认使用官方 main 分支的 nightly 构建）"
  echo "  --network-name NAME          网络名"
  echo "  --network-secret SECRET      网络密钥"
  echo "  --relay-host HOST            要连接的中继域名/IP（客户端/混合）"
  echo "  --relay-port PORT            中继/监听端口，TCP+UDP 同端口"
  echo "  --ipv4 IP                    虚拟 IP（客户端/混合，全网唯一）"
  echo "  --instance-name NAME         实例名，决定配置文件名和服务实例名"
  echo "  --node-hostname NAME         节点 hostname"
  echo "  --machine-id ID              节点 machine_id（全网唯一）"
  echo "  --dev-name NAME              TUN 设备名（客户端/混合）"
  echo "  --token TOKEN                GitHub token（可选，用于 API 限流）"
  echo "  --skip-folder-verify         安装目录非空时也继续"
  echo "  --skip-folder-fix            不自动在安装路径后追加 /easytier"
  echo
  echo "示例:"
  echo "  ./install.sh install"
  echo "  ./install.sh install --mode relay"
  echo "  ./install.sh install --mode hybrid --version v2.6.4"
  echo "  ./install.sh update --version v2.6.4"
  echo "  ./install.sh uninstall"
  echo
  echo "软件源: ${REPO_BASE}/releases"
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
INSTANCE_NAME=""
NODE_HOSTNAME=""
MACHINE_ID=""
DEV_NAME=""
TOKEN=""
SKIP_FOLDER_VERIFY=false
SKIP_FOLDER_FIX=false

# 第一个非选项参数视为安装路径
if [ $# -gt 0 ] && [[ "$1" != --* ]]; then
  INSTALL_PATH="$1"
  shift
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)
      [ -n "${2:-}" ] || die "--mode 需要参数: relay、client 或 hybrid"
      MODE="$2"; shift ;;
    --version)
      [ -n "${2:-}" ] || die "--version 需要参数"
      VERSION="$2"; shift ;;
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
    --instance-name)
      [ -n "${2:-}" ] || die "--instance-name 需要参数"
      INSTANCE_NAME="$2"; shift ;;
    --node-hostname)
      [ -n "${2:-}" ] || die "--node-hostname 需要参数"
      NODE_HOSTNAME="$2"; shift ;;
    --machine-id)
      [ -n "${2:-}" ] || die "--machine-id 需要参数"
      MACHINE_ID="$2"; shift ;;
    --dev-name)
      [ -n "${2:-}" ] || die "--dev-name 需要参数"
      DEV_NAME="$2"; shift ;;
    --token)
      [ -n "${2:-}" ] || die "--token 需要参数"
      TOKEN="$2"; shift ;;
    --skip-folder-verify) SKIP_FOLDER_VERIFY=true ;;
    --skip-folder-fix) SKIP_FOLDER_FIX=true ;;
    *) die "未知选项: $1（用 help 查看用法）" ;;
  esac
  shift
done

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
for cmd in curl unzip; do
  command -v "$cmd" >/dev/null 2>&1 || die "缺少依赖: $cmd"
done

if command -v systemctl >/dev/null 2>&1; then
  INIT_SYSTEM="systemd"
elif command -v rc-service >/dev/null 2>&1; then
  INIT_SYSTEM="openrc"
else
  die "未找到 systemd 或 OpenRC，无法确定服务管理方式"
fi
[ "$(id -u)" = "0" ] || die "请以 root 身份运行本脚本"

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
  done
  printf '%s' "$answer"
}

# 从 GitHub 官方 API 获取 release tag 与资产地址
# 不指定 --version 时取 API 第一个 release（官方 main 分支的 nightly 构建）
FETCH_RELEASE() {
  local response tags
  if [ -n "$VERSION" ]; then
    response=$(curl -fsSL "${CURL_AUTH[@]}" "${API_BASE}/releases/tags/${VERSION}") \
      || die "无法从 GitHub 官方仓库获取版本 ${VERSION}，请确认 tag 存在"
    TAG="$VERSION"
  else
    response=$(curl -fsSL "${CURL_AUTH[@]}" "${API_BASE}/releases") \
      || die "无法访问 ${API_BASE}/releases，请检查网络；如触发 API 限流可用 --token"
    tags=$(printf '%s' "$response" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
      | sed -E 's/.*"([^"]+)"$/\1/')
    TAG=$(printf '%s\n' "$tags" | head -n 1)
    [ -n "$TAG" ] || die "GitHub 官方仓库 ${REPO_BASE}/releases 没有可用 Release"
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
  fi

  echo -e "${GREEN_COLOR}版本: ${TAG}${RES}"
  echo -e "${GREEN_COLOR}下载地址: ${ASSET_URL}${RES}"

  TMP_DIR=$(mktemp -d /tmp/easytier-install-XXXXXX)
  curl -fL "${CURL_AUTH[@]}" "$ASSET_URL" -o "$TMP_DIR/release.zip" $CURL_BAR \
    || die "下载失败，请检查 ${REPO_BASE}/releases 中 ${TAG} 对应的 easytier-linux-${ARCH}-*.zip 资产"
  unzip -q -o "$TMP_DIR/release.zip" -d "$TMP_DIR" || die "解压失败: $ASSET_URL"

  SRC_DIR="$TMP_DIR"
  for d in "$TMP_DIR"/easytier-linux-*; do
    if [ -d "$d" ]; then SRC_DIR="$d"; break; fi
  done
  [ -f "$SRC_DIR/easytier-core" ] && [ -f "$SRC_DIR/easytier-cli" ] \
    || die "压缩包中缺少 easytier-core / easytier-cli"
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
  if [ -z "$MODE" ]; then
    [ -t 0 ] || die "非交互环境请用 --mode relay、--mode client 或 --mode hybrid 指定模式"
    echo -e "\r\n${GREEN_COLOR}请选择安装模式${RES}"
    echo "  1) relay   中继: 不建 TUN，只监听端口转发"
    echo "  2) client  客户端: 建 TUN 加入网络，连接中继"
    echo "  3) hybrid  混合: 建 TUN 加入网络，同时监听端口为其他节点中继"
    while true; do
      read -r -p "输入 1 / 2 / 3: " choice
      case "$choice" in
        1 | relay) MODE="relay"; break ;;
        2 | client) MODE="client"; break ;;
        3 | hybrid) MODE="hybrid"; break ;;
        *) echo "无效输入，请重新选择" ;;
      esac
    done
  fi
  case "$MODE" in
    relay | client | hybrid) ;;
    *) die "--mode 只能是 relay、client 或 hybrid" ;;
  esac

  NETWORK_NAME=${NETWORK_NAME:-$(ask_required "网络名称")}
  NETWORK_SECRET=${NETWORK_SECRET:-$(ask_required "网络密钥（建议 openssl rand -base64 16 生成）")}
  RELAY_PORT=${RELAY_PORT:-$(ask_required "端口（TCP/UDP 同端口）")}
  validate_value "$NETWORK_NAME" "网络名称"
  validate_value "$NETWORK_SECRET" "网络密钥"
  case "$RELAY_PORT" in
    '' | *[!0-9]*) die "端口必须是数字" ;;
  esac
  if [ "$RELAY_PORT" -lt 1 ] || [ "$RELAY_PORT" -gt 65535 ]; then
    die "端口必须在 1-65535 之间"
  fi

  INSTANCE_NAME=${INSTANCE_NAME:-$(ask_required "实例名")}
  NODE_HOSTNAME=${NODE_HOSTNAME:-$(ask_required "节点 hostname")}
  MACHINE_ID=${MACHINE_ID:-$(ask_required "节点 machine_id（全网唯一）")}
  validate_value "$INSTANCE_NAME" "实例名"
  validate_value "$NODE_HOSTNAME" "hostname"
  validate_value "$MACHINE_ID" "machine_id"

  if [ "$MODE" = "relay" ]; then
    # 中继不需要中继地址、虚拟 IP 和 TUN 设备名
    CONFIG_NAME="default"
  else
    RELAY_HOST=${RELAY_HOST:-$(ask_required "要连接的中继域名或公网 IP")}
    IPV4=${IPV4:-$(ask_required "虚拟 IP（全网唯一）")}
    DEV_NAME=${DEV_NAME:-$(ask_required "TUN 设备名")}
    validate_value "$RELAY_HOST" "中继地址"
    validate_value "$DEV_NAME" "TUN 设备名"
    if ! [[ "$IPV4" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      die "虚拟 IP 格式不正确: $IPV4"
    fi
    IFS='.' read -r o1 o2 o3 o4 <<< "$IPV4"
    for o in "$o1" "$o2" "$o3" "$o4"; do
      [ "$o" -le 255 ] 2>/dev/null || die "虚拟 IP 含非法段: $IPV4"
    done
    if [ "$MODE" = "hybrid" ]; then
      CONFIG_NAME="hybrid"
    else
      CONFIG_NAME="client"
    fi
  fi

  CONFIG_FILE="$INSTALL_PATH/config/${CONFIG_NAME}.conf"
  SERVICE="easytier@${CONFIG_NAME}"
}

WRITE_CONFIG() {
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
    client)
      cat > "$CONFIG_FILE" <<EOF
instance_name = "$INSTANCE_NAME"
hostname = "$NODE_HOSTNAME"
machine_id = "$MACHINE_ID"

ipv4 = "$IPV4"
dhcp = false
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
disable_p2p = true
dev_name = "$DEV_NAME"
EOF
      ;;
    hybrid)
      cat > "$CONFIG_FILE" <<EOF
instance_name = "$INSTANCE_NAME"
hostname = "$NODE_HOSTNAME"
machine_id = "$MACHINE_ID"

ipv4 = "$IPV4"
dhcp = false
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
disable_p2p = true
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
    if [ "$MODE" != "relay" ]; then
      CAP_LINES="AmbientCapabilities=CAP_NET_ADMIN
CapabilityBoundingSet=CAP_NET_ADMIN"
    fi
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
  # 客户端和混合模式都要建 TUN；中继零 capability
  [ "$MODE" = "relay" ] && return
  echo 'KERNEL=="tun", MODE="0666"' > /etc/udev/rules.d/99-tun.rules
  udevadm control --reload-rules >/dev/null 2>&1 || true
  udevadm trigger >/dev/null 2>&1 || true
  if command -v setcap >/dev/null 2>&1; then
    setcap 'cap_net_admin+ep' "$INSTALL_PATH/easytier-core" \
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
  if [ "$MODE" = "relay" ] || [ "$MODE" = "hybrid" ]; then
    if command -v ufw >/dev/null 2>&1; then
      read -r -p "检测到 ufw，是否放行 ${RELAY_PORT}/tcp 与 ${RELAY_PORT}/udp? [y/N]: " answer
      case "$answer" in
        y | Y)
          ufw allow "${RELAY_PORT}/tcp" >/dev/null && ufw allow "${RELAY_PORT}/udp" >/dev/null \
            && echo -e "${GREEN_COLOR}ufw 已放行 ${RELAY_PORT}/tcp 与 udp${RES}"
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
      relay) OTHER_SERVICES="easytier@client easytier@hybrid" ;;
      client) OTHER_SERVICES="easytier@default easytier@hybrid" ;;
      hybrid) OTHER_SERVICES="easytier@default easytier@client" ;;
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
  FETCH_RELEASE

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
  if [ "$MODE" = "relay" ] || [ "$MODE" = "hybrid" ]; then
    echo "  监听    : tcp/udp ${RELAY_PORT}（防火墙/安全组需放行）"
  fi
  if [ "$MODE" != "relay" ]; then
    echo "  中继    : tcp://${RELAY_HOST}:${RELAY_PORT}"
    echo "  虚拟 IP : $IPV4"
    echo "  TUN     : $DEV_NAME"
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
  if [ "$MODE" != "relay" ]; then
    echo "  ip a show ${DEV_NAME}"
    echo "  ping <对端虚拟IP>"
    echo -e "${YELLOW_COLOR}验证通过后可删除配置里的 disable_p2p = true 以允许直连${RES}"
  fi
  echo
}

UNINSTALL() {
  echo -e "${GREEN_COLOR}卸载 EasyTier ...${RES}"
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
  echo -e "${GREEN_COLOR}EasyTier 已卸载（easytier 系统用户保留）${RES}"
}

UPDATE() {
  [ -f "$INSTALL_PATH/easytier-core" ] || die "$INSTALL_PATH 下未找到 EasyTier，无法更新"

  local state_file="$INSTALL_PATH/.install-state"
  local old_mode=""
  [ -f "$state_file" ] && old_mode=$(grep '^MODE=' "$state_file" | head -n 1 | cut -d= -f2)

  FETCH_RELEASE

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

  if [ "$old_mode" != "relay" ] && command -v setcap >/dev/null 2>&1; then
    setcap 'cap_net_admin+ep' "$INSTALL_PATH/easytier-core" || true
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
  update) UPDATE ;;
  uninstall) UNINSTALL ;;
  *) die "未知命令: $COMMAND（可用: install, update, uninstall, help）" ;;
esac
