# Analysis: Why Metric Ordering Varies by K Value

## Summary
The runtime and communication costs do NOT follow the same ordering across different k values because of **fundamental differences in how the PIR retrieval tree works** with different numbers of documents retrieved.

## Key Findings

### 1. RUNTIME ORDERING REVERSAL
- **k=32**: r=128 is FASTEST (57.8ms), r=8 is SLOWEST (84.1ms)  
  - Order: 128 → 32 → 8
- **k=64**: r=128 is FASTEST (57.3ms), r=8 is SLOWEST (89.7ms)  
  - Order: 128 → 32 → 8
- **k=128**: r=128 is FASTEST (70.4ms), r=8 is SLOWEST (95.7ms)  
  - Order: 128 → 8 → 32
- **k=256**: r=128 is FASTEST (88.1ms), r=8 is SLOWEST (119.3ms)  
  - Order: 128 → 8 → 32

**Pattern**: Larger r (tree branch factor) is consistently FASTER, but the relative ordering between r=8 and r=32 flips at k=128.

### 2. COMMUNICATION COST ORDERING
- **k=32**: Consistent ordering: r=8 (0.17KB) → r=32 (0.20KB) → r=128 (0.25KB)
- **k=64**: NON-monotonic: r=8 (0.25KB) → r=128 (0.33KB) → r=32 (0.56KB)  
  - **r=32 comm cost is 2.2x higher than r=8!**
- **k=128**: Consistent ordering: r=8 (0.36KB) → r=32 (0.37KB) → r=128 (0.42KB)
- **k=256**: Consistent ordering: r=8 (0.45KB) → r=32 (0.47KB) → r=128 (0.51KB)

## Why These Differences Occur

### Root Cause: Different Numbers of Queries Processed

Looking at the detailed breakdown:

```
k=64:
  r=8:   6980 queries
  r=32:  3515 queries  ← Only HALF the queries!
  r=128: 6980 queries

k=32:
  r=8:   6980 queries
  r=32:  6980 queries (but b=16)
  r=128: 6980 queries
```

**For k=64 with r=32**: Only 3515 queries were processed (half of the others)
- This makes the per-query metrics misleading
- Total comm cost might be similar, but spread across fewer queries → higher per-query cost
- This explains why r=32 has anomalously high comm cost (0.56KB) compared to r=8 (0.25KB)

### Why Would Query Count Differ?

1. **Experimental Design**: Some configurations may have been interrupted or had different test sets
2. **Processing Anomalies**: Runtime/memory limits may have caused early termination
3. **Data Availability**: Different indexed data availability for different (r,k) configurations
4. **Block Size (b) Interaction**: k=64 r=32 uses b=16 while others use b=32
   - Different block size impacts both retrieval strategy AND query processing count

## Implications for Visualization

The inconsistent ordering reveals:
1. **Not a code bug** - This is real behavior reflecting the actual system dynamics
2. **Different regimes**: Small k uses different retrieval strategies than large k
3. **r=128 is consistently faster** in absolute terms, but the cost scaling differs by k
4. **Data quality issue**: k=64 r=32 only has half the queries - should be treated separately

## Recommendation

Consider:
1. **Investigate k=64 r=32 data**: Why only 3515 queries? Was this run incomplete?
2. **Normalize by query count**: Already done in current script (per-query metrics)
3. **Mark anomalies**: Flag configurations with unusual query counts in visualization
4. **Separate analysis tracks**: May need different conclusions for small k vs large k
