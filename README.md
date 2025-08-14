# BON Calculadora MCP Server

> **Example Model Context Protocol (MCP) Server demonstrating leave assistance evaluation based on fictional Navarra 2025 regulations**

[![CI Pipeline](https://github.com/alpha-hack-program/bon-calculadora-mcp-rs/actions/workflows/ci.yml/badge.svg)](https://github.com/alpha-hack-program/bon-calculadora-mcp-rs/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Rust](https://img.shields.io/badge/rust-%23000000.svg?style=flat&logo=rust&logoColor=white)](https://www.rust-lang.org/)

An example Model Context Protocol (MCP) server developed in Rust that demonstrates how to evaluate complex business rules using the ZEN Engine decision engine. This project serves as a reference implementation for building MCP servers with rule-based decision systems.

## ⚠️ **DISCLAIMER**

**This is a demonstration/example project only.** The regulations, amounts, and evaluation logic implemented here are fictional and created solely for educational and demonstration purposes. This software:

- **Should NOT be used for actual legal or administrative decisions**
- **Does NOT represent real Navarra government regulations**
- **Is NOT affiliated with any official government entity**
- **Serves as a technical example of MCP server implementation**

For real legal advice or official information about leave assistance, please consult official government sources and qualified legal professionals.

## 🎯 Features

- **5 Example Evaluation Scenarios**: Demonstrates implementation of complex rule sets (A-E)
- **Decision Engine Integration**: Shows how to use ZEN Engine for rule-based evaluation
- **Multiple Transport Protocols**: Examples of STDIO, SSE, and HTTP streamable implementations
- **Robust Input Validation**: Demonstrates JSON schema validation with detailed error handling
- **Production-Ready Containerization**: Example Docker/Podman setup for deployment
- **Claude Desktop Integration**: Example DXT packaging for MCP integration

## 📋 Example Assistance Scenarios (Fictional)

| Scenario | Description | Example Monthly Amount |
|----------|-------------|------------------------|
| **A** | Care for first-degree relative (illness/accident) | 725€ |
| **B** | Third child or more with newborn | 500€ |
| **C** | Adoption or foster care | 500€ |
| **D** | Multiple birth, adoption, or foster care | 500€ |
| **E** | Single-parent families | 500€ |

> **Note**: These scenarios and amounts are completely fictional and used only for demonstration purposes.

## 🚀 Quick Start

### Prerequisites

- Rust 1.70+ ([Install Rust](https://rustup.rs/))
- Cargo (included with Rust)

### Installation

```bash
# Clone the repository
git clone https://github.com/alpha-hack-program/bon-calculadora-mcp-rs.git
cd bon-calculadora-mcp-rs

# Build all servers
make build-all

# Or build individually
make build-sse      # SSE Server
make build-mcp      # MCP HTTP Server
make build-stdio    # STDIO Server for Claude
```

### Running

```bash
# SSE Server (recommended for development)
make test-sse

# MCP HTTP Server
make test-mcp

# Or directly
RUST_LOG=debug ./target/release/sse_server
```

## 🔧 Configuration

### Environment Variables

```bash
# Server configuration
HOST=127.0.0.1          # Bind address (0.0.0.0 for containers)
PORT=8001               # Server port
RUST_LOG=info           # Logging level (debug, info, warn, error)

# Or use BIND_ADDRESS directly
BIND_ADDRESS=127.0.0.1:8001
```

### Example Usage

```json
{
  "input": {
    "parentesco": "madre",
    "situacion": "enfermedad",
    "familia_monoparental": false,
    "numero_hijos": 2
  }
}
```

**Example Response:**
```json
{
  "output": {
    "supuesto": "A",
    "descripcion": "Care for first-degree relative (illness or accident)",
    "importe_mensual": 725,
    "tiene_derecho_potencial": true,
    "requisitos_adicionales": "The person must have been hospitalized..."
  }
}
```

> **Important**: This is example data for demonstration purposes only.

## 🐳 Containerization

### Build and Run

This requires `podman` or `docker`. Adapt `.env` to your needs.

```bash
# Build container image
./image.sh build

# Run locally
./image.sh run

# Run from remote registry
./image.sh push
./image.sh run-remote
```

### Environment Variables for Containers

```bash
# Production configuration
docker run -p 8001:8001 \
  -e HOST=0.0.0.0 \
  -e PORT=8001 \
  -e RUST_LOG=info \
  quay.io/atarazana/bon-calculadora-mcp-server:latest
```

## 📦 Claude Desktop Integration

### Packaging

```bash
# Create DXT package for Claude Desktop
make pack
```

### Example Claude Configuration

Drag and drop the `DXT` file into the `Settings->Extensions` dropping area.

> **Note**: This demonstrates MCP integration patterns and is not intended for production use with real data.

## 🧪 Testing

```bash
# Run all tests
make test
```

### Manual Testing Examples

Run the server: `make test-sse` or `./image.sh run`.

> This requires NodeJS 19+.

In another terminal.

```bash
make inspector
```

Then connect your browser to the suggest url given by the MCP inspector. Once there connect to `http://localhost:${PORT}/sse`

> `PORT` is set in `.env`

Connect and list tools, select the tool and use this JSON.

```json
{
    "parentesco": "hijo",
    "situacion": "parto",
    "familia_monoparental": true
}
```

## 🛠️ Development

### Available Commands

```bash
make help                    # Show help
make build-all              # Build all servers
make clean                  # Clean artifacts
make fmt                    # Format code
make lint                   # Run clippy
make audit                  # Security audit
make dev                    # Development server with auto-reload
```

### Project Structure

```
├── src/
│   ├── common/
│   │   ├── calculadora.rs      # MCP logic and decision engine
│   │   └── mod.rs
│   ├── sse_server.rs           # SSE Server
│   ├── mcp_server.rs           # MCP HTTP Server
│   └── stdio_server.rs         # STDIO Server
├── dxt/
│   └── manifest.json           # Claude Desktop manifest
├── Containerfile              # Container definition
├── Makefile                   # Build commands
└── container.sh               # Container management script
```

### Debug and Monitoring

```bash
# Debug proxy
make proxy                  # Start mitmproxy on port 8888

# MCP Inspector
make inspector              # Start MCP Inspector

# Supergateway for SSE
make sgw-sse               # STDIO -> SSE wrapping

# Supergateway for MCP
make sgw-mcp               # STDIO -> MCP HTTP wrapping
```

## 📚 API Reference

### Main Endpoint

**POST** `/message` - Example endpoint for rule evaluation

### Example Input Parameters

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `parentesco` | string | ✅ | Family relationship (padre, madre, hijo, hija, conyuge, pareja, esposo, esposa, mujer, marido) |
| `situacion` | string | ✅ | Care reason (parto, adopcion, acogimiento, enfermedad, accidente, etc.) |
| `familia_monoparental` | boolean | ✅ | Is it a single-parent family? |
| `numero_hijos` | number | ❌ | Number of children (optional, required for Scenario B) |

### Response

| Field | Type | Description |
|-------|------|-------------|
| `supuesto` | string | Applicable scenario letter (A-E) |
| `descripcion` | string | Scenario description |
| `importe_mensual` | number | Monthly amount in euros |
| `tiene_derecho_potencial` | boolean | Meets basic requirements? |
| `requisitos_adicionales` | string | Additional specific requirements |
| `errores` | array | List of validation errors |
| `advertencias` | array | Warnings and additional information |

## 🔒 Security

- **Input validation**: Strict JSON schemas
- **Non-root user**: Containers run as user `1001`
- **Security audit**: `cargo audit` in CI/CD
- **Minimal image**: Based on UBI 9 minimal

## 🤝 Contributing

1. Fork the project
2. Create feature branch (`git checkout -b feature/new-feature`)
3. Commit changes (`git commit -am 'Add new feature'`)
4. Push to branch (`git push origin feature/new-feature`)
5. Create Pull Request

### Guidelines

- Follow code style with `cargo fmt`
- Pass linting with `cargo clippy`
- Add tests for new functionality
- Update documentation as needed

## 📄 License

This project is licensed under the MIT License - see [LICENSE](LICENSE) for details.

## 🙋 Support

- **Issues**: [GitHub Issues](https://github.com/alpha-hack-program/bon-calculadora-mcp-rs/issues)
- **Documentation**: [Project Wiki](https://github.com/alpha-hack-program/bon-calculadora-mcp-rs/wiki)

## 🏷️ Tags

`mcp` `model-context-protocol` `rust` `calculator` `navarra` `excedencia` `zen-engine` `claude` `decision-engine`

---

**Developed with ❤️ by [Alpha Hack Group](https://github.com/alpha-hack-program)**