#!/usr/bin/env python3
"""
Visualize MRR, runtime, and communication cost from go_results_* files.
This script:
1. Parses all log files to extract MRR, runtime, and communication cost
2. Extracts parameters (b, r, k) from filenames
3. Creates plots varying by r and doc embedding retrieved (K_CANDIDATES*8)
4. Saves figures to PNG files
"""
import re
import sys
from pathlib import Path
from collections import defaultdict
import numpy as np
import matplotlib.pyplot as plt
import os

def parse_log(filename):
    """
    Parse log file and extract metrics and query IDs.
    
    Returns:
        dict with keys: 'query_data' (list of dicts with qid, mrr, runtime),
                        'comm_costs'
    """
    if not Path(filename).exists():
        return None
    
    with open(filename, 'r') as f:
        lines = f.readlines()
    
    query_data = []
    comm_costs = []
    current_query_id = None
    current_mrr = None
    round_times = []
    
    # Process line by line
    for line in lines:
        # Extract Query ID and MRR
        match = re.search(r'Stage3 Rerank: Query (\d+) MRR@10=([\d.]+)', line)
        if match:
            # Save previous query if exists (even with incomplete rounds >= 1)
            if current_query_id is not None and len(round_times) >= 1:
                query_data.append({
                    'query_id': current_query_id,
                    'mrr': current_mrr,
                    'runtime': sum(round_times)
                })
            
            current_query_id = int(match.group(1))
            current_mrr = float(match.group(2))
            round_times = []
        
        # Extract Round times
        match = re.search(r'Round (\d), took ([\d.]+)ms', line)
        if match:
            time_ms = float(match.group(2))
            round_times.append(time_ms)
        
        # Extract communication costs
        if 'total amortized comm cost' in line:
            match = re.search(r'total amortized comm cost = ([\d.]+)\s*KB', line)
            if match:
                comm_cost = float(match.group(1))
                comm_costs.append(comm_cost)
    
    # Save last query (even with incomplete rounds >= 1)
    if current_query_id is not None and len(round_times) >= 1:
        query_data.append({
            'query_id': current_query_id,
            'mrr': current_mrr,
            'runtime': sum(round_times)
        })
    
    return {
        'query_data': query_data,
        'comm_costs': comm_costs
    }

def extract_parameters(filename):
    """
    Extract b, r, k parameters from filename like 'b32_r32_k32'.
    Returns tuple (b, r, k) or None if parsing fails.
    """
    pattern = r'b(\d+)_r(\d+)_k(\d+)'
    match = re.search(pattern, filename)
    if match:
        return int(match.group(1)), int(match.group(2)), int(match.group(3))
    return None

def collect_results():
    """
    Collect all results from log files and organize by parameters.
    Only uses queries that appear in ALL configurations (intersection).
    Returns dict: {(b, r, k): {'mrr': float, 'runtime': float, 'comm_cost': float}}
    """
    results = {}
    log_dir = Path('/home/snguye63/research/golang')
    
    # Find all log files matching pattern
    log_files = list(log_dir.glob('logs/run_go_b*.log'))
    
    print(f"Found {len(log_files)} log files")
    print("Filtering to only b=32 configurations for consistency\n")
    
    # First pass: collect all data and find query intersection
    all_data = {}
    all_query_sets = {}
    
    for log_file in sorted(log_files):
        # Extract parameters from filename
        params = extract_parameters(log_file.name)
        if params is None:
            print(f"Skipping {log_file.name} - couldn't parse parameters")
            continue
        
        b, r, k = params
        
        # Only include b=32 configurations
        if b != 32:
            print(f"Skipping {log_file.name} - b={b} (only analyzing b=32)")
            continue
        
        # Parse log file
        data = parse_log(str(log_file))
        if data is None or not data['query_data']:
            print(f"Skipping {log_file.name} - couldn't parse log data")
            continue
        
        all_data[(b, r, k)] = data
        all_query_sets[(b, r, k)] = set(q['query_id'] for q in data['query_data'])
    
    # Find intersection of all query sets
    if not all_query_sets:
        print("ERROR: No valid log files found!")
        return results
    
    all_query_set_list = list(all_query_sets.values())
    query_intersection = set.intersection(*all_query_set_list)
    
    print(f"\nQuery Statistics (b=32 only):")
    print(f"  Total unique queries: {len(set.union(*all_query_set_list))}")
    print(f"  Common queries (intersection): {len(query_intersection)}")
    print(f"  Using only {len(query_intersection)} queries for fair comparison\n")
    
    # Second pass: calculate metrics using only intersection queries
    for (b, r, k), data in all_data.items():
        # Filter to only include queries in intersection
        filtered_queries = [q for q in data['query_data'] if q['query_id'] in query_intersection]
        
        if not filtered_queries:
            print(f"Skipping {b=}, {r=}, {k=} - no common queries")
            continue
        
        # Extract filtered data
        mrr_values = [q['mrr'] for q in filtered_queries]
        runtime_values = [q['runtime'] for q in filtered_queries]
        
        # Calculate metrics
        avg_mrr = np.mean(mrr_values)
        num_queries = len(mrr_values)
        total_runtime_ms = sum(runtime_values)
        avg_runtime_per_query_ms = total_runtime_ms / num_queries if num_queries > 0 else 0
        
        # Communication cost (take the first one, or average if multiple stages)
        avg_comm_cost = np.mean(data['comm_costs']) if data['comm_costs'] else 0
        avg_comm_cost_per_query = avg_comm_cost / num_queries if num_queries > 0 else 0
        
        results[(b, r, k)] = {
            'mrr': avg_mrr,
            'runtime': avg_runtime_per_query_ms,
            'comm_cost': avg_comm_cost_per_query,
        }
        
        print(f"✓ b={b:2d}, r={r:3d}, k={k:3d}: MRR={avg_mrr:.4f}, Runtime={avg_runtime_per_query_ms:.1f}ms/query, CommCost={avg_comm_cost_per_query:.2f}KB/query")
    
    return results

