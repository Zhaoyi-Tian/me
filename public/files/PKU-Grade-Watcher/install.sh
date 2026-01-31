#!/usr/bin/env bash
# -*- encoding: utf-8 -*-
# PKU Grade Watcher 一键安装脚本 (Linux Only)
# 使用方法: bash <(curl -fsSL https://www.zhaoyi-tian.cn/files/PKU-Grade-Watcher/install.sh)

set -euo pipefail

# ============ 配置 ============
REPO_URL="https://gist.github.com/067769bcbe0efe581562dc946670efdb.git"
INSTALL_DIR="${HOME}/.pku-grade-watcher"
REPO_NAME="pku-grade-watcher"
SERVICE_NAME="pku-grade-watcher.service"
BIN_LINK="/usr/local/bin/pku-grade"

# 获取脚本自身路径（兼容 curl | bash 方式）
SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
if [[ -z "$SCRIPT_SOURCE" ]] || [[ ! -f "$SCRIPT_SOURCE" ]]; then
    SCRIPT_SOURCE="$0"
fi

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

check_python() {
    if command -v python3 &>/dev/null; then
        PYTHON_CMD="python3"
    elif command -v python &>/dev/null; then
        PYTHON_CMD="python"
    else
        return 1
    fi

    if ! "$PYTHON_CMD" -m pip --version &>/dev/null; then
        return 2
    fi
    # 导出变量，使其在函数外可用
    export PYTHON_CMD
    return 0
}

