#!/bin/bash

# 检查realm是否已安装
if [ -f "/root/realm/realm" ]; then
    echo "检测到realm已安装。"
    realm_status="已安装"
    realm_status_color="\033[0;32m" # 绿色
else
    echo "realm未安装。"
    realm_status="未安装"
    realm_status_color="\033[0;31m" # 红色
fi

# 检查realm服务状态
check_realm_service_status() {
    if systemctl is-active --quiet realm; then
        echo -e "\033[0;32m启用\033[0m" # 绿色
    else
        echo -e "\033[0;31m未启用\033[0m" # 红色
    fi
}

# 显示菜单的函数
show_menu() {
    clear
    echo "欢迎使用realm一键转发脚本"
    echo "================="
    echo "1. 部署环境"
    echo "2. 添加转发"
    echo "3. 删除转发"
    echo "4. 查看转发规则"
    echo "5. 批量添加三网IPv6转发"
    echo "6. 启动服务"
    echo "7. 停止服务"
    echo "8. 诊断realm问题"
    echo "9. 一键卸载"
    echo "================="
    echo -e "realm 状态：${realm_status_color}${realm_status}\033[0m"
    echo -n "realm 转发状态："
    check_realm_service_status
}

# 部署环境的函数
deploy_realm() {
    echo "开始部署realm环境..."
    echo "================="
    echo "请选择部署方式："
    echo "1. 使用现有的realm程序"
    echo "2. 从源码编译realm"
    echo "3. 下载预编译二进制文件（推荐）"
    echo "================="
    read -p "请选择 (1/2/3): " deploy_choice
    
    # 检查/root/realm是否是文件而非目录
    realm_file_backup=""
    if [ -f "/root/realm" ] && [ ! -d "/root/realm" ]; then
        echo "警告：检测到/root/realm是一个realm可执行文件，将临时移动到/root/realm_tmp"
        mv /root/realm /root/realm_tmp
        realm_file_backup="/root/realm_tmp"
    fi
    
    # 确保realm目录存在
    if [ ! -d "/root/realm" ]; then
        mkdir -p /root/realm
    fi
    
    case $deploy_choice in
        1)
            # 使用现有程序
            echo "使用现有realm程序..."
            
            # 如果之前备份了realm文件，提示用户
            if [ -n "$realm_file_backup" ]; then
                echo "提示：原/root/realm文件已被临时移动到 $realm_file_backup"
                read -p "是否使用该文件？(Y/N): " use_backup
                if [[ $use_backup == "Y" || $use_backup == "y" ]]; then
                    realm_path="$realm_file_backup"
                else
                    realm_path=""
                fi
            else
                realm_path=""
            fi
            
            while true; do
                if [ -z "$realm_path" ]; then
                    read -p "请输入realm可执行文件的完整路径: " realm_path
                fi
                
                # 检查是否为空
                if [ -z "$realm_path" ]; then
                    echo "错误：路径不能为空。"
                    continue
                fi
                
                # 特殊处理：如果用户输入/root/realm，但该文件已被移动
                if [ "$realm_path" = "/root/realm" ] && [ -n "$realm_file_backup" ]; then
                    echo "提示：该文件已被移动到 $realm_file_backup，将使用该路径。"
                    realm_path="$realm_file_backup"
                fi
                
                # 检查是否是目录
                if [ -d "$realm_path" ]; then
                    echo "错误：输入的是目录而非文件，请输入realm可执行文件的完整路径。"
                    realm_path=""
                    continue
                fi
                
                # 检查文件是否存在
                if [ ! -f "$realm_path" ]; then
                    echo "错误：文件不存在，请重新输入。"
                    read -p "是否继续？(Y/N): " continue_choice
                    if [[ $continue_choice != "Y" && $continue_choice != "y" ]]; then
                        echo "部署已取消。"
                        # 恢复备份文件
                        if [ -n "$realm_file_backup" ] && [ -f "$realm_file_backup" ]; then
                            mv "$realm_file_backup" /root/realm
                            echo "已恢复原文件到 /root/realm"
                        fi
                        return 1
                    fi
                    realm_path=""
                    continue
                fi
                
                # 检查文件是否可执行
                if [ ! -x "$realm_path" ]; then
                    echo "警告：该文件不可执行，正在添加执行权限..."
                    chmod +x "$realm_path"
                fi
                
                # 获取绝对路径并检查是否与目标路径相同
                realm_path_abs=$(readlink -f "$realm_path")
                target_path_abs=$(readlink -f "/root/realm/realm" 2>/dev/null || echo "/root/realm/realm")
                
                if [ "$realm_path_abs" = "$target_path_abs" ]; then
                    echo "realm程序已在目标位置 /root/realm/realm"
                else
                    # 复制到目标位置
                    cp "$realm_path" /root/realm/realm
                    chmod +x /root/realm/realm
                    echo "realm程序已复制到 /root/realm/realm"
                    
                    # 清理临时备份文件
                    if [ -n "$realm_file_backup" ] && [ -f "$realm_file_backup" ]; then
                        rm -f "$realm_file_backup"
                        echo "已清理临时备份文件。"
                    fi
                fi
                break
            done
            ;;
        2)
            # 从源码编译
            echo "从源码编译realm..."
            echo "请选择编译方式："
            echo "1. 动态链接编译（依赖系统glibc）"
            echo "2. 静态链接编译（推荐，无glibc依赖）"
            read -p "选择 (1/2，默认2): " compile_choice
            if [ -z "$compile_choice" ]; then
                compile_choice="2"
            fi
            
            # 安装必要的依赖
            echo "安装依赖包..."
            apt-get update
            apt-get install -y git curl build-essential cmake pkg-config libssl-dev perl golang libclang-dev llvm-dev clang
            
            # 如果选择静态编译，安装musl工具链
            if [ "$compile_choice" = "2" ]; then
                echo "安装musl静态编译工具链..."
                apt-get install -y musl-tools musl-dev
                
                # 验证musl-gcc是否安装成功
                if ! command -v musl-gcc &> /dev/null; then
                    echo "警告：musl-gcc安装失败，将使用动态编译方式"
                    compile_choice="1"
                fi
            fi
            
            # 检查关键依赖是否安装成功
            if ! command -v cmake &> /dev/null; then
                echo "错误：cmake安装失败，请手动安装后重试。"
                return 1
            fi
            
            # 检查clang是否安装成功
            if ! command -v clang &> /dev/null; then
                echo "错误：clang安装失败，请手动安装后重试。"
                return 1
            fi
            
            # 安装Rust编译环境
            if ! command -v cargo &> /dev/null; then
                echo "安装Rust编译环境..."
                curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
                source "$HOME/.cargo/env"
                export PATH="$HOME/.cargo/bin:$PATH"
            else
                echo "Rust已安装，跳过安装步骤。"
            fi
            
            # 确保cargo可用
            if ! command -v cargo &> /dev/null; then
                echo "错误：Rust安装失败，请手动安装后重试。"
                return 1
            fi
            
            # 克隆realm源码
            cd /root
            if [ -d "realm-src" ]; then
                echo "删除旧的源码目录..."
                rm -rf realm-src
            fi
            echo "克隆realm源码..."
            if ! git clone https://github.com/zhboner/realm.git realm-src; then
                echo "错误：源码克隆失败，请检查网络连接。"
                return 1
            fi
            cd realm-src
            
            # 编译realm
            echo "开始编译realm（这可能需要几分钟）..."
            
            if [ "$compile_choice" = "2" ]; then
                # 静态链接编译（musl target）
                echo "使用musl target进行静态链接编译..."
                
                # 添加musl target
                rustup target add x86_64-unknown-linux-musl
                
                # 设置musl编译器环境变量
                export CC_x86_64_unknown_linux_musl=musl-gcc
                export CARGO_TARGET_X86_64_UNKNOWN_LINUX_MUSL_LINKER=musl-gcc
                
                # 静态编译
                if ! cargo build --release --target x86_64-unknown-linux-musl; then
                    echo "错误：静态编译失败，尝试动态编译..."
                    if ! cargo build --release; then
                        echo "错误：编译失败，请查看上方错误信息。"
                        cd /root
                        return 1
                    fi
                    compile_choice="1"  # 标记为动态编译
                fi
            else
                # 动态链接编译
                if ! cargo build --release; then
                    echo "错误：编译失败，请查看上方错误信息。"
                    cd /root
                    return 1
                fi
            fi
            
            # 检查编译产物是否存在
            if [ "$compile_choice" = "2" ] && [ -f "target/x86_64-unknown-linux-musl/release/realm" ]; then
                # 静态编译的文件
                cp target/x86_64-unknown-linux-musl/release/realm /root/realm/realm
                chmod +x /root/realm/realm
                echo "realm可执行文件已生成（静态链接，无glibc依赖）。"
            elif [ -f "target/release/realm" ]; then
                # 动态编译的文件
                cp target/release/realm /root/realm/realm
                chmod +x /root/realm/realm
                echo "realm可执行文件已生成（动态链接）。"
            else
                echo "错误：编译后的可执行文件不存在。"
                cd /root
                return 1
            fi
            
            # 清理源码目录（可选）
            cd /root
            rm -rf realm-src
            echo "源码目录已清理。"
            ;;
        3)
            # 下载预编译二进制
            echo "下载预编译realm二进制文件..."
            
            # 检测系统架构
            arch=$(uname -m)
            echo "检测到系统架构: $arch"
            
            # 下载最新release
            echo "从GitHub下载最新版本..."
            cd /root/realm
            
            if [ "$arch" = "x86_64" ]; then
                # 尝试下载musl版本（静态链接）
                if ! wget -O realm https://github.com/zhboner/realm/releases/latest/download/realm-x86_64-unknown-linux-musl 2>/dev/null; then
                    echo "下载musl版本失败，尝试下载gnu版本..."
                    if ! wget -O realm https://github.com/zhboner/realm/releases/latest/download/realm-x86_64-unknown-linux-gnu; then
                        echo "错误：下载失败，请检查网络连接或使用其他部署方式。"
                        return 1
                    fi
                fi
            elif [ "$arch" = "aarch64" ]; then
                if ! wget -O realm https://github.com/zhboner/realm/releases/latest/download/realm-aarch64-unknown-linux-musl 2>/dev/null; then
                    echo "下载musl版本失败，尝试下载gnu版本..."
                    if ! wget -O realm https://github.com/zhboner/realm/releases/latest/download/realm-aarch64-unknown-linux-gnu; then
                        echo "错误：下载失败，请检查网络连接或使用其他部署方式。"
                        return 1
                    fi
                fi
            else
                echo "错误：不支持的系统架构: $arch"
                echo "支持的架构: x86_64, aarch64"
                return 1
            fi
            
            chmod +x realm
            echo "realm可执行文件下载完成（预编译二进制）。"
            ;;
        *)
            echo "无效选项，部署已取消。"
            return 1
            ;;
    esac
    
    # 初始化配置文件
    if [ ! -f "/root/realm/config.toml" ]; then
        touch /root/realm/config.toml
        echo "配置文件已创建。"
    fi
    
    # 创建服务文件
    echo "[Unit]
