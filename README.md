# BM25 Tree

## How to run

### Step 1: Download the data
```bash
# clone this code branch
git clone https://github.com/sonnguyenasu/bm25-tree
git checkout ablation

# download the msmarco indexed data for stage 1 and 2
wget -O bm25data.zip https://www.dropbox.com/scl/fi/8lz9a9fhao389r3dva2q1/bm25tree_data.zip\?rlkey\=3oqhu4iuorwl6kupb406dw8o2\&st\=lxvpls6f\&dl\=0

# download the embeddings and permutation for stage 3 for different settings
wget -O bm25exp.zip https://www.dropbox.com/scl/fi/v270bpyaeuba6jphfct2d/bm25tree-exp.zip\?rlkey\=u3k51pxcgvjfidnk19riqafy8\&st\=3okreb51\&dl\=0

# unzip
unzip bm25data.zip #save to data
unzip bm25exp.zip #save to exp_setup
```

### Step 2: Run the code
```bash
./run_go.sh
```
