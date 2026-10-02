# 文档检查工具

两个小工具，用来防止文档再次过时。都是**只读**的，不改任何东西。

## `check_docs.py` —— 静态检查

```bash
python -B tools/check_docs.py
```

检查全仓库的 Markdown：

| 检查项 | 说明 |
|---|---|
| **相对链接** | 链接指向的文件必须存在 |
| **锚点** | `#标题` 必须在目标文件里真的有一个对应标题（按 GitHub 的 slug 规则，支持中文） |
| **JSON 示例** | 标为 ` ```json ` 的代码块必须是**合法 JSON**（可以照抄运行） |

约定：

- 标为 ` ```jsonc ` 的代码块是**故意省略的节选**（含 `...` / `[...]`）或配置片段，
  **不做严格校验** —— 这样读者也知道它不能直接复制。
- `docs/api/v1-260925/REFERENCE.md` 是**逐字保留的历史快照**，豁免检查，
  **永不规范化**。改它等于破坏"老接入方可以照着适配"的承诺。

退出码非 0 表示有失败项，可直接接进 CI。

## `probe_public_api.py` —— 线上只读探测

```bash
python -B tools/probe_public_api.py
python -B tools/probe_public_api.py --base http://127.0.0.1:18096
```

**不带任何凭据**，只打**预期会失败**的路径，所以**不消耗额度**
（唯一的例外 `GET /api` 本身免费）。它核对的是错误处理与发现文档：

- 未知版本 → `404 unknown_version`，且**不带** `X-API-Version`
- `/api/card.png` → `410 gone`（不是 `404`）
- `/api/bancheck` 缺参 → `400 missing_param`（**参数校验先于鉴权**）
- `/api/denick`、`/api/search`、`/api/nick-history`、`/api/player` 无 Key → `401 missing_key`
  （**先鉴权**，与 bancheck 相反）
- `/api/quota` 的任何响应 `X-Quota-Cost` 必须是 `0`

传输层抖动（TLS 中断、连接重置）会**有界重试**，不会误报成文档错误；
HTTP 状态码**不重试**（那正是要探测的答案）。

> ⚠️ **它只覆盖错误路径。** 正常路径需要真实 Key，**不在范围内** ——
> "探测全过"**不等于**"生产接口全部验证通过"，尤其是扣费金额。
