#!/bin/bash

# GCP VLESS Server Deployer with Telegram Bot
# Complete version with proper resource configuration
# Author: Assistant
# Version: 3.0

set -e

# Colors for output
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

# Resource configurations
declare -A CPU_OPTIONS=(
    [1]="1 CPU (Default)"
    [2]="2 CPU"
    [4]="4 CPU"
)

declare -A MEMORY_OPTIONS=(
    [1]="512Mi (Default)"
    [2]="1Gi"
    [3]="2Gi"
    [4]="4Gi"
)

declare -A CONCURRENCY_OPTIONS=(
    [1]="80 (Default)"
    [2]="100"
    [3]="250"
    [4]="500"
    [5]="1000"
)

# Functions
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_dependencies() {
    print_info "Checking dependencies..."
    
    local deps=("gcloud" "curl")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            print_error "$dep is not installed. Please install it first."
            exit 1
        fi
    done
    print_success "All dependencies are installed"
}

check_gcloud_auth() {
    if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        print_warning "Please login to Google Cloud first"
        gcloud auth login --no-launch-browser
    fi
}

get_telegram_info() {
    echo ""
    print_info "Telegram Bot Configuration"
    echo "============================"
    
    while true; do
        read -p "Enter Telegram Bot Token: " TELEGRAM_BOT_TOKEN
        if [[ -n "$TELEGRAM_BOT_TOKEN" ]]; then
            break
        else
            print_error "Bot token is required"
        fi
    done
    
    while true; do
        read -p "Enter Chat ID: " TELEGRAM_CHAT_ID
        if [[ -n "$TELEGRAM_CHAT_ID" ]]; then
            break
        else
            print_error "Chat ID is required"
        fi
    done
}

select_resource_config() {
    echo ""
    print_info "Server Resource Configuration"
    echo "================================"
    
    # CPU Selection
    echo ""
    print_info "CPU Options:"
    for key in "${!CPU_OPTIONS[@]}"; do
        echo "  $key. ${CPU_OPTIONS[$key]}"
    done
    while true; do
        read -p "Select CPU option (1-4) [Default: 1]: " cpu_choice
        cpu_choice=${cpu_choice:-1}
        if [[ $cpu_choice =~ ^[1-4]$ ]]; then
            case $cpu_choice in
                1) CPU="1";;
                2) CPU="2";;
                3) CPU="4";;
                4) CPU="8";;
            esac
            break
        else
            print_error "Invalid choice. Please select 1-4"
        fi
    done
    
    # Memory Selection
    echo ""
    print_info "Memory Options:"
    for key in "${!MEMORY_OPTIONS[@]}"; do
        echo "  $key. ${MEMORY_OPTIONS[$key]}"
    done
    while true; do
        read -p "Select Memory option (1-4) [Default: 1]: " memory_choice
        memory_choice=${memory_choice:-1}
        if [[ $memory_choice =~ ^[1-4]$ ]]; then
            case $memory_choice in
                1) MEMORY="512Mi";;
                2) MEMORY="1Gi";;
                3) MEMORY="2Gi";;
                4) MEMORY="4Gi";;
            esac
            break
        else
            print_error "Invalid choice. Please select 1-4"
        fi
    done
    
    # Concurrency Selection
    echo ""
    print_info "Concurrency Options (requests per container):"
    for key in "${!CONCURRENCY_OPTIONS[@]}"; do
        echo "  $key. ${CONCURRENCY_OPTIONS[$key]}"
    done
    while true; do
        read -p "Select Concurrency option (1-5) [Default: 1]: " concurrency_choice
        concurrency_choice=${concurrency_choice:-1}
        if [[ $concurrency_choice =~ ^[1-5]$ ]]; then
            case $concurrency_choice in
                1) CONCURRENCY="80";;
                2) CONCURRENCY="100";;
                3) CONCURRENCY="250";;
                4) CONCURRENCY="500";;
                5) CONCURRENCY="1000";;
            esac
            break
        else
            print_error "Invalid choice. Please select 1-5"
        fi
    done
    
    # Auto-scaling configuration
    echo ""
    read -p "Enable auto-scaling? (y/n) [Default: y]: " enable_autoscaling
    enable_autoscaling=${enable_autoscaling:-y}
    if [[ $enable_autoscaling == "y" || $enable_autoscaling == "Y" ]]; then
        MIN_INSTANCES="0"
        MAX_INSTANCES="10"
    else
        MIN_INSTANCES="1"
        MAX_INSTANCES="1"
    fi
}

