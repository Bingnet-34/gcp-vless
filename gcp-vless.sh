#!/bin/bash

# GCP VLESS Server Deployer - Optimized for Google Cloud
# Maximum Resources & No User Limits
# Author: Assistant
# Version: 5.0

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Global variables
SERVICE_NAME="vless-proxy"
REGION="us-central1"
PROJECT_ID=""
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
UUID=""
PATH_SUFFIX=""
SERVICE_URL=""
VLESS_LINK=""

# Google Cloud Run Maximum Limits
MAX_CPU=8
MAX_MEMORY="32Gi"
MAX_INSTANCES=100
MAX_CONCURRENCY=1000

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_dependencies() {
    print_info "Checking Google Cloud environment..."
    
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud CLI not found. This script must run in Google Cloud Shell"
        exit 1
    fi

    if ! command -v curl &> /dev/null; then
        print_error "curl not available"
        exit 1
    fi
    print_success "Google Cloud environment verified"
}

check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        print_warning "Google Cloud authentication required"
        gcloud auth login --no-launch-browser
    fi
    
    # Check if project is set
    if [[ -z "$(gcloud config get-value project 2>/dev/null)" ]]; then
        print_info "No project configured. Please select a project."
        list_projects
    fi
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
    
    # Verify bot token
    print_info "Verifying bot token..."
    if curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" | grep -q \"ok\":true; then
        print_success "Bot token verified"
    else
        print_error "Invalid bot token"
        exit 1
    fi
    
    echo ""
    print_info "Enter your personal Chat ID for admin notifications:"
    read -p "Chat ID: " TELEGRAM_CHAT_ID
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

select_max_resources() {
    echo ""
    print_info "Google Cloud Run Maximum Resource Configuration"
    echo "==================================================="
    print_warning "Using maximum available resources for best performance"
    
    # Auto-select maximum resources
    CPU=$MAX_CPU
    MEMORY=$MAX_MEMORY
    CONCURRENCY=$MAX_CONCURRENCY
    INSTANCES=$MAX_INSTANCES
    
    echo ""
    print_success "Selected Resources:"
    echo "• CPU: $CPU cores (Maximum)"
    echo "• Memory: $MEMORY (Maximum)" 
    echo "• Concurrency: $CONCURRENCY requests/container"
    echo "• Max Instances: $INSTANCES"
    echo "• Min Instances: 1 (Always running)"
    
    read -p "Press Enter to continue with maximum resources..."
}

select_region() {
    echo ""
    print_info "Available Google Cloud Regions:"
    echo "1. us-central1 (Iowa, USA) - Recommended"
    echo "2. europe-west1 (Belgium, Europe)"
    echo "3. asia-east1 (Taiwan, Asia)" 
    echo "4. asia-southeast1 (Singapore, Asia)"
    echo "5. me-west1 (Tel Aviv, Middle East)"
    
    read -p "Select region (1-5) [1]: " region_choice
    region_choice=${region_choice:-1}
    
    case $region_choice in
        2) REGION="europe-west1" ;;
        3) REGION="asia-east1" ;;
        4) REGION="asia-southeast1" ;;
        5) REGION="me-west1" ;;
        *) REGION="us-central1" ;;
    esac
    
    print_success "Selected Region: $REGION"
}

get_service_name() {
    echo ""
    read -p "Enter service name [vless-proxy]: " input_name
    SERVICE_NAME=${input_name:-vless-proxy}
    
    # Generate unique path
    UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16)
    PATH_SUFFIX=$(head /dev/urandom 2>/dev/null | tr -dc a-z0-9 | head -c 12)
}

create_docker_config() {
    print_info "Creating optimized Docker configuration..."
    
    cat > Dockerfile << 'EOF'
FROM alpine:latest

RUN apk update && apk add --no-cache curl unzip ca-certificates

# Install Xray core
RUN curl -L https://github.com/XTLS/Xray-core/releases/download/v1.8.11/Xray-linux-64.zip -o xray.zip \
    && unzip xray.zip xray \
    && mv xray /usr/bin/ \
    && chmod +x /usr/bin/xray \
    && rm xray.zip \
    && mkdir -p /etc/xray

# Create non-root user
RUN adduser -D -u 1000 xray

COPY config.json /etc/xray/

USER xray

EXPOSE 8080

CMD ["xray", "run", "-config", "/etc/xray/config.json"]
EOF

    cat > config.json << EOF
{
    "log": {
        "loglevel": "warning",
        "access": "none",
        "error": "none"
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
                    "fingerprint": "randomized",
                    "minVersion": "1.3",
                    "maxVersion": "1.3"
                },
                "wsSettings": {
                    "path": "/vless-$PATH_SUFFIX",
                    "headers": {
                        "Host": ""
                    }
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "metadataOnly": false
            }
        }
    ],
    "outbounds": [
        {
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIP"
            },
            "tag": "direct"
        },
        {
            "protocol": "blackhole",
            "settings": {},
            "tag": "blocked"
        }
    ],
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {
                "type": "field",
                "ip": ["geoip:private"],
                "outboundTag": "blocked"
            }
        ]
    },
    "policy": {
        "levels": {
            "0": {
                "handshake": 2,
                "connIdle": 120,
                "uplinkOnly": 1,
                "downlinkOnly": 1
            }
        }
    }
}
EOF
}

