#!/bin/bash

# PCDN 管理腳本

# 顏色定義
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 更新系統限制設置
update_system_limits() {
    echo -e "${BLUE}Updating system limit settings...${NC}"
    
    # 設定 limits.conf
    LIMITS_CONF="/etc/security/limits.conf"
    if [[ -f "$LIMITS_CONF" ]]; then
        if ! grep -q "^\* soft nofile 524288" "$LIMITS_CONF"; then
            echo "* soft nofile 524288" >> "$LIMITS_CONF"
        fi
        if ! grep -q "^\* hard nofile 524288" "$LIMITS_CONF"; then
            echo "* hard nofile 524288" >> "$LIMITS_CONF"
        fi
        echo -e "${GREEN}Updated limits.conf${NC}"
    else
        echo -e "${YELLOW}Warning: $LIMITS_CONF file not found${NC}"
    fi

    # 讓當前 shell 立即生效新的文件描述符限制
    ulimit -n 524288
    echo -e "${GREEN}File descriptor limit for current shell has been set to $(ulimit -n)${NC}"

    # 設定 sysctl.conf
    SYSCTL_CONF="/etc/sysctl.conf"
    if [[ -f "$SYSCTL_CONF" ]];then
        SYSCTL_SETTINGS=(
            "fs.inotify.max_user_instances = 25535"
            "net.core.rmem_max=600000000"
            "net.core.wmem_max=600000000"
        )
        for setting in "${SYSCTL_SETTINGS[@]}"; do
            if ! grep -q "^${setting}" "$SYSCTL_CONF"; then
                echo "$setting" >> "$SYSCTL_CONF"
            fi
        done
        echo -e "${GREEN}Updated sysctl.conf${NC}"

        # 重新載入 sysctl 設定，立即生效
        sysctl -p > /dev/null 2>&1 || echo -e "${YELLOW}Warning: sysctl -p command failed${NC}"
        echo -e "${GREEN}sysctl settings reloaded${NC}"
    else
        echo -e "${YELLOW}Warning: $SYSCTL_CONF file not found${NC}"
    fi

    echo -e "${GREEN}System limit settings have been updated. Note: limits.conf settings take effect for new sessions, the current shell has been updated via the ulimit command.${NC}"
}

# 檢查 root 權限
check_root_privileges() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script requires root privileges to execute${NC}"
        echo -e "${YELLOW}Please use sudo or run this script as root user${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Root privileges confirmed${NC}"
}

# 檢查是否提供了安裝標誌
parse_install_flag() {
    local auto_install="false"
    for arg in "$@"; do
        if [[ "$arg" == "-i" || "$arg" == "--install" ]]; then
            auto_install="true"
            break
        fi
    done
    echo "$auto_install"
}

# 在腳本開始前檢查 Docker 和 Docker Compose 是否已安裝
check_docker_environment() {
    local install_option="$1"
    
    # 檢查 Docker 是否已安裝
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Docker is not installed${NC}"
        if [[ "$install_option" == "true" || "$install_option" == "cn" ]]; then
            install_docker "$install_option"
        else
            read -p "Install Docker now? (y/n): " confirm
            if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
                install_docker "false"
            else
                echo -e "${RED}PCDN service requires Docker, please install Docker first or use the -i/--install parameter to install automatically${NC}"
                exit 1
            fi
        fi
    else
        echo -e "${GREEN}Docker is installed${NC}"
    fi
    
    # 檢查 Docker Compose 是否已可用 (現代版本的 Docker 已內建 Docker Compose)
    if ! docker compose version &> /dev/null; then
        echo -e "${YELLOW}Warning: Docker Compose is not available. Please ensure you have installed the latest version of Docker.${NC}"
        echo -e "${YELLOW}Attempting to install/reinstall Docker to get Docker Compose functionality...${NC}"
        
        if [[ "$install_option" == "true" || "$install_option" == "cn" ]]; then
            install_docker "$install_option"
        else
            read -p "Install/reinstall Docker now? (y/n): " confirm
            if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
                install_docker "false"
            else
                echo -e "${RED}PCDN service requires Docker Compose and cannot continue.${NC}"
                exit 1
            fi
        fi
    else
        echo -e "${GREEN}Docker Compose is available${NC}"
    fi
}

