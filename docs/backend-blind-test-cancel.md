# 后端需求：盲测「取消」接口

> 交给后端实现。客户端（HarmonyOS / Web）需要「取消进行中的盲测」能力：
> 用户点了取消后，这轮盲测作废、不再出现在「进行中」和周报里，下次开始盲测是全新的一轮。
>
> 现状：`GET/POST /api/blind-tests`、`POST /api/blind-tests/:id/finish` 已有；
> **没有任何取消/删除路由**。线上探测 `DELETE /api/blind-tests/:id`、
> `POST /api/blind-tests/:id/cancel`、`POST /api/blind-tests/:id/abandon` 全部 404；
> `POST /:id/finish` 在 0 条已提交时返回 409 `no_attempts`，无法用来取消。

## 1. 目标 / 非目标

**目标**

1. 新增 `DELETE /api/blind-tests/:id`：把**自己**的一轮盲测标记为「已取消」。
2. 取消后：
   - `GET /api/blind-tests` 的 `in_progress` 不再返回这一批（返回 `null`）；
   - `POST /api/blind-tests`（开始盲测）**不会恢复**已取消批次，而是创建新批次；
   - 周报/趋势/`series` 不包含已取消批次；
   - `POST /api/blind-tests/:id/finish` 对已取消批次返回 409。
3. 幂等：重复取消同一批次返回 200。
4. 权限：只能取消自己的批次；别人的批次一律 404（不泄露存在性）；儿童可以取消自己的。

**非目标**

- 不做「取消后恢复」。
- 不删除用户已经产生的 attempts 记录（保留审计；盲测 attempts 本来就不参与音素/趋势/SRS）。
- 不改 Web 前端（本次只要求后端接口；Web 可后续接入同一个 DELETE）。

## 2. 数据模型改动（推荐：软取消）

不建议物理删除 `blind_tests` 行：`attempts.blind_test_id` 仍引用它，硬删会让历史 attempts 变孤儿，
也无法区分「取消」和「数据丢失」。

### 2.1 schema

`web/src/db/schema.ts` → `blindTests` 增加一列：

```ts
export const blindTests = sqliteTable(
  "blind_tests",
  {
    id: text("id").primaryKey(),
    userId: text("user_id").notNull(),
    startedAt: text("started_at").notNull(),
    /** NULL = 进行中；进行中不得对外暴露任何分数（契约 §13.3） */
    endedAt: text("ended_at"),
    /** 新增：非 NULL = 已取消（用户主动放弃）；取消后不计入周报/趋势 */
    cancelledAt: text("cancelled_at"),
    itemCount: integer("item_count").notNull().default(0),
    avgPron: real("avg_pron"),
    avgAccuracy: real("avg_accuracy"),
    avgFluency: real("avg_fluency"),
    avgIntonationDistance: real("avg_intonation_distance"),
    sentenceIdsJson: text("sentence_ids_json").notNull().default("[]"),
    createdAt: text("created_at").notNull(),
  },
  (t) => [index("idx_blind_tests_user").on(t.userId, t.startedAt)],
);
```

### 2.2 migration（SQLite）

```sql
ALTER TABLE blind_tests ADD COLUMN cancelled_at TEXT;
```

按项目现有 Drizzle migration 流程生成（`drizzle-kit generate` + migrate），不要手改生产库。
旧数据 `cancelled_at = NULL`，语义不变。

### 2.3 状态机（三态，互斥）

| 状态 | 判定 | in_progress | 可 finish | 可提交 attempt |
| --- | --- | --- | --- | --- |
| 进行中 | `ended_at IS NULL AND cancelled_at IS NULL` | ✅ | ✅ | ✅ |
| 已完成 | `ended_at IS NOT NULL AND cancelled_at IS NULL` | ❌ | 幂等返回报告 | ❌ |
| 已取消 | `cancelled_at IS NOT NULL` | ❌ | ❌ 409 | ❌ 409 |

> `ended_at` 和 `cancelled_at` 不应同时有值；取消只允许发生在「进行中」。

## 3. API 契约

### 3.1 `DELETE /api/blind-tests/:id`

**鉴权**：现有 cookie/session（`requireUser`）。

**请求**：无 body。

**成功 200**

```json
{
  "cancelled": true,
  "blind_test_id": "bt_xxx",
  "cancelled_at": "2026-11-07T00:00:00.000Z"
}
```

**错误**

| HTTP | code | 场景 |
| --- | --- | --- |
| 401 | `unauthorized` | 未登录（沿用现有鉴权中间件） |
| 404 | `not_found` | 批次不存在，或不属于当前用户（不泄露存在性） |
| 409 | `already_finished` | 批次已结束（`ended_at` 非空）→ 不能取消 |
| 409 | `blind_cancelled` | （可选）已取消再取消：推荐直接 200 幂等；若返回 409 需与客户端约定 |

**幂等**：已取消再次 DELETE → 200，返回同一 `cancelled_at`。

### 3.2 现有接口的行为调整

| 接口 | 调整 |
| --- | --- |
| `GET /api/blind-tests` | `in_progress` 只认「进行中」三态；`tests` 默认**排除** `cancelled_at` 非空的行（周报列表不显示取消的批次）；`trend/series` 也排除 |
| `POST /api/blind-tests` | 「有进行中批次就恢复」的条件改为 `ended_at IS NULL AND cancelled_at IS NULL`；已取消的批次不能被恢复 |
| `POST /api/blind-tests/:id/finish` | 先查三态：已取消 → 409 `blind_cancelled`；已完成 → 保持现有幂等行为 |
| `POST /api/attempts`（带 `blind_test_id`） | 通过 `requireOpenBlindTest` 校验：已取消 → 409 `blind_cancelled`，已结束 → 409 `blind_ended`（沿用/补齐现有错误码） |