Description=realm
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
DynamicUser=true
WorkingDirectory=/root/realm
ExecStart=/root/realm/realm -c /root/realm/config.toml

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/realm.service
    systemctl daemon-reload
    # 更新realm状态变量
    realm_status="已安装"
    realm_status_color="\033[0;32m" # 绿色
    echo "部署完成。"
}

# 卸载realm
uninstall_realm() {
    systemctl stop realm
    systemctl disable realm
    rm -f /etc/systemd/system/realm.service
    systemctl daemon-reload
    rm -rf /root/realm
    echo "realm已被卸载。"
    # 更新realm状态变量
    realm_status="未安装"
    realm_status_color="\033[0;31m" # 红色
}

# 删除转发规则的函数
delete_forward() {
    # 检查配置文件是否存在
    if [ ! -f "/root/realm/config.toml" ]; then
        echo "配置文件不存在。"
        return
    fi
    
    echo "当前转发规则："
    local IFS=$'\n'
    
    # 读取所有endpoints块
    local endpoint_lines=($(grep -n '\[\[endpoints\]\]' /root/realm/config.toml 2>/dev/null))
    
    if [ ${#endpoint_lines[@]} -eq 0 ]; then
        echo "没有发现任何转发规则。"
        return
    fi
    
    # 显示每个endpoint的详细信息
    local index=1
    declare -a rule_info
    for endpoint_line in "${endpoint_lines[@]}"; do
        local line_num=$(echo $endpoint_line | cut -d ':' -f 1)
        local end_line=$((line_num + 10))  # 读取后续几行
        
        # 提取listen、remote、protocol等信息
        local listen=$(sed -n "${line_num},${end_line}p" /root/realm/config.toml | grep "listen =" | head -1 | cut -d '"' -f 2)
        local remote=$(sed -n "${line_num},${end_line}p" /root/realm/config.toml | grep "remote =" | head -1 | cut -d '"' -f 2)
        local protocol=$(sed -n "${line_num},${end_line}p" /root/realm/config.toml | grep "protocol =" | head -1 | cut -d '"' -f 2)
        local tfo=$(sed -n "${line_num},${end_line}p" /root/realm/config.toml | grep "tcp_fast_open" | head -1)
        
        if [ -z "$protocol" ]; then
            protocol="tcp"
        fi
        
        local tfo_status=""
        if [ -n "$tfo" ]; then
            tfo_status=" [TFO]"
        fi
        
        echo "${index}. $listen -> $remote ($protocol)$tfo_status"
        rule_info[$index]=$line_num
        let index+=1
    done

    echo ""
    echo "请输入要删除的转发规则序号，直接按回车返回主菜单。"
    read -p "选择: " choice
    if [ -z "$choice" ]; then
        echo "返回主菜单。"
        return
    fi

    if ! [[ $choice =~ ^[0-9]+$ ]]; then
        echo "无效输入，请输入数字。"
        return
    fi

    if [ $choice -lt 1 ] || [ $choice -gt ${#endpoint_lines[@]} ]; then
        echo "选择超出范围，请输入有效序号。"
        return
    fi

    local start_line=${rule_info[$choice]}
    
    # 查找下一个[[endpoints]]或文件末尾
    local next_endpoint=$(awk -v start=$((start_line + 1)) 'NR >= start && /^\[\[endpoints\]\]/ {print NR; exit}' /root/realm/config.toml)
    
    local end_line
    if [ -z "$next_endpoint" ]; then
        # 找不到下一个endpoint，删除到下一个非空行之前或文件末尾
        end_line=$(awk -v start=$((start_line + 1)) 'NR >= start && /^$/ {print NR; exit}' /root/realm/config.toml)
        if [ -z "$end_line" ]; then
            end_line=$(wc -l < /root/realm/config.toml)
        fi
    else
        end_line=$((next_endpoint - 1))
    fi

    # 使用sed删除选中的转发规则
    sed -i "${start_line},${end_line}d" /root/realm/config.toml

    echo "转发规则已删除。"
}

# 添加转发规则
add_forward() {
    # 检查配置文件是否存在
    if [ ! -f "/root/realm/config.toml" ]; then
        echo "配置文件不存在，正在创建..."
        touch /root/realm/config.toml
    fi
    
    while true; do
        echo ""
        echo "================="
        echo "添加新的转发规则"
        echo "================="
        
        # 监听地址
        read -p "请输入监听IP地址（默认0.0.0.0，支持IPv6）: " listen_ip
        if [ -z "$listen_ip" ]; then
            listen_ip="0.0.0.0"
        fi
        
        # 监听端口
        read -p "请输入监听端口: " listen_port
        if [ -z "$listen_port" ]; then
            echo "错误：监听端口不能为空。"
            continue
        fi
        
        # 远程地址
        read -p "请输入远程IP地址: " remote_ip
        if [ -z "$remote_ip" ]; then
            echo "错误：远程IP地址不能为空。"
            continue
        fi
        
        # 远程端口
        read -p "请输入远程端口: " remote_port
        if [ -z "$remote_port" ]; then
            echo "错误：远程端口不能为空。"
            continue
        fi
        
        # 协议选择
        echo "请选择转发协议："
        echo "1. TCP"
        echo "2. UDP"
        echo "3. TCP+UDP（创建两条规则）"
        read -p "选择 (1/2/3，默认1): " protocol_choice
        if [ -z "$protocol_choice" ]; then
            protocol_choice="1"
        fi
        
        # TCP Fast Open选项
        tcp_fastopen="false"
        if [[ $protocol_choice == "1" || $protocol_choice == "3" ]]; then
            read -p "是否启用TCP Fast Open? (Y/N，默认N): " enable_tfo
            if [[ $enable_tfo == "Y" || $enable_tfo == "y" ]]; then
                tcp_fastopen="true"
            fi
        fi
        
        # 格式化监听地址（IPv6需要方括号）
        if [[ $listen_ip == *":"* ]]; then
            # IPv6地址
            listen_addr="[$listen_ip]:$listen_port"
        else
            # IPv4地址
            listen_addr="$listen_ip:$listen_port"
        fi
        
        # 根据协议选择添加规则
        case $protocol_choice in
            1)
                # 仅TCP
                echo "" >> /root/realm/config.toml
                echo "[[endpoints]]" >> /root/realm/config.toml
                echo "listen = \"$listen_addr\"" >> /root/realm/config.toml
                echo "remote = \"$remote_ip:$remote_port\"" >> /root/realm/config.toml
                if [ "$tcp_fastopen" = "true" ]; then
                    echo "tcp_fast_open = true" >> /root/realm/config.toml
                fi
                echo "转发规则已添加：$listen_addr -> $remote_ip:$remote_port (TCP)"
                ;;
            2)
                # 仅UDP
                echo "" >> /root/realm/config.toml
                echo "[[endpoints]]" >> /root/realm/config.toml
                echo "listen = \"$listen_addr\"" >> /root/realm/config.toml
                echo "remote = \"$remote_ip:$remote_port\"" >> /root/realm/config.toml
                echo "protocol = \"udp\"" >> /root/realm/config.toml
                echo "转发规则已添加：$listen_addr -> $remote_ip:$remote_port (UDP)"
                ;;
            3)
                # TCP+UDP
                # TCP规则
                echo "" >> /root/realm/config.toml
                echo "[[endpoints]]" >> /root/realm/config.toml
                echo "listen = \"$listen_addr\"" >> /root/realm/config.toml
                echo "remote = \"$remote_ip:$remote_port\"" >> /root/realm/config.toml
                if [ "$tcp_fastopen" = "true" ]; then
                    echo "tcp_fast_open = true" >> /root/realm/config.toml
                fi
                # UDP规则
                echo "" >> /root/realm/config.toml
                echo "[[endpoints]]" >> /root/realm/config.toml
                echo "listen = \"$listen_addr\"" >> /root/realm/config.toml
                echo "remote = \"$remote_ip:$remote_port\"" >> /root/realm/config.toml
                echo "protocol = \"udp\"" >> /root/realm/config.toml
                echo "转发规则已添加：$listen_addr -> $remote_ip:$remote_port (TCP+UDP)"
                ;;
            *)
                echo "无效选项，跳过添加。"
                ;;
        esac

        read -p "是否继续添加(Y/N)? " answer
        if [[ $answer != "Y" && $answer != "y" ]]; then
            break
        fi
    done
}

