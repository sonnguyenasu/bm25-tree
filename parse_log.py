#!/usr/bin/env python3
"""
Parse log file to extract runtimes and MRR values.
Usage: python parse_log.py <log_file> [--stage N]
"""
import re
import sys
from pathlib import Path

def parse_log(filename, stage=None):
    """
    Parse log file and extract:
    - All 'took XXXms' runtimes (Round 1, 2, 3)
    - MRR@10 values
    
    Args:
        filename: path to log file
        stage: if specified (1, 2, or 3), only extract that round's times
    
    Returns:
        dict with keys: 'round1_times', 'round2_times', 'round3_times', 'mrr_values'
    """
    if not Path(filename).exists():
        print(f"Error: File {filename} not found")
        sys.exit(1)
    
    with open(filename, 'r') as f:
        lines = f.readlines()
    
    result = {
        'round1_times': [],
        'round2_times': [],
        'round3_times': [],
        'mrr_values': [],
        'stage1_comm_cost': None,
        'stage2_comm_cost': None,
        'stage3_comm_cost': None,
    }
    
    # Process line by line to maintain order
    for i, line in enumerate(lines):
        # Extract Round 1, 2, 3 times
        # Pattern: "Round X, took X.XXXXXms"
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
        # Pattern: "Stage3 Rerank: Query XXXX MRR@10=X.XXXX, candidates=XXXX"
        match = re.search(r'MRR@10=([\d.]+)', line)
        if match:
            mrr = float(match.group(1))
            result['mrr_values'].append(mrr)
        
        # Extract communication costs
        # Pattern: "total amortized comm cost = X.XX KB"
        if 'total amortized comm cost' in line:
            match = re.search(r'total amortized comm cost = ([\d.]+)\s*KB', line)
            if match:
                comm_cost = float(match.group(1))
                # Determine stage by looking backwards for "DB size" or other markers
                # and by analyzing the comm cost values:
                # Stage1: ~512 KB, Stage2: ~379 KB, Stage3: ~4730 KB (much larger)
                if comm_cost > 1000:  # Stage3 has largest comm cost
                    result['stage3_comm_cost'] = comm_cost
                elif comm_cost > 400:  # Stage1 has ~512 KB
                    result['stage1_comm_cost'] = comm_cost
                else:  # Stage2 has ~379 KB
                    result['stage2_comm_cost'] = comm_cost
    
    return result

def print_report(data, stage=None):
    """Print a formatted report of the parsed data"""
    print("\n" + "="*70)
    print("LOG PARSING REPORT")
    print("="*70 + "\n")
    
    # Communication costs (PIR initialization)
    if any([data['stage1_comm_cost'], data['stage2_comm_cost'], data['stage3_comm_cost']]):
        print("PIR COMMUNICATION COSTS (One-time Preprocessing):")
        if data['stage1_comm_cost']:
            print(f"  Stage1 (BM25 Beam):     {data['stage1_comm_cost']:>10.2f} KB")
        if data['stage2_comm_cost']:
            print(f"  Stage2 (Sub-block):     {data['stage2_comm_cost']:>10.2f} KB")
        if data['stage3_comm_cost']:
            print(f"  Stage3 (Dense Rerank):  {data['stage3_comm_cost']:>10.2f} KB")
        
        total_comm = sum(c for c in [data['stage1_comm_cost'], data['stage2_comm_cost'], data['stage3_comm_cost']] if c)
        print(f"  Total PIR Comm Cost:    {total_comm:>10.2f} KB ({total_comm/1024:>8.2f} MB)")
        print()
    
    # Round statistics
    all_times = data['round1_times'] + data['round2_times'] + data['round3_times']
    
    if data['round1_times']:
        r1_total = sum(data['round1_times'])
        r1_avg = r1_total / len(data['round1_times'])
        print(f"Round 1 (BM25 Beam Search):")
        print(f"  Count:   {len(data['round1_times'])} queries")
        print(f"  Total:   {r1_total:>10.2f} ms")
        print(f"  Average: {r1_avg:>10.2f} ms")
        print()
    
    if data['round2_times']:
        r2_total = sum(data['round2_times'])
        r2_avg = r2_total / len(data['round2_times'])
        print(f"Round 2 (Sub-block Selection):")
        print(f"  Count:   {len(data['round2_times'])} queries")
        print(f"  Total:   {r2_total:>10.2f} ms")
        print(f"  Average: {r2_avg:>10.2f} ms")
        print()
    
    if data['round3_times']:
        r3_total = sum(data['round3_times'])
        r3_avg = r3_total / len(data['round3_times'])
        print(f"Round 3 (Dense Reranking):")
        print(f"  Count:   {len(data['round3_times'])} queries")
        print(f"  Total:   {r3_total:>10.2f} ms")
        print(f"  Average: {r3_avg:>10.2f} ms")
        print()
    
    # Total runtime
    if all_times:
        total_runtime_ms = sum(all_times)
        total_runtime_sec = total_runtime_ms / 1000
        num_queries = len(data['round1_times'])
        avg_per_query = total_runtime_ms / num_queries if num_queries > 0 else 0
        
        print("-"*70)
        print(f"TOTAL RUNTIME (All Rounds):")
        print(f"  Total:       {total_runtime_ms:>10.2f} ms ({total_runtime_sec:>8.2f} sec)")
        print(f"  Per Query:   {avg_per_query:>10.2f} ms")
        print()
    
    # MRR statistics
    if data['mrr_values']:
        avg_mrr = sum(data['mrr_values']) / len(data['mrr_values'])
        max_mrr = max(data['mrr_values'])
        min_mrr = min(data['mrr_values'])
        mrr_perfect = sum(1 for m in data['mrr_values'] if m == 1.0)
        
        print("-"*70)
        print(f"MRR@10 (Mean Reciprocal Rank @ 10):")
        print(f"  Average:  {avg_mrr:>10.4f}")
        print(f"  Max:      {max_mrr:>10.4f}")
        print(f"  Min:      {min_mrr:>10.4f}")
        print(f"  Perfect:  {mrr_perfect:>10d} / {len(data['mrr_values'])} queries (MRR=1.0)")
        print()
    
    print("="*70)

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python parse_log.py <log_file>")
        print("Example: python parse_log.py run.log")
        sys.exit(1)
    
    log_file = sys.argv[1]
    
    data = parse_log(log_file)
    print_report(data)
