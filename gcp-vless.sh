#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Telegram Configuration
TELEGRAM_CHANNEL="https://t.me/cvw_cvw"
TELEGRAM_USERNAME="@iazcc"
DEFAULT_CHANNEL_NAME="CVW Channel"

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${CYAN}[SUCCESS]${NC} $1"
}

banner() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║               GCP V2Ray Deployer                 ║"
    echo "║              Telegram: $TELEGRAM_USERNAME        ║"
    echo "║              Channel: $TELEGRAM_CHANNEL          ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# Function to validate UUID format
validate_uuid() {
    local uuid_pattern='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    if [[ ! $1 =~ $uuid_pattern ]]; then
        error "Invalid UUID format: $1"
    fi
}

# Function to validate Telegram Bot Token
validate_bot_token() {
    local token_pattern='^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$'
    if [[ ! $1 =~ $token_pattern ]]; then
        error "Invalid Telegram Bot Token format"
    fi
}

# Function to validate Channel ID
validate_channel_id() {
    if [[ ! $1 =~ ^-?[0-9]+$ ]]; then
        error "Invalid Channel ID format"
    fi
}

# Function to validate Chat ID
validate_chat_id() {
    if [[ ! $1 =~ ^-?[0-9]+$ ]]; then
        error "Invalid Chat ID format"
    fi
}

# CPU selection function
select_cpu() {
    echo
    info "=== CPU Configuration ==="
    echo "1. 1 CPU Core"
    echo "2. 2 CPU Cores" 
    echo "3. 4 CPU Cores"
    echo "4. 8 CPU Cores"
    echo
    
    while true; do
        read -p "Select CPU cores (1-4) [default: 1]: " cpu_choice
        cpu_choice=${cpu_choice:-1}
        case $cpu_choice in
            1) CPU="1"; break ;;
            2) CPU="2"; break ;;
            3) CPU="4"; break ;;
            4) CPU="8"; break ;;
            *) echo "Invalid selection. Please enter 1-4." ;;
        esac
    done
    info "Selected CPU: $CPU core(s)"
}

# Memory selection function
select_memory() {
    echo
    info "=== Memory Configuration ==="
    
    case $CPU in
        1) echo "Recommended: 512Mi - 2Gi" ;;
        2) echo "Recommended: 1Gi - 4Gi" ;;
        4) echo "Recommended: 2Gi - 8Gi" ;;
        8) echo "Recommended: 4Gi - 16Gi" ;;
    esac
    echo
    
    echo "Memory Options:"
    echo "1. 512Mi"
    echo "2. 1Gi" 
    echo "3. 2Gi"
    echo "4. 4Gi"
    echo "5. 8Gi"
    echo "6. 16Gi"
    echo
    
    while true; do
        read -p "Select memory (1-6) [default: 3]: " memory_choice
        memory_choice=${memory_choice:-3}
        case $memory_choice in
            1) MEMORY="512Mi"; break ;;
            2) MEMORY="1Gi"; break ;;
            3) MEMORY="2Gi"; break ;;
            4) MEMORY="4Gi"; break ;;
            5) MEMORY="8Gi"; break ;;
            6) MEMORY="16Gi"; break ;;
            *) echo "Invalid selection. Please enter 1-6." ;;
        esac
    done
    info "Selected Memory: $MEMORY"
}

# Region selection function
select_region() {
    echo
    info "=== Region Selection ==="
    echo "1. us-central1 (Iowa, USA)"
    echo "2. us-west1 (Oregon, USA)"
    echo "3. us-east1 (South Carolina, USA)" 
    echo "4. europe-west1 (Belgium)"
    echo "5. asia-southeast1 (Singapore)"
    echo "6. asia-southeast2 (Indonesia)"
    echo "7. asia-northeast1 (Tokyo, Japan)"
    echo "8. asia-east1 (Taiwan)"
    echo
    
    while true; do
        read -p "Select region (1-8) [default: 1]: " region_choice
        region_choice=${region_choice:-1}
        case $region_choice in
            1) REGION="us-central1"; break ;;
            2) REGION="us-west1"; break ;;
            3) REGION="us-east1"; break ;;
            4) REGION="europe-west1"; break ;;
            5) REGION="asia-southeast1"; break ;;
            6) REGION="asia-southeast2"; break ;;
            7) REGION="asia-northeast1"; break ;;
            8) REGION="asia-east1"; break ;;
            *) echo "Invalid selection. Please enter 1-8." ;;
        esac
    done
    info "Selected region: $REGION"
}