# 確保 conf 目錄存在
ensure_conf_dir() {
    if ([[ ! -d "conf" ]]); then
        mkdir -p conf
        echo -e "${BLUE}Created conf directory${NC}"
    fi
}

# 啟動 PCDN 服務函數
start_pcdn() {
    if ! check_config; then
        echo -e "${RED}Configuration check failed, unable to start PCDN service${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Starting PCDN service...${NC}"
    
    # 檢查服務是否已經運行
    if docker compose ps | grep -q "Up"; then
        echo -e "${YELLOW}PCDN service is already running${NC}"
        read -p "Restart? (y/n): " restart
        if [[ $restart != [yY] && $restart != [yY][eE][sS] ]]; then
            echo -e "${BLUE}Operation cancelled${NC}"
            return 0
        fi
    fi

    # 停止現有的容器
    echo -e "${BLUE}Stopping existing containers...${NC}"
    docker compose down &> /dev/null

    # 拉取最新映像
    echo -e "${BLUE}Pulling latest image...${NC}"
    retry "docker compose pull" "Pulling Docker image"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Unable to pull latest image, startup failed${NC}"
        return 1
    fi

    # 啟動服務
    echo -e "${BLUE}Starting PCDN service...${NC}"
    retry "docker compose up -d --remove-orphans" "Starting Docker containers"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Failed to start PCDN service${NC}"
        return 1
    fi

    echo -e "${GREEN}PCDN service started successfully!${NC}"
    
    # 顯示運行中的容器
    echo -e "${BLUE}Currently running services:${NC}"
    docker compose ps
    return 0
}

# 停止 PCDN 服務函數
stop_pcdn() {
    echo -e "${RED}Stopping PCDN service...${NC}"
    
    # 檢查服務是否正在運行
    if ! docker compose ps | grep -q "Up"; then
        echo -e "${YELLOW}No running PCDN service${NC}"
        return 0
    fi
    
    # 嘗試解除容器目錄的不可變屬性（如果存在）
    if [[ -d "./data/docker/containers" ]]; then
        echo -e "${BLUE}Removing immutable attribute from container directory...${NC}"
        chattr -i -R ./data/docker/containers &> /dev/null || true
    fi
    
    # 停止服務
    echo -e "${BLUE}Stopping Docker containers...${NC}"
    retry "docker compose down" "Stopping Docker containers"
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Failed to stop PCDN service${NC}"
        return 1
    fi
    
    echo -e "${GREEN}PCDN service stopped successfully${NC}"
    return 0
}

# 刪除 PCDN 服務函數
delete_pcdn() {
    echo -e "${YELLOW}Warning: About to delete PCDN service and all related data!${NC}"
    echo -e "${YELLOW}This operation will:${NC}"
    echo -e "${YELLOW}  - Stop all PCDN containers${NC}"
    echo -e "${YELLOW}  - Delete all PCDN containers${NC}"
    echo -e "${YELLOW}  - Delete all data (./data/*)${NC}"
    echo -e "${YELLOW}This operation is irreversible!${NC}"
    
    read -p "Are you sure you want to continue? Enter 'DELETE' to confirm: " confirm
    if [[ "$confirm" != "DELETE" ]]; then
        echo -e "${BLUE}Operation cancelled${NC}"
        return 0
    fi
    
    echo -e "${RED}Starting deletion operation...${NC}"
    
    # 嘗試解除容器目錄的不可變屬性（如果存在）
    if [[ -d "./data/docker/containers" ]]; then
        echo -e "${BLUE}Removing immutable attribute from container directory...${NC}"
        chattr -i -R ./data/docker/containers &> /dev/null || true
    fi
    
    # 停止所有容器
    echo -e "${BLUE}Stopping all containers...${NC}"
    docker compose down &> /dev/null || true
    
    # 刪除容器
    echo -e "${BLUE}Deleting all containers...${NC}"
    docker compose rm -f &> /dev/null || true

    # 刪除所有映像
    echo -e "${BLUE}Deleting all images...${NC}"
    docker rmi -f $(docker images -q) &> /dev/null || true
    
    # 刪除數據目錄
    if [[ -d "./data" ]]; then
        echo -e "${BLUE}Deleting data directory...${NC}"
        rm -rf ./data
    fi
    
    echo -e "${GREEN}PCDN service and related data deleted successfully${NC}"
    return 0
}

