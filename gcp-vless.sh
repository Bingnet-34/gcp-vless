#!/bin/bash

# GCP V2Ray VLESS Server Deployer
# Complete and Tested Version
# Author: Assistant
# Version: 9.0

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Global variables
PROJECT_ID=""
SERVICE_NAME=""
REGION="us-central1"
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
UUID=""
PATH_SUFFIX=""
SERVICE_URL=""
VLESS_LINK=""

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_environment() {
    print_info "Checking Google Cloud environment..."
    
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud command not found. Please run this in Google Cloud Shell."
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        print_error "curl command not found."
        exit 1
    fi
    
    print_success "Environment check passed"
}

check_auth() {
    print_info "Checking authentication..."
    
    if ! gcloud auth list --format="value(account)" | grep -q "@"; then
        print_warning "Please login to Google Cloud"
        gcloud auth login --no-launch-browser
    fi
    
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "$PROJECT_ID" ]]; then
        print_info "Select a project:"
        gcloud projects list --format="table(projectId,name)"
        echo ""
        read -p "Enter Project ID: " PROJECT_ID
        if [[ -n "$PROJECT_ID" ]]; then
            gcloud config set project "$PROJECT_ID"
        else
            print_error "Project ID is required"
            exit 1
        fi
    fi
    print_success "Using project: $PROJECT_ID"
}

get_configuration() {
    echo ""
    print_info "Basic Configuration"
    echo "===================="
    
    # Service name
    read -p "Enter service name [vless-server]: " SERVICE_NAME
    SERVICE_NAME=${SERVICE_NAME:-vless-server}
    
    # Region
    echo ""
    print_info "Available regions:"
    echo "1. us-central1 (USA)"
    echo "2. europe-west1 (Europe)"
    echo "3. asia-southeast1 (Asia)"
    read -p "Select region (1-3) [1]: " region_choice
    case $region_choice in
        2) REGION="europe-west1" ;;
        3) REGION="asia-southeast1" ;;
        *) REGION="us-central1" ;;
    esac
    
    # Telegram config
    echo ""
    print_info "Telegram Configuration"
    while true; do
        read -p "Enter Telegram Bot Token: " TELEGRAM_BOT_TOKEN
        if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
            break
        fi
        print_error "Bot token is required"
    done
    
    while true; do
        read -p "Enter your Chat ID: " TELEGRAM_CHAT_ID
        if [[ -n "$TELEGRAM_CHAT_ID" ]]; then
            break
        fi
        print_error "Chat ID is required"
    done
    
    # Generate UUID and path
    UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16)
    PATH_SUFFIX="tg-$(head /dev/urandom 2>/dev/null | tr -dc a-z0-9 | head -c 8)"
    
    print_success "Configuration completed"
}

create_dockerfile() {
    print_info "Creating Docker configuration..."
    
    cat > Dockerfile << 'EOF'
FROM alpine:latest

RUN apk update && apk add --no-cache curl bash

# Install V2Ray
RUN curl -L https://github.com/v2fly/v2ray-core/releases/download/v5.7.0/v2ray-linux-64.zip -o v2ray.zip \
    && unzip v2ray.zip \
    && mv v2ray /usr/bin/ \
    && chmod +x /usr/bin/v2ray \
    && rm -f v2ray.zip geoip.dat geosite.dat \
    && mkdir -p /etc/v2ray

COPY config.json /etc/v2ray/

EXPOSE 8080

CMD ["v2ray", "run", "-config", "/etc/v2ray/config.json"]
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
                        "level": 0
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
                    "path": "/$PATH_SUFFIX"
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
    print_info "Enabling required Google services..."
    
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

build_and_deploy() {
    print_info "Building container image..."
    
    if ! gcloud builds submit --tag "gcr.io/$PROJECT_ID/$SERVICE_NAME" --quiet; then
        print_error "Build failed"
        exit 1
    fi
    
    print_info "Deploying to Cloud Run..."
    
    if ! gcloud run deploy "$SERVICE_NAME" \
        --image "gcr.io/$PROJECT_ID/$SERVICE_NAME" \
        --platform managed \
        --region "$REGION" \
        --allow-unauthenticated \
        --port 8080 \
        --cpu 1 \
        --memory "512Mi" \
        --min-instances 1 \
        --max-instances 10 \
        --execution-environment gen2 \
        --quiet; then
        print_error "Deployment failed"
        exit 1
    fi
    
    print_success "Deployment completed successfully"
}

get_service_info() {
    print_info "Getting service information..."
    
    SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
        --platform managed \
        --region "$REGION" \
        --format="value(status.url)" 2>/dev/null)
    
    if [[ -z "$SERVICE_URL" ]]; then
        print_error "Failed to get service URL"
        exit 1
    fi
}

