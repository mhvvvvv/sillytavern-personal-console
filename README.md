# 我的后台 · SillyTavern Personal Console
在扩展设置中查看并复制自己最近一次聊天补全的诊断。支持 OpenAI 兼容 SSE 流式和非流式响应，显示模型、结束原因、工具名和 token 用量（缺失时不估算），以及匹配的错误原文。新请求覆盖旧记录；会话诊断仅在内存短暂保留，10 分钟过期。不保存正常回复正文、推理内容或工具参数，不导出整个终端。

## 安装：两种方式，选一种

### ① VPS 一键安装
适合 **Docker Compose 管理、已在运行的酒馆**。在酒馆的 Compose 目录运行（需要 Docker Compose v2、Python 3、curl、tar，不需要 Git）。公开仓库可直接下载；私有仓库可先登录 `gh`，或用有权限的浏览器下载源码包并放到 VPS 再解压运行。不要把令牌写进命令或发给 Agent。

```sh
(d=$(mktemp -d) && trap 'rm -rf "$d"' EXIT && { curl -fsSL https://github.com/mhvvvvv/sillytavern-personal-console/archive/refs/heads/main.tar.gz -o "$d/src.tgz" || gh api repos/mhvvvvv/sillytavern-personal-console/tarball/main > "$d/src.tgz"; } && tar -xzf "$d/src.tgz" -C "$d" --strip-components=1 && sh "$d/install-vps.sh")
```
0.7.0 默认**不重建容器**：确认后只复制服务端插件和全局面板到现有容器，执行一次 `docker restart`。不会改 Compose、挂载、登录方式和其他插件。安装前可在脚本后加 `--dry-run`。已有安装或未配置受支持的登录方式时停止。普通重启保留；若插件父目录没有持久化，未来升级镜像或由其他工具重建容器后需重新安装。要保证跨重建保留，请预先持久化两个父目录；本脚本不替你改变挂载。

### ② 让 Agent 辅助安装
把下面一句话连同仓库访问权限交给能管理你 VPS 的 Agent（不要发送密码或令牌）：

> 帮我安装「我的后台」：https://github.com/mhvvvvv/sillytavern-personal-console/tree/main 。先读 AGENTS.md，只读确认我的酒馆部署和登录方式，给出安装与回滚方案，等我确认后再修改或重启。保留数据、现有插件和认证，不输出密钥或聊天内容。

已有插件要升级，或使用原生安装、Termux、1Panel、Portainer、自定义 Compose，请选此方式。

## 身份与隐私
安装前会读取酒馆配置并报告模式：显式可信门禁优先，其次原生用户账号，再是 basicAuthMode: true。仅 Basic Auth 时无需再开原生账号：酒馆先验证 Basic 凭据，插件使用酒馆签名会话区分浏览器，不按密码、IP 或共享用户名分组。同浏览器标签页共享记录，不同浏览器分别记录。必须实际启用酒馆 Basic 中间件（listen）；关闭认证或仅在外层代理开 Basic 不会当作此模式。公网请使用 HTTPS。
默认面向酒馆原生密码账号：按已登录用户隔离，同一账号跨设备共享最新一条。共用默认用户不是独立账号。外部登录网关可选 `PERSONAL_CONSOLE_AUTH=verified-door`，仅适用于已在反向代理逐请求验证 `__Host-tavern` Cookie 且后端无法绕过的部署。此模式按会话隔离；插件自身不验证网关 Cookie，普通公网部署不要启用。错误中的凭据检测不可能完备，请在转发前复核。插件不改变酒馆自身的日志保留策略。

## 兼容与测试
已在 SillyTavern 1.19.1 / Node 26 下验证外部门禁双会话隔离、真实手机流式摘要；0.7.0 在独立无外网的真实 Compose 实例验证：安装后容器 ID 不变、酒馆恢复、两个密码账号 A/B/A 互不串记录、认证后全局 UI 可读。未调用真实模型；Termux 和面板托管环境未实机验收。插件依赖聊天补全路由和部分日志调用，并非所有服务商路径都能捕获。升级酒馆请先测试。运行 `npm test`，无额外 npm 依赖。

