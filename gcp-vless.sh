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
        return 1
    fi
    return 0
}

# Function to validate Telegram Bot Token
validate_bot_token() {
    local token_pattern='^[0-9]{8,10}:[a-zA-Z0-9_-]{35}$'
    if [[ ! $1 =~ $token_pattern ]]; then
        error "Invalid Telegram Bot Token format"
        return 1
    fi
    return 0
}

# Function to validate Channel ID
validate_channel_id() {
    if [[ ! $1 =~ ^-?[0-9]+$ ]]; then
        error "Invalid Channel ID format"
        return 1
    fi
    return 0
}

# Function to validate Chat ID (for bot private messages)
validate_chat_id() {
    if [[ ! $1 =~ ^-?[0-9]+$ ]]; then
        error "Invalid Chat ID format"
        return 1
    fi
    return 0
}

# Function to validate URL format - CORRECTED
validate_url() {
    local url="$1"
    # More flexible URL validation
    if [[ "$url" =~ ^https?://[a-zA-Z0-9./?=_-]+$ ]] || [[ "$url" =~ ^https?://t\.me/[a-zA-Z0-9_]+$ ]]; then
        return 0
    else
        error "Invalid URL format: $url"
        return 1
    fi
}

# CPU selection function
select_cpu() {
    echo
    info "=== CPU Configuration ==="
    echo "1. 1 CPU Core (Default)"
    echo "2. 2 CPU Cores"
    echo "3. 4 CPU Cores"
    echo "4. 8 CPU Cores"
    echo
    
    while true; do
        read -p "Select CPU cores (1-4): " cpu_choice
        case ${cpu_choice:-1} in
            1) CPU="1"; break ;;
            2) CPU="2"; break ;;
            3) CPU="4"; break ;;
            4) CPU="8"; break ;;
            *) echo "Invalid selection. Please enter a number between 1-4." ;;
        esac
    done
    
    info "Selected CPU: $CPU core(s)"
}

# Memory selection function - CORRECTED
select_memory() {
    echo
    info "=== Memory Configuration ==="
    
    case $CPU in
        1) echo "Recommended memory: 512Mi - 2Gi" ;;
        2) echo "Recommended memory: 1Gi - 4Gi" ;;
        4) echo "Recommended memory: 2Gi - 8Gi" ;;
        8) echo "Recommended memory: 4Gi - 16Gi" ;;
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
        read -p "Select memory (1-6): " memory_choice
        case ${memory_choice:-3} in
            1) MEMORY="512Mi"; break ;;
            2) MEMORY="1Gi"; break ;;
            3) MEMORY="2Gi"; break ;;
            4) MEMORY="4Gi"; break ;;
            5) MEMORY="8Gi"; break ;;
            6) MEMORY="16Gi"; break ;;
            *) echo "Invalid selection. Please enter a number between 1-6." ;;
        esac
    done
    
    info "Selected Memory: $MEMORY"
}

# Region selection function - CORRECTED
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
        read -p "Select region (1-8): " region_choice
        case ${region_choice:-1} in
            1) REGION="us-central1"; break ;;
            2) REGION="us-west1"; break ;;
            3) REGION="us-east1"; break ;;
            4) REGION="europe-west1"; break ;;
            5) REGION="asia-southeast1"; break ;;
            6) REGION="asia-southeast2"; break ;;
            7) REGION="asia-northeast1"; break ;;
            8) REGION="asia-east1"; break ;;
            *) echo "Invalid selection. Please enter a number between 1-8." ;;
        esac
    done
    
    info "Selected region: $REGION"
}

# Protocol selection function - CORRECTED
select_protocol() {
    echo
    info "=== Protocol Selection ==="
    echo "1. Trojan WS (Recommended)"
    echo "2. VLESS WS"
    echo "3. VLESS gRPC"
    echo "4. VMess WS"
    echo
    
    while true; do
        read -p "Select protocol (1-4): " protocol_choice
        case ${protocol_choice:-1} in
            1) PROTOCOL="trojan-ws"; break ;;
            2) PROTOCOL="vless-ws"; break ;;
            3) PROTOCOL="vless-grpc"; break ;;
            4) PROTOCOL="vmess-ws"; break ;;
            *) echo "Invalid selection. Please enter a number between 1-4." ;;
        esac
    done
    
    info "Selected protocol: $PROTOCOL"
}

