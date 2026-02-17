package pianopir

import (
	"fmt"
	"log"
	"strings"
	"sync"
	"time"
)

const (
	RealQueryPerPartition = 2
	QueryPerPartition     = 2
	DefaultValue          = 0xdeadbeef
	ThreadNum             = 1
)

type SimpleBatchPianoPIRConfig struct {
	DBEntryByteNum  uint64
	DBEntrySize     uint64
	DBSize          uint64
	BatchSize       uint64
	PartitionNum    uint64
	PartitionSize   uint64
	ThreadNum       uint64
	FailureProbLog2 uint64
}

type SimpleBatchPianoPIR struct {
	config *SimpleBatchPianoPIRConfig
	subPIR []*PianoPIR

	// Permutation Key for scrambling offsets within partitions
	offsetKey uint64

	// Stats
	FinishedBatchNum        uint64
	QueriesMadeInPartition  uint64
	SupportBatchNum         uint64
	localStorage            uint64  // bytes
	preprocessingTime       float64 // seconds
	commCostPerBatchOnline  uint64  // bytes
	commCostPerBatchOffline uint64  // bytes
}

// gcd computes the greatest common divisor
func gcd(a, b uint64) uint64 {
	for b != 0 {
		t := b
		b = a % b
		a = t
	}
	return a
}

func NewSimpleBatchPianoPIR(DBSize uint64, DBEntryByteNum uint64, BatchSize uint64, rawDB []uint64, FailureProbLog2 uint64) *SimpleBatchPianoPIR {
	DBEntrySize := DBEntryByteNum / 8
	if len(rawDB) != int(DBSize*DBEntrySize) {
		log.Fatalf("BatchPIR: len(rawDB) = %v; want %v", len(rawDB), DBSize*DBEntrySize)
	}

	PartitionNum := BatchSize / RealQueryPerPartition
	PartitionSize := (DBSize + PartitionNum - 1) / PartitionNum

	config := &SimpleBatchPianoPIRConfig{
		DBEntryByteNum:  DBEntryByteNum,
		DBEntrySize:     DBEntrySize,
		DBSize:          DBSize,
		BatchSize:       BatchSize,
		PartitionNum:    PartitionNum,
		PartitionSize:   PartitionSize,
		ThreadNum:       8,
		FailureProbLog2: FailureProbLog2,
	}

	// --- FIX: SCRAMBLE OFFSETS ---
	// We need a multiplier coprime to PartitionSize to permute the offsets.
	// This ensures (i * offsetKey) % PartitionSize is a unique 1-to-1 mapping.
	offsetKey := uint64(1299827) // Large prime
	for gcd(offsetKey, PartitionSize) != 1 {
		offsetKey++
	}
	
	// Allocate padded buffer (PartitionNum * PartitionSize)
	paddedTotalSize := PartitionNum * PartitionSize * DBEntrySize
	partitionedDB := make([]uint64, paddedTotalSize)

	var wg sync.WaitGroup
	wg.Add(int(config.ThreadNum))
	rowsPerThread := (DBSize + config.ThreadNum - 1) / config.ThreadNum

	for t := uint64(0); t < config.ThreadNum; t++ {
		go func(tIdx uint64) {
			defer wg.Done()
			startRow := tIdx * rowsPerThread
			endRow := startRow + rowsPerThread
			if endRow > DBSize {
				endRow = DBSize
			}

			for r := startRow; r < endRow; r++ {
				// 1. Select Partition: Round-Robin (Load Balance)
				p := r % PartitionNum
				
				// 2. Select Offset: Scrambled (Chunk Balance)
				// We permute the logical offset (r/P) using the coprime key
				logicalOffset := r / PartitionNum
				scrambledOffset := (logicalOffset * offsetKey) % PartitionSize

				// Calculate exact memory location
				destOffset := (p*PartitionSize + scrambledOffset) * DBEntrySize
				srcOffset := r * DBEntrySize

				if destOffset+DBEntrySize <= uint64(len(partitionedDB)) {
					copy(partitionedDB[destOffset:destOffset+DBEntrySize], rawDB[srcOffset:srcOffset+DBEntrySize])
				}
			}
		}(t)
	}
	wg.Wait()

	subPIR := make([]*PianoPIR, PartitionNum)

	for i := uint64(0); i < PartitionNum; i++ {
		chunkLen := PartitionSize * DBEntrySize
		chunkStart := i * PartitionSize * DBEntrySize
		subPIR[i] = NewPianoPIR(PartitionSize, DBEntryByteNum, partitionedDB[chunkStart:chunkStart+chunkLen], FailureProbLog2)
	}

	return &SimpleBatchPianoPIR{
		config:                 config,
		subPIR:                 subPIR,
		offsetKey:              offsetKey,
		FinishedBatchNum:       0,
		QueriesMadeInPartition: 0,
	}
}

