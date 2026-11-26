# EasyTier 安装脚本（本地定制仓库）

本仓库只保留定制安装脚本和许可证，**不包含 EasyTier 源码**。安装时可选从 GitHub 官方源、作者自用备份源或 GH-Proxy 加速源获取二进制包，也可以先下载安装包、再用本地包安装。

源码、文档和问题反馈请访问官方代码仓库：<https://github.com/EasyTier/EasyTier>

- 官方文档：<https://easytier.cn/>
- 官方源：<https://github.com/EasyTier/EasyTier/releases>
- 自用源（备份包）：<https://git.rao.jx.cn/hongyan/EasyTier/releases>
- GH-Proxy 加速源使用说明：<https://gh-proxy.com/docs/github-accelerator>

## 本仓库内容

| 文件 | 说明 |
| --- | --- |
| `install.sh` | Linux 安装 / 更新 / 卸载，支持五种模式 |
| `LICENSE` | 许可证，见文件原文 |

## 五种安装模式

| 模式 | 说明 | 建 TUN | 监听端口 | 配置 / 服务 |
| --- | --- | --- | --- | --- |
| `relay` 中继 | 不建 TUN，只转发流量，几乎零特权 | 否 | 是 | `default.conf` / `easytier@default` |
| `client` 客户端 | 建 TUN 加入网络，连接中继，不监听 | 是 | 否 | `client.conf` / `easytier@client` |
| `hybrid` 混合 | 建 TUN 加入网络，同时监听端口给其他节点中继 | 是 | 是 | `hybrid.conf` / `easytier@hybrid` |
| `forward` 中继+端口转发 | no_tun 加入虚拟网络，低端口监听并转发到虚拟 IP | 否 | 是 | `forward.conf` / `easytier@forward` |
| `oneway` 单向客户端 | no_tun 加入虚拟网络，不监听端口，可被虚拟网访问，靠 `port_forward` 主动访问别人 | 否 | 否 | `oneway.conf` / `easytier@oneway` |

一键卸载使用独立命令 `./install.sh uninstall`，**不经过安装流程、不询问网络名等安装参数**：停止所有 `easytier@*` 实例，清理服务文件、软链、udev 规则和安装目录。卸载时会询问是否同时删除 `easytier` 系统用户，默认保留；非交互环境可用 `--remove-user` 删除、`--keep-user` 保留。

脚本安装时按模式最小化询问，**业务参数没有预设默认值**：

- 所有模式：选择模式、输入网络名、端口；设备名称可选填，直接回车用本机名称。
- 客户端 / 混合 / 端口转发 / 单向客户端：再输入网络密钥、中继节点地址，并选择 DHCP 或静态 IP（选静态 IP 时再填虚拟 IP）。no_tun 节点自身也需要虚拟 IP，否则无法稳定学习到转发目标的路由。
- 端口转发和单向客户端的具体 `[[port_forward]]` 规则不在安装时录入，安装完成时会打印配置模板，按需追加到 `forward.conf` / `oneway.conf` 后重启服务。单向客户端默认不监听端口，只能被虚拟网访问；要主动访问别人必须配置 `[[port_forward]]`。
- 如果 `forward` 节点就部署在中继服务器本机，必须删除 `forward.conf` 中的两段 `[[peer]]`（或改成另一台中继的地址），否则会连接自己并报 `peer id conflict, are you connecting to yourself?`。

实例名、machine_id、TUN 设备名由脚本按模式自动生成。设备名称（hostname）在交互安装时可自定义：直接回车使用本机系统名称，也可以输入自己的名字；自动化安装用 `--hostname` 指定。同一网络内建议不要重名。

需要自动化时可用 `--mode`、`--hostname`、`--network-name`、`--version`、`--source`、`--local-file`、`--ipv4`、`--dhcp` 等参数，详见：

```bash
bash install.sh help
```

## 安装

```bash
curl -fsSL "https://github.com/hongyandev-cpu/EasyTier-install/blob/main/install.sh" -o /tmp/easytier-install.sh
sudo bash /tmp/easytier-install.sh install
```

其他命令：

```bash
sudo bash /tmp/easytier-install.sh update      # 从所选下载源更新，配置保持不变
sudo bash /tmp/easytier-install.sh uninstall   # 卸载
```

安装时如果不传 `--source`，会交互式询问下载源（官方源 / 自用源 / 加速源）；非交互环境默认官方源。

脚本需要 root 运行，依赖 `curl` 与 `unzip`。默认安装目录 `/opt/easytier`，配置在 `/opt/easytier/config/`，服务实例名取决于所选模式。