# Telegram destination selection - CORRECTED
select_telegram_destination() {
    echo
    info "=== Telegram Destination ==="
    echo "1. Send to Channel only"
    echo "2. Send to Bot private message only" 
    echo "3. Send to both Channel and Bot"
    echo "4. Don't send to Telegram"
    echo
    
    while true; do
        read -p "Select destination (1-4): " telegram_choice
        case ${telegram_choice:-4} in
            1) 
                TELEGRAM_DESTINATION="channel"
                while true; do
                    read -p "Enter Telegram Channel ID: " TELEGRAM_CHANNEL_ID
                    if [[ -n "$TELEGRAM_CHANNEL_ID" ]] && validate_channel_id "$TELEGRAM_CHANNEL_ID"; then
                        break
                    elif [[ -z "$TELEGRAM_CHANNEL_ID" ]]; then
                        warn "Channel ID cannot be empty"
                    fi
                done
                break 
                ;;
            2) 
                TELEGRAM_DESTINATION="bot"
                while true; do
                    read -p "Enter your Chat ID (for bot private message): " TELEGRAM_CHAT_ID
                    if [[ -n "$TELEGRAM_CHAT_ID" ]] && validate_chat_id "$TELEGRAM_CHAT_ID"; then
                        break
                    elif [[ -z "$TELEGRAM_CHAT_ID" ]]; then
                        warn "Chat ID cannot be empty"
                    fi
                done
                break 
                ;;
            3) 
                TELEGRAM_DESTINATION="both"
                while true; do
                    read -p "Enter Telegram Channel ID: " TELEGRAM_CHANNEL_ID
                    if [[ -n "$TELEGRAM_CHANNEL_ID" ]] && validate_channel_id "$TELEGRAM_CHANNEL_ID"; then
                        break
                    elif [[ -z "$TELEGRAM_CHANNEL_ID" ]]; then
                        warn "Channel ID cannot be empty"
                    fi
                done
                while true; do
                    read -p "Enter your Chat ID (for bot private message): " TELEGRAM_CHAT_ID
                    if [[ -n "$TELEGRAM_CHAT_ID" ]] && validate_chat_id "$TELEGRAM_CHAT_ID"; then
                        break
                    elif [[ -z "$TELEGRAM_CHAT_ID" ]]; then
                        warn "Chat ID cannot be empty"
                    fi
                done
                break 
                ;;
            4) 
                TELEGRAM_DESTINATION="none"
                break 
                ;;
            *) echo "Invalid selection. Please enter a number between 1-4." ;;
        esac
    done
}