### 3.3 参考实现（`web/src/lib/blind-test.ts`）

```ts
/** 进行中判定：三态互斥 */
function isInProgress(row: BlindTestRow): boolean {
  return !row.endedAt && !row.cancelledAt;
}

export async function cancelBlindTest(user: SessionUser, blindTestId: string) {
  const db = getDb();
  const [row] = await db
    .select()
    .from(blindTests)
    .where(eq(blindTests.id, blindTestId))
    .limit(1);

  // 不存在 / 不是自己的 → 一律 404，不泄露存在性
  if (!row || row.userId !== user.id) {
    throw new HttpError(404, "not_found", "盲测批次不存在");
  }
  if (row.endedAt) {
    throw new HttpError(409, "already_finished", "这轮盲测已经结束，不能取消");
  }
  if (row.cancelledAt) {
    // 幂等
    return { cancelled: true, blind_test_id: row.id, cancelled_at: row.cancelledAt };
  }
  const cancelledAt = new Date().toISOString();
  await db
    .update(blindTests)
    .set({ cancelledAt })
    .where(eq(blindTests.id, blindTestId));
  return { cancelled: true, blind_test_id: row.id, cancelled_at: cancelledAt };
}
```

路由（`web/src/app/api/blind-tests/[id]/route.ts`，当前只有 GET）：

```ts
export const DELETE = route(async (_req: NextRequest, ctx: { params: Promise<{ id: string }> }) => {
  await ensureBootstrap();
  const user = await requireUser();
  const { id } = await ctx.params;
  return jsonOk(await cancelBlindTest(user, id));
});
```

> 事务/并发：取消与 finish 同时发生时，以先写入者为准；建议 `UPDATE ... WHERE id=? AND ended_at IS NULL AND cancelled_at IS NULL`，
> 若 `changes === 0` 再读一次判断是三态中的哪一种并返回对应错误/幂等结果。

## 4. 统计口径（必须明确）

- 已取消批次**不进入**：周报 `tests`、趋势 `trend/series`、`in_progress`、任何平均分。
- 已取消批次里已经提交的 attempts（`is_blind = 1`、`blind_test_id = 该批次`）：
  - 保留在 `attempts` 表（不删录音/文本）；
  - 不计入任何盲测平均分（因为该批次不再参与 `computeBlindAverages` 的调用路径）；
  - 不参与跟读/音素/SRS（现有 `is_blind` 规则已保证）。
- 取消后重新开始盲测：`POST /blind-tests` 生成**新的** `blind_test_id`，`sentence_ids` 按现有抽题逻辑重新抽。

## 5. 权限与安全

- 只能取消自己的批次；他人批次 404。
- 儿童可以取消自己的盲测（与「结束」一致，属于本人操作）。
- 家长不能取消孩子的批次（当前无此需求；如需，另开接口并记录审计）。
- 日志不打印完整 `sentence_ids` 等无关数据；可打印 `{ userId, blindTestId, cancelledAt }` 用于审计。

## 6. 验收用例（curl / 集成测试）

准备：`COOKIE` 为登录后 cookie；`BT` 为进行中批次 id。

1. **取消成功**
   ```bash
   curl -i -X DELETE -b "$COOKIE" https://<host>/api/blind-tests/$BT
   # 200 {"cancelled":true,"blind_test_id":"...","cancelled_at":"..."}
   ```
2. **列表不再进行中**
   ```bash
   curl -s -b "$COOKIE" https://<host>/api/blind-tests
   # in_progress: null；tests 中不包含 $BT
   ```
3. **重复取消幂等**：再次 DELETE → 200，`cancelled_at` 不变。
4. **开始新批次不恢复旧的**：`POST /api/blind-tests` → 返回新的 `blind_test_id` ≠ `$BT`，`resumed=false`。
5. **取消已结束批次**：先 finish 一个批次，再 DELETE → 409 `already_finished`。
6. **取消他人批次**：用另一个账号 DELETE → 404 `not_found`。
7. **取消后提交 attempt**：`POST /api/attempts` 带 `blind_test_id=$BT` → 409 `blind_cancelled`（或现有等价错误码）。
8. **取消后 finish**：`POST /api/blind-tests/$BT/finish` → 409 `blind_cancelled`。
9. **DB 断言**：`SELECT cancelled_at FROM blind_tests WHERE id=$BT` 非空；`attempts` 行仍在。
10. **回归**：正常 finish 的周报平均分/`notice`/`scored/pending` 不受影响。

## 7. 客户端对接（已就绪）

HarmonyOS 客户端已经实现 UI 与调用（commit `b8724b5`）：

- 盲测周报「进行中」卡片：**取消这轮盲测**（二次确认）
- 「退出盲测，回普通跟读」：先尝试取消再退出
- 调用顺序（任一成功即可）：
  1. `DELETE /api/blind-tests/:id`
  2. `POST /api/blind-tests/:id/cancel`
  3. `POST /api/blind-tests/:id/abandon`

**因此只要后端发布 `DELETE /api/blind-tests/:id`，客户端无需再改即可生效。**
如果最终采用别的路径/方法，请同步本文件与客户端。

## 8. 文档同步

实现后请更新：

- `docs/screens-matrix.md` 盲测行（接口列表加 `DELETE /api/blind-tests/:id`）
- `docs/feature-index.md` 盲测行
- `docs/api-contract`（若有）与 release-notes
