#!/bin/bash

# MCP Session Automation Script
# Handles session management for your MCP server

# SERVER_URL="http://localhost:8001/mcp"
SERVER_URL="http://localhost:8888/mcp"

# Function to initialize and get session ID
get_session_id() {
    echo "🔄 Getting new session ID..." >&2
    response=$(curl -s -X POST "$SERVER_URL" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json, text/event-stream" \
        -d '{"jsonrpc": "2.0", "method": "initialize", "id": 1, "params": {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "automation-script", "version": "1.0"}}}' \
        -D /tmp/mcp_headers.txt)
    
    # Extract session ID from headers
    session_id=$(grep -i "mcp-session-id:" /tmp/mcp_headers.txt | cut -d' ' -f2 | tr -d '\r\n')
    
    if [ -z "$session_id" ]; then
        echo "❌ Failed to get session ID" >&2
        echo "Response was: $response" >&2
        echo "Headers were:" >&2
        cat /tmp/mcp_headers.txt >&2
        return 1
    fi
    
    echo "✅ Got session ID: $session_id" >&2
    echo "Initialize response: $response" >&2
    echo "$session_id"
}

# Function to send initialized notification
send_initialized() {
    local session_id="$1"
    
    echo "📬 Sending initialized notification..." >&2
    response=$(curl -s -X POST "$SERVER_URL" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json, text/event-stream" \
        -H "mcp-session-id: $session_id" \
        -d '{"jsonrpc": "2.0", "method": "notifications/initialized"}')
    
    echo "Initialized response: $response" >&2
}
mcp_request() {
    local session_id="$1"
    local method="$2"
    local params="$3"
    local request_id="$4"
    
    if [ -z "$params" ]; then
        params_json=""
    else
        params_json=", \"params\": $params"
    fi
    
    echo "📡 Making request: $method"
    echo "Using session: $session_id"
    
    response=$(curl -s -X POST "$SERVER_URL" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json, text/event-stream" \
        -H "mcp-session-id: $session_id" \
        -d "{\"jsonrpc\": \"2.0\", \"method\": \"$method\", \"id\": $request_id$params_json}")
    
    echo "Raw response: $response"
    
    # Try to parse as JSON after removing SSE formatting
    cleaned_response=$(echo "$response" | sed 's/^data: //' | sed '/^id: /d')
    echo "Cleaned response: $cleaned_response"
    
    if echo "$cleaned_response" | jq '.' >/dev/null 2>&1; then
        echo "$cleaned_response" | jq '.'
    else
        echo "❌ Failed to parse JSON response"
        echo "Original: $response"
    fi
}

# Main automation function
run_mcp_sequence() {
    echo "🚀 Starting MCP automation sequence..."
    
    # Get session ID
    session_id=$(get_session_id)
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    # Send initialized notification (required after initialize)
    send_initialized "$session_id"
    
    echo ""
    echo "📋 Listing available tools..."
    mcp_request "$session_id" "tools/list" "" "2"
    
    echo ""
    echo "📚 Listing available resources (if any)..."
    mcp_request "$session_id" "resources/list" "" "3"
    
    echo ""
    echo "💡 Listing available prompts (if any)..."
    mcp_request "$session_id" "prompts/list" "" "4"
    
    echo ""
    echo "🧮 Testing calculator tools..."
    echo "Testing sum tool:"
    calc_params='{"name": "sum", "arguments": {"a": 5, "b": 3}}'
    mcp_request "$session_id" "tools/call" "$calc_params" "5"
    
    echo ""
    echo "Testing sub tool:"
    calc_params='{"name": "sub", "arguments": {"a": 10, "b": 4}}'
    mcp_request "$session_id" "tools/call" "$calc_params" "6"
    
    # Clean up
    rm -f /tmp/mcp_headers.txt
    
    echo ""
    echo "✨ Automation sequence complete!"
}

# Function for interactive mode
interactive_mode() {
    echo "🎯 Interactive MCP Mode"
    echo "Getting session..."
    session_id=$(get_session_id)
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    echo ""
    echo "Session ID: $session_id"
    echo "Enter MCP method calls (e.g., 'tools/list', 'tools/call', etc.)"
    echo "Type 'quit' to exit, 'new-session' for fresh session"
    echo ""
    
    request_id=10
    
    while true; do
        read -p "MCP> " method
        
        case "$method" in
            "quit"|"exit")
                echo "👋 Goodbye!"
                break
                ;;
            "new-session")
                session_id=$(get_session_id)
                if [ $? -ne 0 ]; then
                    echo "❌ Failed to get new session"
                    continue
                fi
                ;;
            "tools/list"|"resources/list"|"prompts/list")
                mcp_request "$session_id" "$method" "" "$request_id"
                ;;
            "tools/call")
                read -p "Tool name: " tool_name
                read -p "Arguments (JSON): " args
                params="{\"name\": \"$tool_name\", \"arguments\": $args}"
                mcp_request "$session_id" "$method" "$params" "$request_id"
                ;;
            *)
                if [ -n "$method" ]; then
                    read -p "Parameters (JSON, or press enter for none): " params
                    if [ -z "$params" ]; then
                        mcp_request "$session_id" "$method" "" "$request_id"
                    else
                        mcp_request "$session_id" "$method" "$params" "$request_id"
                    fi
                fi
                ;;
        esac
        
        request_id=$((request_id + 1))
        echo ""
    done
    
    # Clean up
    rm -f /tmp/mcp_headers.txt
}

# Check command line arguments
case "${1:-auto}" in
    "auto"|"sequence")
        run_mcp_sequence
        ;;
    "interactive"|"i")
        interactive_mode
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [mode]"
        echo "Modes:"
        echo "  auto|sequence    - Run automated sequence (default)"
        echo "  interactive|i    - Interactive mode"
        echo "  help            - Show this help"
        ;;
    *)
        echo "Unknown mode: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac