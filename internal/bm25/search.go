package bm25

import (
	"fmt"
	"sort"
	"strings"
)

// Round1BeamPrecomputed performs beam search using precomputed stage-1 database with batch PIR queries
func Round1BeamPrecomputed(layout *LayoutWithStats, queryTerms []string, L int, db *Stage1PIRDB) []int {
	return Round1BeamPrecomputedWithWorkTerms(layout, queryTerms, queryTerms, L, db, false)
}

// Round1BeamPrecomputedWithWorkTerms performs beam search and can optionally pad PIR workload
// using workTerms (e.g., padded query terms) without affecting scoring.
func Round1BeamPrecomputedWithWorkTerms(layout *LayoutWithStats, queryTerms []string, workTerms []string, L int, db *Stage1PIRDB, constantPIRWork bool) []int {
	//fmt.Println("Enter Round1BeamPrecomputed")
	frontier := []int{1} // Always start at root
	H := layout.Height()
	r := db.R
	totalScoringRequests := 0
	totalTargetRequests := 0
	totalDummyRequests := 0
	if len(workTerms) == 0 {
		workTerms = queryTerms
	}

	_, workPlan := buildStage1WorkPlan(db, queryTerms, workTerms)
	if len(workPlan) == 0 {
		return []int{}
	}

	// Loop through each level of the tree
	for level := 0; level < H; level++ {
		requests, rowIndices, scoringRequests, dummyRequests := buildStage1ExactRequests(db, frontier, workPlan)
		if len(requests) == 0 {
			break
		}

		totalScoringRequests += scoringRequests
		totalDummyRequests += dummyRequests
		totalTargetRequests += len(requests)

		responses := queryStage1Rows(db, rowIndices)

		// Step 3: Accumulate child scores using responses
		childScores := make(map[int]int)
		for i, req := range requests {
			if !req.useForScore {
				continue
			}
			parentNodeID := req.parentNodeID

			if i >= len(responses) {
				continue
			}
			scoreRow := responses[i]
			if len(scoreRow) == 0 {
				continue // Skip if no data
			}

			// Add scores to all 'r' children
			for j := 0; j < r && j < len(scoreRow); j++ {
				childNodeID := parentNodeID*r + j
				childScores[childNodeID] += int(scoreRow[j])
			}
		}

		// Debug: print stats for this level
		//fmt.Printf("Round1 level %d: requests=%d retrieved=%d childScores=%d\n", level, len(requests), retrieved, len(childScores))

		if len(childScores) == 0 {
			break
		}

		// Sort children by score
		type scoreNode struct {
			nodeID int
			score  int
		}
		sortedChildren := make([]scoreNode, 0, len(childScores))
		for nodeID, score := range childScores {
			sortedChildren = append(sortedChildren, scoreNode{nodeID, score})
		}
		sort.Slice(sortedChildren, func(i, j int) bool {
			return sortedChildren[i].score > sortedChildren[j].score
		})

		// Set new frontier (top L node_ids)
		frontier = make([]int, 0, L)
		for i := 0; i < L && i < len(sortedChildren); i++ {
			frontier = append(frontier, sortedChildren[i].nodeID)
		}
	}

	if constantPIRWork {
		fmt.Printf("[CONST_PIR] Stage1: queried=%d target=%d scoring=%d dummy=%d\n", totalTargetRequests, totalTargetRequests, totalScoringRequests, totalDummyRequests)
	}

	return frontier
}

// Round2BMWPrecomputed performs BMW algorithm using precomputed stage-2 database with batch PIR queries
func Round2BMWPrecomputed(
	layout *LayoutWithStats,
	leafNodes []int,
	queryTerms []string,
	s int,
	kCandidates int,
	pre *Stage2Precomputed,
) []HitSubBlock {
	return Round2BMWPrecomputedWithWorkTerms(layout, leafNodes, queryTerms, queryTerms, s, kCandidates, pre, false)
}