# Channel URL input function - CORRECTED
get_channel_url() {
    echo
    info "=== Channel URL Configuration ==="
    echo "Default URL: $TELEGRAM_CHANNEL"
    echo "Channel Name: $DEFAULT_CHANNEL_NAME"
    echo "You can use the default URL or enter your own custom URL."
    echo
    
    while true; do
        read -p "Enter Channel URL [default: $TELEGRAM_CHANNEL]: " CHANNEL_URL
        CHANNEL_URL=${CHANNEL_URL:-"$TELEGRAM_CHANNEL"}
        
        CHANNEL_URL=$(echo "$CHANNEL_URL" | sed 's|/*$||')
        
        if validate_url "$CHANNEL_URL"; then
            break
        else
            warn "Please enter a valid URL"
        fi
    done
    
    # Extract channel name for button text
    if [[ "$CHANNEL_URL" == *"t.me/"* ]]; then
        CHANNEL_NAME=$(echo "$CHANNEL_URL" | sed 's|.*t.me/||' | sed 's|/*$||')
    else
        CHANNEL_NAME=$(echo "$CHANNEL_URL" | sed 's|.*://||' | sed 's|/.*||' | sed 's|www\.||')
    fi
    
    if [[ -z "$CHANNEL_NAME" ]]; then
        CHANNEL_NAME="$DEFAULT_CHANNEL_NAME"
    fi
    
    if [[ ${#CHANNEL_NAME} -gt 20 ]]; then
        CHANNEL_NAME="${CHANNEL_NAME:0:17}..."
    fi
    
    info "Channel URL: $CHANNEL_URL"
    info "Channel Name: $CHANNEL_NAME"
}

# User input function - CORRECTED
get_user_input() {
    echo
    info "=== Service Configuration ==="
    
    # Service Name
    while true; do
        read -p "Enter service name [default: v2ray-service]: " SERVICE_NAME
        SERVICE_NAME=${SERVICE_NAME:-"v2ray-service"}
        if [[ -n "$SERVICE_NAME" ]]; then
            # Validate service name (alphanumeric and hyphens only)
            if [[ "$SERVICE_NAME" =~ ^[a-z0-9-]+$ ]]; then
                break
            else
                error "Service name can only contain lowercase letters, numbers, and hyphens"
            fi
        else
            error "Service name cannot be empty"
        fi
    done
    
    # UUID
    while true; do
        read -p "Enter UUID [default: ba0e3984-ccc9-48a3-8074-b2f507f41ce8]: " UUID
        UUID=${UUID:-"ba0e3984-ccc9-48a3-8074-b2f507f41ce8"}
        if validate_uuid "$UUID"; then
            break
        fi
    done
    
    # Telegram Bot Token (required for any Telegram option)
    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        while true; do
            read -p "Enter Telegram Bot Token: " TELEGRAM_BOT_TOKEN
            if [[ -n "$TELEGRAM_BOT_TOKEN" ]] && validate_bot_token "$TELEGRAM_BOT_TOKEN"; then
                break
            elif [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
                warn "Bot token cannot be empty for Telegram notifications"
            fi
        done
    fi
    
    # Host Domain (optional)
    read -p "Enter host domain [default: m.googleapis.com]: " HOST_DOMAIN
    HOST_DOMAIN=${HOST_DOMAIN:-"m.googleapis.com"}
    
    # Get Channel URL if Telegram is enabled
    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        get_channel_url
    fi
}

# Display configuration summary - CORRECTED
show_config_summary() {
    echo
    success "=== Configuration Summary ==="
    echo "Project ID:    $(gcloud config get-value project 2>/dev/null || echo 'Not set')"
    echo "Region:        $REGION"
    echo "Protocol:      $PROTOCOL"
    echo "Service Name:  $SERVICE_NAME"
    echo "Host Domain:   $HOST_DOMAIN"
    echo "UUID:          $UUID"
    echo "CPU:           $CPU core(s)"
    echo "Memory:        $MEMORY"
    
    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        echo "Bot Token:     ${TELEGRAM_BOT_TOKEN:0:8}..."
        echo "Destination:   $TELEGRAM_DESTINATION"
        if [[ "$TELEGRAM_DESTINATION" == "channel" || "$TELEGRAM_DESTINATION" == "both" ]]; then
            echo "Channel ID:    $TELEGRAM_CHANNEL_ID"
        fi
        if [[ "$TELEGRAM_DESTINATION" == "bot" || "$TELEGRAM_DESTINATION" == "both" ]]; then
            echo "Chat ID:       $TELEGRAM_CHAT_ID"
        fi
        echo "Channel URL:   $CHANNEL_URL"
        echo "Button Text:   $CHANNEL_NAME"
    else
        echo "Telegram:      Not configured"
    fi
    echo
    
    while true; do
        read -p "Proceed with deployment? (y/n): " confirm
        case ${confirm:-n} in
            [Yy]* ) break;;
            [Nn]* ) 
                info "Deployment cancelled by user"
                exit 0
                ;;
            * ) echo "Please answer yes (y) or no (n).";;
        esac
    done
}

# Validation functions - CORRECTED
validate_prerequisites() {
    log "Validating prerequisites..."
    
    if ! command -v gcloud &> /dev/null; then
        error "gcloud CLI is not installed. Please install Google Cloud SDK."
        exit 1
    fi
    
    local PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "(unset)" ]]; then
        error "No project configured. Run: gcloud config set project PROJECT_ID"
        exit 1
    fi
    
    # Check if user is authenticated
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
        error "Not authenticated. Run: gcloud auth login"
        exit 1
    fi
}

cleanup() {
    log "Cleaning up temporary files..."
    if [[ -d "gcp-v2ray" ]]; then
        rm -rf gcp-v2ray
    fi
}

