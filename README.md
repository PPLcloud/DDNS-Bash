# DDNS-Bash

一个轻量且易用的 **DDNS** 脚本，仅使用 **bash** 实现。目前支持 **Cloudflare** 和 **dynv6** 的 DDNS 服务，自动检测 IPv4 和 IPv6 的可用性，分别更新 A 记录与 AAAA 记录。脚本会自动为您添加 `crontab` 定时任务，并支持通过 **Telegram Bot** 发送通知，依赖于 **curl** 与 **jq**。

---

## 1. 使用 Cloudflare 域名的 DDNS

如果您拥有自己的域名并托管在 Cloudflare 上，可按照以下步骤使用 `DDNS-cloudflare.sh` 脚本：

### 获取脚本

```bash
curl -sSL https://raw.githubusercontent.com/PPLcloud/DDNS-Bash/main/DDNS-cloudflare.sh -o ./DDNS-cloudflare.sh && chmod +x ./DDNS-cloudflare.sh
```

### 获取您的 Cloudflare 的API密钥，如果之前不曾创建过，可以按照下面这段简短教程

1. 进入 [https://dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens)。
2. 选择 **Create Token**。
3. 选择 **Edit zone DNS** 模板。
4. 调整权限，新增 **Zone - DNS - Edit**（默认会添加，确认存在即可）。
5. 在 **Zone Resources** 中，选择您的域名。
6. 点击 **Continue to summary**，然后 **Create Token**。
7. 保存获取到的 40 位 API 密钥。

### 获取 Zone ID

1. 进入 [Cloudflare 仪表盘](https://dash.cloudflare.com/)。
2. 点击您托管的域名（例如，更新 `761.ppl.red` 时，选择 `ppl.red`）。
3. 在页面右侧下方找到 32 位的 **Zone ID** 并保存。

### 修改脚本配置

编辑 `./DDNS-cloudflare.sh`，替换以下内容：

```bash
# ==============================
# 配置部分
# ==============================
API_KEY=""                                          # 替换为你的 Cloudflare API 密钥
ZONE_ID=""                                          # 替换为你的 Zone ID
HOST_NAME=""                                        # 要更新的域名

# Telegram Bot 配置（用于关键日志通知[可选，非必要]）
BOT_TOKEN=""                                        # 替换为你的 Bot Token
CHAT_ID=""                                          # 替换为你的 Chat ID
```

### 试运行脚本

运行以下命令检查 IP 是否正常更新，脚本会自动为您添加 crontab 定时任务：

```bash
./DDNS-cloudflare.sh
```

---

## 2. 使用 dynv6 免费二级域名的 DDNS

如果您没有自己的域名，可以使用 dynv6 提供的免费二级域名，按照以下步骤使用 `DDNS-dynv6.sh` 脚本：

### 获取脚本

```bash
curl -sSL https://raw.githubusercontent.com/PPLcloud/DDNS-Bash/main/DDNS-dynv6.sh -o ./DDNS-dynv6.sh && chmod +x ./DDNS-dynv6.sh
```

### 获取 dynv6 API 密钥（另外别忘了创建免费域名:)

1. 进入 [https://dynv6.com/keys](https://dynv6.com/keys)。
2. 点击 **HTTP Tokens** 下的 **Add HTTP Token** 创建新 token。
3. 保存获取到的 token。

### 修改脚本配置

编辑 `./DDNS-dynv6.sh`，替换以下内容：

```bash
DYNV6_TOKEN=""                                      # 输入您的 dynv6 token
DYNV6_HOSTNAME=""                                   # 输入您的 dynv6 主机名

# Telegram Bot 配置（可选）
TELEGRAM_BOT_TOKEN=""                               # 替换为你的 Bot Token
TELEGRAM_CHAT_ID=""                                 # 替换为你的 Chat ID
```

### 试运行脚本

运行以下命令检查 IP 是否正常更新，会自动添加crontab：

```bash
./DDNS-dynv6.sh
```

---

## 3. 常见问题

### 为什么 IP 未更新？

1. 检查 API 密钥和 Zone ID（Cloudflare）或 Token（dynv6）是否正确。
2. 确保域名已在服务商中正确配置。
3. 检查日志文件，查看错误信息。

### Telegram 通知未收到？

1. 确认 Bot Token 和 Chat ID 是否正确。
2. 确保您的 Bot 未被 Telegram 限制。
3. 检查网络连接是否允许访问 Telegram API。

---

## 4. 贡献与反馈

欢迎提交问题或建议！请访问 [GitHub 仓库](https://github.com/PPLcloud/DDNS-Bash) 提交 Issue 或 Pull Request。