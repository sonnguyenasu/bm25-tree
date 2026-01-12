module bm25-msmarco

go 1.24.0

toolchain go1.24.11

require (
	github.com/dkblackley/bins-go v0.0.0-20260112073316-0a2e89e8e15a
	pianopir v0.0.0
)

require github.com/kshedden/gonpy v0.0.0-20210519231815-fa3c8dd8e59b // indirect

replace pianopir => ./pianopir