get_project_info() {
    echo ""
    print_info "Google Cloud Configuration"
    echo "============================"
    
    # Get current project
    CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)
    
    if [[ -n "$CURRENT_PROJECT" ]]; then
        print_info "Current project: $CURRENT_PROJECT"
        read -p "Use this project? (y/n) [Default: y]: " use_current
        use_current=${use_current:-y}
        if [[ $use_current == "y" || $use_current == "Y" ]]; then
            PROJECT_ID=$CURRENT_PROJECT
        else
            list_projects
        fi
    else
        list_projects
    fi
    
    # Region selection
    echo ""
    print_info "Available Regions:"
    echo "1. us-central1 (USA)"
    echo "2. europe-west1 (Europe)" 
    echo "3. asia-east1 (Asia)"
    echo "4. me-west1 (Middle East)"
    read -p "Select region (1-4) [Default: 1]: " region_choice
    region_choice=${region_choice:-1}
    case $region_choice in
        2) REGION="europe-west1" ;;
        3) REGION="asia-east1" ;;
        4) REGION="me-west1" ;;
        *) REGION="us-central1" ;;
    esac
    
    # Service name
    echo ""
    read -p "Enter service name [Default: vless-server]: " SERVICE_NAME
    SERVICE_NAME=${SERVICE_NAME:-vless-server}
    
    # Generate UUID and path
    UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16)
    PATH_SUFFIX=$(head /dev/urandom 2>/dev/null | tr -dc a-z0-9 | head -c 10)
}

list_projects() {
    print_info "Fetching project list..."
    gcloud projects list --format="table(projectId,name)" --sort-by=projectId
    
    echo ""
    while true; do
        read -p "Enter Project ID: " PROJECT_ID
        if [[ -n "$PROJECT_ID" ]]; then
            if gcloud projects describe $PROJECT_ID &>/dev/null; then
                gcloud config set project $PROJECT_ID
                break
            else
                print_error "Project doesn't exist or you don't have access"
            fi
        fi
    done
}

send_telegram_message() {
    local message="$1"
    if curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=$message" \
        -d "parse_mode=HTML" > /dev/null; then
        print_success "Message sent to Telegram"
        return 0
    else
        print_warning "Failed to send message to Telegram"
        return 1
    fi
}

setup_telegram_bot_commands() {
    print_info "Setting up Telegram bot commands..."
    
    local commands='{
        "commands": [
            {"command": "start", "description": "Get VLESS server configuration"},
            {"command": "status", "description": "Check server status"},
            {"command": "info", "description": "Get server information"}
        ]
    }'
    
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setMyCommands" \
        -H "Content-Type: application/json" \
        -d "$commands" > /dev/null && print_success "Bot commands set successfully"
}

