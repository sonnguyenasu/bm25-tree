#!/usr/bin/env python3
"""
Find intersection of queries across all (r, k) configurations.
This ensures we only compare the same set of queries across all parameters.
"""
import re
from pathlib import Path
from collections import defaultdict
import numpy as np

def parse_log_for_queries(filename):
    """Parse log file and extract query IDs and their metrics."""
    if not Path(filename).exists():
        return None, None
    
    with open(filename, 'r') as f:
        lines = f.readlines()
    
    # Structure: query_id -> {'round_times': [r1, r2, r3], 'mrr': float}
    queries = {}
    current_query = None
    round_times = []
    
    for line in lines:
        # Extract query info: "Stage3 Rerank: Query 1048585 MRR@10=1.0000, candidates=256"
        match = re.search(r'Stage3 Rerank: Query (\d+) MRR@10=([\d.]+)', line)
        if match:
            query_id = int(match.group(1))
            mrr = float(match.group(2))
            
            if current_query is not None:
                # Save previous query
                if round_times and len(round_times) == 3:
                    queries[current_query] = {
                        'mrr': prev_mrr,
                        'round_times': round_times
                    }
            
            current_query = query_id
            prev_mrr = mrr
            round_times = []
        
        # Extract Round times
        match = re.search(r'Round (\d), took ([\d.]+)ms', line)
        if match:
            round_num = int(match.group(1))
            time_ms = float(match.group(2))
            round_times.append(time_ms)
    
    # Save last query
    if current_query is not None and round_times and len(round_times) == 3:
        queries[current_query] = {
            'mrr': prev_mrr,
            'round_times': round_times
        }
    
    # Extract communication costs
    comm_costs = []
    for line in lines:
        if 'total amortized comm cost' in line:
            match = re.search(r'total amortized comm cost = ([\d.]+)\s*KB', line)
            if match:
                comm_cost = float(match.group(1))
                comm_costs.append(comm_cost)
    
    return queries, comm_costs

def extract_parameters(filename):
    """Extract b, r, k parameters from filename."""
    pattern = r'b(\d+)_r(\d+)_k(\d+)'
    match = re.search(pattern, filename)
    if match:
        return int(match.group(1)), int(match.group(2)), int(match.group(3))
    return None

def main():
    log_dir = Path('/home/snguye63/research/golang')
    log_files = sorted(log_dir.glob('logs/run_go_b*.log'))
    
    print(f"Found {len(log_files)} log files\n")
    
    # Parse all logs and collect query IDs
    all_queries_by_config = {}
    all_comm_costs = {}
    
    for log_file in log_files:
        params = extract_parameters(log_file.name)
        if params is None:
            continue
        
        b, r, k = params
        queries, comm_costs = parse_log_for_queries(str(log_file))
        
        if queries is None:
            print(f"Skipping {log_file.name} - couldn't parse")
            continue
        
        all_queries_by_config[(b, r, k)] = set(queries.keys())
        all_comm_costs[(b, r, k)] = comm_costs
        
        print(f"✓ {log_file.name}: {len(queries)} queries, {len(comm_costs)} comm cost measurements")
    
    # Find intersection of all query sets
    print(f"\nTotal configurations: {len(all_queries_by_config)}")
    
    all_query_sets = list(all_queries_by_config.values())
    intersection = set.intersection(*all_query_sets) if all_query_sets else set()
    
    print(f"Union of all queries: {len(set.union(*all_query_sets))}")
    print(f"Intersection of all queries: {len(intersection)}")
    
    if not intersection:
        print("ERROR: No common queries found!")
        return
    
    # Calculate coverage for each config
    print("\nCoverage by configuration:")
    for (b, r, k), query_set in sorted(all_queries_by_config.items()):
        coverage = len(query_set & intersection) / len(intersection) * 100
        print(f"  b={b:2d}, r={r:3d}, k={k:3d}: {len(query_set):5d} total, {len(query_set & intersection):5d} in intersection ({coverage:5.1f}%)")
    
    print(f"\n{'='*80}")
    print(f"Using intersection of {len(intersection)} common queries")
    print(f"{'='*80}")

if __name__ == '__main__':
    main()
