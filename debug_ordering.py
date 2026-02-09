#!/usr/bin/env python3
"""
Debug script to examine why metric ordering varies by k value.
Shows runtime and comm cost for each (r, k) combination.
"""
import re
from pathlib import Path
from collections import defaultdict
import numpy as np

def parse_log(filename):
    """Parse log file and extract metrics."""
    if not Path(filename).exists():
        return None
    
    with open(filename, 'r') as f:
        lines = f.readlines()
    
    result = {
        'round1_times': [],
        'round2_times': [],
        'round3_times': [],
        'mrr_values': [],
        'comm_costs': [],
    }
    
    comm_costs = []
    
    # Process line by line
    for line in lines:
        # Extract Round times
        match = re.search(r'Round (\d), took ([\d.]+)ms', line)
        if match:
            round_num = int(match.group(1))
            time_ms = float(match.group(2))
            
            if round_num == 1:
                result['round1_times'].append(time_ms)
            elif round_num == 2:
                result['round2_times'].append(time_ms)
            elif round_num == 3:
                result['round3_times'].append(time_ms)
        
        # Extract MRR values
        match = re.search(r'MRR@10=([\d.]+)', line)
        if match:
            mrr = float(match.group(1))
            result['mrr_values'].append(mrr)
        
        # Extract communication costs
        if 'total amortized comm cost' in line:
            match = re.search(r'total amortized comm cost = ([\d.]+)\s*KB', line)
            if match:
                comm_cost = float(match.group(1))
                comm_costs.append(comm_cost)
    
    # Average the communication costs
    if comm_costs:
        result['comm_costs'] = comm_costs
    
    return result

def extract_parameters(filename):
    """Extract b, r, k parameters from filename."""
    pattern = r'b(\d+)_r(\d+)_k(\d+)'
    match = re.search(pattern, filename)
    if match:
        return int(match.group(1)), int(match.group(2)), int(match.group(3))
    return None

def main():
    results = {}
    log_dir = Path('/home/snguye63/research/golang')
    
    # Find all log files matching pattern
    log_files = list(log_dir.glob('logs/run_go_b*.log'))
    
    print(f"Found {len(log_files)} log files\n")
    
    for log_file in sorted(log_files):
        params = extract_parameters(log_file.name)
        if params is None:
            continue
        
        b, r, k = params
        
        data = parse_log(str(log_file))
        if data is None or not data['mrr_values']:
            continue
        
        avg_mrr = np.mean(data['mrr_values'])
        num_queries = len(data['mrr_values'])
        total_runtime_ms = sum(data['round1_times']) + sum(data['round2_times']) + sum(data['round3_times'])
        avg_runtime_per_query_ms = total_runtime_ms / num_queries if num_queries > 0 else 0
        
        avg_comm_cost = np.mean(data['comm_costs']) if data['comm_costs'] else 0
        avg_comm_cost_per_query = avg_comm_cost / num_queries if num_queries > 0 else 0
        
        results[(b, r, k)] = {
            'mrr': avg_mrr,
            'runtime': avg_runtime_per_query_ms,
            'comm_cost': avg_comm_cost_per_query,
            'num_queries': num_queries,
        }
    
    # Analyze ordering by k
    print("\n" + "="*80)
    print("RUNTIME ORDERING BY K VALUE")
    print("="*80)
    
    k_values = sorted(set(k for b, r, k in results.keys()))
    r_values = sorted(set(r for b, r, k in results.keys()))
    
    for k in k_values:
        print(f"\nk={k} (docs={k*8}):")
        data_for_k = []
        for r in r_values:
            # Get data from any b value
            for b in sorted(set(b for b, r_, k_ in results.keys() if r_ == r and k_ == k)):
                if (b, r, k) in results:
                    data_for_k.append((r, results[(b, r, k)]['runtime'], results[(b, r, k)]['num_queries']))
                    break
        
        # Sort by runtime to see the order
        data_for_k_sorted = sorted(data_for_k, key=lambda x: x[1])
        print(f"  Runtime order: ", end="")
        print(" → ".join([f"r={r}({rt:.1f}ms)" for r, rt, _ in data_for_k_sorted]))
        
        # Show original r order
        print(f"  Param order:   ", end="")
        print(" → ".join([f"r={r}({rt:.1f}ms)" for r, rt, _ in sorted(data_for_k, key=lambda x: x[0])]))
    
    print("\n" + "="*80)
    print("COMMUNICATION COST ORDERING BY K VALUE")
    print("="*80)
    
    for k in k_values:
        print(f"\nk={k} (docs={k*8}):")
        data_for_k = []
        for r in r_values:
            for b in sorted(set(b for b, r_, k_ in results.keys() if r_ == r and k_ == k)):
                if (b, r, k) in results:
                    data_for_k.append((r, results[(b, r, k)]['comm_cost'], results[(b, r, k)]['num_queries']))
                    break
        
        # Sort by comm cost to see the order
        data_for_k_sorted = sorted(data_for_k, key=lambda x: x[1])
        print(f"  Comm cost order: ", end="")
        print(" → ".join([f"r={r}({cc:.2f}KB)" for r, cc, _ in data_for_k_sorted]))
        
        # Show original r order
        print(f"  Param order:     ", end="")
        print(" → ".join([f"r={r}({cc:.2f}KB)" for r, cc, _ in sorted(data_for_k, key=lambda x: x[0])]))
    
    print("\n" + "="*80)
    print("DETAILED BREAKDOWN")
    print("="*80)
    print("\n(r, k) -> Runtime(ms/query), CommCost(KB/query), NumQueries")
    for k in k_values:
        print(f"\nk={k}:")
        for r in sorted(r_values):
            for b in sorted(set(b for b, r_, k_ in results.keys() if r_ == r and k_ == k)):
                if (b, r, k) in results:
                    res = results[(b, r, k)]
                    print(f"  (r={r:3d}, k={k:3d}) -> {res['runtime']:6.1f}ms, {res['comm_cost']:6.2f}KB, {res['num_queries']:5d} queries (b={b})")
                    break

if __name__ == '__main__':
    main()