# 配置 PCDN 服務函數
config_pcdn() {
    echo -e "${BLUE}Configuring PCDN service...${NC}"
    
    # 配置 .env 檔案
    config_env
    
    # 配置 .key 檔案
    config_key
    
    echo -e "${GREEN}PCDN service configuration completed${NC}"
}

# 顯示選單函數
show_menu() {
    clear
    echo "===================================="
    echo "        PCDN Service Menu           "
    echo "===================================="
    echo "1. Start PCDN Service"
    echo "2. Stop PCDN Service"
    echo "3. Delete PCDN Service"
    echo "4. Configure PCDN Service"
    echo "5. View Docker Logs"
    echo "6. View PCDN Logs (agent.log)"
    echo "0. Exit"
    echo "===================================="
}

# 查看 Docker 日誌
view_docker_logs() {
    echo -e "${BLUE}Viewing Docker logs...${NC}"
    docker compose logs  --tail 100 --follow
}

# 查看 PCDN 日誌
view_pcdn_logs() {
    echo -e "${BLUE}Viewing PCDN logs (agent.log)...${NC}"
    # 確認
    tail -f -n 100 ./data/agent/agent.log
}

# 生成或修改 .env 檔案
config_env() {
    ensure_conf_dir
    local hook_enable=${1:-"false"}
    local hook_region=${2:-"cn"}
    local interactive=${3:-"true"}
    
    # 只有在互動模式下才請求輸入
    if [[ "$interactive" == "true" ]]; then
        echo -e "${BLUE}Set HOOK_ENABLE (true/false): ${NC}"
        read -p "(Default: $hook_enable): " input_hook_enable
        hook_enable=${input_hook_enable:-$hook_enable}
        
        echo -e "${BLUE}Set HOOK_REGION (currently only supports cn): ${NC}"
        read -p "(Default: $hook_region): " input_hook_region
        hook_region=${input_hook_region:-$hook_region}
    fi
    
    # 生成 conf/.env 檔案
    cat > conf/.env << EOF
HOOK_ENABLE=${hook_enable}
HOOK_REGION=${hook_region}
EOF
    echo -e "${GREEN}conf/.env file generated${NC}"
}

# 生成或修改 .key 檔案
config_key() {
    ensure_conf_dir
    local token=${1:-""}
    
    if [[ -z "$token" ]]; then
        echo -e "${BLUE}Please enter token: ${NC}"
        read -p "" token
    fi
    
    # 生成 conf/.key 檔案
    echo "$token" > conf/.key
    echo -e "${GREEN}conf/.key file generated${NC}"
}

# 檢查 Docker 及 Docker Compose 是否已安裝
check_docker_installed() {
    local auto_install=$1
    
    # 檢查 Docker 是否已安裝
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Docker is not installed${NC}"
        if [[ "$auto_install" == "true" ]]; then
            install_docker
        else
            read -p "Install Docker now? (y/n): " confirm
            if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
                install_docker
            else
                echo -e "${RED}PCDN service requires Docker, please install Docker${NC}"
                exit 1
            fi
        fi
    else
        echo -e "${GREEN}Docker is installed${NC}"
    fi
    
    # 檢查 Docker Compose 是否已可用 (現代版本的 Docker 已內建 Docker Compose)
    if ! docker compose version &> /dev/null; then
        echo -e "${YELLOW}Warning: Docker Compose is not available. Please ensure you have installed the latest version of Docker.${NC}"
        echo -e "${YELLOW}Attempting to install/reinstall Docker to get Docker Compose functionality...${NC}"
        
        if [[ "$AUTO_INSTALL" == "true" ]]; then
            install_docker
        else
            read -p "Install/reinstall Docker now? (y/n): " confirm
            if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
                install_docker
            else
                echo -e "${RED}PCDN service requires Docker Compose and cannot continue.${NC}"
                exit 1
            fi
        fi
    else
        echo -e "${GREEN}Docker Compose is available${NC}"
    fi
    return 0
}

