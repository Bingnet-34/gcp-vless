#!/bin/bash

# GCP V2Ray VLESS Server Deployer - No Owner Restrictions
# With Start/Stop Management
# Author: Assistant
# Version: 11.0

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
BOT_SERVICE_NAME=""
REGION="us-central1"
TELEGRAM_BOT_TOKEN=""
UUID=""
PATH_SUFFIX=""
SERVICE_URL=""
BOT_SERVICE_URL=""
VLESS_LINK=""
SELECTED_CPU=""
SELECTED_MEMORY=""

# Resource options
CPU_OPTIONS=("1" "2" "4" "8")
MEMORY_OPTIONS=("512Mi" "1Gi" "2Gi" "4Gi" "8Gi" "16Gi")

# Valid CPU-Memory combinations
declare -A VALID_COMBINATIONS=(
    ["1"]="512Mi 1Gi 2Gi 4Gi"
    ["2"]="1Gi 2Gi 4Gi 8Gi"
    ["4"]="2Gi 4Gi 8Gi 16Gi"
    ["8"]="4Gi 8Gi 16Gi"
)

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_menu() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                 V2Ray VLESS Server Manager                  ║
║                   Google Cloud Platform                     ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    echo "1. Deploy New V2Ray VLESS Server"
    echo "2. Stop/Delete Existing Server"
    echo "3. List All Services"
    echo "4. Check Service Status"
    echo "5. Exit"
    echo ""
}

check_environment() {
    print_info "Checking Google Cloud environment..."
    
    if ! command -v gcloud &> /dev/null; then
        print_error "gcloud not found. Please run in Google Cloud Shell."
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        print_error "curl not found."
        exit 1
    fi
    
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
    print_info "Available Google Cloud projects:"
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
            # Verify bot token
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
    
    read -p "Enter VLESS service name [vless-server]: " SERVICE_NAME
    SERVICE_NAME=${SERVICE_NAME:-vless-server}
    
    BOT_SERVICE_NAME="${SERVICE_NAME}-bot"
    
    # Generate unique identifiers
    UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16)
    PATH_SUFFIX="tg-$(head /dev/urandom 2>/dev/null | tr -dc a-z0-9 | head -c 8)"
    
    print_info "VLESS Service: $SERVICE_NAME"
    print_info "Bot Service: $BOT_SERVICE_NAME"
}

