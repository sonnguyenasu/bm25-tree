# Results Visualization Script

## Overview
The `visualize_results.py` script analyzes and visualizes performance metrics from Go-based retrieval experiments across different parameter configurations.

## What It Does

### 1. **Data Collection**
- Parses all `run_go_b*.log` files from the workspace
- Extracts parameters (b, r, k) from filenames
- Collects three key metrics per experiment:
  - **MRR@10**: Mean Reciprocal Rank at position 10
  - **Runtime**: Total execution time in milliseconds (sum of all 3 rounds)
  - **Communication Cost**: Data transfer cost in KB (PIR preprocessing overhead)

### 2. **Data Organization**
- Groups results by (r, k) pairs, averaging across different b values
- Relates k to doc embedding retrieved: `doc_embeddings = k * 8`
- Creates clean mappings for visualization

### 3. **Visualizations Generated**

#### File 1: `results_visualization.png` (Line Plots)
Three synchronized plots showing metrics vs PIR tree branch factor (r):
- **Left**: MRR@10 vs r - Shows quality trends
- **Middle**: Runtime vs r - Shows latency trends  
- **Right**: Communication Cost vs r - Shows bandwidth overhead
- Each line represents a different k value (256, 512, 1024, 2048 doc embeddings)

#### File 2: `results_heatmap.png` (Heatmaps)
Three heatmaps with r on x-axis and k on y-axis:
- **Left**: MRR@10 heatmap - Darker = higher quality
- **Middle**: Runtime heatmap - Darker = faster execution
- **Right**: Communication Cost heatmap - Darker = lower overhead
- Useful for identifying sweet spots in the parameter space

#### File 3: `results_tradeoff.png` (Trade-off Analysis)
Two scatter plots with annotations:
- **Left**: MRR vs Runtime - Shows quality/latency trade-off
- **Right**: Comm Cost vs Runtime - Shows bandwidth/latency trade-off
- Each point labeled with its r value
- Different colors for different k values (256, 512, 1024, 2048 doc embeddings)

## Parameter Meanings

- **r** (PIR Tree Branch Factor): Branch factor for the tree structure in PIR retrieval
  - Values: 8, 32, 128
  - Larger r → wider tree branches, affects retrieval strategy

- **k** (Scaling Factor): Multiplicative factor for doc embeddings retrieved
  - Values: 32, 64, 128, 256
  - Actual doc embeddings retrieved = k × 8 = [256, 512, 1024, 2048]
  - Larger k → more embeddings to rerank, better accuracy but higher cost

- **b** (Block Size): Block size parameter (fixed at 32 for most runs, also 16)
  - Values: 16, 32

## Key Insights to Extract

1. **Accuracy (MRR)**: Generally improves with higher r and k values
2. **Latency (Runtime)**: Trade-off - larger r/k increases both accuracy and runtime
3. **Communication**: Scales with k (more embeddings to retrieve)
4. **Sweet Spot**: Look for good MRR with reasonable runtime/communication trade-off

## Usage

```bash
python3 visualize_results.py
```

The script will automatically:
1. Find all log files in the workspace
2. Parse metrics from each log file
3. Generate three PNG visualization files
4. Print a summary to console

## Output Files

- `results_visualization.png` - 201 KB - Line plots for trend analysis
- `results_heatmap.png` - 115 KB - Heatmaps for parameter space overview
- `results_tradeoff.png` - 114 KB - Trade-off scatter plots for decision making

All files are saved in `/home/snguye63/research/golang/`