```bash
systemctl status easytier@default     # 或 easytier@client / easytier@hybrid / easytier@forward / easytier@oneway
journalctl -u easytier@client -n 50 --no-pager
```

脚本会创建专用用户 `easytier`，二进制归 `root:root`，只把配置与日志目录交给运行用户；客户端/混合模式加 `CAP_NET_ADMIN` 并放行 tun 设备；端口转发模式是 `no_tun`，只需 `CAP_NET_BIND_SERVICE`，使专用用户能监听 1024 以下端口，通过用户态协议栈把流量送进虚拟网。systemd drop-in 与 `setcap` 都会按模式设置对应 capability。

## 各模式的 systemd 运维命令

同一台机器脚本只保留一个实例；如需换模式，先停旧实例再重新用另一种模式安装。

| 模式 | 服务名 | 配置文件 |
| --- | --- | --- |
| `relay` | `easytier@default` | `/opt/easytier/config/default.conf` |
| `client` | `easytier@client` | `/opt/easytier/config/client.conf` |
| `hybrid` | `easytier@hybrid` | `/opt/easytier/config/hybrid.conf` |
| `forward` | `easytier@forward` | `/opt/easytier/config/forward.conf` |
| `oneway` | `easytier@oneway` | `/opt/easytier/config/oneway.conf` |

把 `SERVICE` 换成上表里的服务名即可：

```bash
SERVICE=easytier@client

systemctl status "$SERVICE"
systemctl start "$SERVICE"
systemctl stop "$SERVICE"
systemctl restart "$SERVICE"

# 开机自启 / 取消自启（安装时已 enable）
systemctl enable "$SERVICE"
systemctl disable --now "$SERVICE"

# 日志
journalctl -u "$SERVICE" -n 50 --no-pager
journalctl -u "$SERVICE" -f

# 查看所有实例
systemctl list-units 'easytier@*' --all
systemctl list-unit-files 'easytier@*'
```

改完配置后必须 `systemctl restart "$SERVICE"` 才生效。卸载用 `./install.sh uninstall`，它会停掉所有 `easytier@*` 实例。

## no_tun 与虚拟 IP 的访问关系

`ipv4` / `dhcp` 是给节点在 EasyTier 虚拟网里分配地址；`no_tun` 只是不创建内核 `tun0`、不把虚拟网段写进系统路由表。两者互不影响：no_tun 节点同样可以有虚拟 IP、可以被 ping。

| 能力 | no_tun（`relay` / `forward` / `oneway`） | 建 TUN（`client` / `hybrid`） |
| --- | --- | --- |
| 被其他节点用虚拟 IP ping / 访问 | 可以 | 可以 |
| 本机任意程序直接访问 `192.168.199.x` | 不行（流量走宿主物理网络） | 可以（走 `tun0`） |
| 本机端口经 `[[port_forward]]` 转发到虚拟 IP | 可以 | 可以 |
| 需要 `CAP_NET_ADMIN` / `/dev/net/tun` | 不需要 | 需要 |

验证本机有没有走 TUN：

```bash
ip route get 192.168.199.3
```

如果输出不是经过 `tun0`，说明本机普通程序不会自动走虚拟网。

**其他机器怎么访问这台节点上的服务：**

- 已加入虚拟网的机器：直接用这台节点的虚拟 IP，例如 `curl http://192.168.199.2:8080`。服务需在节点上监听（建议 `0.0.0.0:8080`）。
- 公网或未加入虚拟网的机器：只能访问 `[[port_forward]]` 里声明并放通防火墙的端口。若要暴露节点自身的服务，把 `dst_addr` 写成该节点自己的虚拟 IP，例如：

```toml
[[port_forward]]
bind_addr = "0.0.0.0:8080"
dst_addr = "192.168.199.2:8080"
proto = "tcp"
```

然后 `systemctl restart easytier@forward`，并在 `ufw` 和云安全组放行 `8080/tcp`。`dst_addr` 必须是虚拟网 IPv4:端口，不能写公网 IP 或域名。

## 访问控制（ACL）

EasyTier 内置 ACL，可限制虚拟网内其他节点访问本机端口。配置写在**本机**配置文件 `/opt/easytier/config/<模式>.conf` 里，本地生效，不是全网统一下发。需要 EasyTier 2.4.0+（按 IP）或 2.4.3+（按身份组）。

常用字段：

