# EasyTier 安装脚本（本地定制仓库）

本仓库只保留定制安装脚本和许可证，**不包含 EasyTier 源码**。二进制包直接取自 GitHub 官方 Releases。

源码、文档和问题反馈请访问官方代码仓库：<https://github.com/EasyTier/EasyTier>

- 官方文档：<https://easytier.cn/>
- 官方预编译包（安装脚本的下载源）：<https://github.com/EasyTier/EasyTier/releases>

## 本仓库内容

| 文件 | 说明 |
| --- | --- |
| `install.sh` | Linux 安装 / 更新 / 卸载，支持三种模式 |
| `LICENSE` | 许可证，见文件原文 |

## 三种安装模式

| 模式 | 说明 | 建 TUN | 监听端口 | 配置 / 服务 |
| --- | --- | --- | --- | --- |
| `relay` 中继 | 不建 TUN，只转发流量，几乎零特权 | 否 | 是 | `default.conf` / `easytier@default` |
| `client` 客户端 | 建 TUN 加入网络，连接中继，不监听 | 是 | 否 | `client.conf` / `easytier@client` |
| `hybrid` 混合 | 建 TUN 加入网络，同时监听端口给其他节点中继 | 是 | 是 | `hybrid.conf` / `easytier@hybrid` |

脚本安装时按模式最小化询问，**业务参数没有预设默认值**：

- 所有模式：选择模式、输入网络名、端口。
- 客户端 / 混合模式：再输入网络密钥、中继节点地址，并选择 DHCP 或静态 IP（选静态 IP 时再填虚拟 IP）。

实例名、hostname、machine_id、TUN 设备名由脚本按模式自动生成，无需输入。

需要自动化时可用 `--mode`、`--network-name`、`--version`、`--ipv4` 或 `--dhcp` 等参数，详见：

```bash
bash install.sh help
```

## 安装

```bash
curl -fsSL "https://git.rao.jx.cn/hongyan/EasyTier/raw/branch/main/install.sh" -o /tmp/easytier-install.sh
sudo bash /tmp/easytier-install.sh install
```

其他命令：

```bash
sudo bash /tmp/easytier-install.sh update      # 从 GitHub 官方 Releases 更新
sudo bash /tmp/easytier-install.sh uninstall   # 卸载
```

脚本需要 root 运行，依赖 `curl` 与 `unzip`。默认安装目录 `/opt/easytier`，配置在 `/opt/easytier/config/`，服务实例名取决于所选模式。

```bash
systemctl status easytier@default     # 或 easytier@client / easytier@hybrid
journalctl -u easytier@client -n 50 --no-pager
```

脚本会创建专用用户 `easytier`，二进制归 `root:root`，只把配置与日志目录交给运行用户；客户端/混合模式会加 `CAP_NET_ADMIN` 并放行 tun 设备。

## 二进制来源

`install.sh` 通过 GitHub API 获取 release：不传 `--version` 时默认使用官方 `main` 分支的 nightly 构建（当前资产如 `easytier-linux-x86_64-v2.7.1.zip`）；如需固定稳定版本（例如中继与客户端版本一致），使用：

```bash
sudo bash /tmp/easytier-install.sh install --version v2.6.4
sudo bash /tmp/easytier-install.sh update --version v2.6.4
```

遇到 GitHub API 限流时可传 `--token <GitHub token>`。

## 许可证

见仓库 [LICENSE](LICENSE) 文件。EasyTier 源码版权归官方项目所有，本仓库仅提供定制安装脚本。