select_cpu() {
    echo ""
    print_info "Select CPU Cores (Max 8):"
    echo "1. 1 CPU Core"
    echo "2. 2 CPU Cores"
    echo "3. 4 CPU Cores"
    echo "4. 8 CPU Cores (Maximum)"
    
    while true; do
        read -p "Choose CPU (1-4) [2]: " cpu_choice
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
    print_info "Select Memory (Max 16Gi):"
    echo "Available memory options for $SELECTED_CPU CPU:"
    
    # Get valid memory options for selected CPU
    VALID_MEMORIES=(${VALID_COMBINATIONS[$SELECTED_CPU]})
    
    for i in "${!VALID_MEMORIES[@]}"; do
        echo "$((i+1)). ${VALID_MEMORIES[i]}"
    done
    
    while true; do
        read -p "Choose memory (1-${#VALID_MEMORIES[@]}) [3]: " mem_choice
        mem_choice=${mem_choice:-3}
        if [[ $mem_choice -ge 1 && $mem_choice -le ${#VALID_MEMORIES[@]} ]]; then
            SELECTED_MEMORY="${VALID_MEMORIES[$((mem_choice-1))]}"
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
    echo "• Max Instances: 10"
    echo "• Min Instances: 1"
}

create_v2ray_dockerfile() {
    print_info "Creating V2Ray VLESS server configuration..."
    
    cat > Dockerfile << 'EOF'
FROM alpine:latest

RUN apk update && apk add --no-cache curl unzip

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

create_bot_dockerfile() {
    print_info "Creating Telegram bot server..."
    
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

# Configuration from environment
BOT_TOKEN = os.environ.get('BOT_TOKEN')
VLESS_LINK = os.environ.get('VLESS_LINK')
SERVICE_URL = os.environ.get('SERVICE_URL')

def send_telegram_message(chat_id, text):
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    payload = {
        'chat_id': chat_id,
        'text': text,
        'parse_mode': 'HTML'
    }
    try:
        response = requests.post(url, json=payload, timeout=10)
        return response.json()
    except Exception as e:
        print(f"Error sending message: {e}")
        return None

@app.route('/webhook', methods=['POST'])
def webhook():
    try:
        data = request.get_json()
        
        if 'message' in data:
            chat_id = data['message']['chat']['id']
            text = data['message'].get('text', '')
            
            if text == '/start':
                message = f"""🚀 <b>Welcome to V2Ray VLESS Server!</b>

🔗 <b>Your VLESS Configuration:</b>
<code>{VLESS_LINK}</code>

📋 <b>How to use:</b>
1. Copy the link above
2. Paste in V2Ray client (Nekobox, V2RayNG, etc.)
3. Connect and enjoy!

⚡ <b>Server Information:</b>
• Status: ✅ Online
• Protocol: V2Ray + VLESS + WS + TLS
• Domain: {SERVICE_URL.split('//')[1] if SERVICE_URL else 'N/A'}

💡 <b>Note:</b> This server is available for all users"""
                
                send_telegram_message(chat_id, message)
                
            elif text == '/status':
                send_telegram_message(chat_id, "✅ Server is online and running!")
                
            elif text == '/info':
                info_msg = f"""📊 <b>Server Information:</b>

🌐 Domain: {SERVICE_URL}
🔧 Service: VLESS Server
🔒 Security: TLS 1.3
🛡️ Fingerprint: Randomized
⚡ Performance: High Speed
👥 Users: Unlimited"""
                
                send_telegram_message(chat_id, info_msg)
        
        return jsonify({'status': 'ok'})
    except Exception as e:
        print(f"Webhook error: {e}")
        return jsonify({'status': 'error', 'message': str(e)})

@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'healthy', 'service': 'telegram-bot'})

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
    print_success "All required services enabled"
}

deploy_v2ray_service() {
    print_info "Deploying V2Ray VLESS server..."
    
    enable_services
    
    # Build V2Ray container
    print_info "Building V2Ray container image..."
    if ! gcloud builds submit --tag "gcr.io/${PROJECT_ID}/${SERVICE_NAME}" --quiet; then
        print_error "V2Ray container build failed"
        exit 1
    fi
    
    # Deploy V2Ray service
    print_info "Deploying V2Ray service with $SELECTED_CPU CPU and $SELECTED_MEMORY RAM..."
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
        print_error "V2Ray service deployment failed"
        exit 1
    fi
    
    print_success "V2Ray VLESS service deployed successfully"
}

deploy_bot_service() {
    print_info "Deploying Telegram bot service..."
    
    # Build bot container
    print_info "Building bot container image..."
    if ! gcloud builds submit --tag "gcr.io/${PROJECT_ID}/${BOT_SERVICE_NAME}" --quiet; then
        print_error "Bot container build failed"
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
        --set-env-vars="BOT_TOKEN=${TELEGRAM_BOT_TOKEN},VLESS_LINK=${VLESS_LINK},SERVICE_URL=${SERVICE_URL}" \
        --min-instances 0 \
        --max-instances 5 \
        --execution-environment gen2 \
        --quiet; then
        print_error "Bot service deployment failed"
        exit 1
    fi
    
    print_success "Telegram bot service deployed successfully"
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
    
    print_success "VLESS Service URL: $SERVICE_URL"
    print_success "Bot Service URL: $BOT_SERVICE_URL"
}

generate_vless_link() {
    local domain=$(echo "$SERVICE_URL" | sed 's|https://||')
    
    # Create exact VLESS link format
    VLESS_LINK="vless://${UUID}@${domain}:443?path=%2F${PATH_SUFFIX}&security=tls&alpn=h3%2Ch2%2Chttp%2F1.1&encryption=none&host=${domain}&fp=randomized&type=ws&sni=${domain}#${SERVICE_NAME}"
    
    print_success "VLESS link generated"
}

setup_webhook() {
    print_info "Setting up Telegram webhook..."
    
    local webhook_url="${BOT_SERVICE_URL}/webhook"
    
    # Set webhook
    if curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook" \
        -d "url=${webhook_url}" \
        -d "max_connections=100" \
        -d "allowed_updates=[\"message\"]" | grep -q \"ok\":true; then
        print_success "Webhook set successfully: $webhook_url"
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

wait_for_services() {
    print_info "Waiting for services to be ready (30 seconds)..."
    sleep 30
    
    # Test services
    if curl -s --max-time 10 -f "${SERVICE_URL}" > /dev/null 2>&1; then
        print_success "VLESS service is responding"
    else
        print_warning "VLESS service might need more time"
    fi
    
    if curl -s --max-time 10 -f "${BOT_SERVICE_URL}/health" > /dev/null 2>&1; then
        print_success "Bot service is responding"
    else
        print_warning "Bot service might need more time"
    fi
}

cleanup_files() {
    print_info "Cleaning up temporary files..."
    rm -f Dockerfile config.json bot.Dockerfile bot.py requirements.txt
}

display_deployment_summary() {
    local domain=$(echo "$SERVICE_URL" | sed 's|https://||')
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                   DEPLOYMENT COMPLETED!                     ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}📊 DEPLOYMENT SUMMARY:${NC}"
    echo "  Project: $PROJECT_ID"
    echo "  Service: $SERVICE_NAME"
    echo "  Bot Service: $BOT_SERVICE_NAME"
    echo "  Region: $REGION"
    echo "  Resources: $SELECTED_CPU CPU | $SELECTED_MEMORY RAM"
    echo "  Domain: $domain"
    echo ""
    echo -e "${CYAN}🔧 SERVER CONFIGURATION:${NC}"
    echo "  UUID: $UUID"
    echo "  Path: /$PATH_SUFFIX"
    echo "  Protocol: V2Ray + VLESS + WebSocket + TLS"
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
    echo "  View V2Ray logs: gcloud logging read 'resource.type=cloud_run_revision AND resource.labels.service_name=$SERVICE_NAME' --limit=10"
    echo "  View Bot logs: gcloud logging read 'resource.type=cloud_run_revision AND resource.labels.service_name=$BOT_SERVICE_NAME' --limit=10"
    echo "  Check services: gcloud run services list --region=$REGION"
    echo "  Update resources: gcloud run services update $SERVICE_NAME --region=$REGION --cpu=2 --memory=4Gi"
    echo ""
}

deploy_new_server() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                 Deploy New V2Ray VLESS Server               ║
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
    echo "• V2Ray Service: $SERVICE_NAME"
    echo "• Bot Service: $BOT_SERVICE_NAME"
    echo "• Resources: $SELECTED_CPU CPU, $SELECTED_MEMORY RAM"
    echo "• UUID: $UUID"
    echo "• Path: /$PATH_SUFFIX"
    echo ""
    
    read -p "Proceed with deployment? (y/n) [y]: " confirm
    if [[ "${confirm:-y}" != "y" ]]; then
        print_info "Deployment cancelled"
        return 1
    fi
    
    # Deployment process
    create_v2ray_dockerfile
    deploy_v2ray_service
    
    get_service_urls
    generate_vless_link
    
    create_bot_dockerfile
    deploy_bot_service
    setup_webhook
    wait_for_services
    display_deployment_summary
    show_management_commands
    cleanup_files
    
    echo ""
    print_success "✅ V2Ray VLESS server deployed successfully!"
    print_success "🤖 Bot is ready! Any user can use /start with @$BOT_USERNAME"
    print_success "🔗 VLESS Link: $VLESS_LINK"
    echo ""
    
    read -p "Press Enter to continue..."
}

stop_existing_server() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                 Stop Existing V2Ray Server                  ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    check_authentication
    
    echo ""
    print_info "Listing all services in project $PROJECT_ID:"
    echo ""
    
    gcloud run services list --region="*" --format="table(NAME,REGION,STATUS)" | head -10
    
    echo ""
    read -p "Enter service name to stop (or press Enter to cancel): " service_to_stop
    
    if [[ -z "$service_to_stop" ]]; then
        print_info "Operation cancelled"
        return 1
    fi
    
    # Find the region of the service
    SERVICE_REGION=$(gcloud run services list --filter="NAME:$service_to_stop" --format="value(REGION)" --limit=1)
    
    if [[ -z "$SERVICE_REGION" ]]; then
        print_error "Service '$service_to_stop' not found"
        return 1
    fi
    
    echo ""
    print_warning "This will PERMANENTLY delete the service: $service_to_stop"
    print_warning "Region: $SERVICE_REGION"
    echo ""
    
    read -p "Are you sure you want to delete this service? (y/n) [n]: " confirm_delete
    if [[ "${confirm_delete:-n}" != "y" ]]; then
        print_info "Deletion cancelled"
        return 1
    fi
    
    # Delete the main service
    print_info "Deleting service: $service_to_stop"
    if gcloud run services delete "$service_to_stop" --region="$SERVICE_REGION" --quiet; then
        print_success "Service '$service_to_stop' deleted successfully"
    else
        print_error "Failed to delete service '$service_to_stop'"
    fi
    
    # Try to delete bot service if exists
    BOT_SERVICE="${service_to_stop}-bot"
    if gcloud run services describe "$BOT_SERVICE" --region="$SERVICE_REGION" &>/dev/null; then
        print_info "Deleting bot service: $BOT_SERVICE"
        if gcloud run services delete "$BOT_SERVICE" --region="$SERVICE_REGION" --quiet; then
            print_success "Bot service '$BOT_SERVICE' deleted successfully"
        else
            print_warning "Failed to delete bot service '$BOT_SERVICE'"
        fi
    fi
    
    echo ""
    print_success "✅ Server stopped successfully!"
    echo ""
    
    read -p "Press Enter to continue..."
}

list_all_services() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                    All Cloud Run Services                   ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    check_authentication
    
    echo ""
    print_info "Services in project: $PROJECT_ID"
    echo ""
    
    gcloud run services list --region="*" --format="table(NAME,REGION,STATIS,URL)" | head -15
    
    echo ""
    read -p "Press Enter to continue..."
}