# 添加 Docker 安裝重試函數
retry() {
    local command="$1"
    local description="$2"
    local max_attempts=3
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        echo -e "${BLUE}Attempt $attempt/$max_attempts: $description${NC}"
        eval $command && break
        echo -e "${YELLOW}Attempt $attempt/$max_attempts failed, retrying after a short delay...${NC}"
        sleep 3
        attempt=$((attempt + 1))
    done
    
    if [[ $attempt -gt $max_attempts ]]; then
        echo -e "${RED}Error: $description operation failed after $max_attempts attempts${NC}"
        return 1
    fi
    return 0
}

# 使用中國地區源安裝 Docker
install_docker_cn() {
    echo -e "${BLUE}Installing Docker using Chinese region source...${NC}"
    
    # 檢測 Linux 發行版
    local ID=""
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        ID=$ID
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        ID=$DISTRIB_ID
    else
        echo -e "${RED}Unrecognized Linux distribution${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}Detected Linux distribution: $ID${NC}"
    
    if [[ "$ID" == "ubuntu" || "$ID" == "debian" ]]; then
        # Ubuntu/Debian 下使用阿里云 Docker 源安装
        apt update -y
        apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
        curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
        apt update -y
        retry "apt install -y docker-ce docker-ce-cli containerd.io" "Installing Docker"
    elif [[ "$ID" == "centos" || "$ID" == "rhel" ]]; then
        # CentOS/RHEL 下使用阿里云 Docker 源安装
        yum install -y yum-utils device-mapper-persistent-data lvm2
        yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
        retry "yum install -y docker-ce docker-ce-cli containerd.io" "Installing Docker"
        systemctl start docker
    elif [[ "$ID" == "fedora" ]]; then
        # Fedora 下使用 dnf 安装
        dnf install -y yum-utils device-mapper-persistent-data lvm2
        dnf config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
        retry "dnf install -y docker-ce docker-ce-cli containerd.io" "Installing Docker"
        systemctl start docker
    else
        echo -e "${RED}Unsupported distribution: $ID${NC}"
        exit 1
    fi
    
    # 修改 Docker 源（設置鏡像加速器）
    echo -e "${BLUE}Modifying Docker source...${NC}"
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["https://docker.dadunode.com"]
}
EOF
    retry "systemctl restart docker" "Restarting Docker"
    
    # 將當前用戶加入 docker 群組
    usermod -aG docker $USER
    echo -e "${GREEN}Docker installation complete!${NC}"
    echo -e "${GREEN}Docker Chinese mirror accelerator has been set${NC}"
}