# Protocol selection function
select_protocol() {
    echo
    info "=== Protocol Selection ==="
    echo "1. Trojan WS"
    echo "2. VLESS WS"
    echo "3. VLESS gRPC" 
    echo "4. VMess WS"
    echo
    
    while true; do
        read -p "Select protocol (1-4) [default: 1]: " protocol_choice
        protocol_choice=${protocol_choice:-1}
        case $protocol_choice in
            1) PROTOCOL="trojan"; break ;;
            2) PROTOCOL="vless"; break ;;
            3) PROTOCOL="vless-grpc"; break ;;
            4) PROTOCOL="vmess"; break ;;
            *) echo "Invalid selection. Please enter 1-4." ;;
        esac
    done
    info "Selected protocol: $PROTOCOL"
}

# Telegram destination selection
select_telegram_destination() {
    echo
    info "=== Telegram Destination ==="
    echo "1. Send to Channel"
    echo "2. Send to Bot private message"
    echo "3. Send to both Channel and Bot" 
    echo "4. Don't send to Telegram"
    echo
    
    while true; do
        read -p "Select destination (1-4) [default: 4]: " telegram_choice
        telegram_choice=${telegram_choice:-4}
        case $telegram_choice in
            1) 
                TELEGRAM_DESTINATION="channel"
                while true; do
                    read -p "Enter Telegram Channel ID: " TELEGRAM_CHANNEL_ID
                    if [[ -n "$TELEGRAM_CHANNEL_ID" ]]; then
                        validate_channel_id "$TELEGRAM_CHANNEL_ID"
                        break
                    else
                        warn "Channel ID cannot be empty"
                    fi
                done
                break 
                ;;
            2) 
                TELEGRAM_DESTINATION="bot"
                while true; do
                    read -p "Enter your Chat ID: " TELEGRAM_CHAT_ID
                    if [[ -n "$TELEGRAM_CHAT_ID" ]]; then
                        validate_chat_id "$TELEGRAM_CHAT_ID"
                        break
                    else
                        warn "Chat ID cannot be empty"
                    fi
                done
                break 
                ;;
            3) 
                TELEGRAM_DESTINATION="both"
                while true; do
                    read -p "Enter Telegram Channel ID: " TELEGRAM_CHANNEL_ID
                    if [[ -n "$TELEGRAM_CHANNEL_ID" ]]; then
                        validate_channel_id "$TELEGRAM_CHANNEL_ID"
                        break
                    else
                        warn "Channel ID cannot be empty"
                    fi
                done
                while true; do
                    read -p "Enter your Chat ID: " TELEGRAM_CHAT_ID
                    if [[ -n "$TELEGRAM_CHAT_ID" ]]; then
                        validate_chat_id "$TELEGRAM_CHAT_ID"
                        break
                    else
                        warn "Chat ID cannot be empty"
                    fi
                done
                break 
                ;;
            4) 
                TELEGRAM_DESTINATION="none"
                break 
                ;;
            *) echo "Invalid selection. Please enter 1-4." ;;
        esac
    done
}

