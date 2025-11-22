#!/bin/bash

# GCP V2Ray VLESS Server - Minimal & Working Version
# Optimized for Google Cloud Shell
# Author: Assistant
# Version: 13.0

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running in Google Cloud Shell
check_environment() {
    print_info "Checking Google Cloud Shell environment..."
    
    if [[ -z "$CLOUD_SHELL" ]]; then
        print_warning "This script is optimized for Google Cloud Shell"
    fi
    
    if ! command -v gcloud >/dev/null 2>&1; then
        print_error "gcloud command not found. Please use Google Cloud Shell."
        exit 1
    fi
    
    if ! command -v curl >/dev/null 2>&1; then
        print_error "curl command not found."
        exit 1
    fi
    
    print_success "Environment check passed"
}

# Check and setup authentication
setup_authentication() {
    print_info "Checking authentication..."
    
    # Check if user is logged in
    if ! gcloud auth list --format="value(account)" | grep -q "@"; then
        print_warning "Please login to Google Cloud"
        gcloud auth login --no-launch-browser
    fi
    
    # Get or set project
    local current_project=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "$current_project" ]]; then
        print_info "Available projects:"
        gcloud projects list --format="table(projectId)" --limit=5
        echo ""
        read -p "Enter your PROJECT_ID: " PROJECT_ID
        if [[ -z "$PROJECT_ID" ]]; then
            print_error "Project ID is required"
            exit 1
        fi
        gcloud config set project $PROJECT_ID
    else
        PROJECT_ID=$current_project
        print_info "Using project: $PROJECT_ID"
        read -p "Use this project? (y/n) [y]: " use_current
        if [[ "$use_current" == "n" ]]; then
            gcloud projects list --format="table(projectId)" --limit=5
            echo ""
            read -p "Enter your PROJECT_ID: " PROJECT_ID
            gcloud config set project $PROJECT_ID
        fi
    fi
}

# Get basic configuration
get_configuration() {
    echo ""
    print_info "Basic Configuration"
    echo "===================="
    
    # Service name
    read -p "Enter service name [vless-server]: " SERVICE_NAME
    SERVICE_NAME=${SERVICE_NAME:-vless-server}
    
    # Region
    echo ""
    print_info "Select region:"
    echo "1. us-central1 (Recommended)"
    echo "2. europe-west1" 
    echo "3. asia-southeast1"
    read -p "Choose [1]: " region_choice
    case $region_choice in
        2) REGION="europe-west1" ;;
        3) REGION="asia-southeast1" ;;
        *) REGION="us-central1" ;;
    esac
    
    # Telegram Bot Token only
    echo ""
    print_info "Telegram Bot Token (for /start command):"
    read -p "Enter Bot Token: " TELEGRAM_BOT_TOKEN
    
    if [[ -z "$TELEGRAM_BOT_TOKEN" ]]; then
        print_error "Bot token is required"
        exit 1
    fi
    
    # Verify bot token
    print_info "Verifying bot token..."
    if curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" | grep -q \"ok\":true; then
        BOT_USERNAME=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" | grep -o '"username":"[^"]*' | cut -d'"' -f4)
        print_success "Bot verified: @$BOT_USERNAME"
    else
        print_error "Invalid bot token"
        exit 1
    fi
    
    # Generate unique identifiers
    UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || openssl rand -hex 16)
    PATH_SUFFIX="path-$(head /dev/urandom 2>/dev/null | tr -dc a-z0-9 | head -c 8)"
}