# ============ 安装流程 ============
do_install() {
    echo ""
    echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                      免责声明                              ║${NC}"
    echo -e "${RED}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${RED}║  本工具仅供学习交流，严禁非法用途。                        ║${NC}"
    echo -e "${RED}║  用户需承担使用本工具产生的一切后果。                      ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    read -rp "我已阅读并同意上述声明 (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "已取消安装"
        exit 0
    fi

    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       PKU Grade Watcher 安装          ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
    echo ""

    log_info "检测系统: Linux"

    # 检查 Python
    if ! check_python; then
        log_warn "未检测到 Python 3，请先安装"
        echo "  Debian/Ubuntu: sudo apt install python3 python3-pip"
        echo "  RHEL/CentOS: sudo yum install python3 python3-pip"
        exit 1
    fi
    log_success "已检测到 Python"

    # 检查是否已安装
    if [[ -d "${INSTALL_DIR}/${REPO_NAME}" ]]; then
        log_error "已安装，如需重新安装请先卸载"
        echo "  运行: pku-grade uninstall"
        exit 1
    fi

    log_info "正在克隆仓库..."
    mkdir -p "${INSTALL_DIR}"
    git clone "$REPO_URL" "${INSTALL_DIR}/${REPO_NAME}" || exit 1

    # 创建虚拟环境
    local venv_dir="${INSTALL_DIR}/venv"
    if [[ ! -d "$venv_dir" ]]; then
        log_info "正在创建虚拟环境..."
        "$PYTHON_CMD" -m venv "$venv_dir"
    fi
    
    # 安装依赖
    log_info "正在安装依赖..."
    "${venv_dir}/bin/python" -m pip install -r "${INSTALL_DIR}/${REPO_NAME}/requirements.txt" || exit 1

    # 配置
    create_config

    # 复制 install.sh 到安装目录
    cp "$SCRIPT_SOURCE" "${INSTALL_DIR}/${REPO_NAME}/install.sh"
    chmod +x "${INSTALL_DIR}/${REPO_NAME}/install.sh"

    # 创建快捷命令
    create_bin_link

    # 设置服务
    create_systemd_service

    log_success "安装完成!"
    echo ""
    echo "使用 pku-grade 进入管理菜单"
}

create_config() {
    local config_file="${INSTALL_DIR}/${REPO_NAME}/config.yaml"

    echo ""
    echo -e "${BLUE}请输入配置信息:${NC}"

    read -rp "北京大学门户账号 (学号): " username

    read -rsp "密码: " password
    echo ""

    read -rp "Server 酱 sendkey (留空则不推送通知): " sendkey

    read -rp "查询间隔 (分钟, 建议 10-20): " interval
    interval="${interval:-10}"

    cat > "$config_file" << EOF
username: "$username"
password: "$password"
sendkey: "$sendkey"
interval: $interval
EOF

    chmod 600 "$config_file"
    log_success "配置文件已创建"
}

# ============ 安装脚本自安装 ============
install_self_to_system() {
    local src="$SCRIPT_SOURCE"
    local downloaded=false

    # 如果是通过 curl | bash 方式运行，脚本源文件不存在，需要从 URL 下载
    if [[ ! -f "$src" ]] || [[ ! -s "$src" ]]; then
        log_info "检测到通过管道运行，正在从远程下载安装脚本..."
        local remote_url="https://www.zhaoyi-tian.cn/files/PKU-Grade-Watcher/install.sh"
        curl -fsSL "$remote_url" -o "${INSTALL_DIR}/${REPO_NAME}/install.sh" || {
            log_error "下载安装脚本失败"
            return 1
        }
        src="${INSTALL_DIR}/${REPO_NAME}/install.sh"
        downloaded=true
    fi

    # 复制安装脚本到安装目录（如果未下载才需要复制）
    if [[ "$downloaded" != "true" ]]; then
        cp -f "$src" "${INSTALL_DIR}/${REPO_NAME}/install.sh"
    fi
    chmod +x "${INSTALL_DIR}/${REPO_NAME}/install.sh"

    # 更新软链接
    local link_dir
    link_dir="$(dirname "$BIN_LINK")"
    local need_sudo=""

    if [[ "$EUID" -ne 0 ]]; then
        need_sudo="sudo"
        # 尝试检查是否可以使用 sudo
        if ! sudo -n true 2>/dev/null; then
            log_info "需要 root 权限创建快捷命令，请输入密码..."
        fi
    fi

    $need_sudo mkdir -p "$link_dir"
    $need_sudo ln -sf "${INSTALL_DIR}/${REPO_NAME}/install.sh" "$BIN_LINK" || {
        log_warn "创建快捷命令失败，请手动执行: sudo ln -sf ${INSTALL_DIR}/${REPO_NAME}/install.sh $BIN_LINK"
    }

    # 验证软链接是否创建成功
    if [[ -L "$BIN_LINK" ]]; then
        log_success "安装脚本已保存至: ${INSTALL_DIR}/${REPO_NAME}/install.sh"
        log_success "快捷命令已更新: pku-grade"
    else
        log_warn "快捷命令创建失败，可手动创建: sudo ln -sf ${INSTALL_DIR}/${REPO_NAME}/install.sh $BIN_LINK"
    fi
}

create_bin_link() {
    # 复用 install_self_to_system 的逻辑
    install_self_to_system
}

generate_env_file() {
    log_info "正在生成环境文件 (.env)..."
    parse_config || return 1
    local env_file="${INSTALL_DIR}/${REPO_NAME}/.env"
    rm -f "$env_file"
    cat > "$env_file" << EOF
username="$USERNAME"
password="$PASSWORD"
sendkey="$SENDKEY"
EOF
    chmod 600 "$env_file"
}

install_systemd_units() {
    parse_config || return 1
    local venv_dir="${INSTALL_DIR}/venv"

    # 创建服务文件
    local service_file="/etc/systemd/system/${SERVICE_NAME}"
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=PKU Grade Watcher - 北大成绩监控
After=network.target

[Service]
Type=oneshot
User=$USER
WorkingDirectory=${INSTALL_DIR}/${REPO_NAME}
EnvironmentFile=${INSTALL_DIR}/${REPO_NAME}/.env
ExecStart=${venv_dir}/bin/python ${INSTALL_DIR}/${REPO_NAME}/main.py

[Install]
WantedBy=multi-user.target
EOF

    # 创建定时器文件
    local timer_file="/etc/systemd/system/${REPO_NAME}.timer"
    sudo tee "$timer_file" > /dev/null << EOF
[Unit]
Description=PKU Grade Watcher Timer

[Timer]
OnBootSec=1min
OnUnitActiveSec=${INTERVAL}min
AccuracySec=1s
Unit=${SERVICE_NAME}

[Install]
WantedBy=timers.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "${SERVICE_NAME}" "${REPO_NAME}.timer"
}

create_systemd_service() {
    log_info "正在创建 systemd 服务..."

    # 虚拟环境已在 do_install 中创建，此处确保存在即可
    local venv_dir="${INSTALL_DIR}/venv"
    if [[ ! -d "$venv_dir" ]]; then
        "$PYTHON_CMD" -m venv "$venv_dir"
        "${venv_dir}/bin/python" -m pip install -r "${INSTALL_DIR}/${REPO_NAME}/requirements.txt" -q
    fi

    generate_env_file
    install_systemd_units
    
    # 立即运行一次服务
    sudo systemctl start "${SERVICE_NAME}"
    # 启动定时器
    sudo systemctl start "${REPO_NAME}.timer"
    
    log_success "systemd 服务已创建并已立即运行"
}

# ============ 配置解析 ============
parse_config() {
    local config_file="${INSTALL_DIR}/${REPO_NAME}/config.yaml"
    [[ -f "$config_file" ]] || return 1

    USERNAME=$(grep "username:" "$config_file" 2>/dev/null | sed 's/username: *"\?\(.*\)"\?/\1/' | tr -d '"' | tr -d "'" || true)
    PASSWORD=$(grep "password:" "$config_file" 2>/dev/null | sed 's/password: *"\?\(.*\)"\?/\1/' | tr -d '"' | tr -d "'" || true)
    SENDKEY=$(grep "sendkey:" "$config_file" 2>/dev/null | sed 's/sendkey: *"\?\(.*\)"\?/\1/' | tr -d '"' | tr -d "'" || true)
    INTERVAL=$(grep "interval:" "$config_file" 2>/dev/null | sed 's/interval: *\([0-9]*\)/\1/' | tr -d ' ' || true)
    INTERVAL="${INTERVAL:-10}"
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
        set -a; source .env
    fi

    local log_file="${INSTALL_DIR}/${REPO_NAME}/run.log"

    log_info "正在运行..."
    "${INSTALL_DIR}/venv/bin/python" main.py 2>&1 | tee "$log_file"
    log_success "运行完成，日志已保存"
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

    # 检查 systemd
    if command -v systemctl &>/dev/null; then
        local timer_status="未设置"
        if systemctl is-enabled "${REPO_NAME}.timer" &>/dev/null; then
            timer_status="已启用"
            if systemctl is-active "${REPO_NAME}.timer" &>/dev/null; then
                timer_status="运行中"
            fi
        fi
        echo -e "  定时器: ${timer_status}"

        local service_status="未设置"
        if systemctl is-enabled "${SERVICE_NAME}" &>/dev/null; then
            service_status="已启用"
        fi
        echo -e "  服务: ${service_status}"

        # 显示 timer 下次执行时间
        local next_run
        next_run=$(systemctl show "${REPO_NAME}.timer" --property=NextElapseUSecRealtime --value 2>/dev/null || echo "N/A")
        if [[ "$next_run" != "N/A" && -n "$next_run" ]]; then
            echo -e "  下次执行: ${next_run}"
        fi

        # 显示上次运行状态
        local last_start
        last_start=$(systemctl show "${SERVICE_NAME}" --property=ExecMainStartTimestamp --value 2>/dev/null || echo "N/A")
        if [[ "$last_start" != "N/A" && -n "$last_start" ]]; then
             echo -e "  上次运行: ${last_start}"
             
             local exit_code
             exit_code=$(systemctl show "${SERVICE_NAME}" --property=ExecMainStatus --value 2>/dev/null || echo "N/A")
             local result
             result=$(systemctl show "${SERVICE_NAME}" --property=Result --value 2>/dev/null || echo "N/A")
             
             if [[ "$result" == "success" && "$exit_code" == "0" ]]; then
                 echo -e "  运行结果: ${GREEN}成功${NC}"
             else
                 echo -e "  运行结果: ${RED}失败 (Code: ${exit_code}, Result: ${result})${NC}"
             fi

             echo ""
             echo "  --- 最近日志 (Last 10 lines) ---"
             sudo journalctl -u "${SERVICE_NAME}" -n 10 --no-pager --output cat 2>/dev/null | sed 's/^/  /' || echo "  (无法获取日志)"
        fi
    fi

    # 显示配置信息
    echo ""
    echo -e "${BLUE}当前配置:${NC}"
    echo "================================"
    if parse_config; then
        echo "  用户名: ${USERNAME:-未设置}"
        if [[ -n "$SENDKEY" ]]; then
             echo "  推送: 已配置 ************"
        else
             echo "  推送: 未设置"
        fi
        echo "  间隔: ${INTERVAL:-10} 分钟"
    else
        echo "  (配置文件不存在)"
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

    generate_env_file
    install_systemd_units

    if command -v systemctl &>/dev/null; then
        sudo systemctl restart "${REPO_NAME}.timer"
    fi

    log_success "配置已更新"
}

# ============ 卸载 ============
do_uninstall() {
    read -rp "确定要完全卸载吗? 这将删除所有数据 (y/n): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "已取消"
        return
    fi

    log_info "正在卸载..."

    # 停止并删除 systemd 服务
    if command -v systemctl &>/dev/null; then
        log_info "停止 systemd 服务..."
        sudo systemctl stop "${REPO_NAME}.timer" 2>/dev/null || true
        sudo systemctl disable "${REPO_NAME}.timer" 2>/dev/null || true
        sudo rm -f "/etc/systemd/system/${REPO_NAME}.timer"

        sudo systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
        sudo systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
        sudo rm -f "/etc/systemd/system/${SERVICE_NAME}"

        sudo systemctl daemon-reload 2>/dev/null || true
    fi

    # 删除快捷命令
    log_info "删除快捷命令..."
    sudo rm -f "$BIN_LINK" 2>/dev/null || rm -f "$BIN_LINK" || true

    # 删除安装目录
    log_info "删除安装目录..."
    rm -rf "${INSTALL_DIR}"

    log_success "卸载完成"
}

# ============ 交互式菜单 ============
show_menu() {
    echo ""
    echo -e "${BLUE}╔═══════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║       PKU Grade Watcher 管理脚本      ║${NC}"
    echo -e "${BLUE}╚═══════════════════════════════════════╝${NC}"
    echo ""
    echo "  [1] 立即运行"
    echo "  [2] 服务状态"
    echo "  [3] 重新配置"
    echo "  [4] 卸载"
    echo "  [0] 退出"
    echo ""

    while true; do
        read -rp "请选择 [0-4]: " opt
        case "$opt" in
            1) do_run; echo ""; read -rp "按回车键返回菜单..." ignore; show_menu; break ;;
            2) do_status; echo ""; read -rp "按回车键返回菜单..." ignore; show_menu; break ;;
            3) do_config; echo ""; read -rp "按回车键返回菜单..." ignore; show_menu; break ;;
            4) do_uninstall; break ;;
            0) exit 0 ;;
            *) log_warn "无效选项，请重新选择" ;;
        esac
    done
}

# ============ 主入口 ============
main() {
    local cmd="${1:-}"

    # 先检查安装状态，决定默认行为
    if [[ ! -d "${INSTALL_DIR}/${REPO_NAME}" ]]; then
        # 无论 cmd 是什么，只要未安装且 cmd 为空或 menu，都走安装流程
        if [[ -z "$cmd" || "$cmd" == "menu" ]]; then
             do_install
             exit 0
        fi
        # 如果是其他命令（如 uninstall）但目前未安装，后续会有专门检查报错
    fi

    # 已安装后的逻辑
    case "$cmd" in
        install) do_install ;;
        run) do_run ;;
        status) do_status ;;
        config) do_config ;;
        uninstall) do_uninstall ;;
        ""|menu) show_menu ;; # 空参数直接显示菜单
        *) echo "用法: $0 {install|run|status|config|uninstall}"; exit 1 ;;
    esac
}

main "$@"