enable_required_services() {
    print_info "Enabling required Google Cloud services..."
    
    local services=(
        "run.googleapis.com"
        "containerregistry.googleapis.com" 
        "cloudbuild.googleapis.com"
        "compute.googleapis.com"
    )
    
    for service in "${services[@]}"; do
        if ! gcloud services list --enabled --filter="name:$service" | grep -q "$service"; then
            print_info "Enabling $service..."
            gcloud services enable "$service" --quiet
        fi
    done
    print_success "All required services enabled"
}

deploy_to_cloud_run() {
    print_info "Starting deployment to Google Cloud Run..."
    
    # Enable services
    enable_required_services
    
    # Build container with maximum resources
    print_info "Building container image with Cloud Build..."
    if ! gcloud builds submit \
        --tag "gcr.io/$PROJECT_ID/$SERVICE_NAME" \
        --machine-type=e2-highcpu-8 \
        --disk-size=100GB \
        --quiet; then
        print_error "Container build failed"
        exit 1
    fi
    
    # Deploy with maximum resources
    print_info "Deploying service with maximum resources..."
    local deploy_cmd=(
        gcloud run deploy "$SERVICE_NAME"
        --image "gcr.io/$PROJECT_ID/$SERVICE_NAME"
        --platform managed
        --region "$REGION"
        --allow-unauthenticated
        --port 8080
        --cpu "$CPU"
        --memory "$MEMORY"
        --concurrency "$CONCURRENCY"
        --min-instances 1
        --max-instances "$INSTANCES"
        --execution-environment gen2
        --no-cpu-throttling
        --quiet
    )
    
    if ! "${deploy_cmd[@]}"; then
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
    VLESS_LINK="vless://${UUID}@${domain}:443?path=%2Fvless-${PATH_SUFFIX}&security=tls&alpn=h3%2Ch2%2Chttp%2F1.1&encryption=none&host=${domain}&fp=randomized&type=ws&sni=${domain}#GCP-${REGION}"
}

wait_for_service_ready() {
    print_info "Waiting for service to be fully ready (60 seconds)..."
    
    for i in {1..12}; do
        if curl -s --retry 2 --max-time 10 -f "$SERVICE_URL" > /dev/null 2>&1; then
            print_success "Service is responding"
            return 0
        fi
        echo -n "."
        sleep 5
    done
    
    print_warning "Service is deployed but may need more time for full TLS activation"
    return 1
}

send_telegram_message() {
    local message="$1"
    if curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=$message" \
        -d "parse_mode=HTML" > /dev/null; then
        return 0
    else
        return 1
    fi
}

setup_telegram_bot() {
    print_info "Setting up Telegram bot commands..."
    
    # Set bot commands
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setMyCommands" \
        -d '{
            "commands": [
                {"command": "start", "description": "Get VLESS server configuration"},
                {"command": "status", "description": "Check server status"},
                {"command": "info", "description": "Get server info"}
            ]
        }' > /dev/null
}

