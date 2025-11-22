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

# Function to validate Chat ID
validate_chat_id() {
    if [[ ! $1 =~ ^-?[0-9]+$ ]]; then
        error "Invalid Chat ID format"
        return 1
    fi
    return 0
}

# Function to install missing dependencies
install_dependencies() {
    log "Checking and installing required dependencies..."
    
    # Check if running on Linux
    if [[ "$(uname)" != "Linux" ]]; then
        warn "This script is optimized for Linux systems. Some features may not work properly."
    fi
    
    # Install uuidgen if not available
    if ! command -v uuidgen &> /dev/null; then
        warn "uuidgen not found, installing..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y uuid-runtime
        elif command -v yum &> /dev/null; then
            sudo yum install -y util-linux
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y util-linux
        else
            error "Cannot install uuidgen automatically. Please install it manually."
            return 1
        fi
    fi
    
    # Install jq for JSON processing if not available
    if ! command -v jq &> /dev/null; then
        warn "jq not found, installing..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get install -y jq
        elif command -v yum &> /dev/null; then
            sudo yum install -y jq
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y jq
        else
            error "Cannot install jq automatically. Please install it manually."
            return 1
        fi
    fi
    
    # Install curl if not available
    if ! command -v curl &> /dev/null; then
        warn "curl not found, installing..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get install -y curl
        elif command -v yum &> /dev/null; then
            sudo yum install -y curl
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y curl
        else
            error "Cannot install curl automatically. Please install it manually."
            return 1
        fi
    fi
    
    return 0
}

# Function to generate UUID if uuidgen is not available
generate_uuid() {
    if command -v uuidgen &> /dev/null; then
        uuidgen
    else
        # Fallback UUID generation
        python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
        echo "$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo '12345678-1234-1234-1234-123456789abc')"
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
                        break
                    else
                        warn "Channel ID cannot be empty"
                    fi
                done
                while true; do
                    read -p "Enter your Chat ID: " TELEGRAM_CHAT_ID
                    if [[ -n "$TELEGRAM_CHAT_ID" ]]; then
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
        read -p "Enter UUID [default: auto-generate]: " UUID
        UUID=${UUID:-$(generate_uuid)}
        if validate_uuid "$UUID"; then
            break
        else
            warn "Invalid UUID format, generating a new one..."
            UUID=$(generate_uuid)
            if validate_uuid "$UUID"; then
                info "Generated new UUID: $UUID"
                break
            fi
        fi
    done
    
    # Telegram Bot Token
    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        while true; do
            read -p "Enter Telegram Bot Token: " TELEGRAM_BOT_TOKEN
            if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
                if validate_bot_token "$TELEGRAM_BOT_TOKEN"; then
                    break
                else
                    warn "Invalid bot token format. Please check and try again."
                fi
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
        error "gcloud CLI is not installed. Please install Google Cloud SDK first."
        error "Visit: https://cloud.google.com/sdk/docs/install"
        exit 1
    fi
    
    local PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "$PROJECT_ID" ]]; then
        error "No project configured. Run: gcloud config set project PROJECT_ID"
        exit 1
    fi
    
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" &>/dev/null; then
        error "Not authenticated. Run: gcloud auth login"
        exit 1
    fi
    
    # Install dependencies
    if ! install_dependencies; then
        error "Failed to install required dependencies"
        exit 1
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
            "password": "$UUID",
            "level": 0
          }
        ],
        "fallbacks": []
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": {
          "path": "/$UUID"
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
          "path": "/$UUID"
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
          "serviceName": "vless-grpc"
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
          "path": "/$UUID"
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
        return 1
    fi
    
    log "Created V2Ray configuration file: $config_file"
    return 0
}

create_dockerfile() {
    cat > Dockerfile << 'EOF'
FROM v2fly/v2fly-core:latest

# Create necessary directories
RUN mkdir -p /var/log/v2ray /var/lib/v2ray

# Copy configuration
COPY config.json /etc/v2ray/config.json

# Create a startup script
RUN echo '#!/bin/sh' > /start.sh && \
    echo 'echo "Starting V2Ray..."' >> /start.sh && \
    echo 'v2ray run -config /etc/v2ray/config.json' >> /start.sh && \
    chmod +x /start.sh

EXPOSE 8080

CMD ["/start.sh"]
EOF

    if [[ ! -f "Dockerfile" ]]; then
        error "Failed to create Dockerfile"
        return 1
    fi
    
    log "Created Dockerfile"
    return 0
}

