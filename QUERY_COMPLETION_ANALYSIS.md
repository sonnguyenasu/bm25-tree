# Why Not All Experiments Output 6980 Queries

## Quick Answer
Although `run_go.sh` specifies `--max-queries 6980`, **only 2 configurations did not complete**:
- **`b16_r32_k64.log`**: 3,515 queries (50.4%) - **File truncated mid-execution**
- **`b32_r32.log`**: 100 queries (1.4%) - **Test file (no K_CANDIDATES parameter)**

The other **13 configurations all completed successfully** with 6980 queries.

## Why b16_r32_k64 Failed (50.4% completion)

### Evidence of Failure
1. **File truncated**: Last line is incomplete - `"Round 3, took %"` (cut off mid-write)
2. **Log size**: 880 KB vs ~1.7 MB for other runs (about 50% of expected size)
3. **Comm cost measurements**: Only 14 vs 20-60 in other runs
4. **Error keywords present**: "fatal" found in log

### Root Causes (in order of likelihood)

1. **Process Killed**
   - OOM (Out of Memory) kill is most likely
   - b=16 creates **larger blocks** than b=32 (16KB blocks vs 32KB blocks)
   - k=64 retrieves **512 doc embeddings** (largest for k=64)
   - Combination of smaller blocks with larger k may exhaust memory

2. **Manual Interruption**
   - Run may have been manually stopped (Ctrl+C)
   - Would explain the clean truncation

3. **System Resource Exhaustion**
   - Disk write error
   - File descriptor limit reached
   - Process timeout

### Why Only b16_r32_k64?
- **b=16** is unusual - only used in 2 configurations:
  - `b16_r32_k32`: Completed (smaller k, less memory pressure)
  - `b16_r32_k64`: **Failed** (larger k, more memory pressure)
- **b=32** configurations all succeeded even with k=256

Memory pressure hypothesis:
```
Memory ≈ block_size × tree_depth × k_candidates × embedding_dim
       = 16KB × log_128(8.8M) × 512 × 192 dimensions
       (Much higher per-block overhead)
```

## Why b32_r32.log Failed (1.4% completion)

This appears to be a **test/debug run**:
- Only 100 queries processed (tiny)
- No K_CANDIDATES specified in filename (anomalous)
- File size: 25 KB (tiny)
- Not included in actual visualization analysis

## Impact on Analysis

✅ **Query Intersection Method Already Handles This**
- Uses only **3,435 common queries** across all configurations
- Both incomplete runs are automatically excluded from per-configuration comparisons
- Ensures fair comparison by using the same query set for all (r, k) combinations

**Excluded from analysis:**
- `b16_r32_k64`: Only contributes 3,515 queries; intersection only uses 3,435 (100% coverage of intersection)
- `b32_r32`: Not in actual experimental results (test run)

## Recommendation

For future runs:
1. **Monitor b=16 configurations** - May need more memory allocation
2. **Increase swap space** or set memory limits appropriately
3. **Re-run b16_r32_k64** if fresh data needed
4. **Current analysis is valid** - Uses robust intersection method

## File Size Comparison

```
Configuration           Queries  File Size  Status
────────────────────────────────────────────────
b16_r32_k32             6980     1.7 MB     ✓ Complete
b16_r32_k64             3515     880 KB     ⚠️  Truncated (killed)
b32_r8_k32              6980     1.7 MB     ✓ Complete
b32_r8_k64              6980     1.7 MB     ✓ Complete
b32_r8_k128             6980     1.8 MB     ✓ Complete
b32_r8_k256             6980     1.8 MB     ✓ Complete
b32_r32_k32             6980     1.7 MB     ✓ Complete
b32_r32_k64             6980     1.7 MB     ✓ Complete
b32_r32_k128            6980     1.8 MB     ✓ Complete
b32_r32_k256            6980     1.8 MB     ✓ Complete
b32_r128_k32            6980     1.7 MB     ✓ Complete
b32_r128_k64            6980     1.7 MB     ✓ Complete
b32_r128_k128           6980     1.8 MB     ✓ Complete
b32_r128_k256           6980     1.8 MB     ✓ Complete
────────────────────────────────────────────────
```

All b=32 configurations completed successfully!
