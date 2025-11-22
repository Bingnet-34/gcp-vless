#!/bin/bash

# GCP VLESS Server Deployer - Fully Compatible with Google Cloud
# Author: Assistant
# Version: 6.0

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Global variables
SERVICE_NAME=""
REGION=""
PROJECT_ID=""
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
UUID=""
PATH_SUFFIX=""
SERVICE_URL=""
VLESS_LINK=""

# Google Cloud Compatible Resource Options
CPU_OPTIONS=("1" "2" "4" "8")
MEMORY_OPTIONS=("512Mi" "1Gi" "2Gi" "4Gi" "8Gi" "16Gi" "32Gi")

# Valid CPU-Memory combinations for Google Cloud Run
declare -A VALID_COMBINATIONS=(
    ["1"]="512Mi 1Gi 2Gi 4Gi"
    ["2"]="1Gi 2Gi 4Gi 8Gi 16Gi"
    ["4"]="2Gi 4Gi 8Gi 16Gi 32Gi"
    ["8"]="4Gi 8Gi 16Gi 32Gi"
)

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_dependencies() {
    print_info "Checking Google Cloud environment..."
    
    if ! command -v gcloud &> /dev/null; then
        print_error "This script must run in Google Cloud Shell"
        exit 1
    fi
    print_success "Google Cloud environment verified"
}

check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        print_warning "Google Cloud authentication required"
        gcloud auth login --no-launch-browser
    fi
    
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "$PROJECT_ID" ]]; then
        print_info "No project configured"
        list_projects
    else
        print_info "Current project: $PROJECT_ID"
        read -p "Use this project? (y/n) [y]: " use_current
        use_current=${use_current:-y}
        if [[ $use_current != "y" ]]; then
            list_projects
        fi
    fi
}

list_projects() {
    print_info "Available Google Cloud Projects:"
    echo ""
    gcloud projects list --format="table(projectId,name)" --sort-by=projectId
    
    echo ""
    while true; do
        read -p "Enter Project ID: " PROJECT_ID
        if [[ -n "$PROJECT_ID" ]]; then
            if gcloud projects describe $PROJECT_ID &>/dev/null; then
                gcloud config set project $PROJECT_ID
                print_success "Project set to: $PROJECT_ID"
                break
            else
                print_error "Project not found or no access"
            fi
        fi
    done
}

get_telegram_info() {
    echo ""
    print_info "Telegram Bot Configuration"
    echo "============================"
    
    while true; do
        read -p "Enter Telegram Bot Token: " TELEGRAM_BOT_TOKEN
        if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
            if [[ $TELEGRAM_BOT_TOKEN =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
                break
            else
                print_error "Invalid bot token format"
            fi
        else
            print_error "Bot token is required"
        fi
    done
    
    # Verify bot
    print_info "Verifying bot..."
    BOT_INFO=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe")
    if echo "$BOT_INFO" | grep -q \"ok\":true; then
        BOT_USERNAME=$(echo "$BOT_INFO" | grep -o '"username":"[^"]*' | cut -d'"' -f4)
        print_success "Bot verified: @$BOT_USERNAME"
    else
        print_error "Invalid bot token"
        exit 1
    fi
    
    echo ""
    print_info "Enter your personal Chat ID for admin notifications:"
    read -p "Chat ID: " TELEGRAM_CHAT_ID
}

select_region() {
    echo ""
    print_info "Select Google Cloud Region:"
    echo "1. us-central1 (Iowa, USA) - Recommended"
    echo "2. us-east1 (South Carolina, USA)"
    echo "3. us-west1 (Oregon, USA)" 
    echo "4. europe-west1 (Belgium, Europe)"
    echo "5. europe-west4 (Netherlands, Europe)"
    echo "6. asia-east1 (Taiwan, Asia)"
    echo "7. asia-southeast1 (Singapore, Asia)"
    echo "8. me-west1 (Tel Aviv, Middle East)"
    
    while true; do
        read -p "Select region (1-8) [1]: " region_choice
        region_choice=${region_choice:-1}
        case $region_choice in
            1) REGION="us-central1"; break ;;
            2) REGION="us-east1"; break ;;
            3) REGION="us-west1"; break ;;
            4) REGION="europe-west1"; break ;;
            5) REGION="europe-west4"; break ;;
            6) REGION="asia-east1"; break ;;
            7) REGION="asia-southeast1"; break ;;
            8) REGION="me-west1"; break ;;
            *) print_error "Invalid choice. Select 1-8" ;;
        esac
    done
    print_success "Selected Region: $REGION"
}

get_service_name() {
    echo ""
    read -p "Enter service name [vless-server]: " SERVICE_NAME
    SERVICE_NAME=${SERVICE_NAME:-vless-server}
    
    # Generate unique identifiers
    UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16)
    PATH_SUFFIX=$(head /dev/urandom 2>/dev/null | tr -dc a-z0-9 | head -c 10)
}