def organize_by_r_and_k(results):
    """
    Organize results by r and k values (doc embedding retrieved = k*8).
    Returns:
        - dict of r values
        - dict of k values  
        - dict indexed by (r, k) with metrics
    """
    by_r_k = defaultdict(lambda: {'mrr': [], 'runtime': [], 'comm_cost': []})
    
    for (b, r, k), metrics in results.items():
        by_r_k[(r, k)]['mrr'].append(metrics['mrr'])
        by_r_k[(r, k)]['runtime'].append(metrics['runtime'])
        by_r_k[(r, k)]['comm_cost'].append(metrics['comm_cost'])
    
    # Average multiple results for same (r, k)
    aggregated = {}
    for (r, k), values in by_r_k.items():
        aggregated[(r, k)] = {
            'mrr': np.mean(values['mrr']),
            'runtime': np.mean(values['runtime']),
            'comm_cost': np.mean(values['comm_cost']),
        }
    
    return aggregated

def plot_results(aggregated):
    """
    Create plots for MRR, runtime, and communication cost.
    Plots vary by r and K_CANDIDATES*8 (doc embedding retrieved).
    """
    # Extract unique r and k values
    r_values = sorted(set(r for r, k in aggregated.keys()))
    k_values = sorted(set(k for r, k in aggregated.keys()))
    
    print(f"\nUnique r values: {r_values}")
    print(f"Unique k values: {k_values}")
    print(f"Doc embedding retrieved (k*8): {[k*8 for k in k_values]}")
    
    # Create figure with 3 subplots
    fig, axes = plt.subplots(1, 3, figsize=(16, 5))
    fig.suptitle('Performance Metrics vs Retrieval Parameters', fontsize=14, fontweight='bold')
    
    # Plot 1: MRR vs r for different k values
    ax = axes[0]
    for k in k_values:
        r_vals = []
        mrr_vals = []
        for r in r_values:
            if (r, k) in aggregated:
                r_vals.append(r)
                mrr_vals.append(aggregated[(r, k)]['mrr'])
        if r_vals:
            ax.plot(r_vals, mrr_vals, marker='o', label=f'k={k} (docs={k*8})', linewidth=2, markersize=6)
    
    ax.set_xlabel('r (PIR Tree Branch Factor)', fontsize=11, fontweight='bold')
    ax.set_ylabel('MRR@10 (Mean Reciprocal Rank)', fontsize=11, fontweight='bold')
    ax.set_title('MRR vs PIR Tree Branch Factor', fontsize=12, fontweight='bold')
    ax.legend()
    ax.grid(True, alpha=0.3)
    ax.set_xscale('log', base=2)
    
    # Plot 2: Runtime vs r for different k values
    ax = axes[1]
    for k in k_values:
        r_vals = []
        runtime_vals = []
        for r in r_values:
            if (r, k) in aggregated:
                r_vals.append(r)
                runtime_vals.append(aggregated[(r, k)]['runtime'])
        if r_vals:
            ax.plot(r_vals, runtime_vals, marker='s', label=f'k={k} (docs={k*8})', linewidth=2, markersize=6)
    
    ax.set_xlabel('r (PIR Tree Branch Factor)', fontsize=11, fontweight='bold')
    ax.set_ylabel('Runtime per Query (ms)', fontsize=11, fontweight='bold')
    ax.set_title('Runtime per Query vs PIR Tree Branch Factor', fontsize=12, fontweight='bold')
    ax.set_title('Runtime vs PIR Tree Branch Factor', fontsize=12, fontweight='bold')
    ax.legend()
    ax.grid(True, alpha=0.3)
    ax.set_xscale('log', base=2)
    
    # Plot 3: Communication Cost vs r for different k values
    ax = axes[2]
    for k in k_values:
        r_vals = []
        comm_vals = []
        for r in r_values:
            if (r, k) in aggregated:
                r_vals.append(r)
                comm_vals.append(aggregated[(r, k)]['comm_cost'])
        if r_vals:
            ax.plot(r_vals, comm_vals, marker='^', label=f'k={k} (docs={k*8})', linewidth=2, markersize=6)
    
    ax.set_xlabel('r (PIR Tree Branch Factor)', fontsize=11, fontweight='bold')
    ax.set_ylabel('Communication Cost per Query (KB)', fontsize=11, fontweight='bold')
    ax.set_title('Communication Cost per Query vs PIR Tree Branch Factor', fontsize=12, fontweight='bold')
    ax.legend()
    ax.grid(True, alpha=0.3)
    ax.set_xscale('log', base=2)
    
    plt.tight_layout()
    
    # Save figure
    output_path = '/home/snguye63/research/golang/results_visualization.png'
    plt.savefig(output_path, dpi=150, bbox_inches='tight')
    print(f"\n✓ Saved visualization to {output_path}")
    
    return fig

