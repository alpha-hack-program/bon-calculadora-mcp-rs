.PHONY: all clean build-mcp build-http pack-mcp pack-http test-http

all: build-all

# Build MCP server (streamable-http)
build-mcp:
	cargo build --release --bin mcp_server

# Build SSE server (sse)
build-sse:
	cargo build --release --bin sse_server

# Build stdio server (stdio)
build-stdio:
	cargo build --release --bin stdio_server

# Build all servers
build-all: build-mcp build-sse build-stdio

# Pack MCP server for Claude Desktop
pack: build-stdio
	@echo "Packing MCP server for Claude Desktop..."
	chmod +x ./target/release/stdio_server
	zip -rX bon-calculadora-mcp-server.dxt -j dxt/manifest.json ./target/release/stdio_server

# Test SSE server locally
test-sse: build-sse
	@echo "🧪 Testing SSE server..."
	@echo ""
	RUST_LOG=debug ./target/release/sse_server

# Test MCP server locally
test-mcp: build-mcp
	@echo "🧪 Testing MCP server..."
	@echo ""
	RUST_LOG=debug ./target/release/mcp_server
	
clean:
	rm -f *.dxt *.zip
	cargo clean

proxy:
	mitmweb -p 8888 --mode reverse:http://localhost:8001 --web-port 8081

inspector:
	npx @modelcontextprotocol/inspector

sgw-sse: build-stdio
	npx -y supergateway \
    --stdio "./target/release/calculator_stdio" \
    --port 8001 --baseUrl http://localhost:8001 \
    --ssePath /sse --messagePath /message

sgw-mcp: build-stdio
	npx -y supergateway \
	--stdio "./target/release/calculator_stdio" \
    --outputTransport streamableHttp \
    --port 8001 --baseUrl http://localhost:8001

test:
	@echo "Running all tests..."
	cargo test

help:
	@echo "Usage:"
	@echo "  make all           - Build both MCP and HTTP servers"
	@echo "  make build-mcp    - Build MCP server (streamable-http)"
	@echo "  make build-sse    - Build SSE server"
	@echo "  make build-stdio  - Build stdio server"
	@echo "  make build-all    - Build all servers"
	@echo "  make pack         - Pack MCP server for Claude Desktop"
	@echo "  make test-sse     - Test SSE server locally"
	@echo "  make test-mcp     - Test MCP server locally"
	@echo "  make clean        - Clean build artifacts"
	@echo "  make proxy        - Start mitmproxy for debugging"
	@echo "  make inspector    - Start Model Context Protocol Inspector"
	@echo "  make sgw-sse      - Start Supergateway for SSE server"
	@echo "  make sgw-mcp      - Start Supergateway for MCP server"
	@echo "  make test         - Run all tests"
	@echo "  make help          - Show this help message"