# 启动服务
start_service() {
    sudo systemctl unmask realm.service
    sudo systemctl daemon-reload
    sudo systemctl restart realm.service
    sudo systemctl enable realm.service
    echo "realm服务已启动并设置为开机自启。"
}

# 停止服务
stop_service() {
    systemctl stop realm
    echo "realm服务已停止。"
}

# 查看转发规则
view_forwards() {
    if [ ! -f "/root/realm/config.toml" ]; then
        echo "配置文件不存在。"
        return
    fi
    
    echo "================="
    echo "当前转发规则："
    echo "================="
    
    local endpoint_lines=($(grep -n '\[\[endpoints\]\]' /root/realm/config.toml 2>/dev/null))
    
    if [ ${#endpoint_lines[@]} -eq 0 ]; then
        echo "没有发现任何转发规则。"
        return
    fi
    
    local index=1
    for endpoint_line in "${endpoint_lines[@]}"; do
        local line_num=$(echo $endpoint_line | cut -d ':' -f 1)
        local end_line=$((line_num + 10))
        
        local listen=$(sed -n "${line_num},${end_line}p" /root/realm/config.toml | grep "listen =" | head -1 | cut -d '"' -f 2)
        local remote=$(sed -n "${line_num},${end_line}p" /root/realm/config.toml | grep "remote =" | head -1 | cut -d '"' -f 2)
        local protocol=$(sed -n "${line_num},${end_line}p" /root/realm/config.toml | grep "protocol =" | head -1 | cut -d '"' -f 2)
        local tfo=$(sed -n "${line_num},${end_line}p" /root/realm/config.toml | grep "tcp_fast_open" | head -1)
        
        if [ -z "$protocol" ]; then
            protocol="tcp"
        fi
        
        local tfo_status=""
        if [ -n "$tfo" ]; then
            tfo_status=" [TCP Fast Open: 已启用]"
        fi
        
        echo ""
        echo "规则 ${index}:"
        echo "  监听: $listen"
        echo "  转发: $remote"
        echo "  协议: $protocol$tfo_status"
        let index+=1
    done
    echo ""
}

# 批量添加三网IPv6转发
batch_add_ipv6() {
    echo "================="
    echo "批量添加三网IPv6转发规则"
    echo "================="
    echo "说明：此功能适用于A机器有多个IPv6地址，需要统一转发到香港机器的场景"
    echo ""
    
    # 输入三个IPv6地址
    read -p "请输入电信IPv6地址: " ipv6_telecom
    read -p "请输入联通IPv6地址: " ipv6_unicom
    read -p "请输入移动IPv6地址: " ipv6_mobile
    
    if [ -z "$ipv6_telecom" ] || [ -z "$ipv6_unicom" ] || [ -z "$ipv6_mobile" ]; then
        echo "错误：IPv6地址不能为空。"
        return
    fi
    
    # 输入监听端口
    read -p "请输入监听端口: " listen_port
    if [ -z "$listen_port" ]; then
        echo "错误：监听端口不能为空。"
        return
    fi
    
    # 输入香港机器的SD-WAN地址
    read -p "请输入香港机器SD-WAN地址（如192.168.90.179）: " hk_ip
    if [ -z "$hk_ip" ]; then
        echo "错误：香港机器地址不能为空。"
        return
    fi
    
    # 输入目标端口
    read -p "请输入目标端口: " remote_port
    if [ -z "$remote_port" ]; then
        echo "错误：目标端口不能为空。"
        return
    fi
    
    # 协议选择
    echo "请选择转发协议："
    echo "1. TCP"
    echo "2. UDP"
    echo "3. TCP+UDP"
    read -p "选择 (1/2/3，默认3): " protocol_choice
    if [ -z "$protocol_choice" ]; then
        protocol_choice="3"
    fi
    
    # TCP Fast Open
    tcp_fastopen="false"
    if [[ $protocol_choice == "1" || $protocol_choice == "3" ]]; then
        read -p "是否启用TCP Fast Open? (Y/N，默认Y): " enable_tfo
        if [ -z "$enable_tfo" ] || [[ $enable_tfo == "Y" || $enable_tfo == "y" ]]; then
            tcp_fastopen="true"
        fi
    fi
    
    # 添加规则
    echo ""
    echo "正在添加转发规则..."
    
    for isp in "电信:$ipv6_telecom" "联通:$ipv6_unicom" "移动:$ipv6_mobile"; do
        local isp_name=$(echo $isp | cut -d ':' -f 1)
        local ipv6_addr=$(echo $isp | cut -d ':' -f 2-)
        
        echo ""
        echo "添加 $isp_name 规则..."
        
        case $protocol_choice in
            1|3)
                # TCP规则
                echo "" >> /root/realm/config.toml
                echo "# $isp_name IPv6 - TCP" >> /root/realm/config.toml
                echo "[[endpoints]]" >> /root/realm/config.toml
                echo "listen = \"[$ipv6_addr]:$listen_port\"" >> /root/realm/config.toml
                echo "remote = \"$hk_ip:$remote_port\"" >> /root/realm/config.toml
                if [ "$tcp_fastopen" = "true" ]; then
                    echo "tcp_fast_open = true" >> /root/realm/config.toml
                fi
                echo "  ✓ [$ipv6_addr]:$listen_port -> $hk_ip:$remote_port (TCP)"
                ;;
        esac
        
        if [ "$protocol_choice" = "2" ] || [ "$protocol_choice" = "3" ]; then
            # UDP规则
            echo "" >> /root/realm/config.toml
            echo "# $isp_name IPv6 - UDP" >> /root/realm/config.toml
            echo "[[endpoints]]" >> /root/realm/config.toml
            echo "listen = \"[$ipv6_addr]:$listen_port\"" >> /root/realm/config.toml
            echo "remote = \"$hk_ip:$remote_port\"" >> /root/realm/config.toml
            echo "protocol = \"udp\"" >> /root/realm/config.toml
            echo "  ✓ [$ipv6_addr]:$listen_port -> $hk_ip:$remote_port (UDP)"
        fi
    done
    
    echo ""
    echo "所有规则添加完成！"
    echo "提示：请记得重启realm服务使配置生效。"
}

# 诊断realm问题
diagnose_realm() {
    echo "================="
    echo "Realm 诊断工具"
    echo "================="
    echo ""
    
    # 检查realm文件是否存在
    if [ ! -f "/root/realm/realm" ]; then
        echo "❌ realm程序不存在于 /root/realm/realm"
        echo "   请先使用选项1部署realm环境。"
        return
    fi
    
    echo "✓ realm程序文件存在"
    
    # 检查文件权限
    if [ -x "/root/realm/realm" ]; then
        echo "✓ realm程序具有可执行权限"
    else
        echo "❌ realm程序没有可执行权限"
        echo "   正在添加执行权限..."
        chmod +x /root/realm/realm
        echo "✓ 已添加执行权限"
    fi
    
    # 检查文件类型
    echo ""
    echo "文件信息："
    file /root/realm/realm
    
    # 检查依赖库
    echo ""
    echo "检查动态链接库依赖："
    if ldd /root/realm/realm 2>&1 | grep -q "not a dynamic executable"; then
        echo "✓ 静态链接可执行文件（无外部依赖）"
    else
        echo "动态链接库依赖："
        ldd /root/realm/realm 2>&1
        
        # 检查是否有缺失的库
        if ldd /root/realm/realm 2>&1 | grep -q "not found"; then
            echo ""
            echo "❌ 发现缺失的动态链接库！"
            echo "   建议：重新使用选项1部署环境，选择'静态链接编译'方式"
        fi
    fi
    
    # 检查glibc版本
    echo ""
    echo "系统glibc版本："
    ldd --version | head -1
    
    # 尝试运行realm
    echo ""
    echo "尝试运行realm（显示版本）："
    if /root/realm/realm --version 2>&1; then
        echo "✓ realm可以正常运行"
    else
        echo "❌ realm运行失败"
        echo ""
        echo "错误详情："
        /root/realm/realm --version 2>&1 || true
    fi
    
    # 检查配置文件
    echo ""
    if [ -f "/root/realm/config.toml" ]; then
        echo "✓ 配置文件存在"
        echo "   配置内容预览："
        head -20 /root/realm/config.toml
    else
        echo "❌ 配置文件不存在"
    fi
    
    # 检查服务状态
    echo ""
    echo "Systemd服务状态："
    systemctl status realm --no-pager -l || true
    
    echo ""
    echo "最近的服务日志："
    journalctl -u realm -n 10 --no-pager || true
    
    echo ""
    echo "================="
    echo "诊断建议："
    echo "================="
    
    if ldd /root/realm/realm 2>&1 | grep -q "GLIBC.*not found"; then
        echo "⚠️  检测到glibc版本不兼容问题"
        echo "   解决方案："
        echo "   1. 重新部署realm（选项1），选择'静态链接编译'方式"
        echo "   2. 或者下载针对您系统版本的预编译realm二进制文件"
    elif ! /root/realm/realm --version &>/dev/null; then
        echo "⚠️  realm程序无法运行"
        echo "   建议重新部署realm环境"
    else
        echo "✓ realm程序检查通过，如果服务仍无法启动，请检查配置文件和网络设置"
    fi
}

# 主循环
while true; do
    show_menu
    read -p "请选择一个选项: " choice
    case $choice in
        1)
            deploy_realm
            ;;
        2)
            add_forward
            ;;
        3)
            delete_forward
            ;;
        4)
            view_forwards
            ;;
        5)
            batch_add_ipv6
            ;;
        6)
            start_service
            ;;
        7)
            stop_service
            ;;
        8)
            diagnose_realm
            ;;
        9)
            uninstall_realm
            ;;
        *)
            echo "无效选项: $choice"
            ;;
    esac
    read -p "按任意键继续..." key
done