| 字段 | 含义 |
| --- | --- |
| `chain_type = 1` | 入站链（别人访问本机）；`2` 出站；`3` 转发链 |
| `default_action = 1` | 没有规则命中时的默认动作：`1` 放行，`2` 拒绝 |
| `action` | 规则命中后的动作：`0` 无操作，`1` 放行，`2` 拒绝 |
| `priority` | 优先级 0-65535，数字越大越先匹配；第一条命中的规则生效，后续规则不再检查 |
| `protocol` | `1` TCP，`2` UDP，`3` ICMP，`5` 所有协议 |
| `ports` | 目标端口列表，如 `["22"]`；`[]` 表示所有端口 |
| `source_ips` | 来源虚拟 IP（CIDR），如 `["10.0.0.2/32"]`；`[]` 表示所有来源 |
| `source_groups` | 来源身份组，需配合 `group.declares`，所有节点的声明必须一致 |

**例：拒绝所有虚拟网节点访问本机 TCP 22，其他端口不受影响**（`default_action = 1` 表示其余入站默认放行）。追加到对应模式的 `.conf` 末尾：

```toml
[[acl.acl_v1.chains]]
name = "deny_ssh_from_virtual_net"
chain_type = 1
enabled = true
default_action = 1

[[acl.acl_v1.chains.rules]]
name = "deny_ssh"
priority = 1000
action = 2
source_ips = []
protocol = 1
ports = ["22"]
enabled = true
```

**如果你自己正是通过 EasyTier SSH 登录这台机器**，必须先放行自己的管理机 IP 再拒绝其他人，否则会把自己锁在外面。例外规则的 `priority` 必须比拒绝规则大：

```toml
[[acl.acl_v1.chains.rules]]
name = "allow_my_ssh"
priority = 1001
action = 1
source_ips = ["<管理机虚拟IP>/32"]
protocol = 1
ports = ["22"]
enabled = true
```

改完重启服务并验证：

```bash
systemctl restart easytier@<实例名>
easytier-cli acl stats
```

`oneway` 模式的 RPC 在 `127.0.0.1:15888`，查看 ACL 统计需要：

```bash
easytier-cli --rpc-portal 127.0.0.1:15888 acl stats
```

**注意**：`forward` / `oneway` 是 `no_tun`，虚拟网流量走 EasyTier 用户态协议栈，系统防火墙（ufw/iptables）通常拦不到，这类节点要用 ACL 限制；`client` / `hybrid` 建了 TUN，也可配合系统防火墙。

官方完整文档：<https://easytier.cn/guide/config/acl.html>

## 下载源与离线安装

安装时选择下载源（交互选择，或用 `--source` 指定）：

| `--source` | 来源 | 说明 |
| --- | --- | --- |
| `github` | 官方源 | GitHub 官方仓库，版本最全 |
| `self` | 自用源 | 作者备份仓库，官方源网络不通时可尝试 |
| `proxy` | 加速源 | 通过 GH-Proxy 访问官方仓库，下载慢时可尝试 |

`proxy` 源仍以官方仓库为内容来源，脚本按[官方文档](https://gh-proxy.com/docs/github-accelerator)把原始 GitHub 资源地址（包括 API 与 release 资产）完整拼在代理前缀后。

```bash
sudo bash /tmp/easytier-install.sh install --source self
sudo bash /tmp/easytier-install.sh install --source proxy
sudo bash /tmp/easytier-install.sh update --source github
```

不传 `--version` 时取所选源 API 返回的最新 release；固定版本（例如中继与客户端版本一致）用 `--version`：

```bash
sudo bash /tmp/easytier-install.sh install --version v2.6.4
sudo bash /tmp/easytier-install.sh update --version v2.6.4
```

遇到 API 限流时可传 `--token <token>`。

可以先只下载安装包，之后再设置配置并用本地包安装（跳过联网下载）：

```bash
# 只下载，不安装、不改动系统；默认保存到当前目录，可用 --output 指定目录
sudo bash /tmp/easytier-install.sh download --source self --output /tmp/easytier-pkg
sudo bash /tmp/easytier-install.sh download --source proxy --output /tmp/easytier-pkg

# 之后安装：会照常引导填写网络名、模式等配置，但不再联网下载
sudo bash /tmp/easytier-install.sh install --local-file /tmp/easytier-pkg/easytier-linux-x86_64-v2.6.4.zip
```

`--local-file` 也适用于 `update`（只替换二进制，配置保持不变）。本地包必须是与本机架构匹配的官方 zip。

## 许可证

见仓库 [LICENSE](LICENSE) 文件。EasyTier 源码版权归官方项目所有，本仓库仅提供定制安装脚本。