// Round2BMWPrecomputedWithWorkTerms performs BMW and can optionally pad PIR workload
// using workTerms (e.g., padded query terms) without affecting scoring.
func Round2BMWPrecomputedWithWorkTerms(
	layout *LayoutWithStats,
	leafNodes []int,
	queryTerms []string,
	workTerms []string,
	s int,
	kCandidates int,
	pre *Stage2Precomputed,
	constantPIRWork bool,
) []HitSubBlock {
	if pre.S != s {
		panic(fmt.Sprintf("Precomputed s=%d does not match requested s=%d", pre.S, s))
	}
	r := pre.R
	if len(workTerms) == 0 {
		workTerms = queryTerms
	}

	// Step 1: Perform batch PIR query for all leaf nodes and all terms at once
	// This collects all required IDs upfront: map[leafNodeID][]int (per-leaf bounds)
	var sumsByLeaf map[int][]int
	if constantPIRWork {
		acc, scoringRequests, dummyRequests := sumBoundsForTermsWithPIRExact(pre, queryTerms, workTerms, leafNodes)
		sumsByLeaf = acc
		targetRequests := len(leafNodes) * len(workTerms)
		fmt.Printf("[CONST_PIR] Stage2: queried=%d target=%d scoring=%d dummy=%d\n", targetRequests, targetRequests, scoringRequests, dummyRequests)
	} else {
		sumsByLeaf = pre.SumBoundsForTermsWithPIR(queryTerms, leafNodes)
	}

	var hits []HitSubBlock
	var totalDocs int

	// Step 2: Expand each leaf into sub-blocks and attach summed scores
	for _, node := range leafNodes {
		a, b := layout.NodeToDocRange(node)
		if a >= b {
			continue // Skip invalid ranges
		}

		vec, ok := sumsByLeaf[node]
		if !ok {
			continue // Skip if no data for this leaf
		}

		// Create sub-blocks
		for j := 0; j < r; j++ {
			start := a + j*s
			if start >= b {
				break
			}
			end := min(b, start+s)

			// Score: divide by scale to get back to approx float UB
			scoreUB := float64(vec[j]) / pre.Scale

			if scoreUB <= 0.0 {
				continue
			}

			hits = append(hits, HitSubBlock{
				Start:   start,
				End:     end,
				ScoreUB: scoreUB,
			})
			totalDocs += end - start
		}
	}

	// Global top-k by score
	sort.Slice(hits, func(i, j int) bool {
		return hits[i].ScoreUB > hits[j].ScoreUB
	})

	// Keep top k_candidates sub-blocks for Stage 3 reranking
	// With default B=32, s=8: we get 200 leaf nodes × 4 sub-blocks = 800 candidates
	// Keep top 200 for Stage 3: 200 × s(=8) = 1,600 documents
	if kCandidates > 0 && len(hits) > kCandidates {
		hits = hits[:kCandidates]
	}

	return hits
}

func issueDummyPIRQueriesStage1(db *Stage1PIRDB, count int) {
	if count <= 0 || db == nil || db.pir == nil {
		return
	}
	idx := make([]uint64, count)
	_, _ = db.pir.Query(idx)
}

func issueDummyPIRQueriesStage2(pre *Stage2Precomputed, count int) {
	if count <= 0 || pre == nil || pre.pir == nil {
		return
	}
	idx := make([]uint64, count)
	_, _ = pre.pir.Query(idx)
}

type stage1WorkTerm struct {
	termID      int
	useForScore bool
}

func buildStage1WorkPlan(db *Stage1PIRDB, queryTerms []string, workTerms []string) ([]int, []stage1WorkTerm) {
	if db == nil {
		return nil, nil
	}

	remainingRealCounts := make(map[string]int)
	var realTermIDs []int
	for _, term := range queryTerms {
		tid, ok := db.Vocab[term]
		if !ok {
			tid, ok = db.Vocab[strings.ToLower(term)]
		}
		if ok {
			realTermIDs = append(realTermIDs, tid)
			remainingRealCounts[strings.ToLower(term)]++
		}
	}

	var plan []stage1WorkTerm
	for _, term := range workTerms {
		tid, ok := db.Vocab[term]
		if !ok {
			tid, ok = db.Vocab[strings.ToLower(term)]
		}
		key := strings.ToLower(term)
		useForScore := false
		if ok && remainingRealCounts[key] > 0 {
			useForScore = true
			remainingRealCounts[key]--
		}
		if !ok {
			tid = -1
		}
		plan = append(plan, stage1WorkTerm{termID: tid, useForScore: useForScore})
	}

	return realTermIDs, plan
}

