#!/usr/bin/env python3
"""
Analysis of incomplete query runs.
Investigates why some configurations didn't process all 6980 queries.
"""
import re
from pathlib import Path

def analyze_log(filepath):
    """Analyze a log file to understand completion status."""
    if not Path(filepath).exists():
        return None
    
    with open(filepath, 'r') as f:
        content = f.read()
        lines = content.split('\n')
    
    # Count queries processed
    query_count = content.count('Stage3 Rerank: Query')
    
    # Check for errors
    has_errors = False
    error_patterns = [
        'panic', 'fatal', 'error', 'Error', 'ERROR',
        'failed', 'Failed', 'FAILED',
        'killed', 'Killed', 'KILLED',
        'segmentation', 'Segmentation'
    ]
    
    errors_found = []
    for pattern in error_patterns:
        if pattern in content:
            errors_found.append(pattern)
    
    # Check if file ends properly
    last_line = lines[-1].strip() if lines else ""
    truncated = False
    if last_line and not last_line.endswith(']') and not last_line.endswith('ms'):
        truncated = True
    
    # Check for timeout signals
    has_timeout = 'timeout' in content.lower() or 'timed out' in content.lower()
    
    # Count comm cost measurements
    comm_costs = content.count('total amortized comm cost')
    
    return {
        'query_count': query_count,
        'expected_queries': 6980,
        'completion_rate': query_count / 6980 * 100,
        'errors': errors_found,
        'truncated': truncated,
        'timeout': has_timeout,
        'comm_cost_measurements': comm_costs,
        'last_line': last_line,
        'file_size_bytes': len(content),
        'file_lines': len(lines)
    }

def main():
    log_dir = Path('/home/snguye63/research/golang/logs')
    log_files = sorted(log_dir.glob('run_go_b*.log'))
    
    print("="*100)
    print("ANALYSIS OF QUERY COMPLETION ACROSS ALL CONFIGURATIONS")
    print("="*100)
    
    incomplete_runs = []
    complete_runs = []
    
    for log_file in log_files:
        analysis = analyze_log(str(log_file))
        if analysis is None:
            continue
        
        filename = log_file.name
        query_count = analysis['query_count']
        completion = analysis['completion_rate']
        
        status = "✓ COMPLETE" if completion >= 99.9 else "⚠️  INCOMPLETE"
        
        print(f"\n{status} {filename}")
        print(f"  Queries processed: {query_count} / {analysis['expected_queries']} ({completion:.1f}%)")
        print(f"  File size: {analysis['file_size_bytes']:,} bytes")
        print(f"  Comm cost measurements: {analysis['comm_cost_measurements']}")
        
        if analysis['truncated']:
            print(f"  ⚠️  File appears TRUNCATED - last line: {analysis['last_line'][:80]}")
        
        if analysis['errors']:
            print(f"  ⚠️  Errors found in log: {', '.join(analysis['errors'])}")
        
        if analysis['timeout']:
            print(f"  ⚠️  Timeout detected")
        
        if completion >= 99.9:
            complete_runs.append(filename)
        else:
            incomplete_runs.append((filename, query_count, completion))
    
    print("\n" + "="*100)
    print("SUMMARY")
    print("="*100)
    print(f"\nComplete runs (≥99.9% of 6980 queries): {len(complete_runs)}")
    print(f"Incomplete runs: {len(incomplete_runs)}")
    
    if incomplete_runs:
        print("\nIncomplete Runs Details:")
        for filename, count, completion in sorted(incomplete_runs, key=lambda x: x[2]):
            missing = 6980 - count
            print(f"  • {filename}: {count:5d} queries ({completion:5.1f}%) - Missing {missing:4d} queries")
    
    print("\n" + "="*100)
    print("LIKELY CAUSES")
    print("="*100)
    print("""
For b16_r32_k64.log (3515 queries, ~50.3% complete):
  1. Process killed mid-execution (possible OOM on this configuration)
  2. File truncated (last line incomplete: "Round 3, took %")
  3. Disk write error or buffer overflow
  4. System resource exhaustion - block size b=16 with large k=64 may use more memory
  
Why only this run?
  • b=16 creates larger blocks → more data to process per block
  • k=64 means 512 doc embeddings retrieved → more reranking work
  • Combination may cause memory pressure not seen in b=32 runs
  • OR: Process was manually stopped partway through
  
Note: The intersection analysis already accounts for this by using only
      the 3435 common queries that ALL configurations processed.
""")

if __name__ == '__main__':
    main()
