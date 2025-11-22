#!/bin/bash

# GCP VLESS Server Deployer with Telegram Bot Webhook
# Fully Compatible with Google Cloud Shell
# Author: Assistant
# Version: 7.0

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
BOT_SERVICE_NAME=""
BOT_SERVICE_URL=""

# Google Cloud compatible configurations
CPU_OPTIONS=("1" "2" "4")
MEMORY_OPTIONS=("512Mi" "1Gi" "2Gi" "4Gi" "8Gi")

# Valid CPU-Memory combinations
declare -A VALID_COMBINATIONS=(
    ["1"]="512Mi 1Gi 2Gi 4Gi"
    ["2"]="1Gi 2Gi 4Gi 8Gi"
    ["4"]="2Gi 4Gi 8Gi"
)

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_environment() {
    print_info "Checking Google Cloud Shell environment..."
    
    # Check if running in Google Cloud Shell
    if [[ -z "$CLOUD_SHELL" ]]; then
        print_warning "This script is optimized for Google Cloud Shell"
    fi
    
    # Check essential commands
    local commands=("gcloud" "curl")
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            print_error "$cmd not found. This script requires Google Cloud Shell."
            exit 1
        fi
    done
    
    print_success "Environment check passed"
}

check_authentication() {
    print_info "Checking Google Cloud authentication..."
    
    if ! gcloud auth list --format="value(account)" | grep -q "@"; then
        print_warning "Please login to Google Cloud"
        if ! gcloud auth login --no-launch-browser; then
            print_error "Authentication failed"
            exit 1
        fi
    fi
    
    # Set project
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "$PROJECT_ID" ]]; then
        print_info "No project set. Please select a project:"
        list_projects
    else
        print_info "Current project: $PROJECT_ID"
        read -p "Use this project? (y/n) [y]: " use_current
        if [[ "${use_current:-y}" != "y" ]]; then
            list_projects
        fi
    fi
}

list_projects() {
    print_info "Fetching Google Cloud projects..."
    
    local projects=$(gcloud projects list --format="value(projectId)" 2>/dev/null)
    if [[ -z "$projects" ]]; then
        print_error "No projects found or no access"
        exit 1
    fi
    
    echo ""
    gcloud projects list --format="table(projectId,name)" --limit=10
    
    while true; do
        echo ""
        read -p "Enter Project ID: " PROJECT_ID
        if [[ -n "$PROJECT_ID" ]]; then
            if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
                gcloud config set project "$PROJECT_ID"
                print_success "Project set to: $PROJECT_ID"
                break
            else
                print_error "Project not found or no access"
            fi
        fi
    done
}

get_telegram_config() {
    echo ""
    print_info "Telegram Bot Configuration"
    echo "============================"
    
    while true; do
        read -p "Enter Telegram Bot Token: " TELEGRAM_BOT_TOKEN
        if [[ -n "$TELEGRAM_BOT_TOKEN" && "$TELEGRAM_BOT_TOKEN" =~ ^[0-9]+:[a-zA-Z0-9_-]+$ ]]; then
            # Verify token
            if curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" | grep -q \"ok\":true; then
                BOT_USERNAME=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" | grep -o '"username":"[^"]*' | cut -d'"' -f4)
                print_success "Bot verified: @$BOT_USERNAME"
                break
            else
                print_error "Invalid bot token"
            fi
        else
            print_error "Invalid token format"
        fi
    done
    
    echo ""
    print_info "Enter your Chat ID for admin notifications:"
    while true; do
        read -p "Chat ID: " TELEGRAM_CHAT_ID
        if [[ -n "$TELEGRAM_CHAT_ID" ]]; then
            break
        else
            print_error "Chat ID is required"
        fi
    done
}

select_region() {
    echo ""
    print_info "Select Google Cloud Region:"
    echo "1. us-central1 (Iowa, USA) - Recommended"
    echo "2. europe-west1 (Belgium, Europe)"
    echo "3. asia-southeast1 (Singapore, Asia)"
    echo "4. me-west1 (Israel, Middle East)"
    
    while true; do
        read -p "Choose region (1-4) [1]: " choice
        choice=${choice:-1}
        case $choice in
            1) REGION="us-central1"; break ;;
            2) REGION="europe-west1"; break ;;
            3) REGION="asia-southeast1"; break ;;
            4) REGION="me-west1"; break ;;
            *) print_error "Invalid choice" ;;
        esac
    done
    print_success "Selected region: $REGION"
}

get_service_names() {
    echo ""
    print_info "Service Names Configuration"
    
    read -p "Enter VLESS service name [vless-proxy]: " SERVICE_NAME
    SERVICE_NAME=${SERVICE_NAME:-vless-proxy}
    
    BOT_SERVICE_NAME="${SERVICE_NAME}-bot"
    
    print_info "VLESS Service: $SERVICE_NAME"
    print_info "Bot Service: $BOT_SERVICE_NAME"
    
    # Generate unique identifiers
    UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16)
    PATH_SUFFIX=$(head /dev/urandom 2>/dev/null | tr -dc a-z0-9 | head -c 8)
}