func (p *SimpleBatchPianoPIR) PrintInfo() {
	fmt.Printf("-----------BatchPIR config --------\n")
	DBSizeInBytes := float64(p.config.DBSize) * float64(p.config.DBEntryByteNum)
	fmt.Printf("DB size in MB = %v\n", DBSizeInBytes/1024/1024)
	fmt.Printf("DBSize: %v, DBEntryByteNum: %v, BatchSize: %v, PartitionNum: %v, PartitionSize: %v, ThreadNum: %v, FailureProbLog2: %v\n", p.config.DBSize, p.config.DBEntryByteNum, p.config.BatchSize, p.config.PartitionNum, p.config.PartitionSize, p.config.ThreadNum, p.config.FailureProbLog2)
	maxQuery := p.subPIR[0].client.MaxQueryNum / QueryPerPartition
	fmt.Printf("max query num = %v\n", maxQuery)
	fmt.Printf("max query per chunk = %v\n", p.subPIR[0].client.maxQueryPerChunk)
	fmt.Printf("total storage = %v MB\n", p.LocalStorageSize()/1024/1024)
	fmt.Printf("comm cost per batch = %v KB\n", p.CommCostPerBatchOnline()/1024)
	fmt.Printf("amortized preprocessing comm cost = %v KB\n", float64(DBSizeInBytes)/float64(maxQuery)/1024)
	fmt.Printf("total amortized comm cost = %v KB\n", float64(DBSizeInBytes)/float64(maxQuery)/1024+float64(p.CommCostPerBatchOnline())/1024)
	fmt.Printf("-----------------------------\n")
}

func (p *SimpleBatchPianoPIR) RecordStats(prepTime float64) {
	p.preprocessingTime = prepTime
	p.localStorage = uint64(p.LocalStorageSize())                 // bytes
	p.commCostPerBatchOnline = uint64(p.CommCostPerBatchOnline()) // bytes
	p.SupportBatchNum = p.subPIR[0].client.MaxQueryNum / QueryPerPartition
	DBSizeInBytes := float64(p.config.DBSize) * float64(p.config.DBEntryByteNum)
	p.commCostPerBatchOffline = uint64(float64(DBSizeInBytes) / float64(p.SupportBatchNum)) // bytes
}

func (p *SimpleBatchPianoPIR) Preprocessing() {
	p.PrintInfo()

	p.FinishedBatchNum = 0
	p.QueriesMadeInPartition = 0
	startTime := time.Now()

	var wg sync.WaitGroup
	wg.Add(int(p.config.ThreadNum))

	perThreadPartitionNum := (p.config.PartitionNum + p.config.ThreadNum - 1) / p.config.ThreadNum

	for tid := uint64(0); tid < p.config.ThreadNum; tid++ {
		go func(tid uint64) {
			defer wg.Done()
			start := tid * perThreadPartitionNum
			end := min(uint64((tid+1)*perThreadPartitionNum), p.config.PartitionNum)
			for i := start; i < end; i++ {
				p.subPIR[i].Preprocessing()
			}
		}(tid)
	}

	wg.Wait()

	endTime := time.Now()
	prepTime := endTime.Sub(startTime).Seconds()
	log.Printf("Preprocessing time = %v\n", endTime.Sub(startTime))

	p.RecordStats(prepTime)
}

