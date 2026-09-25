/**
 * BSK denick 查询 API —— Node.js 客户端示例（需要 Node 18+，原生 fetch）
 *
 * 用法:
 *   export BSK_KEY="bsk_你的key"
 *   node denick_client.js theoshadow
 *   node denick_client.js --uuid 694cd52b-8197-45f0-b28d-ad73eb299699
 *   node denick_client.js --batch a b c
 *   node denick_client.js --json theoshadow      # 打印原始 JSON
 *
 * 文档: https://github.com/bedkillerspacex-boop/bsk-hypixel-api
 * 申请 Key: 在 QQ 群里发  /apikey 你的QQ号  (机器人发不出私聊, Key 走你的 QQ 邮箱)
 */

const API = "https://api.firebounce.today/api/denick";
const KEY = process.env.BSK_KEY || "";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * 查一个昵称 / UUID。
 *
 * 成功返回（完整字段见文档）:
 *   {
 *     nick, ign, uuid, seen_at, seen_ts, first_seen, first_ts,
 *     names,        // 同一个 UUID 用过的**所有**正版 ID（改过名就 >1 个）
 *     nicks,        // 同一个 UUID 用过的**所有**昵称（新的在前）
 *     nick_count
 *   }
 *
 * ⚠️ UUID 不会变、正版 ID 会变 —— 长期跟踪请存 uuid。
 * 查不到抛错（err.code === "not_found"）；429 自动退避重试。
 * Key 走请求头，不放进 URL（否则会进访问日志）。
 */
export async function denick({ nick, uuid, key = KEY, retries = 2 } = {}) {
  if (!key) throw Object.assign(new Error("环境变量 BSK_KEY 没设置"), { code: "no_key" });
  if (!nick && !uuid) throw Object.assign(new Error("要传 nick 或 uuid"), { code: "missing_param" });

  const qs = new URLSearchParams(nick ? { nick } : { uuid });
  let wait = 1000;

  for (let attempt = 0; attempt <= retries; attempt++) {
    const r = await fetch(`${API}?${qs}`, {
      headers: { Authorization: `Bearer ${key}`, Accept: "application/json" },
    });
    const d = await r.json().catch(() => ({}));
    if (r.ok && d.ok) return d.data;
    if (r.status === 429 && attempt < retries) {
      await sleep(wait);
      wait *= 2;
      continue;
    }
    throw Object.assign(new Error(d.message || `HTTP ${r.status}`), {
      code: d.error || `http_${r.status}`,
      status: r.status,
    });
  }
}

/** 长期跟踪: 存 uuid 而不是存 ign, 他改名了你也跟得住 */
export async function trackPlayer(uuid, opts = {}) {
  const d = await denick({ uuid, ...opts });
  return {
    uuid: d.uuid,
    currentName: d.ign,
    allNames: d.names || [],
    nicks: d.nicks || [],
  };
}

// ---- CLI ----
const isMain = process.argv[1]?.endsWith("denick_client.js");
if (isMain) {
  let args = process.argv.slice(2);
  const asJson = args.includes("--json");
  args = args.filter((a) => a !== "--json");
  if (!args.length) {
    console.log("用法: node denick_client.js <昵称> | --uuid <UUID> | --batch a b c | --json <昵称>");
    process.exit(1);
  }
  let targets;
  if (args[0] === "--uuid") targets = [{ uuid: args[1] }];
  else if (args[0] === "--batch") targets = args.slice(1).map((n) => ({ nick: n }));
  else targets = args.map((n) => ({ nick: n }));

  let rc = 0;
  for (const t of targets) {
    try {
      const d = await denick(t);
      if (asJson) {
        console.log(JSON.stringify(d, null, 2));
        continue;
      }
      console.log(
        `${(d.nick || t.uuid).padEnd(18)} -> ${String(d.ign).padEnd(18)} ${d.uuid || "-"}   (${d.seen_at || "-"})`
      );
      if ((d.names || []).length > 1) {
        console.log(`${"".padEnd(18)}    ⚠️ 这个 UUID 用过 ${d.names.length} 个名字: ${d.names.join(", ")}`);
      }
      if ((d.nicks || []).length) {
        const show = d.nicks.slice(0, 5).join(", ") + (d.nicks.length > 5 ? " …" : "");
        console.log(`${"".padEnd(18)}    昵称 ${d.nicks.length} 个: ${show}`);
      }
    } catch (e) {
      rc = 1;
      console.error(`${(t.nick || t.uuid).padEnd(18)} -> ❌ ${e.code}: ${e.message}`);
    }
  }
  process.exit(rc);
}
