#!/usr/bin/env python3
"""
Simple script to generate layout_with_stats.json without needing pyserini preprocessing.
This is used when you already have Stage1/Stage2 data for a specific r value and just need the layout file.
"""
import json
import math
import sys

def generate_layout(N, B, r):
    """Generate layout dict"""
    # Calculate tree structure
    num_leaves = math.ceil(N / B)
    height = math.ceil(math.log(num_leaves, r)) if r > 1 else 0
    
    # We'll use empty min_dl_map - the Go code can work with this
    layout = {
        'N': N,
        'B': B,
        'r': r,
        'min_dl_map': {}
    }
    return layout

if __name__ == '__main__':
    if len(sys.argv) != 4:
        print("Usage: gen_layout.py <N> <B> <r>")
        print("Example: gen_layout.py 8841823 32 32")
        sys.exit(1)
    
    N = int(sys.argv[1])
    B = int(sys.argv[2])
    r = int(sys.argv[3])
    
    layout = generate_layout(N, B, r)
    
    with open(f'data/layout_with_stats_{B}_{r}.json', 'w') as f:
        json.dump(layout, f, indent=2)
    
    print(f"Generated layout_with_stats_{B}_{r}.json:")
    print(f"  N={N}, B={B}, r={r}")
    print(f"  num_leaves={math.ceil(N / B)}")
    print(f"  height={math.ceil(math.log(math.ceil(N / B), r)) if r > 1 else 0}")