# 安裝 Docker (根據選擇的區域)
install_docker() {
    local region="international"
    local install_option="$1"
    
    # 如果明確指定了中國區域安裝
    if [[ "$install_option" == "cn" ]]; then
        region="cn"
    else
        # 如果未指定區域，詢問用戶
        echo -e "${BLUE}Please select Docker installation source:${NC}"
        echo "1. International source (default)"
        echo "2. Chinese source (Aliyun)"
        read -p "Please select [1/2]: " choice
        case $choice in
            2)
                region="cn"
                ;;
            *)
                region="international"
                ;;
        esac
    fi
    
    echo -e "${BLUE}Installing Docker (using ${region} source)...${NC}"
    if [[ "$region" == "cn" ]]; then
        install_docker_cn
        return $?
    fi
    
    # 檢測作業系統類型（國際版安裝）
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # 使用官方安裝腳本
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker $USER
        echo -e "${GREEN}Docker installation complete!${NC}"
        echo -e "${GREEN}This installation includes Docker Compose functionality${NC}"
        # 移除安裝腳本
        rm get-docker.sh
    elif ([[ "$OSTYPE" == "darwin"* ]]); then
        echo -e "${YELLOW}Please download and install Docker Desktop for Mac from https://docs.docker.com/desktop/install/mac/${NC}"
        echo -e "${YELLOW}Docker Desktop includes Docker Compose functionality${NC}"
        exit 1
    elif ([[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]); then
        echo -e "${YELLOW}Please download and install Docker Desktop for Windows from https://docs.docker.com/desktop/install/windows/${NC}"
        echo -e "${YELLOW}Docker Desktop includes Docker Compose functionality${NC}"
        exit 1
    else
        echo -e "${RED}Unrecognized operating system, please install Docker manually${NC}"
        exit 1
    fi
}

# 解析命令行參數
parse_args() {
    local token=""
    local region=""
    local hook_enable="false"
    local command="$1"
    shift
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--token)
                token="$2"
                shift 2
                ;;
            -r|--region)
                region="$2"
                hook_enable="true"  # 當有指定 region 時，自動啟用 HOOK_ENABLE
                shift 2
                ;;
            -i|--install)
                # 已經在腳本開頭處理了
                shift
                ;;
            *)
                echo -e "${RED}Error: Unknown parameter $1${NC}"
                return 1
                ;;
        esac
    done
    
    case "$command" in
        start)
            # 如果提供了參數，先進行配置
            if [[ -n "$token" || -n "$region" ]]; then
                ensure_conf_dir
                
                # 如果提供了 region，更新 env 檔案 (非互動模式)
                if [[ -n "$region" ]]; then
                    config_env "$hook_enable" "$region" "false"
                fi
                
                # 如果提供了 token，更新 key 檔案 
                if [[ -n "$token" ]]; then
                    config_key "$token"
                fi
            fi
            start_pcdn
            ;;
        config)
            ensure_conf_dir
            
            # 如果提供了 region，更新 env 檔案 
            if [[ -n "$region" ]]; then
                config_env "$hook_enable" "$region"
            fi
            
            # 如果提供了 token，更新 key 檔案 
            if [[ -n "$token" ]]; then
                config_key "$token"
            fi
            
            # 如果沒有提供任何參數，進入互動式配置
            if [[ -z "$region" && -z "$token" ]]; then
                config_pcdn
            fi
            ;;
        stop)
            stop_pcdn
            ;;
        delete)
            delete_pcdn
            ;;
        *)
            show_menu
            read -p "Please select an operation [0-4]: " choice
            handle_menu_choice "$choice"
            ;;
    esac
}

# 檢查配置文件是否存在
check_config() {
    local config_needed=false
    ensure_conf_dir
    
    if [[ ! -f "conf/.env" ]]; then
        echo -e "${YELLOW}conf/.env file does not exist, configuration is required${NC}"
        config_needed=true
    fi
    
    if [[ ! -f "conf/.key" ]]; then
        echo -e "${YELLOW}conf/.key file does not exist, configuration is required${NC}"
        config_needed=true
    fi
    
    if [[ "$config_needed" = true ]]; then
        read -p "Configure now? (y/n): " confirm
        if [[ $confirm == [yY] || $confirm == [yY][eE][sS] ]]; then
            config_pcdn
        else
            echo -e "${RED}Configuration not completed, unable to start service${NC}"
            return 1
        fi
    fi
    return 0
}

# 初始化函數，處理所有啟動前的檢查和設置
init() {
    # 解析命令行參數
    parse_command_args "$@"
    
    # 檢查 root 權限
    check_root_privileges
    
    # 檢查 Docker 環境
    check_docker_environment "$CMD_INSTALL"
}