# User input function
get_user_input() {
    echo
    info "=== Service Configuration ==="
    
    # Service Name
    while true; do
        read -p "Enter service name [default: v2ray-service]: " SERVICE_NAME
        SERVICE_NAME=${SERVICE_NAME:-"v2ray-service"}
        if [[ -n "$SERVICE_NAME" ]]; then
            break
        fi
    done
    
    # UUID
    while true; do
        read -p "Enter UUID [default: ba0e3984-ccc9-48a3-8074-b2f507f41ce8]: " UUID
        UUID=${UUID:-"ba0e3984-ccc9-48a3-8074-b2f507f41ce8"}
        validate_uuid "$UUID"
        break
    done
    
    # Telegram Bot Token
    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        while true; do
            read -p "Enter Telegram Bot Token: " TELEGRAM_BOT_TOKEN
            if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
                validate_bot_token "$TELEGRAM_BOT_TOKEN"
                break
            else
                warn "Bot token cannot be empty"
            fi
        done
    fi
    
    # Host Domain
    read -p "Enter host domain [default: m.googleapis.com]: " HOST_DOMAIN
    HOST_DOMAIN=${HOST_DOMAIN:-"m.googleapis.com"}
}

# Display configuration summary
show_config_summary() {
    echo
    success "=== Configuration Summary ==="
    echo "Project:     $(gcloud config get-value project 2>/dev/null || echo 'Not set')"
    echo "Region:      $REGION" 
    echo "Protocol:    $PROTOCOL"
    echo "Service:     $SERVICE_NAME"
    echo "Host Domain: $HOST_DOMAIN"
    echo "UUID:        $UUID"
    echo "CPU:         $CPU core(s)"
    echo "Memory:      $MEMORY"
    
    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        echo "Bot Token:   ${TELEGRAM_BOT_TOKEN:0:8}..."
        echo "Destination: $TELEGRAM_DESTINATION"
        if [[ "$TELEGRAM_DESTINATION" == "channel" || "$TELEGRAM_DESTINATION" == "both" ]]; then
            echo "Channel ID:  $TELEGRAM_CHANNEL_ID"
        fi
        if [[ "$TELEGRAM_DESTINATION" == "bot" || "$TELEGRAM_DESTINATION" == "both" ]]; then
            echo "Chat ID:     $TELEGRAM_CHAT_ID"
        fi
    else
        echo "Telegram:    Not configured"
    fi
    echo
    
    read -p "Proceed with deployment? (y/N) [default: y]: " confirm
    confirm=${confirm:-y}
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        info "Deployment cancelled"
        exit 0
    fi
}

# Validation functions
validate_prerequisites() {
    log "Validating prerequisites..."
    
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK."
    fi
    
    local PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
        error "No project configured. Run: gcloud config set project PROJECT_ID"
    fi
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
        error "Not authenticated. Run: gcloud auth login"
    fi
}