create_cloudbuild_yaml() {
    cat > cloudbuild.yaml << EOF
steps:
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', 'gcr.io/\$PROJECT_ID/${SERVICE_NAME}', '.']
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', 'gcr.io/\$PROJECT_ID/${SERVICE_NAME}']
images:
  - 'gcr.io/\$PROJECT_ID/${SERVICE_NAME}'
EOF

    if [[ ! -f "cloudbuild.yaml" ]]; then
        error "Failed to create cloudbuild.yaml"
        return 1
    fi
    
    log "Created cloudbuild.yaml"
    return 0
}

send_telegram_message() {
    local chat_id="$1"
    local message="$2"
    
    local keyboard='{"inline_keyboard":[[{"text":"Join Channel","url":"https://t.me/cvw_cvw"}]]}'
    
    # URL encode the message
    local encoded_message=$(echo "$message" | jq -s -R -r @uri)
    
    local response=$(curl -s -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "{
            \"chat_id\": \"$chat_id\",
            \"text\": \"$message\",
            \"parse_mode\": \"HTML\",
            \"disable_web_page_preview\": true,
            \"reply_markup\": $keyboard
        }" \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" 2>/dev/null)
    
    local http_code="${response: -3}"
    local response_body="${response%???}"
    
    if [[ "$http_code" == "200" ]]; then
        return 0
    else
        warn "Failed to send Telegram message. HTTP Code: $http_code"
        return 1
    fi
}

send_deployment_notification() {
    local message="$1"
    local success_count=0
    
    case $TELEGRAM_DESTINATION in
        "channel")
            if send_telegram_message "$TELEGRAM_CHANNEL_ID" "$message"; then
                success_count=$((success_count+1))
            fi
            ;;
        "bot")
            if send_telegram_message "$TELEGRAM_CHAT_ID" "$message"; then
                success_count=$((success_count+1))
            fi
            ;;
        "both")
            if send_telegram_message "$TELEGRAM_CHANNEL_ID" "$message"; then
                success_count=$((success_count+1))
            fi
            if send_telegram_message "$TELEGRAM_CHAT_ID" "$message"; then
                success_count=$((success_count+1))
            fi
            ;;
    esac
    
    if [[ $success_count -gt 0 ]]; then
        log "Telegram notifications sent successfully"
    else
        warn "Failed to send Telegram notifications"
    fi
}

# Function to cleanup on exit
cleanup() {
    if [[ -n "${temp_dir:-}" && -d "$temp_dir" ]]; then
        log "Cleaning up temporary files..."
        rm -rf "$temp_dir"
    fi
}

