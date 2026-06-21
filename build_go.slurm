#!/bin/bash -l
#SBATCH --job-name=tree_build
#SBATCH --partition=normal
#SBATCH --output=build.out
#SBATCH --error=build.err
#SBATCH --cpus-per-task=16
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --mem=32G
#SBATCH --time=0-01:30:00

# Build the Go binary once per job (or pre-build it before submitting)
go build -o bm25-search ./cmd