# Create configuration based on protocol
create_config() {
    local config_file="config.json"
    
    case $PROTOCOL in
        "trojan")
            cat > $config_file << EOF
{
  "inbounds": [
    {
      "port": 8080,
      "protocol": "trojan",
      "settings": {
        "clients": [
          {
            "password": "Trojan-2025",
            "level": 0
          }
        ],
        "fallbacks": []
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/tg-@iazcc"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF
            ;;
        "vless")
            cat > $config_file << EOF
{
  "inbounds": [
    {
      "port": 8080,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/tg-@iazcc"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF
            ;;
        "vless-grpc")
            cat > $config_file << EOF
{
  "inbounds": [
    {
      "port": 8080,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "level": 0
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "security": "none",
        "grpcSettings": {
          "serviceName": "vless-grpc-service"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF
            ;;
        "vmess")
            cat > $config_file << EOF
{
  "inbounds": [
    {
      "port": 8080,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "level": 0,
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/tg-@iazcc"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF
            ;;
    esac
    
    if [[ ! -f "$config_file" ]]; then
        error "Failed to create config.json"
    fi
    
    log "Created config.json for $PROTOCOL"
}

create_dockerfile() {
    cat > Dockerfile << 'EOF'
FROM v2fly/v2fly-core:latest

RUN apk add --no-cache curl

COPY config.json /etc/v2ray/config.json

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/tg-@iazcc || exit 1

CMD ["v2ray", "run", "-config", "/etc/v2ray/config.json"]
EOF

    if [[ ! -f "Dockerfile" ]]; then
        error "Failed to create Dockerfile"
    fi
    
    log "Created Dockerfile"
}

send_telegram_message() {
    local chat_id="$1"
    local message="$2"
    
    # Escape message for JSON
    message=$(echo "$message" | sed 's/"/\\"/g' | sed 's/\\n/\\\\n/g')
    
    local response=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d '{
            "chat_id": "'"$chat_id"'",
            "text": "'"$message"'",
            "parse_mode": "HTML",
            "disable_web_page_preview": true
        }' \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage")
    
    if [[ "$response" == "200" ]]; then
        return 0
    else
        return 1
    fi
}

send_deployment_notification() {
    local message="$1"
    local success_count=0
    
    case $TELEGRAM_DESTINATION in
        "channel")
            if send_telegram_message "$TELEGRAM_CHANNEL_ID" "$message"; then
                log "✅ Sent to Telegram Channel"
                success_count=1
            else
                warn "❌ Failed to send to Telegram Channel"
            fi
            ;;
        "bot")
            if send_telegram_message "$TELEGRAM_CHAT_ID" "$message"; then
                log "✅ Sent to Bot private message"
                success_count=1
            else
                warn "❌ Failed to send to Bot private message"
            fi
            ;;
        "both")
            if send_telegram_message "$TELEGRAM_CHANNEL_ID" "$message"; then
                log "✅ Sent to Telegram Channel"
                success_count=$((success_count + 1))
            else
                warn "❌ Failed to send to Telegram Channel"
            fi
            if send_telegram_message "$TELEGRAM_CHAT_ID" "$message"; then
                log "✅ Sent to Bot private message"
                success_count=$((success_count + 1))
            else
                warn "❌ Failed to send to Bot private message"
            fi
            ;;
    esac
    
    if [[ $success_count -gt 0 ]]; then
        log "Telegram notifications completed ($success_count successful)"
    else
        warn "All Telegram notifications failed"
    fi
}

# Main deployment function
main() {
    banner
    
    # Initialize variables
    CPU="1"
    MEMORY="2Gi" 
    REGION="us-central1"
    PROTOCOL="trojan"
    TELEGRAM_DESTINATION="none"
    
    # Get user input
    select_region
    select_cpu
    select_memory
    select_protocol
    select_telegram_destination
    get_user_input
    show_config_summary
    
    PROJECT_ID=$(gcloud config get-value project)
    
    log "Starting deployment..."
    log "Project: $PROJECT_ID"
    log "Region: $REGION"
    log "Service: $SERVICE_NAME"
    log "Protocol: $PROTOCOL"
    
    validate_prerequisites
    
    # Enable APIs
    log "Enabling required APIs..."
    gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet || {
        warn "Failed to enable APIs, but continuing..."
    }
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    
    # Create configuration files
    log "Creating configuration files..."
    create_config
    create_dockerfile
    
    # Verify files were created
    if [[ ! -f "config.json" || ! -f "Dockerfile" ]]; then
        error "Configuration files were not created properly"
    fi
    
    # Build container image
    log "Building container image..."
    if ! gcloud builds submit --tag "gcr.io/${PROJECT_ID}/${SERVICE_NAME}" --quiet; then
        error "Build failed. Check Cloud Build logs in GCP console."
    fi
    
    # Deploy to Cloud Run
    log "Deploying to Cloud Run..."
    if ! gcloud run deploy "$SERVICE_NAME" \
        --image "gcr.io/${PROJECT_ID}/${SERVICE_NAME}" \
        --platform managed \
        --region "$REGION" \
        --allow-unauthenticated \
        --cpu "$CPU" \
        --memory "$MEMORY" \
        --port=8080 \
        --min-instances=0 \
        --max-instances=10 \
        --quiet; then
        error "Deployment failed. Check Cloud Run logs in GCP console."
    fi
    
    # Get service URL
    SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
        --region "$REGION" \
        --format 'value(status.url)' \
        --quiet)
    
    if [[ -z "$SERVICE_URL" ]]; then
        error "Failed to get service URL"
    fi
    
    DOMAIN=$(echo "$SERVICE_URL" | sed 's|https://||')
    
    # Create share link
    case $PROTOCOL in
        "trojan")
            SHARE_LINK="trojan://Trojan-2025@${HOST_DOMAIN}:443?path=%2Ftg-%40iazcc&security=tls&host=${DOMAIN}&type=ws&sni=${DOMAIN}#${SERVICE_NAME}"
            ;;
        "vless")
            SHARE_LINK="vless://${UUID}@${HOST_DOMAIN}:443?path=%2Ftg-%40iazcc&security=tls&encryption=none&host=${DOMAIN}&type=ws&sni=${DOMAIN}#${SERVICE_NAME}"
            ;;
        "vless-grpc")
            SHARE_LINK="vless://${UUID}@${HOST_DOMAIN}:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc-service&sni=${DOMAIN}#${SERVICE_NAME}"
            ;;
        "vmess")
            VMESS_CONFIG='{"v":"2","ps":"'${SERVICE_NAME}'","add":"'${HOST_DOMAIN}'","port":"443","id":"'${UUID}'","aid":"0","net":"ws","type":"none","host":"'${DOMAIN}'","path":"/tg-@iazcc","tls":"tls","sni":"'${DOMAIN}'"}'
            SHARE_LINK="vmess://$(echo -n "$VMESS_CONFIG" | base64 -w 0)"
            ;;
    esac
    
    # Create messages
    local MESSAGE="🚀 <b>GCP V2Ray Deployment Successful</b> 🚀

✨ <b>Deployment Details:</b>
• <b>Project:</b> <code>${PROJECT_ID}</code>
• <b>Service:</b> <code>${SERVICE_NAME}</code>  
• <b>Region:</b> <code>${REGION}</code>
• <b>Protocol:</b> <code>${PROTOCOL^^}</code>
• <b>Resources:</b> <code>${CPU} CPU | ${MEMORY} RAM</code>
• <b>Domain:</b> <code>${DOMAIN}</code>

🔗 <b>Configuration Link:</b>
<code>${SHARE_LINK}</code>

📝 <b>Usage Instructions:</b>
1. Copy the configuration link
2. Open your V2Ray client  
3. Import from clipboard
4. Connect and enjoy! 🎉"

    local CONSOLE_MESSAGE="🚀 GCP V2Ray Deployment Successful 🚀

✨ Deployment Details:
• Project: ${PROJECT_ID}
• Service: ${SERVICE_NAME}
• Region: ${REGION}
• Protocol: ${PROTOCOL^^}
• Resources: ${CPU} CPU | ${MEMORY} RAM
• Domain: ${DOMAIN}
• Service URL: ${SERVICE_URL}

🔗 Configuration Link:
${SHARE_LINK}

📝 Usage Instructions:
1. Copy the configuration link
2. Open your V2Ray client  
3. Import from clipboard
4. Connect and enjoy! 🎉"

    # Display info
    echo
    success "=== Deployment Information ==="
    echo "$CONSOLE_MESSAGE"
    echo
    
    # Save to file
    INFO_FILE="${SERVICE_NAME}-deployment-info.txt"
    echo "$CONSOLE_MESSAGE" > "$INFO_FILE"
    
    # Send Telegram notification
    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        log "Sending Telegram notification..."
        send_deployment_notification "$MESSAGE"
    fi
    
    success "🎉 Deployment completed successfully!"
    log "📝 Service URL: $SERVICE_URL"
    log "💾 Configuration saved to: $INFO_FILE"
    
    # Cleanup
    cd /
    rm -rf "$TEMP_DIR"
    log "Cleaned up temporary files"
}

# Run main function
main "$@"
