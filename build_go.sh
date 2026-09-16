export GOROOT="/home/dblackle/go/pkg/mod/golang.org/toolchain@v0.0.1-go1.24.5.linux-amd64"
export PATH="$GOROOT/bin:$PATH"
export GOTOOLCHAIN=local

echo "Tidying modules..."
go mod tidy

echo "Compiling the binary..."
go build -v -o bm25-search ./cmd