# Main deployment function
main() {
    # Set up cleanup on exit
    trap cleanup EXIT INT TERM
    
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
    
    # Create temporary directory
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    log "Working directory: $temp_dir"
    
    # Enable APIs
    log "Enabling required APIs..."
    if ! gcloud services enable run.googleapis.com cloudbuild.googleapis.com containerregistry.googleapis.com --quiet 2>/dev/null; then
        error "Failed to enable required APIs. Please check your permissions."
        exit 1
    fi
    
    # Create configuration files
    log "Creating configuration files..."
    if ! create_config; then
        error "Failed to create V2Ray configuration"
        exit 1
    fi
    
    if ! create_dockerfile; then
        error "Failed to create Dockerfile"
        exit 1
    fi
    
    if ! create_cloudbuild_yaml; then
        error "Failed to create cloudbuild.yaml"
        exit 1
    fi
    
    # Verify files were created
    log "Verifying configuration files..."
    for file in config.json Dockerfile cloudbuild.yaml; do
        if [[ ! -f "$file" ]]; then
            error "Missing required file: $file"
            exit 1
        fi
    done
    
    # Build and deploy
    log "Building container image using Cloud Build..."
    if ! gcloud builds submit --config=cloudbuild.yaml --quiet; then
        error "Build failed. Check Cloud Build logs in GCP Console."
        exit 1
    fi
    
    log "Deploying to Cloud Run..."
    if ! gcloud run deploy "$SERVICE_NAME" \
        --image "gcr.io/${PROJECT_ID}/${SERVICE_NAME}" \
        --platform managed \
        --region "$REGION" \
        --allow-unauthenticated \
        --cpu "$CPU" \
        --memory "$MEMORY" \
        --port 8080 \
        --quiet; then
        error "Deployment failed. Check Cloud Run logs in GCP Console."
        exit 1
    fi
    
    # Get service URL and details
    SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
        --region "$REGION" \
        --format 'value(status.url)' \
        --quiet)
    
    DOMAIN=$(echo "$SERVICE_URL" | sed 's|https://||')
    
    # Create share link based on protocol
    case $PROTOCOL in
        "trojan")
            SHARE_LINK="trojan://${UUID}@${HOST_DOMAIN}:443?path=%2F${UUID}&security=tls&host=${DOMAIN}&type=ws&sni=${DOMAIN}#${SERVICE_NAME}"
            ;;
        "vless")
            SHARE_LINK="vless://${UUID}@${HOST_DOMAIN}:443?path=%2F${UUID}&security=tls&encryption=none&host=${DOMAIN}&type=ws&sni=${DOMAIN}#${SERVICE_NAME}"
            ;;
        "vless-grpc")
            SHARE_LINK="vless://${UUID}@${HOST_DOMAIN}:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless-grpc&sni=${DOMAIN}#${SERVICE_NAME}"
            ;;
        "vmess")
            VMESS_CONFIG="{\"v\":\"2\",\"ps\":\"${SERVICE_NAME}\",\"add\":\"${HOST_DOMAIN}\",\"port\":\"443\",\"id\":\"${UUID}\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${DOMAIN}\",\"path\":\"/${UUID}\",\"tls\":\"tls\",\"sni\":\"${DOMAIN}\"}"
            SHARE_LINK="vmess://$(echo "$VMESS_CONFIG" | base64 -w 0)"
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
• <b>UUID:</b> <code>${UUID}</code>

🔗 <b>Configuration Link:</b>
<code>${SHARE_LINK}</code>

📝 <b>Usage Instructions:</b>
1. Copy the configuration link
2. Open your V2Ray client  
3. Import from clipboard
4. Connect and enjoy! 🎉

💡 <b>Note:</b> The service uses domain fronting with <code>${HOST_DOMAIN}</code>"

    local CONSOLE_MESSAGE="🚀 GCP V2Ray Deployment Successful 🚀

✨ Deployment Details:
• Project: ${PROJECT_ID}
• Service: ${SERVICE_NAME}
• Region: ${REGION}
• Protocol: ${PROTOCOL^^}
• Resources: ${CPU} CPU | ${MEMORY} RAM
• Domain: ${DOMAIN}
• UUID: ${UUID}

🔗 Configuration Link:
${SHARE_LINK}

📝 Usage Instructions:
1. Copy the configuration link
2. Open your V2Ray client  
3. Import from clipboard
4. Connect and enjoy! 🎉

💡 Note: The service uses domain fronting with ${HOST_DOMAIN}"

    # Save to file
    local output_file="/tmp/${SERVICE_NAME}-info.txt"
    echo "$CONSOLE_MESSAGE" > "$output_file"
    
    # Display info
    echo
    success "=== Deployment Information ==="
    echo "$CONSOLE_MESSAGE"
    echo
    log "Detailed information saved to: $output_file"
    
    # Send Telegram notification
    if [[ "$TELEGRAM_DESTINATION" != "none" ]]; then
        log "Sending Telegram notification..."
        send_deployment_notification "$MESSAGE"
    fi
    
    success "Deployment completed successfully!"
    log "Service URL: $SERVICE_URL"
    log "You can monitor the service in Google Cloud Console: https://console.cloud.google.com/run"
    
    # Test the service
    log "Testing the service..."
    if curl -s -I --connect-timeout 10 "$SERVICE_URL" | head -1 | grep -q "200\|302"; then
        success "Service is responding correctly"
    else
        warn "Service might not be responding as expected. Please check the logs."
    fi
}

# Run main function
main "$@"
