# TieredVol — Windows 報告 Agent

> 在 Windows 的 tieredvol-thesis 目錄啟動 opencode，把 prompt 貼進去
> 前提：B85 已經跑完 benchmark 並 push，這邊已經 pull TieredVol 最新數據

---

## Prompt — 完整貼入 opencode

```
幫我完成以下 3 項任務。先從 TieredVol/BENCHMARK-RESULTS.md 讀取 benchmark 數據。

=== #6：Pandoc HTML Build 測試 ===

1. 確認 Pandoc 是否安裝：pandoc --version
2. 如果沒安裝，跳過此項並報告
3. 如果有安裝，在 tieredvol-thesis 目錄執行：
   pandoc thesis.md -o test_output.html --toc --toc-depth 2 --standalone
4. 檢查 test_output.html：
   - 是否只有一份 TOC（不該有手寫 + Pandoc 自動生成的兩份）
   - Chapter 5 是否有 Generality（§5.5）和 Lessons Learned（§5.7）sections
   - Appendix C (Glossary) 和 D (References) 是否在 TOC 裡出現
   - 有無 broken links（搜尋 href="#..." 但找不到對應 id 的）
5. 刪除 test_output.html
6. 回報檢查結果

=== #3：SPA Content 同步 ===

1. diff 比對以下檔案對，確認差異：
   - chapters/05-discussion.md vs spa/src/content/en/chapters/05-discussion.md
   - zh/chapters/05-discussion.md vs spa/src/content/cn/chapters/05-discussion.md
   - appendices/C-glossary.md vs spa/src/content/en/appendices/C-glossary.md
   - appendices/D-references.md vs spa/src/content/en/appendices/D-references.md
   - zh/appendices/C-glossary.md vs spa/src/content/cn/appendices/C-glossary.md
   - zh/appendices/D-references.md vs spa/src/content/cn/appendices/D-references.md

2. 如果有差異，用 chapters/ 或 zh/ 的最新版本覆蓋到 spa/src/content/ 對應位置

3. 回報哪些檔案有更新、哪些已經同步

=== #7：Quantization Error Sensitivity Analysis ===

1. 先讀取 chapters/05-discussion.md 的 §5.1 Quantization Error 段落

2. 在 §5.1 現有內容之後、§5.2 之前，新增一小段：

   ### Chunk Size Sensitivity

   The choice of chunk size affects stripe granularity but has minimal impact on
   quantization accuracy, as the error is bounded by integer weight assignment.

   | Chunk Size | Stripe Size (2-disk [2,1]) | Error (2-disk) | Stripe Size (3-disk [2,1,1]) | Error (3-disk) |
   |-----------|--------------------------|----------------|-----------------------------|----------------|
   | 256 KB | 768 KB | 10.0% | 1 MB | 12.5% |
   | 512 KB | 1.5 MB | 10.0% | 2 MB | 12.5% |
   | 1 MB | 3 MB | 10.0% | 4 MB | 12.5% |
   | 2 MB | 6 MB | 10.0% | 8 MB | 12.5% |

   計算說明（用 BENCHMARK-RESULTS.md 裡的碟速度）：
   - true_ratio = NVMe_speed / SATA_speed
   - assigned_weight = round(true_ratio)
   - error = |true_ratio - assigned_weight| / true_ratio
   - 2-disk weights = [2, 1]
   - 3-disk weights = [2, 1, 1]

   **注意：請先從 BENCHMARK-RESULTS.md 讀取實際的碟速度，用實際數據計算，不要用上面的假設值。上面的 10.0% 和 12.5% 是 placeholder，請替換為真實計算結果。**

3. 在表格之後加一句：
   "Smaller chunk sizes reduce stripe granularity but do not significantly improve
   quantization accuracy, as the error is bounded by the integer weight assignment
   rather than the chunk size. A 1 MB chunk provides a practical balance between
   I/O granularity and memory overhead."

4. 同步更新 thesis_zh.md 的 §5.1 對應段落（中文翻譯）

=== 完成後 ===

回報三項的完成狀態：
#6 Pandoc: PASS/FAIL（附原因）
#3 SPA: X 個檔案已更新
#7 Quantization: 表格已加入 + thesis_zh 已同步
```

---

## 注意事項

- 確認已從 TieredVol pull 最新數據再開始
- #7 的表格數值必須用 BENCHMARK-RESULTS.md 的實際碟速度計算
- 如果 Pandoc 沒裝就跳過 #6，不影響其他項
- SPA 同步是 copy 操作，不會丟資料
- 所有改動完成後在 tieredvol-thesis 目錄 git commit + push
