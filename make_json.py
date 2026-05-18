#!/usr/bin/env python3
"""
Parse log file to extract runtimes and MRR values, then save to JSON.
"""
import re
import sys
import json
import argparse
from pathlib import Path

def convert_to_ms(value, unit):
    """Convert various time units to milliseconds."""
    unit = unit.lower()
    if unit == 's':
        return value * 1000.0
    elif unit == 'ms':
        return value
    elif unit in ['us', 'µs', 'micro']:
        return value / 1000.0
    elif unit in ['ns', 'nano']:
        return value / 1000000.0
    return value

def format_time(ms_value):
    """Format time in ms or s to match the expected JSON style."""
    if ms_value >= 1000:
        return f"{ms_value / 1000.0}s"
    return f"{ms_value}ms"

def parse_log_to_json(log_file, out_file, k=10):
    if not Path(log_file).exists():
        print(f"Error: File {log_file} not found")
        sys.exit(1)

    with open(log_file, 'r') as f:
        lines = f.readlines()

    round1_times = []
    round2_times = []
    round3_times = []
    mrr_values = []
    stage1_comm_cost = 0.0
    stage2_comm_cost = 0.0
    stage3_comm_cost = 0.0

    for line in lines:
        # Extract Round 1, 2, 3 times scanning for s, ms, us, ns
        # Pattern: "Round X, took X.XXXXX[unit]"
        time_match = re.search(r'Round (\d), took ([\d.]+)\s*(s|ms|us|µs|micro|ns|nano)', line, re.IGNORECASE)
        if time_match:
            round_num = int(time_match.group(1))
            val = float(time_match.group(2))
            unit = time_match.group(3)
            time_ms = convert_to_ms(val, unit)

            if round_num == 1:
                round1_times.append(time_ms)
            elif round_num == 2:
                round2_times.append(time_ms)
            elif round_num == 3:
                round3_times.append(time_ms)

        # Extract MRR values
        mrr_match = re.search(rf'MRR@{k}=([\d.]+)', line)
        if mrr_match:
            mrr_values.append(float(mrr_match.group(1)))

        # Extract communication costs
        if 'total amortized comm cost' in line:
            comm_match = re.search(r'total amortized comm cost = ([\d.]+)\s*KB', line)
            if comm_match:
                comm_cost = float(comm_match.group(1))
                if comm_cost > 1000:
                    stage3_comm_cost = comm_cost
                elif comm_cost > 400:
                    stage1_comm_cost = comm_cost
                else:
                    stage2_comm_cost = comm_cost

    # Aggregate into the target JSON structure
    output_data = {}

    # NumQueries & MRR
    if mrr_values:
        output_data["NumQueries"] = str(len(mrr_values))
        avg_mrr = sum(mrr_values) / len(mrr_values)
        output_data["MRR"] = f"{avg_mrr:.4f}"

    # Communication Cost (Total PIR Comm Cost mapped to CommCostPerBatchKB)
    total_comm = stage1_comm_cost + stage2_comm_cost + stage3_comm_cost
    if total_comm > 0:
        # Stripping trailing zero decimals if it's a clean float
        output_data["CommCostPerBatchKB"] = str(int(total_comm)) if total_comm.is_integer() else str(total_comm)

    # Time Calculations
    all_times = round1_times + round2_times + round3_times
    if all_times:
        output_data["TotalAnswerTime"] = format_time(sum(all_times))

    if round3_times:
        # Round 3 maps to Dense Rerank in your logs
        output_data["ReRankTime"] = format_time(sum(round3_times))

    # Write to JSON
    with open(out_file, 'w') as f:
        json.dump(output_data, f, indent=2)

    print(f"Successfully parsed {log_file} and saved to {out_file}")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Parse log file and save metrics to JSON.")
    parser.add_argument("log_file", help="Path to the input log file")
    parser.add_argument("--out", required=True, help="Path to save the output JSON (e.g., metadata.json)")
    parser.add_argument("-k", type=int, default=10, help="k value for MRR (default: 10)")

    args = parser.parse_args()

    parse_log_to_json(args.log_file, args.out, k=args.k)