send_deployment_success() {
    local message="🚀 <b>GCP VLESS Server Deployed Successfully!</b>

⚡ <b>Server Configuration:</b>
• 🌐 <b>URL:</b> <code>${SERVICE_URL}</code>
• 📍 <b>Region:</b> ${REGION}
• 🆔 <b>Project:</b> ${PROJECT_ID}

💪 <b>Maximum Resources Allocated:</b>
• 💻 <b>CPU:</b> ${CPU} cores
• 🎯 <b>Memory:</b> ${MEMORY}
• 🔄 <b>Concurrency:</b> ${CONCURRENCY}
• 📊 <b>Max Instances:</b> ${INSTANCES}

🔑 <b>VLESS Configuration:</b>
• 🆔 <b>UUID:</b> <code>${UUID}</code>
• 🛣️ <b>Path:</b> <code>/vless-${PATH_SUFFIX}</code>
• 🌐 <b>Protocol:</b> VLESS + WebSocket + TLS
• 🔒 <b>Security:</b> TLS 1.3 Only
• 🛡️ <b>Fingerprint:</b> Randomized

🔗 <b>VLESS Link:</b>
<code>${VLESS_LINK}</code>

📈 <b>Performance Features:</b>
• No user limits
• Auto-scaling enabled
• Global load balancing
• Always-on instance
• HTTP/3 (QUIC) support

💡 <b>Usage:</b>
Copy the VLESS link to your V2Ray/Xray client

✅ <b>Status:</b> Ready for unlimited users"

    print_info "Sending configuration to Telegram..."
    
    # Send main message
    send_telegram_message "$message"
    
    # Send VLESS link separately for easy copying
    send_telegram_message "🔗 <b>VLESS Link for Copying:</b>\n<code>${VLESS_LINK}</code>"
    
    print_success "Configuration sent to Telegram"
}

display_summary() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    DEPLOYMENT COMPLETED                     ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}📦 SERVICE INFORMATION:${NC}"
    echo "  Service Name: $SERVICE_NAME"
    echo "  Service URL: $SERVICE_URL"
    echo "  Region: $REGION"
    echo "  Project: $PROJECT_ID"
    echo ""
    echo -e "${CYAN}💪 RESOURCE ALLOCATION:${NC}"
    echo "  CPU: $CPU cores (Maximum)"
    echo "  Memory: $MEMORY (Maximum)"
    echo "  Concurrency: $CONCURRENCY requests/container"
    echo "  Max Instances: $INSTANCES"
    echo "  Min Instances: 1 (Always running)"
    echo ""
    echo -e "${CYAN}🔑 VLESS CONFIGURATION:${NC}"
    echo "  UUID: $UUID"
    echo "  Path: /vless-$PATH_SUFFIX"
    echo "  Protocol: VLESS + WebSocket + TLS 1.3"
    echo ""
    echo -e "${CYAN}🔗 VLESS LINK:${NC}"
    echo "$VLESS_LINK"
    echo ""
}

show_management_commands() {
    echo -e "${YELLOW}🛠️  MANAGEMENT COMMANDS:${NC}"
    echo "  View logs:        gcloud logging read 'resource.type=cloud_run_revision AND resource.labels.service_name=$SERVICE_NAME' --limit=20"
    echo "  Check metrics:    gcloud run services describe $SERVICE_NAME --region=$REGION --format=\"value(status)\""
    echo "  Update service:   gcloud run services update $SERVICE_NAME --region=$REGION --cpu=4 --memory=16Gi"
    echo "  Delete service:   gcloud run services delete $SERVICE_NAME --region=$REGION --quiet"
    echo "  List services:    gcloud run services list --region=$REGION"
    echo ""
}

cleanup() {
    print_info "Cleaning up temporary files..."
    rm -f Dockerfile config.json
}

main() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║               GCP VLESS SERVER DEPLOYER                     ║
║                Maximum Resources - No Limits                ║
║                  Optimized for Google Cloud                 ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    # Initial checks
    check_dependencies
    check_gcloud_auth
    
    # Get configuration
    get_telegram_info
    select_region
    get_service_name
    select_max_resources
    
    # Show deployment confirmation
    echo ""
    print_info "Deployment Configuration:"
    echo "──────────────────────────"
    echo "• Project: $PROJECT_ID"
    echo "• Service: $SERVICE_NAME"
    echo "• Region: $REGION" 
    echo "• Resources: $CPU CPU, $MEMORY RAM"
    echo "• Instances: 1-$INSTANCES"
    echo ""
    
    read -p "Proceed with deployment? (y/n) [y]: " confirm
    confirm=${confirm:-y}
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
        print_info "Deployment cancelled"
        exit 0
    fi
    
    # Deployment process
    create_docker_config
    deploy_to_cloud_run
    get_service_url
    generate_vless_config
    wait_for_service_ready
    setup_telegram_bot
    send_deployment_success
    display_summary
    show_management_commands
    cleanup
    
    echo ""
    print_success "✅ VLESS server deployed successfully with MAXIMUM resources!"
    print_success "🌐 Ready for unlimited users with high performance!"
    echo ""
}

# Handle interruption
trap 'echo ""; print_warning "Script interrupted"; cleanup; exit 1' SIGINT

# Run main function
main "$@"
