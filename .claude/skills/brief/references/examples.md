# Examples

## Single PR (flat — TL;DR only)

```
幫看 debfactory wireguard-modules kmod rebuild

升級 wireguard-modules 到 v1.0.20241231，修復 ARM64 big-endian allowedips 問題。

PRs：
 https://github.com/ubiquiti/debfactory/pull/4821

驗證結果：CI green，在 UDM-SE + UNAS Pro 跑 wg-quick up/down 100 cycles 無 crash。
```

## Multi-PR kernel backport (flat, deep-link)

```
幫看 ENVR btrfs stable backport

把 linux-stable 5.15.y 的 234 個 btrfs patch（v5.15.72 → v5.15.210）backport 到 ENVR kernel branch ui-5.15.y-enterprise-nvr，涵蓋 crash fix、data corruption 修正、穩定性改善。

PRs：
 https://github.com/ubiquiti/debbox-kernel/pull/1571
 https://github.com/ubiquiti/debbox-kernel/pull/1572
 https://github.com/ubiquiti/debbox-kernel/pull/1573

驗證結果：在 ENVR-212-Office（cn10k, ARM64 64K-page）跑完 881 筆 xfstests A/B 測試，零 regression，backport 額外修掉 4 個原本就 fail 的 test case。
Confluence（A/B 結果 + root cause 說明）: https://ubiquiti.atlassian.net/wiki/spaces/UN/pages/5021204519/btrfs+stable+backport+A+B+results+ENVR+5.15.72-210
```

## Layered bugfix (TL;DR + Origin — negative/positive contrast)

❌ BAD — jargon wall, reviewer cannot skim:

```
幫看 UNAS Pro md/raid5 use-after-free fix

修復 raid5 plug callback use-after-free：release_stripe_plug 在 blk_check_plugged 返回後對已回收的 cb@x20 解引用 sh@x19，因為 plug->cb_list 自環 sh2@x21 觸發 release_stripe_plug 走 raid5_release_stripe→free_stripe→__free_stripe→return_io，sh@x19 的 refcount 歸零被 release_inactive_stripe_list 回收，後續 for_each_safe 繼續讀取 sh@x19->batch_head 觸發 UAF。on UNAS Pro RAID5 4-disk fio randwrite 4K 8-job 10min 無 oops。

PRs：
 https://github.com/ubiquiti/debbox-kernel/pull/1600
```

✅ GOOD — TL;DR leads with the symptom, Origin tells the story in plain labels:

```
幫看 UNAS Pro md/raid5 use-after-free fix

RAID5 在高併發寫入時 kernel oops（use-after-free），影響所有使用 md/raid5 的 NAS 產品。已用 stress + code inspection 驗證修復。

PRs：
 https://github.com/ubiquiti/debbox-kernel/pull/1600

為什麼會這樣：
高併發 4K random write 下，plug callback 釋放 stripe 後，迴圈仍讀取已回收 stripe 的 batch_head 指標。根本原因是 STRIPE_ON_UNPLUG_LIST flag 在特定路徑未清除，同一 stripe 重複入列。

怎麼修的：
在 release_stripe_plug 釋放 stripe 後立即 clear_bit(STRIPE_ON_UNPLUG_LIST)。

驗證了什麼：
① 機制：patch 後 plug callback 不再對已釋放 stripe 解引用
② 行為：fio randwrite 4K 8-job 跑 10 min，零 oops/hung_task
③ 實機：UNAS Pro RAID5 4-disk rebuild 2 TB 正常完成
④ 效能：rebuild speed 前後 ±3%

還沒把握的地方：
- 乾淨復現未達成（需特定 timing window），驗證依賴 stress + code inspection
- 僅測試 4-disk RAID5；6/8-disk 組態未覆蓋
```

## HTML attachment (design doc / postmortem)

Slack message points at the attachment; the reviewer opens the `.html` in a
browser. Message:

```
幫看 UNAS storage-tiering 設計文件

新增 SSD 快取分層，把熱資料自動搬到 NVMe。設計已對齊 storage + fw 兩組，三個 tradeoff 都收斂。

文件：
 storage-tiering-review.html （附件，瀏覽器開）

驗證結果：架構已過 storage team + fw team review，watermark 策略、回寫時機、故障降級三點對齊。
```

The `storage-tiering-review.html` file — self-contained, inline `<style>`, two
sections:

```html
<!doctype html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8">
<title>UNAS storage-tiering 設計 review</title>
<style>
  body { font: 15px/1.6 -apple-system, system-ui, sans-serif; max-width: 46rem; margin: 2rem auto; padding: 0 1rem; color: #1a1a1a; }
  section { margin-bottom: 2rem; }
  h1 { font-size: 1.1rem; color: #666; text-transform: uppercase; letter-spacing: .05em; border-bottom: 2px solid #eee; padding-bottom: .3rem; }
  .verdict { color: #0a7; font-weight: 600; }
  ol { padding-left: 1.4rem; }
</style>
</head>
<body>
  <section>
    <h1>TL;DR</h1>
    <p>新增 SSD 快取分層，把熱資料自動搬到 NVMe，冷資料留在 HDD。目標把隨機讀延遲從 ~8ms 壓到 &lt;1ms。</p>
    <p class="verdict">設計已對齊 storage + fw 兩組，三個 tradeoff 都收斂 — 可 review。</p>
  </section>
  <section>
    <h1>Origin</h1>
    <p><strong>為什麼要做：</strong>UNAS Pro 全 HDD，隨機讀延遲高，客戶回報媒體庫縮圖載入慢。</p>
    <p><strong>對齊了誰：</strong>storage team（分層策略）+ fw team（回寫時機、故障降級路徑）。</p>
    <p><strong>三個 tradeoff 怎麼收斂：</strong></p>
    <ol>
      <li>快取寫回時機 — 選 writeback + 5s flush，非 writethrough（吞吐優先，斷電風險靠 UPS 降級為 writethrough）。</li>
      <li>熱資料判定 — LRU + 存取頻率，非純 LRU（避免大順序讀污染快取）。</li>
      <li>SSD 故障降級 — 直接 bypass 到 HDD，非 rebuild（快取非持久，資料本就在 HDD）。</li>
    </ol>
  </section>
</body>
</html>
```