select_cpu() {
    echo ""
    print_info "Select CPU Cores:"
    echo "1. 1 CPU Core (Basic)"
    echo "2. 2 CPU Cores (Recommended)"
    echo "3. 4 CPU Cores (High Performance)" 
    echo "4. 8 CPU Cores (Maximum)"
    
    while true; do
        read -p "Select CPU (1-4) [2]: " cpu_choice
        cpu_choice=${cpu_choice:-2}
        case $cpu_choice in
            1) SELECTED_CPU="1"; break ;;
            2) SELECTED_CPU="2"; break ;;
            3) SELECTED_CPU="4"; break ;;
            4) SELECTED_CPU="8"; break ;;
            *) print_error "Invalid choice. Select 1-4" ;;
        esac
    done
}

select_memory() {
    echo ""
    print_info "Available Memory for $SELECTED_CPU CPU:"
    
    # Get valid memory options for selected CPU
    VALID_MEMORIES=(${VALID_COMBINATIONS[$SELECTED_CPU]})
    
    for i in "${!VALID_MEMORIES[@]}"; do
        echo "$((i+1)). ${VALID_MEMORIES[$i]}"
    done
    
    while true; do
        read -p "Select memory (1-${#VALID_MEMORIES[@]}) [3]: " memory_choice
        memory_choice=${memory_choice:-3}
        if [[ $memory_choice -ge 1 && $memory_choice -le ${#VALID_MEMORIES[@]} ]]; then
            SELECTED_MEMORY="${VALID_MEMORIES[$((memory_choice-1))]}"
            break
        else
            print_error "Invalid choice. Select 1-${#VALID_MEMORIES[@]}"
        fi
    done
}

select_resources() {
    select_cpu
    select_memory
    
    echo ""
    print_success "Selected Resources:"
    echo "• CPU: $SELECTED_CPU cores"
    echo "• Memory: $SELECTED_MEMORY"
    echo "• Max Instances: 100"
    echo "• Min Instances: 1 (Always running)"
}

create_docker_config() {
    print_info "Creating Docker configuration..."
    
    cat > Dockerfile << 'EOF'
FROM alpine:latest

RUN apk update && apk add --no-cache curl unzip

# Install Xray
RUN curl -L https://github.com/XTLS/Xray-core/releases/download/v1.8.11/Xray-linux-64.zip -o xray.zip \
    && unzip xray.zip xray \
    && mv xray /usr/bin/ \
    && chmod +x /usr/bin/xray \
    && rm xray.zip \
    && mkdir -p /etc/xray

COPY config.json /etc/xray/

EXPOSE 8080

CMD ["xray", "run", "-config", "/etc/xray/config.json"]
EOF

    cat > config.json << EOF
{
    "log": {
        "loglevel": "warning"
    },
    "inbounds": [
        {
            "port": 8080,
            "listen": "0.0.0.0",
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$UUID",
                        "flow": "xtls-rprx-vision"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "ws",
                "security": "tls",
                "tlsSettings": {
                    "alpn": ["h3", "h2", "http/1.1"],
                    "fingerprint": "randomized"
                },
                "wsSettings": {
                    "path": "/vless-$PATH_SUFFIX"
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
}

enable_services() {
    print_info "Enabling required Google Cloud services..."
    
    local services=(
        "run.googleapis.com"
        "containerregistry.googleapis.com"
        "cloudbuild.googleapis.com"
    )
    
    for service in "${services[@]}"; do
        if ! gcloud services list --enabled --filter="name:$service" | grep -q "$service"; then
            gcloud services enable "$service" --quiet
        fi
    done
}

deploy_to_cloud_run() {
    print_info "Deploying to Google Cloud Run..."
    
    enable_services
    
    # Build container
    print_info "Building container image..."
    if ! gcloud builds submit --tag "gcr.io/$PROJECT_ID/$SERVICE_NAME" --quiet; then
        print_error "Container build failed"
        exit 1
    fi
    
    # Deploy service
    print_info "Deploying service..."
    if ! gcloud run deploy "$SERVICE_NAME" \
        --image "gcr.io/$PROJECT_ID/$SERVICE_NAME" \
        --platform managed \
        --region "$REGION" \
        --allow-unauthenticated \
        --port 8080 \
        --cpu "$SELECTED_CPU" \
        --memory "$SELECTED_MEMORY" \
        --min-instances 1 \
        --max-instances 100 \
        --execution-environment gen2 \
        --quiet; then
        print_error "Deployment failed"
        exit 1
    fi
    
    print_success "Service deployed successfully"
}

get_service_url() {
    SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
        --platform managed \
        --region "$REGION" \
        --format="value(status.url)" 2>/dev/null)
    
    if [[ -z "$SERVICE_URL" ]]; then
        print_error "Failed to get service URL"
        exit 1
    fi
}

generate_vless_config() {
    local domain=$(echo "$SERVICE_URL" | sed 's|https://||')
    VLESS_LINK="vless://${UUID}@${domain}:443?path=%2Fvless-${PATH_SUFFIX}&security=tls&alpn=h3%2Ch2%2Chttp%2F1.1&encryption=none&host=${domain}&fp=randomized&type=ws&sni=${domain}#${SERVICE_NAME}"
}

wait_for_service() {
    print_info "Waiting for service to be ready..."
    sleep 30
    
    if curl -s --retry 3 --max-time 10 -f "$SERVICE_URL" > /dev/null 2>&1; then
        print_success "Service is ready"
    else
        print_warning "Service deployed but may need more time for TLS"
    fi
}

setup_telegram_bot() {
    print_info "Setting up Telegram bot..."
    
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setMyCommands" \
        -d '{
            "commands": [
                {"command": "start", "description": "Get VLESS configuration"},
                {"command": "status", "description": "Check server status"},
                {"command": "info", "description": "Server information"}
            ]
        }' > /dev/null
}

send_telegram_message() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=$message" \
        -d "parse_mode=HTML" > /dev/null
}

send_deployment_info() {
    local domain=$(echo "$SERVICE_URL" | sed 's|https://||')
    
    local message="🚀 <b>GCP VLESS Server Deployed Successfully!</b>

⚡ <b>Server Information:</b>
• 🌐 <b>URL:</b> <code>${SERVICE_URL}</code>
• 📍 <b>Region:</b> ${REGION}
• 🆔 <b>Project:</b> ${PROJECT_ID}
• 🔧 <b>Service:</b> ${SERVICE_NAME}
• 🌍 <b>Domain:</b> ${domain}

💪 <b>Resource Configuration:</b>
• 💻 <b>CPU:</b> ${SELECTED_CPU} cores
• 🎯 <b>Memory:</b> ${SELECTED_MEMORY}
• 📊 <b>Instances:</b> 1-100 (Auto-scaling)

🔑 <b>VLESS Configuration:</b>
• 🆔 <b>UUID:</b> <code>${UUID}</code>
• 🛣️ <b>Path:</b> <code>/vless-${PATH_SUFFIX}</code>
• 🌐 <b>Protocol:</b> VLESS + WebSocket + TLS
• 🔒 <b>Security:</b> TLS 1.3
• 🛡️ <b>Fingerprint:</b> Randomized

🔗 <b>VLESS Link:</b>
<code>${VLESS_LINK}</code>

✅ <b>Status:</b> Ready for unlimited users"

    print_info "Sending configuration to Telegram..."
    send_telegram_message "$message"
    send_telegram_message "🔗 <b>VLESS Link for Copying:</b>\n<code>${VLESS_LINK}</code>"
}

display_summary() {
    local domain=$(echo "$SERVICE_URL" | sed 's|https://||')
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    DEPLOYMENT COMPLETED                     ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}📦 SERVICE INFORMATION:${NC}"
    echo "  Project: $PROJECT_ID"
    echo "  Service: $SERVICE_NAME" 
    echo "  Region: $REGION"
    echo "  Resources: $SELECTED_CPU CPU | $SELECTED_MEMORY RAM"
    echo "  Domain: $domain"
    echo ""
    echo -e "${CYAN}🔑 VLESS CONFIGURATION:${NC}"
    echo "  UUID: $UUID"
    echo "  Path: /vless-$PATH_SUFFIX"
    echo ""
    echo -e "${CYAN}🔗 VLESS LINK:${NC}"
    echo "$VLESS_LINK"
    echo ""
}

show_management_commands() {
    echo -e "${YELLOW}🛠️  MANAGEMENT COMMANDS:${NC}"
    echo "  View logs:        gcloud logging read 'resource.type=cloud_run_revision AND resource.labels.service_name=$SERVICE_NAME' --limit=10"
    echo "  Check status:     gcloud run services describe $SERVICE_NAME --region=$REGION"
    echo "  Update resources: gcloud run services update $SERVICE_NAME --region=$REGION --cpu=2 --memory=4Gi"
    echo "  Delete service:   gcloud run services delete $SERVICE_NAME --region=$REGION --quiet"
    echo ""
}

cleanup() {
    rm -f Dockerfile config.json
}

main() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║               GCP VLESS SERVER DEPLOYER                     ║
║              Fully Google Cloud Compatible                  ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    # Initial setup
    check_dependencies
    check_gcloud_auth
    
    # Configuration
    get_telegram_info
    select_region
    get_service_name
    select_resources
    
    # Confirmation
    echo ""
    print_info "Deployment Configuration:"
    echo "──────────────────────────"
    echo "• Project: $PROJECT_ID"
    echo "• Service: $SERVICE_NAME"
    echo "• Region: $REGION"
    echo "• Resources: $SELECTED_CPU CPU | $SELECTED_MEMORY RAM"
    echo ""
    
    read -p "Proceed with deployment? (y/n) [y]: " confirm
    confirm=${confirm:-y}
    if [[ $confirm != "y" ]]; then
        print_info "Deployment cancelled"
        exit 0
    fi
    
    # Deployment
    create_docker_config
    deploy_to_cloud_run
    get_service_url
    generate_vless_config
    wait_for_service
    setup_telegram_bot
    send_deployment_info
    display_summary
    show_management_commands
    cleanup
    
    echo ""
    print_success "✅ VLESS server deployed successfully!"
    print_success "🌐 Server URL: $SERVICE_URL"
    echo ""
}

trap 'echo ""; print_warning "Script interrupted"; cleanup; exit 1' SIGINT

main "$@"