func extractDummyTerms(queryTerms []string, workTerms []string) []string {
	remainingRealCounts := make(map[string]int)
	for _, term := range queryTerms {
		remainingRealCounts[strings.ToLower(term)]++
	}

	var dummyTerms []string
	for _, term := range workTerms {
		key := strings.ToLower(term)
		if remainingRealCounts[key] > 0 {
			remainingRealCounts[key]--
			continue
		}
		dummyTerms = append(dummyTerms, term)
	}

	return dummyTerms
}

type stage1ExactRequest struct {
	parentNodeID int
	rowIdx       uint64
	useForScore  bool
}

func buildStage1ExactRequests(db *Stage1PIRDB, frontier []int, workPlan []stage1WorkTerm) ([]stage1ExactRequest, []uint64, int, int) {
	requests := make([]stage1ExactRequest, 0, len(frontier)*len(workPlan))
	rowIndices := make([]uint64, 0, len(frontier)*len(workPlan))
	scoringRequests := 0
	dummyRequests := 0

	for _, parentNodeID := range frontier {
		for _, plan := range workPlan {
			rowIdx := uint64(0)
			useForScore := false

			if plan.termID >= 0 {
				if termMap, ok := db.LookupTable[plan.termID]; ok {
					if idx, ok := termMap[parentNodeID]; ok {
						rowIdx = uint64(idx)
						useForScore = plan.useForScore
					} else {
						dummyRequests++
					}
				} else {
					dummyRequests++
				}
			} else {
				dummyRequests++
			}

			if useForScore {
				scoringRequests++
			}

			requests = append(requests, stage1ExactRequest{parentNodeID: parentNodeID, rowIdx: rowIdx, useForScore: useForScore})
			rowIndices = append(rowIndices, rowIdx)
		}
	}

	return requests, rowIndices, scoringRequests, dummyRequests
}

func queryStage1Rows(db *Stage1PIRDB, rowIndices []uint64) [][]byte {
	if len(rowIndices) == 0 {
		return nil
	}

	if len(rowIndices) > 0 && len(rowIndices) <= 3 {
		fmt.Printf("[DEBUG] Stage1: Executing PIR batch query with %d row indices: %v\n", len(rowIndices), rowIndices)
	} else if len(rowIndices) > 3 {
		fmt.Printf("[DEBUG] Stage1: Executing PIR batch query with %d row indices (first 3): %v\n", len(rowIndices), rowIndices[:3])
	}
	fmt.Printf("[DEBUG] Stage1: Executing PIR batch query with %d row indices\n", len(rowIndices))

	out := make([][]byte, len(rowIndices))

	if db != nil && db.pir != nil {
		responses, err := db.pir.Query(rowIndices)
		if err == nil {
			fmt.Printf("[DEBUG] Stage1: PIR query succeeded, got %d responses\n", len(responses))
			for i, words := range responses {
				out[i] = convertUint64ToBytes(words)
			}
			return out
		}
		fmt.Printf("[DEBUG] Stage1 batch query error: %v, falling back to direct read\n", err)
	}

	for i, rowIdx := range rowIndices {
		out[i] = db.readRowDirectByte(int(rowIdx))
	}
	return out
}

type stage2WorkTerm struct {
	termID      int
	useForScore bool
}

type stage2ExactRequest struct {
	nodeID      int
	rowIdx      uint64
	useForScore bool
}

func buildStage2WorkPlan(pre *Stage2Precomputed, queryTerms []string, workTerms []string) []stage2WorkTerm {
	remainingRealCounts := make(map[string]int)
	for _, term := range queryTerms {
		key := strings.ToLower(term)
		remainingRealCounts[key]++
	}

	plan := make([]stage2WorkTerm, 0, len(workTerms))
	for _, term := range workTerms {
		tid, ok := pre.Vocab[term]
		if !ok {
			tid, ok = pre.Vocab[strings.ToLower(term)]
		}

		key := strings.ToLower(term)
		useForScore := false
		if ok && remainingRealCounts[key] > 0 {
			useForScore = true
			remainingRealCounts[key]--
		}

		if !ok {
			tid = -1
		}
		plan = append(plan, stage2WorkTerm{termID: tid, useForScore: useForScore})
	}

	return plan
}

