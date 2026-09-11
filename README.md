# dev-setup — 一条命令配好这个团队的开发环境

新人入职、或者换了一台新机器，**只需要一条命令 + 一个凭证**。不用 clone 任何私有仓库，
不用先装什么工具，不用有 GitHub 权限 —— 这个仓库是公开的，就是为了让"什么都还没有的人"
也能跑。

```bash
curl -fsSL https://raw.githubusercontent.com/when2buy/dev-setup/main/install.sh | bash
```

它会问你要那个凭证（形如 `<uuid>:<一长串>`，Steve 直接发给你）。粘进去、回车，完事。之后
**每开一个新 shell，全部 key 都已经在环境变量里**，而且**私有仓库直接 `git clone` 就能拉**。

```
==> Checking what this machine already has
    ✓ linux/amd64
==> Installing the Infisical CLI
    ✓ ~/.local/bin/infisical  (infisical version 0.43.129)
==> Storing your credential
    ✓ client id 36 chars, secret 64 chars
==> Checking the credential against Infisical
    ✓ accepted; got a session token of 862 chars (it expires in 2 hours)
    ✓ ~/.secrets/infisical.env  (mode 600)
==> Installing the `keys` loader
    ✓ ~/.local/share/team-keys/keys.sh
    ✓ ~/.bashrc  →  KEYS_AUTO="all"
==> Wiring `git clone` for private repos
    ✓ git clone https://github.com/when2buy/<repo>  works with no further setup
==> Fetching for real
keys: all — 63 key(s) in this shell
```

实测：一台什么都没有的机器（没装 CLI、没有卡、`.bashrc` 没动过）上，从零到全部 key
在环境变量里 —— **4.8 秒**，其中大头是下那个 56 MB 的 CLI。

---

## 先说清楚：你拿到的那个凭证**不是 API key**

它是一张**门卡**（`client id` + `client secret`）。这张卡本身打不开任何第三方服务，
它只能换一张**两小时后过期**的 token，那张 token 才去把真正的 key 取下来。

这个区别不是文字游戏，它决定了三件事：

| | 直接发 API key（以前） | 发门卡（现在） |
|---|---|---|
| key 存在你机器上吗 | 存在 `.env` / `.bashrc` 里，明文 | **不存在**。用的时候现场取，进内存，随 shell 消失 |
| 轮换一个 key | 得通知每个人、每台机器改一遍 | **你什么都不用做**，下次取到的自动是新的 |
| 你离职 / 卡泄漏 | 所有 key 全部得换 | 吊销**你这一张卡**，别人一个都不受影响 |

所以：**不要把这张卡转发给别人**。新来的人有自己的一张，这样台账才有意义。

---

## 装完之后怎么用

**默认情况下你不需要用它** —— 装完之后每个 shell 里已经是全部 key（72 条、63 个不同名字），以及能用的
`git clone` / `gh`。要手动干预的时候才有这几条：

```bash
keys --status          # 现在加载了什么（只打名字和长度，永远不打值）
keys --refresh all     # 不走缓存，现在就去取（刚有人轮换过 key 的时候）
keys --list            # 有哪些 key 组、分别在哪
keys aitist            # 只把某一组加进【当前这个】shell
```

`keys` 是一个 shell 函数，不是可执行文件 —— 它必须能改**当前** shell 的环境变量，
而子进程改不了父进程的环境。所以 rc 文件里是 `. keys.sh` 而不是执行它。

### key 组（profile）

| profile | 里面是什么 | 说明 |
|---|---|---|
| **`all`** | 下面那五组全部（**72 条，63 个不同名字**） | **默认，每个 shell 自动加载**。有 9 个名字同时存在于两个文件夹（6 个 Cloudflare 在 `/when2buy` 和 `/Aitist`，3 个 GitHub 在 `/when2buy` 和 `/Steve`）。加载顺序固定 paper→aitist→…→steve，所以 `/Aitist` 和 `/Steve` 胜出、行为和以前一样。九个里只有 `CF_ZONE_*` 的值真的不同（when2buy=aitist.ai，Aitist=afoundry.org），其余都是引用同一份 |
| `paper` | 模拟盘券商凭证 | ⛔ 见下面那条红线 |
| `aitist` / `airacle` / `zhongtian` / `steve` | 各应用的第三方厂商 key + GitHub token | 想只要某一组时 `keys <名字>` |
| `*-prod` / `live` | 生产 / **实盘真钱** | 只有服务器的卡读得到；开发机拿到 `403` 是**预期行为**，不是坏了 |

> ⛔ **`paper` 里有 5 对券商凭证，其中两对上面有正在运行的策略 —— 别拿它们下测试单。**
> `ALPHA_VAULT_OPS_PAPER_*` 和 `ZOUYANG_PAPER_ALPACA_*` 这两对是自动交易 controller 在用的；
> 往那两个账户下一张手动单，会污染它们的盈亏归因，而那是那些策略**唯一的证据**。
> **要试手就用 `AITIST_DEBUG_PAPER_ALPACA_*`。** 模拟盘的钱是免费的，模拟盘的证据不是。
> （`AITIST_OFFICIAL_*` / `AITIST_ENRICO_DEV_*` 也有人在用，问一声再动。）
>
> 平仓请指定数量，**不要 `percentage=100`** —— 那些账户里已经有别人的持仓，
> 100% 平仓会把你没开的那部分一起平掉（这个我们自己踩过）。

不想全部自动加载，就改 `~/.local/share/team-keys/rc.sh` 里那行 `KEYS_AUTO="all"`
（空格分隔几组，或者 `none` 什么都不加）。

### 私有仓库

装完就能拉，不用再找 token：