# 主程序函數
main() {
    # 初始化
    init "$@"
    
    if [[ -n "$CMD_ACTION" ]]; then
        # 執行指定的命令
        execute_command "$CMD_ACTION" "$CMD_TOKEN" "$CMD_REGION"
    else
        show_menu
        read -p "Please select an operation [0-6]: " choice
        handle_menu_choice "$choice"
    fi
}

# 處理選單選擇
handle_menu_choice() {
    case "$1" in
        1)
            start_pcdn
            ;;
        2)
            stop_pcdn
            ;;
        3)
            delete_pcdn
            ;;
        4)
            config_pcdn
            ;;
        5)
            view_docker_logs
            ;;
        6)
            view_pcdn_logs
            ;;
        0)
            echo "Thank you for using! Goodbye!"
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Invalid selection, please re-enter${NC}"
            ;;
    esac
    
    # 顯示「按任意鍵返回選單」提示（除非選擇了退出選項）
    if [[ "$1" != "0" ]]; then
        echo
        read -n 1 -s -r -p "Press any key to return to menu..."
        echo
        show_menu
        read -p "Please select an operation [0-6]: " choice
        handle_menu_choice "$choice"
    fi
}

# 查看 Docker 日誌（優化版）
view_docker_logs() {
    echo -e "${BLUE}Viewing Docker logs...${NC}"
    
    # 檢查 Docker 服務是否運行中
    if ! docker compose ps | grep -q "Up"; then
        echo -e "${YELLOW}Warning: No running Docker containers${NC}"
        read -p "Still want to view recent logs? (y/n): " confirm
        if [[ $confirm != [yY] && $confirm != [yY][eE][sS] ]]; then
            return 0
        fi
    fi
    
    # 提供有用的提示
    echo -e "${YELLOW}Displaying the latest 100 log entries, press Ctrl+C to exit...${NC}"
    echo -e "${YELLOW}Log display will update in real time until you press Ctrl+C${NC}"
    
    # 使用 timeout 命令運行 docker compose logs，這樣不會一直阻塞
    timeout --foreground 30s docker compose logs --tail 100 --follow || true
    echo -e "${GREEN}Log viewing ended${NC}"
}

# 查看 PCDN 日誌（優化版）
view_pcdn_logs() {
    echo -e "${BLUE}Viewing PCDN logs (agent.log)...${NC}"
    
    # 確認日誌檔案存在
    if [[ ! -f "./data/agent/agent.log" ]]; then
        echo -e "${RED}Error: PCDN log file not found (./data/agent/agent.log)${NC}"
        echo -e "${YELLOW}Possible reasons:${NC}"
        echo -e "${YELLOW}1. PCDN service has not been started${NC}"
        echo -e "${YELLOW}2. PCDN service just started, logs not yet generated${NC}"
        echo -e "${YELLOW}3. Log file is in another location${NC}"
        
        # 嘗試找出可能的日誌文件
        echo -e "${BLUE}Attempting to find possible log files...${NC}"
        potential_logs=$(find ./data -name "*.log" 2>/dev/null)
        
        if [[ -n "$potential_logs" ]]; then
            echo -e "${GREEN}Found the following potential log files:${NC}"
            echo "$potential_logs"
            
            # 讓用戶選擇要查看的日誌文件
            read -p "Enter the path of the log file to view (or press Enter to cancel): " log_file
            if [[ -z "$log_file" ]]; then
                return 1
            elif [[ -f "$log_file" ]]; then
                echo -e "${YELLOW}Displaying the latest 100 entries from $log_file, press Ctrl+C to exit...${NC}"
                timeout --foreground 30s tail -f -n 100 "$log_file" || true
                return 0
            else
                echo -e "${RED}Error: Specified file does not exist${NC}"
                return 1
            fi
        else
            echo -e "${YELLOW}No log files found${NC}"
            return 1
        fi
    fi
    
    # 提供有用的提示
    echo -e "${YELLOW}Displaying the latest 100 log entries, press Ctrl+C to exit...${NC}"
    echo -e "${YELLOW}Log display will update in real time until you press Ctrl+C${NC}"
    
    # 使用 timeout 命令運行 tail，這樣不會一直阻塞
    timeout --foreground 30s tail -f -n 100 ./data/agent/agent.log || true
    echo -e "${GREEN}Log viewing ended${NC}"
}