send_to_telegram() {
    local chat_id="$1"
    local message="$2"
    local response
    
    # Create inline keyboard with dynamic button - CORRECTED
    local keyboard='{"inline_keyboard":[[{"text":"'"$CHANNEL_NAME"'","url":"'"$CHANNEL_URL"'"}]]}'
    
    response=$(curl -s -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d @- \
        https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage << EOF
{
    "chat_id": "${chat_id}",
    "text": "$message",
    "parse_mode": "MARKDOWN",
    "disable_web_page_preview": true,
    "reply_markup": $keyboard
}
EOF
)
    
    local http_code="${response: -3}"
    
    if [[ "$http_code" == "200" ]]; then
        return 0
    else
        error "Failed to send to Telegram (HTTP $http_code)"
        return 1
    fi
}

send_deployment_notification() {
    local message="$1"
    local success_count=0
    
    case $TELEGRAM_DESTINATION in
        "channel")
            log "Sending to Telegram Channel..."
            if send_to_telegram "$TELEGRAM_CHANNEL_ID" "$message"; then
                log "✅ Successfully sent to Telegram Channel"
                success_count=$((success_count + 1))
            else
                error "❌ Failed to send to Telegram Channel"
            fi
            ;;
            
        "bot")
            log "Sending to Bot private message..."
            if send_to_telegram "$TELEGRAM_CHAT_ID" "$message"; then
                log "✅ Successfully sent to Bot private message"
                success_count=$((success_count + 1))
            else
                error "❌ Failed to send to Bot private message"
            fi
            ;;
            
        "both")
            log "Sending to both Channel and Bot..."
            
            if send_to_telegram "$TELEGRAM_CHANNEL_ID" "$message"; then
                log "✅ Successfully sent to Telegram Channel"
                success_count=$((success_count + 1))
            else
                error "❌ Failed to send to Telegram Channel"
            fi
            
            if send_to_telegram "$TELEGRAM_CHAT_ID" "$message"; then
                log "✅ Successfully sent to Bot private message"
                success_count=$((success_count + 1))
            else
                error "❌ Failed to send to Bot private message"
            fi
            ;;
            
        "none")
            log "Skipping Telegram notification as configured"
            return 0
            ;;
    esac
    
    if [[ $success_count -gt 0 ]]; then
        log "Telegram notification completed ($success_count successful)"
        return 0
    else
        warn "All Telegram notifications failed, but deployment was successful"
        return 1
    fi
}

# Create appropriate configuration based on protocol - CORRECTED
create_config() {
    local config_file="config.json"
    
    case $PROTOCOL in
        "trojan-ws")
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
        "vless-ws")
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
        "vmess-ws")
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
}

create_dockerfile() {
    cat > Dockerfile << EOF
FROM v2fly/v2fly-core:latest

COPY config.json /etc/v2ray/config.json

EXPOSE 8080

CMD ["v2ray", "run", "-config", "/etc/v2ray/config.json"]
EOF
}

