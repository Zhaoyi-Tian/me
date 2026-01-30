#!/usr/bin/env bash
# -*- encoding: utf-8 -*-
# PKU Grade Watcher 一键安装脚本
# 使用方法: bash <(curl -fsSL https://raw.githubusercontent.com/haierkeys/pku-grade-watcher/master/install.sh)

set -euo pipefail

# ============ 配置 ============
REPO_URL="https://github.com/Zhaoyi-Tian/pku-grade-watcher.git"
INSTALL_DIR="${HOME}/.pku-grade-watcher"
REPO_NAME="pku-grade-watcher"
SERVICE_NAME="pku-grade-watcher.service"
BIN_LINK="/usr/local/bin/pku-grade"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============ 工具函数 ============
log_info() { echo -e "${BLUE}[i]${NC} $*"; }
log_success() { echo -e "${GREEN}[+]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $*"; }
log_error() { echo -e "${RED}[-]${NC} $*"; }

detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
        echo "windows"
    else
        echo "unknown"
    fi
}

is_linux() { [[ "$(detect_os)" == "linux" ]]; }
is_macos() { [[ "$(detect_os)" == "macos" ]]; }

check_python() {
    command -v python3 &>/dev/null || command -v python &>/dev/null
}

# ============ 安装流程 ============
do_install() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       PKU Grade Watcher 安装          ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
    echo ""

    local os
    os=$(detect_os)
    log_info "检测系统: $os"

    # 检查 Python
    if ! check_python; then
        log_warn "未检测到 Python 3，请先安装 Python 3"
        echo "  Linux: sudo apt install python3 python3-pip"
        echo "  macOS: brew install python3"
        exit 1
    fi
    log_success "已检测到 Python"

    # 克隆/更新仓库
    if [[ -d "${INSTALL_DIR}/${REPO_NAME}" ]]; then
        log_warn "检测到已安装，正在更新..."
        cd "${INSTALL_DIR}/${REPO_NAME}"
        git pull
    else
        log_info "正在克隆仓库..."
        mkdir -p "${INSTALL_DIR}"
        git clone "$REPO_URL" "${INSTALL_DIR}/${REPO_NAME}"
    fi

    # 安装依赖
    log_info "正在安装依赖..."
    pip3 install -r "${INSTALL_DIR}/${REPO_NAME}/requirements.txt" --user

    # 配置
    create_config

    # 创建快捷命令
    create_bin_link

    # 设置服务
    if is_linux; then
        create_systemd_service
    fi
    setup_cron

    log_success "安装完成!"
    echo ""
    echo "使用 pku-grade 进入管理菜单"
}

create_config() {
    local config_file="${INSTALL_DIR}/${REPO_NAME}/config.yaml"
    if [[ -f "$config_file" ]]; then
        log_warn "配置文件已存在，如需重新配置请使用 [4] 重新配置"
        return
    fi

    echo ""
    echo -e "${BLUE}请输入配置信息:${NC}"

    echo -n "北京大学门户账号 (学号): "
    read -r username

    echo -n "密码: "
    read -r -s password
    echo ""

    echo -n "Server 酱 sendkey (留空则不推送通知): "
    read -r sendkey
    echo ""

    cat > "$config_file" << EOF
username: "$username"
password: "$password"
sendkey: "$sendkey"
EOF

    log_success "配置文件已创建"
}

create_bin_link() {
    local script_content="${INSTALL_DIR}/${REPO_NAME}/install.sh"

    # 确保脚本文件存在（从当前脚本复制）
    if [[ ! -f "$script_content" ]]; then
        cp "$0" "$script_content"
    fi

    # 更新或创建快捷命令
    sudo rm -f "$BIN_LINK" 2>/dev/null || rm -f "$BIN_LINK"
    sudo ln -sf "$script_content" "$BIN_LINK" 2>/dev/null || ln -sf "$script_content" "$BIN_LINK"
    sudo chmod +x "$script_content" 2>/dev/null || chmod +x "$script_content"
    log_success "快捷命令已更新: pku-grade"
}

create_systemd_service() {
    if ! command -v systemctl &>/dev/null; then
        return
    fi

    log_info "正在创建 systemd 服务..."

    # 创建虚拟环境
    local venv_dir="${INSTALL_DIR}/venv"
    if [[ ! -d "$venv_dir" ]]; then
        python3 -m venv "$venv_dir"
        "$venv_dir/bin/pip" install -r "${INSTALL_DIR}/${REPO_NAME}/requirements.txt"
    fi

    # 创建环境变量文件
    local env_file="${INSTALL_DIR}/${REPO_NAME}/.env"
    local config_file="${INSTALL_DIR}/${REPO_NAME}/config.yaml"
    if [[ -f "$config_file" ]]; then
        # 从 YAML 配置文件读取（移除引号）
        local cfg_username cfg_password cfg_sendkey
        cfg_username=$(grep "username:" "$config_file" | sed 's/username: *"\?\(.*\)"\?/\1/' | tr -d '"' | tr -d "'")
        cfg_password=$(grep "password:" "$config_file" | sed 's/password: *"\?\(.*\)"\?/\1/' | tr -d '"' | tr -d "'")
        cfg_sendkey=$(grep "sendkey:" "$config_file" | sed 's/sendkey: *"\?\(.*\)"\?/\1/' | tr -d '"' | tr -d "'")

        sudo tee "$env_file" > /dev/null << EOF
username="$cfg_username"
password="$cfg_password"
sendkey="$cfg_sendkey"
EOF
    fi

    # 创建服务文件
    local service_file="/etc/systemd/system/${SERVICE_NAME}"
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=PKU Grade Watcher - 北大成绩监控
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=$USER
WorkingDirectory=${INSTALL_DIR}/${REPO_NAME}
EnvironmentFile=${INSTALL_DIR}/${REPO_NAME}/.env
ExecStart=${venv_dir/bin/python} ${INSTALL_DIR}/${REPO_NAME}/main.py

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "${SERVICE_NAME}"
    log_success "systemd 服务已创建并开机自启"
}