# Create minimal V2Ray configuration
create_v2ray_config() {
    print_info "Creating V2Ray configuration..."
    
    cat > Dockerfile << 'EOF'
FROM alpine:latest

RUN apk update && apk add --no-cache curl unzip

# Download and install V2Ray
RUN curl -L https://github.com/v2fly/v2ray-core/releases/download/v5.7.0/v2ray-linux-64.zip -o v2ray.zip \
    && unzip -j v2ray.zip v2ray -d /usr/bin/ \
    && chmod +x /usr/bin/v2ray \
    && rm v2ray.zip \
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
                "wsSettings": {
                    "path": "/$PATH_SUFFIX"
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
}

# Create simple Telegram bot webhook handler
create_bot_handler() {
    print_info "Creating Telegram bot webhook handler..."
    
    cat > app.py << EOF
import os
import requests
from flask import Flask, request, jsonify

app = Flask(__name__)

BOT_TOKEN = os.environ.get('BOT_TOKEN')
VLESS_LINK = os.environ.get('VLESS_LINK')

def send_message(chat_id, text):
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    data = {
        'chat_id': chat_id,
        'text': text,
        'parse_mode': 'HTML'
    }
    try:
        requests.post(url, json=data, timeout=5)
    except:
        pass

@app.route('/webhook', methods=['POST'])
def webhook():
    try:
        data = request.get_json()
        if 'message' in data:
            chat_id = data['message']['chat']['id']
            text = data['message'].get('text', '')
            
            if text == '/start':
                message = f"🔗 Your VLESS Configuration:\\n<code>{VLESS_LINK}</code>\\n\\n📋 Copy and use in V2Ray client"
                send_message(chat_id, message)
            elif text == '/status':
                send_message(chat_id, "✅ Server is online")
            elif text == '/info':
                send_message(chat_id, "⚡ V2Ray VLESS Server\\n🔒 TLS + WebSocket")
                
        return jsonify({'status': 'ok'})
    except:
        return jsonify({'status': 'error'})

@app.route('/')
def home():
    return jsonify({'status': 'running'})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
EOF

    cat > requirements.txt << 'EOF'
Flask==2.3.3
requests==2.31.0
EOF

    cat > bot.Dockerfile << 'EOF'
FROM python:3.9-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY app.py .

CMD ["python", "app.py"]
EOF
}

# Enable required services
enable_services() {
    print_info "Enabling required Google Cloud services..."
    
    for service in run.googleapis.com containerregistry.googleapis.com cloudbuild.googleapis.com; do
        if ! gcloud services list --enabled --filter="name:$service" | grep -q "$service"; then
            gcloud services enable "$service" --quiet
        fi
    done
    print_success "Services enabled"
}

# Deploy V2Ray service
deploy_v2ray() {
    print_info "Deploying V2Ray service..."
    
    enable_services
    
    # Build and deploy
    if gcloud builds submit --tag "gcr.io/$PROJECT_ID/$SERVICE_NAME" --quiet && \
       gcloud run deploy "$SERVICE_NAME" \
        --image "gcr.io/$PROJECT_ID/$SERVICE_NAME" \
        --platform managed \
        --region "$REGION" \
        --allow-unauthenticated \
        --port 8080 \
        --cpu 1 \
        --memory "512Mi" \
        --min-instances 1 \
        --max-instances 3 \
        --quiet; then
        print_success "V2Ray service deployed"
        return 0
    else
        print_error "V2Ray deployment failed"
        return 1
    fi
}

# Deploy bot service
deploy_bot() {
    print_info "Deploying bot service..."
    
    BOT_SERVICE_NAME="${SERVICE_NAME}-bot"
    
    if gcloud builds submit --tag "gcr.io/$PROJECT_ID/$BOT_SERVICE_NAME" --quiet && \
       gcloud run deploy "$BOT_SERVICE_NAME" \
        --image "gcr.io/$PROJECT_ID/$BOT_SERVICE_NAME" \
        --platform managed \
        --region "$REGION" \
        --allow-unauthenticated \
        --port 8080 \
        --cpu 1 \
        --memory "256Mi" \
        --set-env-vars="BOT_TOKEN=$TELEGRAM_BOT_TOKEN,VLESS_LINK=$VLESS_LINK" \
        --min-instances 0 \
        --max-instances 3 \
        --quiet; then
        print_success "Bot service deployed"
        return 0
    else
        print_error "Bot deployment failed"
        return 1
    fi
}

# Get service URLs
get_urls() {
    SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
        --platform managed \
        --region "$REGION" \
        --format="value(status.url)" 2>/dev/null)
    
    BOT_SERVICE_URL=$(gcloud run services describe "${SERVICE_NAME}-bot" \
        --platform managed \
        --region "$REGION" \
        --format="value(status.url)" 2>/dev/null)
    
    if [[ -n "$SERVICE_URL" && -n "$BOT_SERVICE_URL" ]]; then
        print_success "Services URLs obtained"
        return 0
    else
        print_error "Failed to get service URLs"
        return 1
    fi
}

# Generate VLESS link
generate_vless_link() {
    local domain=$(echo "$SERVICE_URL" | sed 's|https://||')
    VLESS_LINK="vless://${UUID}@${domain}:443?path=%2F${PATH_SUFFIX}&security=tls&type=ws&sni=${domain}#${SERVICE_NAME}"
    print_success "VLESS link generated"
}

# Setup Telegram webhook
setup_webhook() {
    print_info "Setting up Telegram webhook..."
    
    local webhook_url="${BOT_SERVICE_URL}/webhook"
    
    # Set webhook
    if curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook" \
        -d "url=${webhook_url}" | grep -q \"ok\":true; then
        print_success "Webhook configured"
    else
        print_warning "Webhook setup may need retry"
    fi
    
    # Set commands
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setMyCommands" \
        -d '{"commands": [{"command": "start", "description": "Get VLESS link"}]}' > /dev/null
}