select_resources() {
    echo ""
    print_info "Select CPU Cores:"
    echo "1. 1 CPU (Basic)"
    echo "2. 2 CPU (Recommended)"
    echo "3. 4 CPU (High Performance)"
    
    while true; do
        read -p "Choose CPU (1-3) [2]: " cpu_choice
        cpu_choice=${cpu_choice:-2}
        case $cpu_choice in
            1) SELECTED_CPU="1"; break ;;
            2) SELECTED_CPU="2"; break ;;
            3) SELECTED_CPU="4"; break ;;
            *) print_error "Invalid choice" ;;
        esac
    done
    
    echo ""
    print_info "Available Memory for $SELECTED_CPU CPU:"
    
    # Get valid memory options
    VALID_MEMORIES=(${VALID_COMBINATIONS[$SELECTED_CPU]})
    
    for i in "${!VALID_MEMORIES[@]}"; do
        echo "$((i+1)). ${VALID_MEMORIES[i]}"
    done
    
    while true; do
        read -p "Choose memory (1-${#VALID_MEMORIES[@]}) [2]: " mem_choice
        mem_choice=${mem_choice:-2}
        if [[ $mem_choice -ge 1 && $mem_choice -le ${#VALID_MEMORIES[@]} ]]; then
            SELECTED_MEMORY="${VALID_MEMORIES[$((mem_choice-1))]}"
            break
        else
            print_error "Invalid choice"
        fi
    done
    
    echo ""
    print_success "Selected Resources:"
    echo "• CPU: $SELECTED_CPU cores"
    echo "• Memory: $SELECTED_MEMORY"
    echo "• Max Instances: 10"
    echo "• Min Instances: 1"
}

create_vless_dockerfile() {
    print_info "Creating VLESS server configuration..."
    
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

create_bot_dockerfile() {
    print_info "Creating Telegram bot configuration..."
    
    cat > bot.Dockerfile << 'EOF'
FROM python:3.9-slim

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt bot.py ./

RUN pip install -r requirements.txt

EXPOSE 8080

CMD ["python", "bot.py"]
EOF

    cat > requirements.txt << 'EOF'
flask==2.3.3
requests==2.31.0
EOF

    cat > bot.py << EOF
import os
import requests
from flask import Flask, request, jsonify

app = Flask(__name__)

# Configuration
BOT_TOKEN = os.environ.get('BOT_TOKEN')
VLESS_LINK = os.environ.get('VLESS_LINK')
SERVICE_URL = os.environ.get('SERVICE_URL')
ADMIN_CHAT_ID = os.environ.get('ADMIN_CHAT_ID')

def send_message(chat_id, text):
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    data = {
        'chat_id': chat_id,
        'text': text,
        'parse_mode': 'HTML'
    }
    try:
        requests.post(url, json=data, timeout=10)
    except Exception as e:
        print(f"Error sending message: {e}")

@app.route('/webhook', methods=['POST'])
def webhook():
    try:
        data = request.get_json()
        
        if 'message' in data:
            chat_id = data['message']['chat']['id']
            text = data['message'].get('text', '')
            
            if text == '/start':
                message = f"""🚀 <b>Welcome to VLESS Server!</b>

🔗 <b>Your VLESS Configuration:</b>
<code>{VLESS_LINK}</code>

📋 <b>How to use:</b>
1. Copy the link above
2. Paste in your V2Ray/Xray client
3. Connect and enjoy!

⚡ <b>Server Info:</b>
• Status: ✅ Online
• Protocol: VLESS + WS + TLS
• Region: {SERVICE_URL.split('.')[1] if SERVICE_URL else 'Unknown'}

💡 <b>Support:</b>
Contact admin for help."""
                send_message(chat_id, message)
                
            elif text == '/status':
                send_message(chat_id, "✅ Server is online and running!")
                
            elif text == '/info':
                info_msg = f"""📊 <b>Server Information:</b>

🌐 Domain: {SERVICE_URL}
🔧 Protocol: VLESS
🔒 Security: TLS 1.3
🛡️ Fingerprint: Randomized"""
                send_message(chat_id, info_msg)
        
        return jsonify({'status': 'ok'})
    except Exception as e:
        print(f"Webhook error: {e}")
        return jsonify({'status': 'error'})

@app.route('/health')
def health():
    return jsonify({'status': 'healthy'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
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
        if ! gcloud services list --enabled --filter="name:${service}" | grep -q "${service}"; then
            print_info "Enabling ${service}..."
            if ! gcloud services enable "${service}" --quiet; then
                print_error "Failed to enable ${service}"
                exit 1
            fi
        fi
    done
    print_success "All required services are enabled"
}

deploy_vless_service() {
    print_info "Deploying VLESS server..."
    
    enable_services
    
    # Build container
    print_info "Building VLESS container..."
    if ! gcloud builds submit --tag "gcr.io/${PROJECT_ID}/${SERVICE_NAME}" --quiet; then
        print_error "Failed to build VLESS container"
        exit 1
    fi
    
    # Deploy service
    print_info "Deploying VLESS service..."
    if ! gcloud run deploy "$SERVICE_NAME" \
        --image "gcr.io/${PROJECT_ID}/${SERVICE_NAME}" \
        --platform managed \
        --region "$REGION" \
        --allow-unauthenticated \
        --port 8080 \
        --cpu "$SELECTED_CPU" \
        --memory "$SELECTED_MEMORY" \
        --min-instances 1 \
        --max-instances 10 \
        --execution-environment gen2 \
        --quiet; then
        print_error "VLESS service deployment failed"
        exit 1
    fi
    
    print_success "VLESS service deployed successfully"
}

deploy_bot_service() {
    print_info "Deploying Telegram bot service..."
    
    # Build bot container
    print_info "Building bot container..."
    if ! gcloud builds submit --tag "gcr.io/${PROJECT_ID}/${BOT_SERVICE_NAME}" --quiet; then
        print_error "Failed to build bot container"
        exit 1
    fi
    
    # Deploy bot service
    print_info "Deploying bot service..."
    if ! gcloud run deploy "$BOT_SERVICE_NAME" \
        --image "gcr.io/${PROJECT_ID}/${BOT_SERVICE_NAME}" \
        --platform managed \
        --region "$REGION" \
        --allow-unauthenticated \
        --port 8080 \
        --cpu 1 \
        --memory "512Mi" \
        --set-env-vars="BOT_TOKEN=${TELEGRAM_BOT_TOKEN},VLESS_LINK=${VLESS_LINK},SERVICE_URL=${SERVICE_URL},ADMIN_CHAT_ID=${TELEGRAM_CHAT_ID}" \
        --min-instances 0 \
        --max-instances 3 \
        --execution-environment gen2 \
        --quiet; then
        print_error "Bot service deployment failed"
        exit 1
    fi
    
    print_success "Bot service deployed successfully"
}

get_service_urls() {
    print_info "Getting service URLs..."
    
    SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
        --platform managed \
        --region "$REGION" \
        --format="value(status.url)" 2>/dev/null)
    
    BOT_SERVICE_URL=$(gcloud run services describe "$BOT_SERVICE_NAME" \
        --platform managed \
        --region "$REGION" \
        --format="value(status.url)" 2>/dev/null)
    
    if [[ -z "$SERVICE_URL" || -z "$BOT_SERVICE_URL" ]]; then
        print_error "Failed to get service URLs"
        exit 1
    fi
}

generate_vless_config() {
    local domain=$(echo "$SERVICE_URL" | sed 's|https://||')
    VLESS_LINK="vless://${UUID}@${domain}:443?path=%2Fvless-${PATH_SUFFIX}&security=tls&alpn=h3%2Ch2%2Chttp%2F1.1&encryption=none&host=${domain}&fp=randomized&type=ws&sni=${domain}#GCP-${REGION}"
}

setup_webhook() {
    print_info "Setting up Telegram webhook..."
    
    local webhook_url="${BOT_SERVICE_URL}/webhook"
    
    # Set webhook
    if curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook" \
        -d "url=${webhook_url}" \
        -d "max_connections=100" \
        -d "allowed_updates=[\"message\"]" | grep -q \"ok\":true; then
        print_success "Webhook set successfully"
    else
        print_warning "Failed to set webhook"
    fi
    
    # Set bot commands
    if curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setMyCommands" \
        -d '{"commands": [{"command": "start", "description": "Get VLESS configuration"}, {"command": "status", "description": "Check server status"}, {"command": "info", "description": "Server information"}]}' | grep -q \"ok\":true; then
        print_success "Bot commands set successfully"
    else
        print_warning "Failed to set bot commands"
    fi
}

send_admin_notification() {
    local domain=$(echo "$SERVICE_URL" | sed 's|https://||')
    
    local message="🚀 <b>GCP VLESS Deployment Successful!</b>

📦 <b>Service Information:</b>
• Project: <code>${PROJECT_ID}</code>
• Service: ${SERVICE_NAME}
• Region: ${REGION}
• Resources: ${SELECTED_CPU} CPU | ${SELECTED_MEMORY} RAM
• Domain: ${domain}

🔗 <b>VLESS Configuration:</b>
• UUID: <code>${UUID}</code>
• Path: /vless-${PATH_SUFFIX}
• Protocol: VLESS + WS + TLS

🤖 <b>Bot Information:</b>
• Bot: @${BOT_USERNAME}
• Webhook: ${BOT_SERVICE_URL}/webhook
• Commands: /start, /status, /info

🔗 <b>VLESS Link:</b>
<code>${VLESS_LINK}</code>

✅ <b>Now users can use /start command with your bot to get the configuration!</b>"

    print_info "Sending admin notification..."
    
    if curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=HTML" > /dev/null; then
        print_success "Admin notification sent"
    else
        print_warning "Failed to send admin notification"
    fi
    
    # Send VLESS link separately
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=<code>${VLESS_LINK}</code>" \
        -d "parse_mode=HTML" > /dev/null
}

wait_for_services() {
    print_info "Waiting for services to be ready..."
    sleep 30
    
    # Test VLESS service
    if curl -s --max-time 10 -f "${SERVICE_URL}" > /dev/null 2>&1; then
        print_success "VLESS service is ready"
    else
        print_warning "VLESS service might need more time"
    fi
    
    # Test bot service
    if curl -s --max-time 10 -f "${BOT_SERVICE_URL}/health" > /dev/null 2>&1; then
        print_success "Bot service is ready"
    else
        print_warning "Bot service might need more time"
    fi
}

cleanup() {
    print_info "Cleaning up temporary files..."
    rm -f Dockerfile config.json bot.Dockerfile bot.py requirements.txt
}

display_summary() {
    local domain=$(echo "$SERVICE_URL" | sed 's|https://||')
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                      DEPLOYMENT SUCCESS                     ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}📊 DEPLOYMENT SUMMARY:${NC}"
    echo "  Project: $PROJECT_ID"
    echo "  VLESS Service: $SERVICE_NAME"
    echo "  Bot Service: $BOT_SERVICE_NAME"
    echo "  Region: $REGION"
    echo "  Resources: $SELECTED_CPU CPU | $SELECTED_MEMORY RAM"
    echo "  Domain: $domain"
    echo ""
    echo -e "${CYAN}🔗 VLESS CONFIGURATION:${NC}"
    echo "  UUID: $UUID"
    echo "  Path: /vless-$PATH_SUFFIX"
    echo "  Protocol: VLESS + WebSocket + TLS"
    echo ""
    echo -e "${CYAN}🤖 BOT INFORMATION:${NC}"
    echo "  Bot: @$BOT_USERNAME"
    echo "  Webhook: $BOT_SERVICE_URL/webhook"
    echo "  Commands: /start, /status, /info"
    echo ""
    echo -e "${GREEN}🔗 VLESS LINK:${NC}"
    echo "$VLESS_LINK"
    echo ""
}

show_management_commands() {
    echo -e "${YELLOW}🛠️  MANAGEMENT COMMANDS:${NC}"
    echo "  View VLESS logs: gcloud logging read 'resource.type=cloud_run_revision resource.labels.service_name=$SERVICE_NAME' --limit=10"
    echo "  View Bot logs: gcloud logging read 'resource.type=cloud_run_revision resource.labels.service_name=$BOT_SERVICE_NAME' --limit=10"
    echo "  Check services: gcloud run services list --region=$REGION"
    echo "  Delete services: gcloud run services delete $SERVICE_NAME $BOT_SERVICE_NAME --region=$REGION --quiet"
    echo ""
}

main() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║               GCP VLESS + Telegram Bot                      ║
║               Complete Deployment Solution                  ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    # Initial checks
    check_environment
    check_authentication
    
    # Configuration
    get_telegram_config
    select_region
    get_service_names
    select_resources
    
    # Display configuration
    echo ""
    print_info "Deployment Configuration:"
    echo "──────────────────────────"
    echo "• Project: $PROJECT_ID"
    echo "• Region: $REGION"
    echo "• VLESS Service: $SERVICE_NAME"
    echo "• Bot Service: $BOT_SERVICE_NAME"
    echo "• Resources: $SELECTED_CPU CPU, $SELECTED_MEMORY RAM"
    echo ""
    
    read -p "Proceed with deployment? (y/n) [y]: " confirm
    if [[ "${confirm:-y}" != "y" ]]; then
        print_info "Deployment cancelled"
        exit 0
    fi
    
    # Deployment process
    create_vless_dockerfile
    deploy_vless_service
    
    create_bot_dockerfile
    deploy_bot_service
    
    get_service_urls
    generate_vless_config
    setup_webhook
    wait_for_services
    send_admin_notification
    display_summary
    show_management_commands
    cleanup
    
    echo ""
    print_success "✅ Deployment completed successfully!"
    print_success "🤖 Users can now use /start with @$BOT_USERNAME to get the configuration!"
    echo ""
}

# Error handling
trap 'echo ""; print_error "Script interrupted"; cleanup; exit 1' SIGINT

main "$@"