create_docker_config() {
    print_info "Creating Docker configuration..."
    
    cat > Dockerfile << EOF
FROM alpine:latest

RUN apk update && apk add --no-cache curl unzip

# Install Xray
RUN curl -L https://github.com/XTLS/Xray-core/releases/download/v1.8.11/Xray-linux-64.zip -o xray.zip && \
    unzip xray.zip xray && \
    mv xray /usr/bin/ && \
    chmod +x /usr/bin/xray && \
    rm xray.zip && \
    mkdir -p /etc/xray

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

deploy_to_cloud_run() {
    print_info "Deploying to Google Cloud Run..."
    
    # Enable required services
    print_info "Enabling required Google services..."
    gcloud services enable run.googleapis.com containerregistry.googleapis.com cloudbuild.googleapis.com --quiet
    
    # Build container
    print_info "Building container image (this may take 5-10 minutes)..."
    if ! gcloud builds submit --tag gcr.io/$PROJECT_ID/$SERVICE_NAME --quiet; then
        print_error "Failed to build container image"
        exit 1
    fi
    
    # Deploy service with selected resources
    print_info "Deploying service with ${CPU} CPU, ${MEMORY} memory..."
    local deploy_cmd="gcloud run deploy $SERVICE_NAME \
        --image gcr.io/$PROJECT_ID/$SERVICE_NAME \
        --platform managed \
        --region $REGION \
        --allow-unauthenticated \
        --port 8080 \
        --cpu $CPU \
        --memory $MEMORY \
        --concurrency $CONCURRENCY \
        --min-instances $MIN_INSTANCES \
        --max-instances $MAX_INSTANCES \
        --quiet"
    
    if ! eval $deploy_cmd; then
        print_error "Failed to deploy service"
        exit 1
    fi
}

get_service_info() {
    print_info "Getting service information..."
    SERVICE_URL=$(gcloud run services describe $SERVICE_NAME \
        --platform managed \
        --region $REGION \
        --format="value(status.url)" 2>/dev/null)
    
    if [[ -z "$SERVICE_URL" ]]; then
        print_error "Failed to get service URL"
        exit 1
    fi
}

generate_vless_config() {
    local domain=$(echo $SERVICE_URL | sed 's|https://||')
    VLESS_LINK="vless://${UUID}@${domain}:443?path=%2Fvless-${PATH_SUFFIX}&security=tls&alpn=h3%2Ch2%2Chttp%2F1.1&encryption=none&host=${domain}&fp=randomized&type=ws&sni=${domain}#${SERVICE_NAME}"
}

test_service() {
    print_info "Testing service (waiting 30 seconds for TLS activation)..."
    sleep 30
    
    if curl -s --retry 3 --retry-delay 5 -f "${SERVICE_URL}/health" > /dev/null 2>&1; then
        print_success "Service is responding correctly"
        return 0
    else
        print_warning "Service might need more time for full TLS activation"
        return 1
    fi
}

send_configuration_to_telegram() {
    print_info "Sending configuration to Telegram bot..."
    
    local message="🚀 <b>VLESS Server Successfully Deployed!</b>

📦 <b>Service Information:</b>
• 🔗 <b>URL:</b> <code>${SERVICE_URL}</code>
• 📍 <b>Region:</b> ${REGION}
• ⚡ <b>Platform:</b> Google Cloud Run

🖥️ <b>Server Resources:</b>
• 💻 <b>CPU:</b> ${CPU} core(s)
• 🎯 <b>Memory:</b> ${MEMORY}
• 🔄 <b>Concurrency:</b> ${CONCURRENCY} requests
• 📊 <b>Instances:</b> ${MIN_INSTANCES}-${MAX_INSTANCES}

🔑 <b>VLESS Configuration:</b>
• 🆔 <b>UUID:</b> <code>${UUID}</code>
• 🛣️ <b>Path:</b> <code>/vless-${PATH_SUFFIX}</code>
• 🌐 <b>Protocol:</b> VLESS + WebSocket + TLS
• 🔒 <b>Security:</b> TLS 1.3
• 🛡️ <b>Fingerprint:</b> Randomized

🔗 <b>VLESS Link:</b>
<code>${VLESS_LINK}</code>

💡 <b>Bot Commands Available:</b>
/start - Get this configuration
/status - Check server status
/info - Get server information

📝 <b>Note:</b> The link is ready to use in V2Ray/Xray clients"

    # Send main configuration message
    send_telegram_message "$message"
    
    # Send separate message with just the link for easy copying
    send_telegram_message "🔗 <b>VLESS Link for copying:</b>\n<code>${VLESS_LINK}</code>"
    
    # Set up bot commands
    setup_telegram_bot_commands
}

display_summary() {
    echo ""
    print_success "✅ Deployment Completed Successfully!"
    echo ""
    echo -e "${GREEN}Service Information:${NC}"
    echo "📦 Service Name: $SERVICE_NAME"
    echo "🌐 Service URL: $SERVICE_URL"
    echo "📍 Region: $REGION"
    echo ""
    echo -e "${GREEN}Resource Configuration:${NC}"
    echo "💻 CPU: $CPU"
    echo "🎯 Memory: $MEMORY"
    echo "🔄 Concurrency: $CONCURRENCY"
    echo "📊 Instances: $MIN_INSTANCES-$MAX_INSTANCES"
    echo ""
    echo -e "${GREEN}VLESS Configuration:${NC}"
    echo "🔑 UUID: $UUID"
    echo "🛣️ Path: /vless-$PATH_SUFFIX"
    echo "🔒 Security: TLS + WebSocket"
    echo ""
    echo -e "${CYAN}VLESS Link:${NC}"
    echo "$VLESS_LINK"
    echo ""
}

cleanup() {
    print_info "Cleaning up temporary files..."
    rm -f Dockerfile config.json
}

show_management_commands() {
    echo ""
    print_info "Management Commands:"
    echo "─────────────────────"
    echo "• View logs: gcloud logging read \"resource.type=cloud_run_revision AND resource.labels.service_name=$SERVICE_NAME\" --limit=10"
    echo "• Check status: gcloud run services describe $SERVICE_NAME --region=$REGION"
    echo "• Delete service: gcloud run services delete $SERVICE_NAME --region=$REGION --quiet"
    echo "• Scale service: gcloud run services update $SERVICE_NAME --region=$REGION --min-instances=1 --max-instances=5"
    echo ""
}

main() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════╗
║      GCP VLESS Server Deployer      ║
║        With Telegram Bot Integration║
║           VLESS + WS + TLS          ║
╚══════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    # Initial checks
    check_dependencies
    check_gcloud_auth
    
    # Get configuration
    get_project_info
    get_telegram_info
    select_resource_config
    
    # Show configuration summary
    echo ""
    print_info "Deployment Configuration Summary:"
    echo "──────────────────────────────────"
    echo "• Project: $PROJECT_ID"
    echo "• Service: $SERVICE_NAME"
    echo "• Region: $REGION"
    echo "• CPU: $CPU"
    echo "• Memory: $MEMORY"
    echo "• Concurrency: $CONCURRENCY"
    echo "• UUID: $UUID"
    echo ""
    
    read -p "Proceed with deployment? (y/n) [Default: y]: " confirm
    confirm=${confirm:-y}
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
        print_info "Deployment cancelled"
        exit 0
    fi
    
    # Deployment process
    create_docker_config
    deploy_to_cloud_run
    get_service_info
    generate_vless_config
    test_service
    send_configuration_to_telegram
    display_summary
    show_management_commands
    cleanup
    
    print_success "Deployment completed successfully! 🎉"
}

# Handle script interruption
trap 'echo ""; print_warning "Script interrupted"; cleanup; exit 1' SIGINT

# Run main function
main "$@"