def create_heatmap_plots(aggregated):
    """
    Create heatmap plots with r on x-axis and k on y-axis.
    """
    r_values = sorted(set(r for r, k in aggregated.keys()))
    k_values = sorted(set(k for r, k in aggregated.keys()))
    
    # Create heatmaps for each metric
    fig, axes = plt.subplots(1, 3, figsize=(16, 5))
    fig.suptitle('Performance Metrics Heatmaps (PIR Tree Branch Factor vs Doc Embedding Retrieved)', fontsize=14, fontweight='bold')
    
    for idx, (metric_name, metric_key) in enumerate([('MRR@10', 'mrr'), 
                                                       ('Runtime per Query (ms)', 'runtime'), 
                                                       ('Comm Cost per Query (KB)', 'comm_cost')]):
        ax = axes[idx]
        
        # Create matrix
        matrix = np.zeros((len(k_values), len(r_values)))
        for i, k in enumerate(k_values):
            for j, r in enumerate(r_values):
                if (r, k) in aggregated:
                    matrix[i, j] = aggregated[(r, k)][metric_key]
        
        # Plot heatmap
        im = ax.imshow(matrix, cmap='viridis', aspect='auto')
        
        # Set ticks and labels
        ax.set_xticks(range(len(r_values)))
        ax.set_yticks(range(len(k_values)))
        ax.set_xticklabels(r_values, rotation=45)
        ax.set_yticklabels([f'k={k} ({k*8} docs)' for k in k_values])
        
        ax.set_xlabel('r (PIR Tree Branch Factor)', fontsize=11, fontweight='bold')
        ax.set_ylabel('k (Scaling Factor)', fontsize=11, fontweight='bold')
        ax.set_title(metric_name, fontsize=12, fontweight='bold')
        
        # Add colorbar
        cbar = plt.colorbar(im, ax=ax)
        cbar.set_label(metric_name, fontsize=10)
    
    plt.tight_layout()
    
    # Save figure
    output_path = '/home/snguye63/research/golang/results_heatmap.png'
    plt.savefig(output_path, dpi=150, bbox_inches='tight')
    print(f"✓ Saved heatmap visualization to {output_path}")
    
    return fig