func sumBoundsForTermsWithPIRExact(pre *Stage2Precomputed, queryTerms []string, workTerms []string, leafNodes []int) (map[int][]int, int, int) {
	acc := make(map[int][]int)
	for _, ln := range leafNodes {
		acc[ln] = make([]int, pre.R)
	}

	if len(leafNodes) == 0 || len(workTerms) == 0 {
		return acc, 0, 0
	}

	plan := buildStage2WorkPlan(pre, queryTerms, workTerms)
	if len(plan) == 0 {
		return acc, 0, 0
	}

	requests := make([]stage2ExactRequest, 0, len(leafNodes)*len(plan))
	rowIndices := make([]uint64, 0, len(leafNodes)*len(plan))
	scoringRequests := 0
	dummyRequests := 0

	for _, nodeID := range leafNodes {
		for _, p := range plan {
			rowIdx := uint64(0)
			useForScore := false

			if p.termID >= 0 {
				if termMap, ok := pre.LookupTable[p.termID]; ok {
					if idx, ok := termMap[nodeID]; ok {
						rowIdx = uint64(idx)
						useForScore = p.useForScore
					} else {
						dummyRequests++
					}
				} else {
					dummyRequests++
				}
			} else {
				dummyRequests++
			}

			if useForScore {
				scoringRequests++
			}

			requests = append(requests, stage2ExactRequest{nodeID: nodeID, rowIdx: rowIdx, useForScore: useForScore})
			rowIndices = append(rowIndices, rowIdx)
		}
	}

	if len(rowIndices) > 0 && len(rowIndices) <= 3 {
		fmt.Printf("[DEBUG] Stage2: Executing PIR batch query with %d row indices: %v\n", len(rowIndices), rowIndices)
	} else if len(rowIndices) > 3 {
		fmt.Printf("[DEBUG] Stage2: Executing PIR batch query with %d row indices (first 3): %v\n", len(rowIndices), rowIndices[:3])
	}
	fmt.Printf("[DEBUG] Stage2: Executing PIR batch query with %d row indices\n", len(rowIndices))

	var responses [][]uint64
	if pre.pir != nil {
		res, err := pre.pir.Query(rowIndices)
		if err == nil {
			responses = res
			fmt.Printf("[DEBUG] Stage2: PIR query succeeded, got %d responses\n", len(responses))
		} else {
			fmt.Printf("[DEBUG] Stage2 batch query error: %v, falling back to direct read\n", err)
		}
	}

	if len(responses) == 0 {
		responses = make([][]uint64, len(rowIndices))
		for i, idx := range rowIndices {
			responses[i] = pre.readRowDirectUint64(idx)
		}
	}

	for i, req := range requests {
		if !req.useForScore {
			continue
		}
		if i >= len(responses) {
			continue
		}
		rowBytes := convertUint64ToBytes(responses[i])
		for j := 0; j < pre.R && j < len(rowBytes); j++ {
			acc[req.nodeID][j] += int(rowBytes[j])
		}
	}

	return acc, scoringRequests, dummyRequests
}

func countStage2ActualRequests(pre *Stage2Precomputed, terms []string, leafNodes []int) int {
	if pre == nil || len(terms) == 0 || len(leafNodes) == 0 {
		return 0
	}

	termIDs := make([]int, 0, len(terms))
	for _, term := range terms {
		tid, ok := pre.Vocab[term]
		if !ok {
			tid, ok = pre.Vocab[strings.ToLower(term)]
		}
		if ok {
			termIDs = append(termIDs, tid)
		}
	}

	if len(termIDs) == 0 {
		return 0
	}

	count := 0
	for _, termID := range termIDs {
		if termMap, ok := pre.LookupTable[termID]; ok {
			for _, nodeID := range leafNodes {
				if _, ok := termMap[nodeID]; ok {
					count++
				}
			}
		}
	}
	return count
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