# Wait for services to be ready
wait_for_services() {
    print_info "Waiting for services to be ready..."
    sleep 20
    
    if curl -s --max-time 10 "$SERVICE_URL" > /dev/null; then
        print_success "V2Ray service is ready"
    else
        print_warning "V2Ray service starting..."
    fi
}

# Cleanup temporary files
cleanup() {
    rm -f Dockerfile config.json app.py requirements.txt bot.Dockerfile
}

# Display final information
show_results() {
    local domain=$(echo "$SERVICE_URL" | sed 's|https://||')
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                      DEPLOYMENT SUCCESS!                    ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}📊 DEPLOYMENT INFO:${NC}"
    echo "  Project: $PROJECT_ID"
    echo "  Service: $SERVICE_NAME"
    echo "  Region: $REGION"
    echo "  Domain: $domain"
    echo ""
    echo -e "${BLUE}🔧 CONFIGURATION:${NC}"
    echo "  UUID: $UUID"
    echo "  Path: /$PATH_SUFFIX"
    echo ""
    echo -e "${BLUE}🤖 BOT INFO:${NC}"
    echo "  Bot: @$BOT_USERNAME"
    echo "  Try: /start command"
    echo ""
    echo -e "${GREEN}🔗 VLESS LINK:${NC}"
    echo "$VLESS_LINK"
    echo ""
}

# Main deployment function
deploy_server() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║               V2Ray VLESS Server Deployer                   ║"
    echo "║                 Google Cloud Shell Edition                  ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    # Step 1: Environment checks
    check_environment
    setup_authentication
    
    # Step 2: Get configuration
    get_configuration
    
    # Step 3: Show summary
    echo ""
    print_info "Deployment Summary:"
    echo "• Project: $PROJECT_ID"
    echo "• Service: $SERVICE_NAME"
    echo "• Region: $REGION"
    echo "• Bot: @$BOT_USERNAME"
    echo ""
    
    read -p "Continue with deployment? (y/n) [y]: " confirm
    if [[ "${confirm:-y}" != "y" ]]; then
        print_info "Deployment cancelled"
        exit 0
    fi
    
    # Step 4: Deploy V2Ray
    create_v2ray_config
    if ! deploy_v2ray; then
        print_error "V2Ray deployment failed"
        exit 1
    fi
    
    # Step 5: Get URL and generate link
    if ! get_urls; then
        print_error "Failed to get service URLs"
        exit 1
    fi
    generate_vless_link
    
    # Step 6: Deploy bot
    create_bot_handler
    if ! deploy_bot; then
        print_error "Bot deployment failed"
        exit 1
    fi
    
    # Step 7: Setup webhook and wait
    get_urls
    setup_webhook
    wait_for_services
    
    # Step 8: Show results
    show_results
    cleanup
    
    echo ""
    print_success "✅ Deployment completed successfully!"
    echo ""
}

# Stop server function
stop_server() {
    clear
    echo -e "${YELLOW}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                   Stop V2Ray Server                         ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    setup_authentication
    
    echo ""
    print_info "Current services:"
    gcloud run services list --region="*" --format="table(NAME,REGION,STATUS)" --limit=10
    
    echo ""
    read -p "Enter service name to stop: " service_name
    
    if [[ -z "$service_name" ]]; then
        print_error "Service name required"
        exit 1
    fi
    
    # Find service region
    local service_region=$(gcloud run services list --filter="NAME:$service_name" --format="value(REGION)" --limit=1)
    
    if [[ -z "$service_region" ]]; then
        print_error "Service not found"
        exit 1
    fi
    
    print_warning "This will delete: $service_name (Region: $service_region)"
    read -p "Are you sure? (y/n) [n]: " confirm
    
    if [[ "$confirm" == "y" ]]; then
        gcloud run services delete "$service_name" --region="$service_region" --quiet
        print_success "Service $service_name deleted"
        
        # Try to delete bot service
        local bot_service="${service_name}-bot"
        if gcloud run services describe "$bot_service" --region="$service_region" &>/dev/null; then
            gcloud run services delete "$bot_service" --region="$service_region" --quiet
            print_success "Bot service $bot_service deleted"
        fi
    else
        print_info "Cancelled"
    fi
}

# Main menu
main_menu() {
    clear
    echo -e "${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                 V2Ray Server Manager                        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "1. Deploy New V2Ray Server"
    echo "2. Stop Existing Server"
    echo "3. Exit"
    echo ""
    read -p "Choose option [1]: " choice
    
    case $choice in
        2) stop_server ;;
        3) exit 0 ;;
        *) deploy_server ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    main_menu
}

# Handle interrupts
trap 'echo ""; print_error "Script interrupted"; cleanup; exit 1' SIGINT

# Start the script
main_menu