def create_tradeoff_plot(aggregated):
    """
    Create a plot showing the tradeoff between different metrics.
    """
    fig, axes = plt.subplots(1, 2, figsize=(14, 5))
    fig.suptitle('Performance Trade-offs', fontsize=14, fontweight='bold')
    
    # Plot 1: MRR vs Runtime
    ax = axes[0]
    k_values = sorted(set(k for r, k in aggregated.keys()))
    r_values = sorted(set(r for r, k in aggregated.keys()))
    
    for k in k_values:
        mrr_vals = []
        runtime_vals = []
        r_for_k = []
        for r in r_values:
            if (r, k) in aggregated:
                mrr_vals.append(aggregated[(r, k)]['mrr'])
                runtime_vals.append(aggregated[(r, k)]['runtime'])
                r_for_k.append(r)
        if mrr_vals:
            # Sort by runtime for proper line connection
            sorted_indices = sorted(range(len(runtime_vals)), key=lambda i: runtime_vals[i])
            sorted_runtime = [runtime_vals[i] for i in sorted_indices]
            sorted_mrr = [mrr_vals[i] for i in sorted_indices]
            sorted_r = [r_for_k[i] for i in sorted_indices]
            
            # Plot line connecting points of same k
            ax.plot(sorted_runtime, sorted_mrr, linewidth=2, alpha=0.5)
            # Plot scatter points
            scatter = ax.scatter(runtime_vals, mrr_vals, s=100, label=f'k={k} (docs={k*8})', alpha=0.7)
            # Add r values as annotations
            for i, r in enumerate(r_for_k):
                ax.annotate(f'r={r}', (runtime_vals[i], mrr_vals[i]), fontsize=12, fontweight='bold', alpha=0.9)
    
    ax.set_xlabel('Runtime per Query (ms)', fontsize=11, fontweight='bold')
    ax.set_ylabel('MRR@10', fontsize=11, fontweight='bold')
    ax.set_title('MRR vs Runtime per Query Trade-off', fontsize=12, fontweight='bold')
    ax.legend()
    ax.grid(True, alpha=0.3)
    
    # Plot 2: MRR vs Comm Cost
    ax = axes[1]
    for k in k_values:
        comm_vals = []
        mrr_vals = []
        r_for_k = []
        for r in r_values:
            if (r, k) in aggregated:
                comm_vals.append(aggregated[(r, k)]['comm_cost'])
                mrr_vals.append(aggregated[(r, k)]['mrr'])
                r_for_k.append(r)
        if comm_vals:
            # Sort by comm cost for proper line connection
            sorted_indices = sorted(range(len(comm_vals)), key=lambda i: comm_vals[i])
            sorted_comm = [comm_vals[i] for i in sorted_indices]
            sorted_mrr = [mrr_vals[i] for i in sorted_indices]
            sorted_r = [r_for_k[i] for i in sorted_indices]
            
            # Plot line connecting points of same k
            ax.plot(sorted_comm, sorted_mrr, linewidth=2, alpha=0.5)
            # Plot scatter points
            scatter = ax.scatter(comm_vals, mrr_vals, s=100, label=f'k={k} (docs={k*8})', alpha=0.7)
            # Add r values as annotations
            for i, r in enumerate(r_for_k):
                ax.annotate(f'r={r}', (comm_vals[i], mrr_vals[i]), fontsize=12, fontweight='bold', alpha=0.9)
    
    ax.set_xlabel('Communication Cost per Query (KB)', fontsize=11, fontweight='bold')
    ax.set_ylabel('MRR@10', fontsize=11, fontweight='bold')
    ax.set_title('MRR vs Comm Cost per Query Trade-off', fontsize=12, fontweight='bold')
    ax.legend()
    ax.grid(True, alpha=0.3)
    
    plt.tight_layout()
    
    # Save figure
    output_path = '/home/snguye63/research/golang/results_tradeoff.png'
    plt.savefig(output_path, dpi=150, bbox_inches='tight')
    print(f"✓ Saved trade-off visualization to {output_path}")
    
    return fig

def main():
    print("="*70)
    print("Visualizing Results from go_results_* files")
    print("="*70)
    
    # Collect results
    print("\n[1/4] Collecting results from log files...")
    results = collect_results()
    
    if not results:
        print("ERROR: No results collected!")
        sys.exit(1)
    
    print(f"\nTotal results collected: {len(results)}")
    
    # Organize by r and k
    print("\n[2/4] Organizing results by r and k...")
    aggregated = organize_by_r_and_k(results)
    print(f"Organized into {len(aggregated)} (r, k) combinations")
    
    # Create plots
    print("\n[3/4] Creating line plots...")
    plot_results(aggregated)
    
    print("\n[4/4] Creating additional visualizations...")
    create_heatmap_plots(aggregated)
    create_tradeoff_plot(aggregated)
    
    print("\n" + "="*70)
    print("✓ All visualizations completed successfully!")
    print("="*70)
    print("\nGenerated files:")
    print("  - results_visualization.png   (line plots)")
    print("  - results_heatmap.png         (heatmap plots)")
    print("  - results_tradeoff.png        (trade-off plots)")

if __name__ == '__main__':
    main()