# Main deployment function - CORRECTED
main() {
    banner
    
    # Set default values
    CPU="1"
    MEMORY="2Gi"
    REGION="us-central1"
    PROTOCOL="trojan-ws"
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
    
    log "Starting Cloud Run deployment..."
    log "Project: $PROJECT_ID"
    log "Region: $REGION"
    log "Service: $SERVICE_NAME"
    log "Protocol: $PROTOCOL"
    log "CPU: $CPU core(s)"
    log "Memory: $MEMORY"
    
    validate_prerequisites
    
    # Set trap for cleanup
    trap cleanup EXIT
    
    log "Enabling required APIs..."
    if ! gcloud services enable \
        cloudbuild.googleapis.com \
        run.googleapis.com \
        iam.googleapis.com \
        --quiet; then
        error "Failed to enable required APIs"
        exit 1
    fi
    
    # Clean up any existing directory
    cleanup
    
    # Create local files instead of cloning from repository
    log "Creating configuration files locally..."
    mkdir -p gcp-v2ray
    cd gcp-v2ray
    
    # Create configuration files
    create_config
    create_dockerfile
    
    log "Building container image..."
    if ! gcloud builds submit --tag gcr.io/${PROJECT_ID}/gcp-v2ray-image --quiet; then
        error "Build failed"
        exit 1
    fi
    
    log "Deploying to Cloud Run..."
    if ! gcloud run deploy ${SERVICE_NAME} \
        --image gcr.io/${PROJECT_ID}/gcp-v2ray-image \
        --platform managed \
        --region ${REGION} \
        --allow-unauthenticated \
        --cpu ${CPU} \
        --memory ${MEMORY} \
        --quiet; then
        error "Deployment failed"
        exit 1
    fi
    
    # Get the service URL
    SERVICE_URL=$(gcloud run services describe ${SERVICE_NAME} \
        --region ${REGION} \
        --format 'value(status.url)' \
        --quiet)
    
    DOMAIN=$(echo $SERVICE_URL | sed 's|https://||')
    
    # Create share link based on protocol - CORRECTED
    case $PROTOCOL in
        "trojan-ws")
            SHARE_LINK="trojan://Trojan-2025@${HOST_DOMAIN}:443?path=%2Ftg-%40iazcc&security=tls&alpn=h3%2Ch2%2Chttp%2F1.1&host=${DOMAIN}&fp=randomized&type=ws&sni=${DOMAIN}#${SERVICE_NAME}"
            ;;
        "vless-ws")
            SHARE_LINK="vless://${UUID}@${HOST_DOMAIN}:443?path=%2Ftg-%40iazcc&security=tls&alpn=h3%2Ch2%2Chttp%2F1.1&encryption=none&host=${DOMAIN}&fp=randomized&type=ws&sni=${DOMAIN}#${SERVICE_NAME}"
            ;;
        "vless-grpc")
            SHARE_LINK="vless://${UUID}@${HOST_DOMAIN}:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc-service&sni=${DOMAIN}#${SERVICE_NAME}"
            ;;
        "vmess-ws")
            VMESS_CONFIG='{"v":"2","ps":"'${SERVICE_NAME}'","add":"'${HOST_DOMAIN}'","port":"443","id":"'${UUID}'","aid":"0","scy":"auto","net":"ws","type":"none","host":"'${DOMAIN}'","path":"/tg-@iazcc","tls":"tls","sni":"'${DOMAIN}'","alpn":"h3,h2,http/1.1","fp":"randomized"}'
            SHARE_LINK="vmess://$(echo -n "$VMESS_CONFIG" | base64 -w 0)"
            ;;
    esac
    
    # Create beautiful telegram message with emojis - CORRECTED
    MESSAGE="🚀 *GCP V2Ray Deployment Successful* 🚀
━━━━━━━━━━━━━━━━━━━━
✨ *Deployment Details:*
• *Project:* \`${PROJECT_ID}\`
• *Service:* \`${SERVICE_NAME}\`
• *Region:* \`${REGION}\`
• *Protocol:* \`${PROTOCOL^^}\`
• *Resources:* \`${CPU} CPU | ${MEMORY} RAM\`
• *Domain:* \`${DOMAIN}\`

🔗 *Configuration Link:*
\`\`\`
${SHARE_LINK}
\`\`\`
📝 *Usage Instructions:*
1. Copy the above configuration link
2. Open your V2Ray client
3. Import from clipboard
4. Connect and enjoy! 🎉
━━━━━━━━━━━━━━━━━━━━"

    # Create console message
    CONSOLE_MESSAGE="🚀 GCP V2Ray Deployment Successful 🚀
━━━━━━━━━━━━━━━━━━━━
✨ Deployment Details:
• Project: ${PROJECT_ID}
• Service: ${SERVICE_NAME}
• Region: ${REGION}
• Protocol: ${PROTOCOL^^}
• Resources: ${CPU} CPU | ${MEMORY} RAM
• Domain: ${DOMAIN}

🔗 Configuration Link:
${SHARE_LINK}

📝 Usage Instructions:
1. Copy the above configuration link
2. Open your V2Ray client  
3. Import from clipboard
4. Connect and enjoy! 🎉
━━━━━━━━━━━━━━━━━━━━"
    
    # Save to file
    echo "$CONSOLE_MESSAGE" > deployment-info.txt
    log "Deployment info saved to deployment-info.txt"
    
    # Display locally
    echo
    success "=== Deployment Information ==="
    echo "$CONSOLE_MESSAGE"
    echo
    
    # Send to Telegram based on user selection
    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        log "Sending deployment info to Telegram..."
        send_deployment_notification "$MESSAGE"
    else
        log "Skipping Telegram notification as per user selection"
    fi
    
    success "Deployment completed successfully!"
    log "Service URL: $SERVICE_URL"
    log "Configuration saved to: deployment-info.txt"
    log "Telegram Channel: $TELEGRAM_CHANNEL"
    log "Username: $TELEGRAM_USERNAME"
}

# Run main function
main "$@"