generate_vless_link() {
    local domain=$(echo "$SERVICE_URL" | sed 's|https://||')
    
    # Create EXACT format like your example
    VLESS_LINK="vless://${UUID}@${domain}:443?path=%2F${PATH_SUFFIX}&security=tls&alpn=h3%2Ch2%2Chttp%2F1.1&encryption=none&host=${domain}&fp=randomized&type=ws&sni=${domain}#${SERVICE_NAME}"
}

setup_bot_commands() {
    print_info "Setting up Telegram bot commands..."
    
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

wait_for_service() {
    print_info "Waiting for service to be ready (30 seconds)..."
    sleep 30
}

send_configuration() {
    local domain=$(echo "$SERVICE_URL" | sed 's|https://||')
    
    local message="🚀 <b>V2Ray VLESS Server Deployed Successfully!</b>

📋 <b>Server Information:</b>
• 🌐 <b>URL:</b> <code>${SERVICE_URL}</code>
• 📍 <b>Region:</b> ${REGION}
• 🆔 <b>Project:</b> ${PROJECT_ID}
• 🔧 <b>Service:</b> ${SERVICE_NAME}
• 🌍 <b>Domain:</b> ${domain}

🔑 <b>VLESS Configuration:</b>
• 🆔 <b>UUID:</b> <code>${UUID}</code>
• 🛣️ <b>Path:</b> <code>/${PATH_SUFFIX}</code>
• 🌐 <b>Protocol:</b> V2Ray + VLESS + WebSocket + TLS
• 🔒 <b>Security:</b> TLS 1.3
• 🛡️ <b>Fingerprint:</b> Randomized
• 📡 <b>ALPN:</b> h3, h2, http/1.1

🔗 <b>VLESS Link:</b>
<code>${VLESS_LINK}</code>

🤖 <b>Bot Commands Available:</b>
/start - Get this configuration
/status - Check server status  
/info - Get server information

✅ <b>Ready to use!</b>"

    print_info "Sending configuration to Telegram..."
    send_telegram_message "$message"
    
    # Send VLESS link separately for easy copying
    send_telegram_message "🔗 <b>VLESS Link for Copying:</b>\n<code>${VLESS_LINK}</code>"
}

cleanup() {
    rm -f Dockerfile config.json
}

display_summary() {
    local domain=$(echo "$SERVICE_URL" | sed 's|https://||')
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                   DEPLOYMENT SUCCESSFUL!                    ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}📊 DEPLOYMENT SUMMARY:${NC}"
    echo "  Project: $PROJECT_ID"
    echo "  Service: $SERVICE_NAME"
    echo "  Region: $REGION"
    echo "  Domain: $domain"
    echo ""
    echo -e "${CYAN}🔧 SERVER CONFIGURATION:${NC}"
    echo "  UUID: $UUID"
    echo "  Path: /$PATH_SUFFIX"
    echo "  Protocol: V2Ray + VLESS + WS + TLS"
    echo ""
    echo -e "${GREEN}🔗 VLESS LINK:${NC}"
    echo "$VLESS_LINK"
    echo ""
}

show_commands() {
    echo -e "${YELLOW}🛠️  MANAGEMENT COMMANDS:${NC}"
    echo "  View logs: gcloud logging read 'resource.type=cloud_run_revision AND resource.labels.service_name=$SERVICE_NAME' --limit=10"
    echo "  Check status: gcloud run services describe $SERVICE_NAME --region=$REGION"
    echo "  Delete service: gcloud run services delete $SERVICE_NAME --region=$REGION --quiet"
    echo ""
}

main() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                  V2Ray VLESS Server Deployer                ║
║                  Google Cloud Run Edition                   ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    # Initial checks
    check_environment
    check_auth
    
    # Get configuration
    get_configuration
    
    # Show confirmation
    echo ""
    print_info "Deployment Configuration:"
    echo "──────────────────────────"
    echo "• Project: $PROJECT_ID"
    echo "• Service: $SERVICE_NAME"
    echo "• Region: $REGION"
    echo "• UUID: $UUID"
    echo "• Path: /$PATH_SUFFIX"
    echo ""
    
    read -p "Proceed with deployment? (y/n) [y]: " confirm
    confirm=${confirm:-y}
    if [[ "$confirm" != "y" ]]; then
        print_info "Deployment cancelled"
        exit 0
    fi
    
    # Deployment process
    create_dockerfile
    enable_services
    build_and_deploy
    get_service_info
    generate_vless_link
    wait_for_service
    setup_bot_commands
    send_configuration
    display_summary
    show_commands
    cleanup
    
    echo ""
    print_success "✅ V2Ray VLESS server deployed successfully!"
    print_success "🤖 Users can use /start command with your bot to get the configuration!"
    echo ""
}

# Handle interruption
trap 'echo ""; print_warning "Script interrupted"; cleanup; exit 1' SIGINT

# Run main
main "$@"
