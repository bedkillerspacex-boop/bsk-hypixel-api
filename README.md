# BSK Hypixel / 玩家 API

[![API](https://img.shields.io/badge/API-v1--261001-blue)](docs/api/v1-261001/README.md)
[![参数 ID](https://img.shields.io/badge/parameter_IDs-1--24-orange)](docs/api/parameter-registry.md)

本仓库维护 [BSK QQ Bot](https://github.com/bedkillerspacex-boop/bsk-qqbot) 的公开 API 文档。当前版本 **v1-261001**；历史中文兼容版 **v1-260925** 独立归档。首页只维护导航，完整契约按版本维护。

| 入口 | 内容 |
| --- | --- |
| [版本总览与迁移](docs/api/README.md) | 当前/历史版本、版本头、维护规则 |
| [当前完整契约](docs/api/v1-261001/README.md) | 鉴权、额度、限速、缓存、接口与错误 |
| [历史中文兼容契约](docs/api/v1-260925/README.md) | 当前服务提供的旧语言/结构行为 |
| [历史原文快照](docs/api/v1-260925/REFERENCE.md) | 原文保留，不作为当前计费依据 |
| [永久参数注册表](docs/api/parameter-registry.md) | 24 个服务端参数 ID，不重新编号、不复用 |
| [核对记录和已知缺口](docs/api/verification.md) | 实现证据、检查范围、尚未实现的承诺 |
| [检查工具](tools/README.md) | 链接、JSON、离线实现对照与无凭据探测 |
| [拦截器](interceptor/README.md) | 既有客户端接入工具 |
| [客户端示例](examples/) | curl、Python、JavaScript |
| [AI 文档索引](llms.txt) | 精简导航 |

## 快速开始

通过机器人 `/apikey help` 查看邮箱验证、申请与发放步骤。Bugland 使用独立 `/bjdkey` 流程和 `bsk_bjd_` Key。示例只使用占位凭据。

```bash
curl -H 'X-API-Key: <YOUR_BSK_KEY>' \
  'https://api.firebounce.today/api/denick/v1-261001?nick=ExampleNick'

curl -H 'X-API-Key: <YOUR_BSK_KEY>' \
  'https://api.firebounce.today/api/bancheck/v1-261001?uuid=00000000000000000000000000000001'

curl -H 'X-API-Key: <YOUR_BSK_KEY>' \
  'https://hyp-api.firebounce.today/v2/player?uuid=00000000000000000000000000000001'
```

`GET /api` 免费提供端点清单和参数定义。无版本与 `/v1` 指向当前版；固定结构请使用日期版本。

## 公开接口

| 接口 | 方法 | 基础额度 | 文档 |
| --- | --- | ---: | --- |
| `/api/denick` | GET / POST | 1 | [昵称解析](docs/api/v1-261001/endpoints/denick.md) |
| `/api/player` | GET / POST | 1.5 | [玩家资料](docs/api/v1-261001/endpoints/player.md) |
| `/api/player/card` | GET / POST | 1.5 | [卡片 JSON](docs/api/v1-261001/endpoints/player-card.md) |
| `/api/tags` | GET / POST | 1.5 | [标签](docs/api/v1-261001/endpoints/tags.md) |
| `/api/search` | GET / POST | 1 | [搜索](docs/api/v1-261001/endpoints/search.md) |
| `/api/recent` | GET / POST | 1 | [增量记录](docs/api/v1-261001/endpoints/recent.md) |
| `/api/nick-history` | GET / POST | 1 | [昵称历史](docs/api/v1-261001/endpoints/nick-history.md) |
| `/api/bancheck`、`/api/checkban` | GET / POST | UUID 0.7 / name 1.0 | [封禁索引](docs/api/v1-261001/endpoints/bancheck.md) |
| `/api/quota` | GET / POST | 0 | [额度状态](docs/api/v1-261001/endpoints/quota.md) |
| `/v2/*`、`/api/hypixel/*` | GET | 1 | [Hypixel 反代](docs/api/v1-261001/endpoints/hypixel-proxy.md) |
| `/bjd/v2/*` | GET / POST | 1 | [Bugland 反代](docs/api/v1-261001/endpoints/bugland-proxy.md) |
| `/api/card.png` | GET / POST | 0 | 已下线，返回 410 |
| `/api`、裸 `/api/hypixel` | 见完整契约 | 0 | 发现/使用说明 |

旧 `/denick/api` 调用同一查询函数，但无新版信封/版本头。POST 别名支持有差异，见[注册表缺口](docs/api/parameter-registry.md#已知缺口)。内部管理端点不属于公开目录。

## 接入注意

- Hypixel 单 Key 最多 **12 秒**、最多 3 把不同 Key、上游尝试总预算 **30 秒**；HTTP 200 非空成功响应固定缓存 **300 秒**，最多 512 条。
- Hypixel 成功写回后收完整基础额度及体积费；失败收基础额度 50%。鉴权/配额拒绝未预留时不计费；全局反代闸门拒绝已有预留时收半价。
- 全局反代闸门默认 **600/分钟**，管理员用 `/apikey rate proxy` 修改；`0` 不限，`off` 恢复环境默认。每 Key、并发和 Bugland 限额分别管理。
- `X-Quota-Cost` 通常是响应体积理论档位 **1/7/15**，不是实际账单；实时水位读 `/api/quota`。
- bancheck 查 tracking/hyp_dc **本地索引**，不是官方实时验证。无记录为 `state: unknown`，不能保证未封禁；按 UUID 跨改名追踪更可靠。
- 英文版有 `api_version`、`locale`、`schema` 信封，但少量错误/地区数组仍可能含中文；第三方名字/备注保留原文，详见完整契约。
- 两套反代保持上游状态码和原始响应体，只透传白名单响应头，不套用卡片翻译。

## 实现基线与维护

对齐服务 main：[`75ec6037a5cd6f6e59bfde10bf8fb03a74c4d7a9`](https://github.com/bedkillerspacex-boop/bsk-qqbot/commit/75ec6037a5cd6f6e59bfde10bf8fb03a74c4d7a9)；线上发布 `20261002064434-4520d9e5dc`，2026-10-02 核对。文档起始基线 `68ea291`，历史原文快照保持不变。

```text
python -B tools/check_docs.py
python -m pip install -r tools/requirements.txt
python -B tools/check_contract.py --implementation ../bsk-qqbot
python -B tools/probe_public_api.py
```

最后一项仅验证免费发现/无凭据错误路径，不验证真实 Key 成功请求，不消耗生产额度。仓库没有网站构建项目；Markdown、JSON 和离线契约检查不等于生产端到端验证。

服务改路由、参数、响应、计费、限速或缓存时，必须同时更新相应版本文档、示例与基线。参数 ID 只追加；历史原文快照永久保留。源码与文档矛盾时以路由、响应生成代码、计费和契约测试为准。