```bash
git clone https://github.com/when2buy/<repo>     # 私有的也行
gh repo list when2buy                            # gh 也已经带好 GH_TOKEN
```

原理：`install.sh` 给 github.com 配了一个 credential helper，它在 clone 的**当时**去环境
变量里读 token —— 所以 token 轮换了你什么都不用改，磁盘上也没有 token 的副本。

### 为什么新 shell 不会变慢

登录路径**只读本地缓存，永远不碰网络**。从一台云上机器到 `app.infisical.com` 一个来回实测约
240 ms，而读本地文件约 0.1 ms —— 比 bash 自己 2.8 ms 的启动还低。如果每开一个 shell 都
联网，那每个 tmux pane、每个 `bash -c`、每次 agent 调工具都要交这笔税，而且网络一抖
**新 shell 就打不开**。所以只有 `--refresh`、冷缓存、以及后台 `--daemon` 才联网。

缓存 12 小时过期，文件权限强制 `600`（不是 600 就拒绝加载）。

---

## 出问题了

| 现象 | 真因 / 怎么办 |
|---|---|
| `Infisical rejected it` | 大概率是粘贴被截断（脚本会打出长度，对一下 —— 应该是 36 + 64），或者这张卡已经被吊销。找 Steve 要新的一行，几秒钟的事 |
| `keys: no card at ~/.secrets/infisical.env` | 还没跑过 install.sh，或者换了机器 / 家目录被重建了。重跑上面那条命令 |
| `keys: 403 ... not a member` 读 `live` | **预期行为**。实盘凭证单独一个项目，开发机的卡不在里面 —— 这是设计，不是故障 |
| `keys: infisical CLI not installed` | `~/.local/bin` 不在 `PATH` 上。重跑 install.sh，它会补 |
| 装完当前这个 shell 里还是没有 | 开一个新 shell，或者 `. ~/.bashrc` |
| `cron` / 裸 `bash -c 'cmd'` / **`ssh box 'cmd'`** 里没有 key | **这是 bash 本身的规则，不是 bug**：这几种 shell **不读任何 rc 文件**，所以我们没有任何地方可以挂。写成 `bash -lc 'cmd'`（`ssh box 'bash -lc "cmd"'`），或者在脚本开头 `. ~/.local/share/team-keys/rc.sh`。<br>⚠️ `ssh box 'cmd'` 到底读不读 `~/.bashrc` 取决于 bash 的**编译选项**（`SSH_SOURCE_BASHRC`）：Fedora/RHEL 打了那个补丁，**Debian/Ubuntu 没有**（Ubuntu 22.04 / bash 5.1.16 实测：不读）。所以两边都别指望，一律写 `bash -lc` |
| 交互终端里有 key，但**登录 shell** / cron / CI / agent 里没有 | 2026-09-06 之前的版本有这个 bug：块被追加在 `~/.bashrc` **末尾**，而 Debian/Ubuntu 的 `.bashrc` 开头就为**非交互** shell `return` 掉了。**重跑一次 install.sh** 即可（现在块在文件顶部）|
| 用的是 zsh | 支持，装的时候会同时写 `~/.zshrc`。⚠️ 只有 `keys --status` 在 zsh 上没验过；取 key 本身是好的 |

---

## 这个仓库里为什么可以没有秘密

`keys.sh` 里写着几个项目 id。**id 是门牌号，不是钥匙** —— 它告诉你 key 放在哪个房间，
不提供任何进入的能力。没有卡，这些 id 一文不值；而每张卡都能单独吊销、单独审计。
把安装器放公开，正是为了让**权限为零的新人也能跑起来**，这是它的功能而不是它的代价。

这个仓库里**永远不会有**：任何 API key、任何 client secret、任何 `.env` 内容。
如果你发现有，那是事故 —— 请立刻说。

### CLI 版本是钉死的

`install.sh` 里 `CLI_VERSION` 写死一个版本号，**故意的**：这样不用去打 GitHub 的
API 查 latest（共享出口 IP 很容易撞上 60 次/小时的匿名限额，那会让安装在最不该失败的
时候失败）。要用别的版本：`INFISICAL_CLI_VERSION=0.43.200 bash install.sh`。

### 让 coding agent 帮你装（Claude Code / Codex / Cursor）

把下面这两行发给 agent 就行，**不需要别的提示**：

```
把我们团队的开发环境配起来，说明在这里：https://github.com/when2buy/dev-setup
TEAM_KEY=<你收到的那一行>
```

它会读这个 README、读 `install.sh`，然后跑非交互那条路。实测（一台全新机器，agent 自己
先审代码再跑，最后自己验证）**103 秒、13 轮**。

> 那行会留在 agent 的会话记录里 —— 这是可以接受的：它**是一张门卡不是 key**，而且是**可以
> 单独吊销**的一张，吊销不影响任何人。会话记录要外发（贴 issue、贴群）之前跟 Steve 说一声，
> 换一张就好。

### 非交互安装（CI、镜像构建、批量装机）

```bash
TEAM_KEY='<id>:<secret>' bash <(curl -fsSL .../install.sh)
```

⚠️ 这样写会把凭证留在 shell history 和进程列表里。批量装机请从文件读，或者用
`--card-only` 先只落卡、别拉 key。

---

## 其他开关

| | |
|---|---|
| `--profiles "paper aitist"` | 只自动加载某几组，默认 `all`（全部） |
| `--no-rc` | 不动 `~/.bashrc` / `~/.zshrc` |
| `--card-only` | 只装 CLI + 落卡，不拉 key、不改 rc |
| `-h` | 帮助 |

脚本**可以反复重跑**，每一步都是幂等的：rc 里那段用 `# >>> team-keys >>>` 标记界定，
重跑是**替换**它而不是再追加一份。