check_service_status() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════╗
║                    Check Service Status                     ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    
    check_authentication
    
    echo ""
    read -p "Enter service name to check: " service_name
    
    if [[ -z "$service_name" ]]; then
        print_error "Service name is required"
        return 1
    fi
    
    # Find the service in all regions
    SERVICE_INFO=$(gcloud run services list --filter="NAME:$service_name" --format="table(NAME,REGION,STATUS,URL)" --limit=5)
    
    if [[ -z "$SERVICE_INFO" || "$SERVICE_INFO" == "Listed 0 items." ]]; then
        print_error "Service '$service_name' not found"
        return 1
    fi
    
    echo ""
    print_info "Service Information:"
    echo "$SERVICE_INFO"
    echo ""
    
    read -p "Press Enter to continue..."
}

main() {
    while true; do
        show_menu
        read -p "Choose an option (1-5): " choice
        
        case $choice in
            1)
                deploy_new_server
                ;;
            2)
                stop_existing_server
                ;;
            3)
                list_all_services
                ;;
            4)
                check_service_status
                ;;
            5)
                echo ""
                print_info "Thank you for using V2Ray VLESS Server Manager!"
                echo ""
                exit 0
                ;;
            *)
                print_error "Invalid option. Please choose 1-5."
                sleep 2
                ;;
        esac
    done
}

# Error handling
trap 'echo ""; print_error "Script interrupted"; cleanup_files; exit 1' SIGINT

main "$@"