func (p *SimpleBatchPianoPIR) DummyPreprocessing() {
	p.PrintInfo()
	for i := uint64(0); i < p.config.PartitionNum; i++ {
		p.subPIR[i].DummyPreprocessing()
	}
	log.Printf("Skipping Prep")
	p.RecordStats(0)
}

func (p *SimpleBatchPianoPIR) Query(idx []uint64) ([][]uint64, error) {

	// COMPREHENSIVE DIAGNOSTIC: Track where all-zeros come from
	failureReasons := make(map[string]int)
	totalRealQueries := 0
	totalPaddingQueries := 0
	responsesStored := 0
	allZeroResponses := 0
	missingResponses := 0

	queryNumToMake := (len(idx) + int(p.config.PartitionNum) - 1) / int(p.config.PartitionNum)
	partitionQueries := make([][]uint64, p.config.PartitionNum)
	
	// Helper struct to match responses back to original requests
	// Note: We cannot easily invert the hash, so we store the context
	type reqCtx struct {
		partitionID uint64
		scrambledOffset uint64
	}
	
	// Map LogicalID -> Scrambled Location
	reqMap := make(map[uint64]reqCtx)

	for _, id := range idx {
		partID := id % p.config.PartitionNum
		
		logicalOffset := id / p.config.PartitionNum
		scrambledOffset := (logicalOffset * p.offsetKey) % p.config.PartitionSize
		
		partitionQueries[partID] = append(partitionQueries[partID], scrambledOffset)
		reqMap[id] = reqCtx{partID, scrambledOffset}
	}

	// We need to look up responses by (PartID, ScrambledOffset)
	// Combine them into a unique key for the map: (part << 32) | offset
	// Assuming offset fits in 32 bits (4B * 8B = 32GB partition size limit)
	responses := make(map[uint64][]uint64)

	for i := uint64(0); i < p.config.PartitionNum; i++ {
		actualQueries := partitionQueries[i]
		padCount := 0
		if len(actualQueries) < queryNumToMake {
			padCount = queryNumToMake - len(actualQueries)
			for k := 0; k < padCount; k++ {
				partitionQueries[i] = append(partitionQueries[i], 0) // Valid dummy
			}
		}
		totalPaddingQueries += padCount
		totalRealQueries += len(actualQueries)

		for j := 0; j < len(partitionQueries[i]); j++ {
			isReal := true
			if j >= len(actualQueries) {
				isReal = false
			}
			
			offset := partitionQueries[i][j]
			val, err := p.subPIR[i].Query(offset, isReal)

			// Track if this is an all-zero response
			isAllZero := true
			for _, v := range val {
				if v != 0 {
					isAllZero = false
					break
				}
			}

			// Retry logic for safety
			if err != nil {
				// DIAGNOSTIC: Track failure reason
				if strings.Contains(err.Error(), "DIAG_MAXQUERYNUM") {
					failureReasons["MaxQueryNum"]++
					fmt.Printf("[DIAG] Error caught in batch: %s\n", err.Error())
				} else if strings.Contains(err.Error(), "DIAG_CHUNKLIMIT") {
					failureReasons["ChunkLimit"]++
					fmt.Printf("[DIAG] Error caught in batch: %s\n", err.Error())
				} else if strings.Contains(err.Error(), "DIAG_NOHINT") {
					failureReasons["NoHint"]++
					fmt.Printf("[DIAG] Error caught in batch: %s\n", err.Error())
				} else if strings.Contains(err.Error(), "QUERY_OUT_OF_BOUNDS") {
					failureReasons["OutOfBounds"]++
					fmt.Printf("[CRITICAL] Out-of-bounds error in batch: %s\n", err.Error())
				} else {
					failureReasons["Other"]++
					fmt.Printf("[DIAG] Other error caught in batch: %s\n", err.Error())
				}
				
				p.Preprocessing()
				val, err = p.subPIR[i].Query(offset, isReal)
				if err != nil {
					// Hard failure after retry
					if isReal {
						// Don't store failed real queries as zeros - skip them
						fmt.Printf("[REAL_QUERY_FAILED] Partition=%d, offset=%d will not be stored (failed after retry)\n", i, offset)
						continue
					} else {
						// Padding query failed - use zeros
						val = make([]uint64, p.config.DBEntrySize)
					}
				}
			}
			
			if isReal {
				// Key = (Partition << 48) | Offset
				// Support larger offsets
				key := (i << 48) | offset
				responses[key] = val
				responsesStored++
				
				// Track if this response is all-zeros
				if isAllZero {
					allZeroResponses++
					// Enhanced diagnostic: log all-zero responses for real queries
					fmt.Printf("[PARTITION_ZERO] Partition=%d, Offset=%d (real_query_idx=%d/%d), isAllZero=true\n", 
						i, offset, j, len(actualQueries))
				}
			}
		}
	}

	ret := make([][]uint64, len(idx))
	for i, id := range idx {
		ctx := reqMap[id]
		key := (ctx.partitionID << 48) | ctx.scrambledOffset
		
		if val, ok := responses[key]; ok {
			ret[i] = val
		} else {
			ret[i] = make([]uint64, p.config.DBEntrySize)
			missingResponses++
		}
	}

	if p.QueriesMadeInPartition >= p.subPIR[0].client.MaxQueryNum-2 {
		fmt.Printf("Redo preprocessing. Made %v batches\n", p.FinishedBatchNum)
		p.Preprocessing()
	} else {
		p.FinishedBatchNum += uint64(len(idx) / int(p.config.BatchSize))
		p.QueriesMadeInPartition += uint64(queryNumToMake)
	}

	// DIAGNOSTIC: Report failure reason distribution AND zero summary
	if len(failureReasons) > 0 || allZeroResponses > 0 || missingResponses > 0 {
		fmt.Printf("[DIAG_SUMMARY] Batch query completed:\n")
		fmt.Printf("[DIAG_SUMMARY]   Real queries: %d, Padding queries: %d\n", totalRealQueries, totalPaddingQueries)
		fmt.Printf("[DIAG_SUMMARY]   Responses stored: %d, All-zero responses: %d, Missing responses: %d\n", responsesStored, allZeroResponses, missingResponses)
		if len(failureReasons) > 0 {
			fmt.Printf("[DIAG_SUMMARY]   Failure Distribution:\n")
			totalFailures := 0
			for reason, count := range failureReasons {
				totalFailures += count
				fmt.Printf("[DIAG_SUMMARY]     %s: %d\n", reason, count)
			}
			fmt.Printf("[DIAG_SUMMARY]     TOTAL FAILURES: %d\n", totalFailures)
		}
	}

	return ret, nil
}

func (p *SimpleBatchPianoPIR) LocalStorageSize() float64 {
	ret := float64(0)
	for i := uint64(0); i < p.config.PartitionNum; i++ {
		ret += p.subPIR[i].LocalStorageSize()
	}
	return ret
}

func (p *SimpleBatchPianoPIR) CommCostPerBatchOnline() uint64 {
	ret := float64(0)
	for i := uint64(0); i < p.config.PartitionNum; i++ {
		ret += p.subPIR[i].CommCostPerQuery() * float64(QueryPerPartition)
	}
	return uint64(ret)
}

func (p *SimpleBatchPianoPIR) CommCostPerBatchOffline() uint64 {
	return p.commCostPerBatchOffline
}

func (p *SimpleBatchPianoPIR) PreprocessingTime() float64 {
	return p.preprocessingTime
}

func (p *SimpleBatchPianoPIR) Config() *SimpleBatchPianoPIRConfig {
	return p.config
}

func min(a, b uint64) uint64 {
	if a < b {
		return a
	}
	return b
}