setup_cron() {
    log_info "正在设置定时任务 (每 10 分钟)..."

    local work_dir="${INSTALL_DIR}/${REPO_NAME}"
    local cron_cmd="cd ${work_dir} && python3 main.py"

    # 添加定时任务
    existing_cron=$(crontab -l 2>/dev/null | grep -v "pku-grade-watcher" || true)
    new_cron=$(printf "%s\n*/10 * * * * %s\n" "$existing_cron" "$cron_cmd")
    echo "$new_cron" | crontab -

    # 启动 cron 服务
    if command -v systemctl &>/dev/null; then
        sudo systemctl start crond 2>/dev/null || sudo systemctl start cron 2>/dev/null || true
    fi

    log_success "定时任务已设置: 每 10 分钟执行一次"
}

# ============ 运行程序 ============
do_run() {
    if [[ ! -d "${INSTALL_DIR}/${REPO_NAME}" ]]; then
        log_error "未安装，请先运行安装"
        exit 1
    fi

    cd "${INSTALL_DIR}/${REPO_NAME}"

    # 加载环境变量
    if [[ -f ".env" ]]; then
        set -a
        source .env
        set +a
    fi

    python3 main.py
}

# ============ 查看状态 ============
do_status() {
    echo ""
    echo -e "${BLUE}PKU Grade Watcher 状态${NC}"
    echo "================================"

    # 检查安装
    if [[ -d "${INSTALL_DIR}/${REPO_NAME}" ]]; then
        log_success "已安装: ${INSTALL_DIR}/${REPO_NAME}"
    else
        log_error "未安装"
        return
    fi

    # 检查 cron
    if crontab -l 2>/dev/null | grep -q "pku-grade-watcher"; then
        log_success "定时任务: 已设置"
    else
        log_warn "定时任务: 未设置"
    fi

    # 检查 systemd
    if is_linux && command -v systemctl &>/dev/null; then
        if systemctl is-enabled "${SERVICE_NAME}" &>/dev/null; then
            log_success "systemd 服务: 已启用开机自启"
        else
            log_warn "systemd 服务: 未启用"
        fi
    fi

    # 上次执行
    local last_run_log="${INSTALL_DIR}/${REPO_NAME}/.last_run"
    if [[ -f "$last_run_log" ]]; then
        echo ""
        echo "上次运行: $(cat "$last_run_log")"
    fi
}

# ============ 重新配置 ============
do_config() {
    if [[ ! -d "${INSTALL_DIR}/${REPO_NAME}" ]]; then
        log_error "未安装，请先运行安装"
        exit 1
    fi

    local config_file="${INSTALL_DIR}/${REPO_NAME}/config.yaml"
    rm -f "$config_file"
    create_config

    # 更新 .env
    if is_linux && [[ -f "/etc/systemd/system/${SERVICE_NAME}" ]]; then
        source "${INSTALL_DIR}/${REPO_NAME}/config.yaml" 2>/dev/null || true
        cat > "${INSTALL_DIR}/${REPO_NAME}/.env" << EOF
username="$username"
password="$password"
sendkey="$sendkey"
EOF
    fi

    log_success "配置已更新"
}

# ============ 卸载 ============
do_uninstall() {
    echo -n "确定要卸载吗? (y/n): "
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "已取消"
        return
    fi

    log_info "正在卸载..."

    # 停止并删除 systemd 服务
    if is_linux && command -v systemctl &>/dev/null; then
        sudo systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
        sudo systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
        sudo rm -f "/etc/systemd/system/${SERVICE_NAME}"
        sudo systemctl daemon-reload 2>/dev/null || true
    fi

    # 删除 cron 任务
    if command -v crontab &>/dev/null; then
        local current_cron
        current_cron=$(crontab -l 2>/dev/null || true)
        if echo "$current_cron" | grep -q "pku-grade-watcher"; then
            echo "$current_cron" | grep -v "pku-grade-watcher" | crontab -
        fi
    fi

    # 删除快捷命令
    sudo rm -f "$BIN_LINK" 2>/dev/null || rm -f "$BIN_LINK" || true

    # 删除安装目录
    rm -rf "${INSTALL_DIR}"

    log_success "卸载完成"
}

# ============ 交互式菜单 ============
show_menu() {
    clear
    echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       PKU Grade Watcher 管理脚本      ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
    echo ""
    echo "  [1] 安装/更新程序"
    echo "  [2] 立即运行"
    echo "  [3] 服务状态"
    echo "  [4] 重新配置"
    echo "  [5] 卸载"
    echo "  [0] 退出"
    echo ""

    while true; do
        read -p "请选择 [0-5]: " opt
        case "$opt" in
            1) do_install; break ;;
            2) do_run; break ;;
            3) do_status; break ;;
            4) do_config; break ;;
            5) do_uninstall; break ;;
            0) exit 0 ;;
            *) log_warn "无效选项，请重新选择" ;;
        esac
    done
}

# ============ 主入口 ============
main() {
    local cmd="${1:-}"
    case "$cmd" in
        install|i) do_install ;;
        run|r) do_run ;;
        status|s) do_status ;;
        config|c) do_config ;;
        uninstall|un) do_uninstall ;;
        ""|menu) show_menu ;;
        *) echo "用法: $0 {install|run|status|config|uninstall}"; exit 1 ;;
    esac
}

main "$@"