# 統一解析命令行參數
parse_command_args() {
    # 重置全局變數
    CMD_ACTION=""
    CMD_TOKEN=""
    CMD_REGION=""
    CMD_INSTALL="false"
    
    # 如果沒有參數，直接返回
    if [[ $# -eq 0 ]]; then
        return 0
    fi
    
    # 第一個參數通常是命令
    CMD_ACTION="$1"
    shift
    
    # 處理剩餘參數
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--token)
                if [[ $# -gt 1 ]]; then
                    CMD_TOKEN="$2"
                    echo -e "${BLUE}Setting token: $CMD_TOKEN${NC}"
                    shift 2
                else
                    echo -e "${RED}Error: -t/--token requires a parameter${NC}"
                    return 1
                fi
                ;;
            -r|--region)
                if [[ $# -gt 1 ]]; then
                    CMD_REGION="$2"
                    echo -e "${BLUE}Setting region: $CMD_REGION${NC}"
                    shift 2
                else
                    echo -e "${RED}Error: -r/--region requires a parameter${NC}"
                    return 1
                fi
                ;;
            -i|--install)
                if [[ $# -gt 1 && "$2" != -* ]]; then
                    # 如果下一個參數不是以 - 開頭，就認為是此參數的值
                    CMD_INSTALL="$2"
                    echo -e "${BLUE}Setting installation option: $CMD_INSTALL${NC}"
                    shift 2
                else
                    CMD_INSTALL="true"
                    echo -e "${BLUE}Setting installation option: true${NC}"
                    shift
                fi
                ;;
            *)
                echo -e "${RED}Error: Unknown parameter $1${NC}"
                return 1
                ;;
        esac
    done
    
    # 可以添加參數驗證邏輯
    # if [[ "$CMD_INSTALL" != "true" && "$CMD_INSTALL" != "false" && "$CMD_INSTALL" != "cn" ]]; then
    #     CMD_INSTALL="true"  # 如果值不合法，設為預設值
    # fi
    return 0
}

# 執行指定命令
execute_command() {
    local command="$1"
    local token="$2"
    local region="$3"
    local hook_enable="false"
    
    # 如果提供了 region，自動啟用 HOOK_ENABLE
    if [[ -n "$region" ]]; then
        hook_enable="true"
    fi
    
    case "$command" in
        start)
            # 如果提供了參數，先進行配置
            if [[ -n "$token" || -n "$region" ]]; then
                ensure_conf_dir
                
                # 如果提供了 region，更新 env 檔案
                if [[ -n "$region" ]]; then
                    config_env "$hook_enable" "$region" "false"
                fi
                
                # 如果提供了 token，更新 key 檔案
                if [[ -n "$token" ]]; then
                    config_key "$token"
                fi
            fi
            
            # 更新系統限制設置
            update_system_limits

            start_pcdn
            return $?
            ;;
        stop)
            stop_pcdn
            return $?
            ;;
        delete)
            delete_pcdn
            return $?
            ;;
        config)
            ensure_conf_dir
            
            # 如果提供了 region，更新 env 檔案
            if [[ -n "$region" ]]; then
                config_env "$hook_enable" "$region" "false"
            fi
            
            # 如果提供了 token，更新 key 檔案
            if [[ -n "$token" ]]; then
                config_key "$token"
            fi
            
            # 如果沒有提供任何參數，進入互動式配置
            if [[ -z "$region" && -z "$token" ]]; then
                config_pcdn
            fi
            return $?
            ;;
        logs)
            view_docker_logs
            return $?
            ;;
        agent-logs)
            view_pcdn_logs
            return $?
            ;;
        *)
            show_menu
            read -p "Please select an operation [0-6]: " choice
            handle_menu_choice "$choice"
            return $?
            ;;
    esac
}

main "$@"
