#!/usr/bin/env bash
# ==============================================================================
#  X-UI PANEL - PART 2: Config Generation, Cloudflare, Subscription,
#                        Telegram Bot, Backup System, SSL, Self-Update
#  این فایل توسط xui-panel.sh به صورت خودکار بارگذاری می‌شود.
# ==============================================================================

# ==============================================================================
# SECTION 15: INBOUND MANAGEMENT
# ==============================================================================

inbound_management_menu() {
    while true; do
        draw_header "مدیریت اینباند‌ها" "Inbound Management"
        draw_section "عملیات اینباند"
        echo ""
        draw_menu_item "1" "📋" "لیست اینباند‌ها"             "مشاهده همه اینباند‌ها"
        draw_menu_item "2" "➕" "ایجاد اینباند جدید"          "VLESS/VMess/Trojan/SS/HY2"
        draw_menu_item "3" "✏️" "ویرایش اینباند"              "تغییر پورت، پروتکل"
        draw_menu_item "4" "🗑️" "حذف اینباند"                 "حذف کامل"
        draw_menu_item "5" "🔄" "فعال/غیرفعال اینباند"        ""
        draw_menu_item "6" "📊" "آمار ترافیک اینباند"         ""
        draw_menu_footer
        echo -ne "  ${B}${CYAN}انتخاب: ${R}"
        read -r choice
        case "$choice" in
            1) list_inbounds_table; press_enter ;;
            2) create_inbound_interactive ;;
            3) edit_inbound_interactive ;;
            4) delete_inbound_interactive ;;
            5) toggle_inbound_status ;;
            6) show_inbound_stats ;;
            0|"") return ;;
            *) log_warn "گزینه نامعتبر."; sleep 1 ;;
        esac
    done
}

create_inbound_interactive() {
    draw_header "ایجاد اینباند جدید" "Create New Inbound"

    # Protocol selection
    echo -e "\n  ${CYAN}پروتکل:${R}"
    echo -e "  ${WHITE}1${R}) VLESS   ${WHITE}2${R}) VMess   ${WHITE}3${R}) Trojan"
    echo -e "  ${WHITE}4${R}) ShadowSocks   ${WHITE}5${R}) Hysteria2"
    echo -ne "  انتخاب: "
    read -r proto_choice

    local protocol
    case "$proto_choice" in
        1) protocol="vless" ;;
        2) protocol="vmess" ;;
        3) protocol="trojan" ;;
        4) protocol="shadowsocks" ;;
        5) protocol="hysteria2" ;;
        *) log_error "پروتکل نامعتبر."; press_enter; return ;;
    esac

    local remark port
    prompt_input "نام اینباند (Remark)" "${protocol}_$(date +%s)" remark
    prompt_input "پورت" "$(shuf -i 10000-60000 -n 1)" port

    # Check port availability
    if ss -tlnp "sport = :${port}" 2>/dev/null | grep -q LISTEN; then
        log_error "پورت ${port} در حال استفاده است."
        press_enter; return
    fi

    # Transport selection
    local network snifff
    echo -e "\n  ${CYAN}Transport:${R}"
    echo -e "  ${WHITE}1${R}) TCP   ${WHITE}2${R}) WebSocket (WS)   ${WHITE}3${R}) gRPC"
    echo -e "  ${WHITE}4${R}) HTTP/2 (h2)   ${WHITE}5${R}) XHTTP   ${WHITE}6${R}) QUIC"
    echo -ne "  انتخاب: "
    read -r net_choice
    case "$net_choice" in
        1) network="tcp" ;;
        2) network="ws" ;;
        3) network="grpc" ;;
        4) network="h2" ;;
        5) network="xhttp" ;;
        6) network="quic" ;;
        *) network="tcp" ;;
    esac

    # TLS selection
    echo -e "\n  ${CYAN}Security:${R}"
    echo -e "  ${WHITE}1${R}) None   ${WHITE}2${R}) TLS   ${WHITE}3${R}) Reality   ${WHITE}4${R}) XTLS"
    echo -ne "  انتخاب: "
    read -r sec_choice
    local security
    case "$sec_choice" in
        1) security="none" ;;
        2) security="tls" ;;
        3) security="reality" ;;
        4) security="xtls" ;;
        *) security="none" ;;
    esac

    # Build settings JSON
    local settings_json stream_json sniffing_json
    settings_json=$(build_inbound_settings "$protocol")
    stream_json=$(build_stream_settings "$network" "$security" "$protocol")
    sniffing_json='{"enabled":true,"destOverride":["http","tls","quic"],"metadataOnly":false}'

    # Insert into DB
    local now_ms
    now_ms=$(( $(date +%s) * 1000 ))
    db_query "INSERT INTO inbounds
        (user_id, up, down, total, remark, enable, expiry_time, listen,
         port, protocol, settings, stream_settings, tag, sniffing)
        VALUES (1, 0, 0, 0, '${remark}', 1, 0, '',
                ${port}, '${protocol}',
                '$(echo "$settings_json" | sed "s/'/''/g")',
                '$(echo "$stream_json" | sed "s/'/''/g")',
                'inbound-${port}',
                '$(echo "$sniffing_json" | sed "s/'/''/g")');"

    restart_xui_service
    log_success "اینباند '${remark}' روی پورت ${port} ایجاد شد."
    press_enter
}

build_inbound_settings() {
    local protocol="$1"
    case "${protocol,,}" in
        vless)
            local uuid
            uuid=$(generate_uuid)
            jq -n --arg id "$uuid" \
                '{"clients": [{"id": $id, "flow": "", "email": "default",
                  "limitIp": 0, "totalGB": 0, "expiryTime": 0,
                  "enable": true, "tgId": "", "subId": "", "comment": "", "reset": 0}],
                  "decryption": "none", "fallbacks": []}'
            ;;
        vmess)
            local uuid
            uuid=$(generate_uuid)
            jq -n --arg id "$uuid" \
                '{"clients": [{"id": $id, "alterId": 0, "email": "default",
                  "limitIp": 0, "totalGB": 0, "expiryTime": 0,
                  "enable": true, "tgId": "", "subId": "", "comment": "", "reset": 0}]}'
            ;;
        trojan)
            local password
            password=$(generate_password 16)
            jq -n --arg pw "$password" \
                '{"clients": [{"password": $pw, "email": "default",
                  "limitIp": 0, "totalGB": 0, "expiryTime": 0,
                  "enable": true, "tgId": "", "subId": "", "comment": "", "reset": 0}],
                  "fallbacks": []}'
            ;;
        shadowsocks)
            local password
            password=$(generate_password 16)
            jq -n --arg pw "$password" \
                '{"method": "chacha20-ietf-poly1305", "password": $pw,
                  "clients": [{"password": $pw, "email": "default",
                  "limitIp": 0, "totalGB": 0, "expiryTime": 0,
                  "enable": true, "tgId": "", "subId": "", "comment": "", "reset": 0}],
                  "network": "tcp,udp"}'
            ;;
        hysteria2)
            local password
            password=$(generate_password 16)
            jq -n --arg pw "$password" \
                '{"clients": [{"password": $pw, "email": "default",
                  "limitIp": 0, "totalGB": 0, "expiryTime": 0,
                  "enable": true, "tgId": "", "subId": "", "comment": "", "reset": 0}],
                  "masquerade": "", "salamander": {"password": ""}}'
            ;;
    esac
}

build_stream_settings() {
    local network="$1"
    local security="$2"
    local protocol="${3:-vless}"

    local network_settings tls_settings

    # Network-specific settings
    case "$network" in
        ws)
            local ws_path="/$(generate_short_id)"
            network_settings=$(jq -n --arg path "$ws_path" \
                '{"path": $path, "headers": {"Host": ""}}')
            ;;
        grpc)
            local service_name
            service_name=$(generate_short_id)
            network_settings=$(jq -n --arg sn "$service_name" \
                '{"serviceName": $sn, "authority": "", "multiMode": false}')
            ;;
        xhttp)
            local xhttp_path
            xhttp_path="/$(generate_short_id)"
            network_settings=$(jq -n --arg path "$xhttp_path" \
                '{"path": $path, "host": "", "method": "POST",
                  "headers": {}, "noGRPCHeader": false,
                  "keepAlivePeriod": 300}')
            ;;
        h2)
            network_settings=$(jq -n '{"path": "/", "host": []}')
            ;;
        quic)
            network_settings=$(jq -n \
                '{"security": "none", "key": "", "header": {"type": "none"}}')
            ;;
        tcp|*)
            network_settings=$(jq -n '{"header": {"type": "none"}}')
            ;;
    esac

    # Security settings
    case "$security" in
        tls)
            tls_settings=$(jq -n \
                '{"serverName": "", "minVersion": "1.2", "maxVersion": "1.3",
                  "cipherSuites": "", "rejectUnknownSni": false, "disableSystemRoot": false,
                  "enableSessionResumption": false, "certificates": [],
                  "alpn": ["h2","http/1.1"], "settings": null}')
            ;;
        reality)
            local private_key public_key short_id
            private_key=$(openssl genpkey -algorithm X25519 2>/dev/null | openssl pkey -text -noout 2>/dev/null | grep "priv:" -A3 | tail -3 | tr -d ' \n:' || echo "$(generate_short_id)$(generate_short_id)")
            public_key=$(echo "$private_key" | openssl pkey -pubout 2>/dev/null || echo "$(generate_short_id)$(generate_short_id)")
            short_id=$(generate_short_id)
            tls_settings=$(jq -n \
                --arg dest "www.microsoft.com:443" \
                --arg sid "$short_id" \
                '{"show": false, "xver": 0, "dest": $dest,
                  "serverNames": ["www.microsoft.com"],
                  "privateKey": "", "minClientVer": "", "maxClientVer": "",
                  "maxTimeDiff": 0, "shortIds": [$sid],
                  "fingerprint": "chrome", "publicKey": ""}')
            ;;
        xtls)
            tls_settings=$(jq -n \
                '{"serverName": "", "certificates": [], "alpn": ["h2","http/1.1"]}')
            ;;
        none|*)
            tls_settings="null"
            ;;
    esac

    # Compose stream settings
    local net_key="${network}Settings"
    [[ "$network" == "xhttp" ]] && net_key="xhttpSettings"
    [[ "$network" == "quic" ]] && net_key="quicSettings"
    [[ "$network" == "grpc" ]] && net_key="grpcSettings"
    [[ "$network" == "h2" ]]   && net_key="httpSettings"

    jq -n \
        --arg network "$network" \
        --arg security "$security" \
        --argjson netSettings "$network_settings" \
        --argjson tlsSettings "$tls_settings" \
        --arg netKey "$net_key" \
        '{
          "network": $network,
          "security": $security,
          ($netKey): $netSettings,
          "tlsSettings": (if $security == "tls" or $security == "xtls" then $tlsSettings else null end),
          "realitySettings": (if $security == "reality" then $tlsSettings else null end),
          "tcpSettings": null,
          "externalProxy": []
        }'
}

edit_inbound_interactive() {
    draw_header "ویرایش اینباند" "Edit Inbound"
    list_inbounds_table
    local inbound_id
    prompt_input "شماره اینباند" "" inbound_id
    [[ -z "$inbound_id" ]] && return

    local current
    current=$(db_query "SELECT remark, port, enable FROM inbounds WHERE id=${inbound_id} LIMIT 1;")
    if [[ -z "$current" ]]; then
        log_error "اینباند یافت نشد."
        press_enter; return
    fi
    local remark port enable
    IFS='|' read -r remark port enable <<< "$current"

    local new_remark new_port
    prompt_input "نام جدید" "$remark" new_remark
    prompt_input "پورت جدید" "$port" new_port

    [[ -z "$new_remark" ]] && new_remark="$remark"
    [[ -z "$new_port" ]]   && new_port="$port"

    db_query "UPDATE inbounds SET remark='${new_remark}', port=${new_port} WHERE id=${inbound_id};"
    restart_xui_service
    log_success "اینباند '${new_remark}' بروزرسانی شد."
    press_enter
}

delete_inbound_interactive() {
    draw_header "حذف اینباند" "Delete Inbound"
    list_inbounds_table
    local inbound_id
    prompt_input "شماره اینباند جهت حذف" "" inbound_id
    [[ -z "$inbound_id" ]] && return

    if confirm_action "اینباند #${inbound_id} و تمام کلاینت‌های آن حذف خواهند شد!"; then
        db_query "DELETE FROM inbounds WHERE id=${inbound_id};"
        db_query "DELETE FROM client_traffics WHERE inbound_id=${inbound_id};"
        restart_xui_service
        log_success "اینباند #${inbound_id} حذف شد."
    fi
    press_enter
}

toggle_inbound_status() {
    draw_header "تغییر وضعیت اینباند" "Toggle Inbound"
    list_inbounds_table
    local inbound_id
    prompt_input "شماره اینباند" "" inbound_id
    [[ -z "$inbound_id" ]] && return

    local current_enable
    current_enable=$(db_query "SELECT enable FROM inbounds WHERE id=${inbound_id} LIMIT 1;")
    local new_enable
    [[ "$current_enable" == "1" ]] && new_enable=0 || new_enable=1

    db_query "UPDATE inbounds SET enable=${new_enable} WHERE id=${inbound_id};"
    restart_xui_service
    local status_str
    [[ "$new_enable" == "1" ]] && status_str="فعال" || status_str="غیرفعال"
    log_success "اینباند #${inbound_id} ${status_str} شد."
    press_enter
}

show_inbound_stats() {
    draw_header "آمار اینباند‌ها" "Inbound Statistics"
    echo ""
    printf "  ${CYAN}%-4s %-20s %-12s %-15s %-15s %-10s${R}\n" \
        "ID" "نام" "پروتکل" "آپلود" "دانلود" "کاربران"
    draw_line "─" "$DIM"
    local data
    data=$(db_query "SELECT i.id, i.remark, i.protocol, i.up, i.down,
        (SELECT count(*) FROM client_traffics ct WHERE ct.inbound_id=i.id)
        FROM inbounds i ORDER BY i.id;")
    while IFS='|' read -r id remark protocol up down clients; do
        printf "  ${WHITE}%-4s${R} ${CYAN}%-20s${R} ${MAGENTA}%-12s${R} ${GREEN}%-15s${R} ${RED}%-15s${R} ${YELLOW}%-10s${R}\n" \
            "$id" "$remark" "$protocol" "$(bytes_to_human "$up")" "$(bytes_to_human "$down")" "$clients"
    done <<< "$data"
    press_enter
}

# ==============================================================================
# SECTION 16: CONFIG GENERATION (Multi-Protocol)
# ==============================================================================

config_generation_menu() {
    while true; do
        draw_header "تولید کانفیگ" "Config Generation"
        draw_section "نوع کانفیگ"
        echo ""
        draw_menu_item "1" "🔵" "VLESS کانفیگ"                "Reality, TLS, WS, gRPC, XHTTP"
        draw_menu_item "2" "🟢" "VMess کانفیگ"                "WS-TLS, gRPC, XHTTP"
        draw_menu_item "3" "🔴" "Trojan کانفیگ"               "WS-TLS, gRPC, Reality"
        draw_menu_item "4" "🟡" "ShadowSocks کانفیگ"          "WS, gRPC"
        draw_menu_item "5" "🚀" "Hysteria2 کانفیگ"            "UDP, Multi-hop"
        draw_menu_item "6" "⚡" "XHTTP کانفیگ"               "جدیدترین پروتکل Xray"
        draw_menu_item "7" "📦" "کانفیگ دسته‌جمعی"            "همه پروتکل‌ها برای یک کاربر"
        draw_menu_item "8" "📲" "QR Code کانفیگ"              "نمایش QR برای اسکن"
        draw_menu_footer
        echo -ne "  ${B}${CYAN}انتخاب: ${R}"
        read -r choice
        case "$choice" in
            1) generate_vless_config ;;
            2) generate_vmess_config ;;
            3) generate_trojan_config ;;
            4) generate_shadowsocks_config ;;
            5) generate_hysteria2_config ;;
            6) generate_xhttp_config ;;
            7) generate_all_configs_for_user ;;
            8) show_qr_menu ;;
            0|"") return ;;
            *) log_warn "گزینه نامعتبر."; sleep 1 ;;
        esac
    done
}

# Helper: pick a random SNI
pick_sni() {
    local sni_list=()
    if [[ -n "${PANEL_CUSTOM_SNIS:-}" ]]; then
        IFS=',' read -ra sni_list <<< "$PANEL_CUSTOM_SNIS"
    else
        sni_list=("${DEFAULT_SNIS[@]}")
    fi
    echo "${sni_list[$((RANDOM % ${#sni_list[@]}))]}"
}

# Helper: pick a clean Cloudflare IP
pick_clean_ip() {
    local ip_list=()
    if [[ -n "${PANEL_CF_CLEAN_IPS:-}" ]]; then
        IFS=',' read -ra ip_list <<< "$PANEL_CF_CLEAN_IPS"
    else
        ip_list=("${CF_CLEAN_IPS[@]}")
    fi
    echo "${ip_list[$((RANDOM % ${#ip_list[@]}))]}"
}

# Helper: prompt for connection type (Direct/CDN)
prompt_connection_type() {
    echo -e "\n  ${CYAN}نوع اتصال:${R}"
    echo -e "  ${WHITE}1${R}) مستقیم (Direct IP) - مناسب Reality / Hysteria"
    echo -e "  ${WHITE}2${R}) Cloudflare CDN - نیاز به دامنه"
    echo -e "  ${WHITE}3${R}) IP تمیز Cloudflare (بدون دامنه)"
    echo -ne "  انتخاب: "
    read -r conn_type
    echo "$conn_type"
}

generate_config_link_for_email() {
    local inbound_id="$1"
    local email="$2"

    local inbound_data settings stream_settings
    inbound_data=$(db_query "SELECT protocol, port FROM inbounds WHERE id=${inbound_id} LIMIT 1;")
    settings=$(get_inbound_settings "$inbound_id")
    stream_settings=$(get_inbound_stream_settings "$inbound_id")

    local protocol port
    IFS='|' read -r protocol port <<< "$inbound_data"

    local server_ip="${PANEL_PUBLIC_IP:-$(get_public_ip)}"

    # Extract client credentials from settings JSON
    local uuid password
    uuid=$(echo "$settings" | jq -r --arg em "$email" '.clients[] | select(.email==$em) | .id // empty' 2>/dev/null)
    password=$(echo "$settings" | jq -r --arg em "$email" '.clients[] | select(.email==$em) | .password // empty' 2>/dev/null)

    local network security
    network=$(echo "$stream_settings" | jq -r '.network // "tcp"' 2>/dev/null)
    security=$(echo "$stream_settings" | jq -r '.security // "none"' 2>/dev/null)

    local config_link=""

    case "${protocol,,}" in
        vless)
            config_link=$(build_vless_link "$uuid" "$server_ip" "$port" "$network" "$security" "$email" "$stream_settings")
            ;;
        vmess)
            config_link=$(build_vmess_link "$uuid" "$server_ip" "$port" "$network" "$security" "$email" "$stream_settings")
            ;;
        trojan)
            config_link=$(build_trojan_link "$password" "$server_ip" "$port" "$network" "$security" "$email" "$stream_settings")
            ;;
        shadowsocks)
            local method
            method=$(echo "$settings" | jq -r '.method // "chacha20-ietf-poly1305"' 2>/dev/null)
            config_link=$(build_ss_link "$method" "$password" "$server_ip" "$port" "$email")
            ;;
        hysteria2)
            config_link=$(build_hysteria2_link "$password" "$server_ip" "$port" "$email")
            ;;
    esac

    if [[ -n "$config_link" ]]; then
        echo ""
        echo -e "  ${GREEN}${B}لینک کانفیگ:${R}"
        echo ""
        echo -e "  ${CYAN}${config_link}${R}"
        echo ""
        # Show QR if qrencode is available
        if command -v qrencode &>/dev/null; then
            echo "$config_link" | qrencode -t UTF8 -s 2
        fi
    else
        log_error "نتوانستم لینک تولید کنم."
    fi
}

build_vless_link() {
    local uuid="$1" host="$2" port="$3" network="$4" security="$5"
    local remark="$6" stream="$7"

    local path sni pbk sid fp
    path=$(echo "$stream" | jq -r '.wsSettings.path // .xhttpSettings.path // .grpcSettings.serviceName // "/"' 2>/dev/null)
    sni=$(echo "$stream" | jq -r '.tlsSettings.serverName // .realitySettings.serverNames[0] // ""' 2>/dev/null)
    pbk=$(echo "$stream" | jq -r '.realitySettings.publicKey // ""' 2>/dev/null)
    sid=$(echo "$stream" | jq -r '.realitySettings.shortIds[0] // ""' 2>/dev/null)
    fp=$(echo "$stream" | jq -r '.realitySettings.fingerprint // "chrome"' 2>/dev/null)

    local flow=""
    [[ "$security" == "reality" || "$security" == "xtls" ]] && flow="xtls-rprx-vision"

    local params="type=${network}&security=${security}"
    [[ -n "$path" && "$path" != "/" ]] && params+="&path=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$path'))" 2>/dev/null || echo "$path")"
    [[ -n "$sni" ]] && params+="&sni=${sni}&host=${sni}"
    [[ -n "$pbk" ]] && params+="&pbk=${pbk}"
    [[ -n "$sid" ]] && params+="&sid=${sid}"
    [[ -n "$fp"  ]] && params+="&fp=${fp}"
    [[ -n "$flow" ]] && params+="&flow=${flow}"
    [[ "$security" == "tls" ]] && params+="&alpn=h2%2Chttp%2F1.1"

    local encoded_remark
    encoded_remark=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$remark'))" 2>/dev/null || echo "$remark")
    echo "vless://${uuid}@${host}:${port}?${params}#${encoded_remark}"
}

build_vmess_link() {
    local uuid="$1" host="$2" port="$3" network="$4" security="$5"
    local remark="$6" stream="$7"

    local path sni
    path=$(echo "$stream" | jq -r '.wsSettings.path // "/"' 2>/dev/null)
    sni=$(echo "$stream" | jq -r '.tlsSettings.serverName // ""' 2>/dev/null)

    local tls_val
    [[ "$security" == "tls" ]] && tls_val="tls" || tls_val=""

    local vmess_obj
    vmess_obj=$(jq -n \
        --arg v "2" --arg ps "$remark" --arg add "$host" \
        --arg port "$port" --arg id "$uuid" --arg aid "0" \
        --arg scy "auto" --arg net "$network" --arg type "none" \
        --arg host "$sni" --arg path "$path" \
        --arg tls "$tls_val" --arg sni "$sni" --arg alpn "" \
        '{"v":$v,"ps":$ps,"add":$add,"port":($port|tonumber),
          "id":$id,"aid":($aid|tonumber),"scy":$scy,
          "net":$net,"type":$type,"host":$host,"path":$path,
          "tls":$tls,"sni":$sni,"alpn":$alpn,"fp":""}')

    local encoded
    encoded=$(echo -n "$vmess_obj" | base64 -w 0)
    echo "vmess://${encoded}"
}

build_trojan_link() {
    local password="$1" host="$2" port="$3" network="$4" security="$5"
    local remark="$6" stream="$7"

    local sni path
    sni=$(echo "$stream" | jq -r '.tlsSettings.serverName // .realitySettings.serverNames[0] // ""' 2>/dev/null)
    path=$(echo "$stream" | jq -r '.wsSettings.path // .grpcSettings.serviceName // "/"' 2>/dev/null)

    local params="security=${security}&type=${network}"
    [[ -n "$sni" ]] && params+="&sni=${sni}&peer=${sni}"
    [[ -n "$path" && "$path" != "/" ]] && params+="&path=${path}"
    [[ "$security" == "tls" ]] && params+="&alpn=h2%2Chttp%2F1.1"

    local encoded_remark
    encoded_remark=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$remark'))" 2>/dev/null || echo "$remark")
    echo "trojan://${password}@${host}:${port}?${params}#${encoded_remark}"
}

build_ss_link() {
    local method="$1" password="$2" host="$3" port="$4" remark="$5"
    local userinfo
    userinfo=$(echo -n "${method}:${password}" | base64 -w 0)
    echo "ss://${userinfo}@${host}:${port}#${remark}"
}

build_hysteria2_link() {
    local password="$1" host="$2" port="$3" remark="$4"
    echo "hysteria2://${password}@${host}:${port}?insecure=1&sni=${host}#${remark}"
}

generate_vless_config() {
    draw_header "تولید کانفیگ VLESS" "VLESS Config Generator"
    list_inbounds_table

    local inbound_id
    prompt_input "شماره اینباند VLESS" "" inbound_id
    [[ -z "$inbound_id" ]] && return

    local protocol
    protocol=$(db_query "SELECT protocol FROM inbounds WHERE id=${inbound_id} LIMIT 1;")
    if [[ "${protocol,,}" != "vless" ]]; then
        log_error "اینباند انتخابی VLESS نیست (${protocol})."
        press_enter; return
    fi

    list_clients_table "$inbound_id"
    local email
    prompt_input "ایمیل کاربر" "" email
    [[ -z "$email" ]] && return

    local conn_type
    conn_type=$(prompt_connection_type)

    local server_ip="${PANEL_PUBLIC_IP:-$(get_public_ip)}"
    local target_host="$server_ip"

    case "$conn_type" in
        2)
            if [[ -z "${PANEL_CF_DOMAIN:-}" ]]; then
                log_error "دامنه Cloudflare تنظیم نشده. ابتدا در تنظیمات پنل آن را وارد کنید."
                press_enter; return
            fi
            target_host="$PANEL_CF_DOMAIN"
            ;;
        3) target_host=$(pick_clean_ip) ;;
    esac

    local settings stream_settings
    settings=$(get_inbound_settings "$inbound_id")
    stream_settings=$(get_inbound_stream_settings "$inbound_id")

    local uuid port network security
    uuid=$(echo "$settings" | jq -r --arg em "$email" '.clients[] | select(.email==$em) | .id // empty' 2>/dev/null)
    port=$(db_query "SELECT port FROM inbounds WHERE id=${inbound_id} LIMIT 1;")
    network=$(echo "$stream_settings" | jq -r '.network // "tcp"' 2>/dev/null)
    security=$(echo "$stream_settings" | jq -r '.security // "none"' 2>/dev/null)

    if [[ -z "$uuid" ]]; then
        log_error "کاربر '${email}' در این اینباند یافت نشد."
        press_enter; return
    fi

    # Override SNI for CDN configs
    if [[ "$conn_type" == "2" ]]; then
        stream_settings=$(echo "$stream_settings" | jq \
            --arg domain "$PANEL_CF_DOMAIN" \
            '(.tlsSettings.serverName) = $domain |
             (.wsSettings.headers.Host) = $domain |
             (.xhttpSettings.host) = $domain' 2>/dev/null || echo "$stream_settings")
    fi

    local config_link
    config_link=$(build_vless_link "$uuid" "$target_host" "$port" "$network" "$security" "$email" "$stream_settings")

    echo ""
    echo -e "  ${GREEN}${B}VLESS کانفیگ:${R}"
    echo -e "  ${DIM}Host: ${WHITE}${target_host}${R}  |  ${DIM}Network: ${WHITE}${network}${R}  |  ${DIM}Security: ${WHITE}${security}${R}"
    echo ""
    echo -e "  ${CYAN}${config_link}${R}"
    echo ""
    command -v qrencode &>/dev/null && echo "$config_link" | qrencode -t UTF8 -s 2

    press_enter
}

generate_vmess_config() {
    draw_header "تولید کانفیگ VMess" "VMess Config Generator"
    list_inbounds_table
    local inbound_id
    prompt_input "شماره اینباند VMess" "" inbound_id
    [[ -z "$inbound_id" ]] && return

    local protocol
    protocol=$(db_query "SELECT protocol FROM inbounds WHERE id=${inbound_id} LIMIT 1;")
    if [[ "${protocol,,}" != "vmess" ]]; then
        log_error "اینباند انتخابی VMess نیست."
        press_enter; return
    fi

    list_clients_table "$inbound_id"
    local email
    prompt_input "ایمیل کاربر" "" email
    [[ -z "$email" ]] && return

    local conn_type
    conn_type=$(prompt_connection_type)
    local server_ip="${PANEL_PUBLIC_IP:-$(get_public_ip)}"
    local target_host="$server_ip"
    [[ "$conn_type" == "2" ]] && target_host="${PANEL_CF_DOMAIN:-$server_ip}"
    [[ "$conn_type" == "3" ]] && target_host=$(pick_clean_ip)

    local settings stream_settings uuid port network security
    settings=$(get_inbound_settings "$inbound_id")
    stream_settings=$(get_inbound_stream_settings "$inbound_id")
    uuid=$(echo "$settings" | jq -r --arg em "$email" '.clients[] | select(.email==$em) | .id // empty' 2>/dev/null)
    port=$(db_query "SELECT port FROM inbounds WHERE id=${inbound_id} LIMIT 1;")
    network=$(echo "$stream_settings" | jq -r '.network // "tcp"' 2>/dev/null)
    security=$(echo "$stream_settings" | jq -r '.security // "none"' 2>/dev/null)

    if [[ -z "$uuid" ]]; then
        log_error "کاربر '${email}' یافت نشد."
        press_enter; return
    fi

    local config_link
    config_link=$(build_vmess_link "$uuid" "$target_host" "$port" "$network" "$security" "$email" "$stream_settings")

    echo ""
    echo -e "  ${GREEN}${B}VMess کانفیگ:${R}"
    echo -e "  ${CYAN}${config_link}${R}"
    echo ""
    command -v qrencode &>/dev/null && echo "$config_link" | qrencode -t UTF8 -s 2
    press_enter
}

generate_trojan_config() {
    draw_header "تولید کانفیگ Trojan" "Trojan Config Generator"
    list_inbounds_table
    local inbound_id
    prompt_input "شماره اینباند Trojan" "" inbound_id
    [[ -z "$inbound_id" ]] && return

    local protocol
    protocol=$(db_query "SELECT protocol FROM inbounds WHERE id=${inbound_id} LIMIT 1;")
    if [[ "${protocol,,}" != "trojan" ]]; then
        log_error "اینباند انتخابی Trojan نیست."
        press_enter; return
    fi

    list_clients_table "$inbound_id"
    local email
    prompt_input "ایمیل کاربر" "" email
    [[ -z "$email" ]] && return

    local conn_type
    conn_type=$(prompt_connection_type)
    local server_ip="${PANEL_PUBLIC_IP:-$(get_public_ip)}"
    local target_host="$server_ip"
    [[ "$conn_type" == "2" ]] && target_host="${PANEL_CF_DOMAIN:-$server_ip}"
    [[ "$conn_type" == "3" ]] && target_host=$(pick_clean_ip)

    local settings stream_settings password port network security
    settings=$(get_inbound_settings "$inbound_id")
    stream_settings=$(get_inbound_stream_settings "$inbound_id")
    password=$(echo "$settings" | jq -r --arg em "$email" '.clients[] | select(.email==$em) | .password // empty' 2>/dev/null)
    port=$(db_query "SELECT port FROM inbounds WHERE id=${inbound_id} LIMIT 1;")
    network=$(echo "$stream_settings" | jq -r '.network // "tcp"' 2>/dev/null)
    security=$(echo "$stream_settings" | jq -r '.security // "tls"' 2>/dev/null)

    if [[ -z "$password" ]]; then
        log_error "کاربر '${email}' یافت نشد."
        press_enter; return
    fi

    local config_link
    config_link=$(build_trojan_link "$password" "$target_host" "$port" "$network" "$security" "$email" "$stream_settings")

    echo ""
    echo -e "  ${GREEN}${B}Trojan کانفیگ:${R}"
    echo -e "  ${CYAN}${config_link}${R}"
    echo ""
    command -v qrencode &>/dev/null && echo "$config_link" | qrencode -t UTF8 -s 2
    press_enter
}

generate_shadowsocks_config() {
    draw_header "تولید کانفیگ ShadowSocks" "ShadowSocks Config Generator"
    list_inbounds_table
    local inbound_id
    prompt_input "شماره اینباند ShadowSocks" "" inbound_id
    [[ -z "$inbound_id" ]] && return

    local settings method password port
    settings=$(get_inbound_settings "$inbound_id")
    password=$(echo "$settings" | jq -r '.password // empty' 2>/dev/null)
    method=$(echo "$settings" | jq -r '.method // "chacha20-ietf-poly1305"' 2>/dev/null)
    port=$(db_query "SELECT port FROM inbounds WHERE id=${inbound_id} LIMIT 1;")

    local server_ip="${PANEL_PUBLIC_IP:-$(get_public_ip)}"
    local config_link
    config_link=$(build_ss_link "$method" "$password" "$server_ip" "$port" "SS-${inbound_id}")

    echo ""
    echo -e "  ${GREEN}${B}ShadowSocks کانفیگ:${R}"
    echo -e "  ${CYAN}${config_link}${R}"
    echo ""
    command -v qrencode &>/dev/null && echo "$config_link" | qrencode -t UTF8 -s 2
    press_enter
}

generate_hysteria2_config() {
    draw_header "تولید کانفیگ Hysteria2" "Hysteria2 Config Generator"
    list_inbounds_table
    local inbound_id
    prompt_input "شماره اینباند Hysteria2" "" inbound_id
    [[ -z "$inbound_id" ]] && return

    list_clients_table "$inbound_id"
    local email
    prompt_input "ایمیل کاربر" "" email
    [[ -z "$email" ]] && return

    local settings password port
    settings=$(get_inbound_settings "$inbound_id")
    password=$(echo "$settings" | jq -r --arg em "$email" '.clients[] | select(.email==$em) | .password // empty' 2>/dev/null)
    port=$(db_query "SELECT port FROM inbounds WHERE id=${inbound_id} LIMIT 1;")

    local server_ip="${PANEL_PUBLIC_IP:-$(get_public_ip)}"

    if [[ -z "$password" ]]; then
        log_error "کاربر '${email}' یافت نشد."
        press_enter; return
    fi

    local config_link
    config_link=$(build_hysteria2_link "$password" "$server_ip" "$port" "$email")

    # Also generate YAML client config
    local yaml_config
    yaml_config=$(cat <<EOF
server: ${server_ip}:${port}
auth: ${password}
bandwidth:
  up: 20 mbps
  down: 100 mbps
tls:
  sni: ${server_ip}
  insecure: true
socks5:
  listen: 127.0.0.1:1080
http:
  listen: 127.0.0.1:8080
EOF
)
    echo ""
    echo -e "  ${GREEN}${B}Hysteria2 URI:${R}"
    echo -e "  ${CYAN}${config_link}${R}"
    echo ""
    echo -e "  ${GREEN}${B}Hysteria2 YAML Client Config:${R}"
    echo -e "${DIM}${yaml_config}${R}"
    echo ""
    command -v qrencode &>/dev/null && echo "$config_link" | qrencode -t UTF8 -s 2
    press_enter
}

generate_xhttp_config() {
    draw_header "تولید کانفیگ XHTTP" "XHTTP Config Generator (Latest Xray)"
    echo -e "  ${DIM}XHTTP: جدیدترین پروتکل Transport در Xray - جایگزین پیشرفته WS${R}\n"
    list_inbounds_table

    local inbound_id
    prompt_input "شماره اینباند با Transport=XHTTP" "" inbound_id
    [[ -z "$inbound_id" ]] && return

    local stream_settings
    stream_settings=$(get_inbound_stream_settings "$inbound_id")
    local net
    net=$(echo "$stream_settings" | jq -r '.network // "tcp"' 2>/dev/null)

    if [[ "$net" != "xhttp" ]]; then
        log_warn "این اینباند از XHTTP استفاده نمی‌کند (${net}). ادامه می‌دهید؟"
        echo -ne "  (بله/خیر): "
        read -r ans
        [[ ! "$ans" =~ ^(بله|yes|y)$ ]] && return
    fi

    list_clients_table "$inbound_id"
    local email
    prompt_input "ایمیل کاربر" "" email
    [[ -z "$email" ]] && return

    generate_config_link_for_email "$inbound_id" "$email"
    press_enter
}

generate_all_configs_for_user() {
    draw_header "کانفیگ دسته‌جمعی برای کاربر" "All Configs for One User"
    local email
    prompt_input "ایمیل کاربر" "" email
    [[ -z "$email" ]] && return

    local results
    results=$(db_query "SELECT inbound_id FROM client_traffics WHERE email='${email}';")
    if [[ -z "$results" ]]; then
        log_error "کاربر '${email}' یافت نشد."
        press_enter; return
    fi

    local all_configs=()
    while IFS= read -r iid; do
        local link
        local settings stream
        settings=$(get_inbound_settings "$iid")
        stream=$(get_inbound_stream_settings "$iid")
        local proto port
        IFS='|' read -r proto port <<< "$(db_query "SELECT protocol,port FROM inbounds WHERE id=${iid} LIMIT 1;")"
        local server_ip="${PANEL_PUBLIC_IP:-$(get_public_ip)}"
        local uuid pw net sec
        uuid=$(echo "$settings" | jq -r --arg em "$email" '.clients[] | select(.email==$em) | .id // empty' 2>/dev/null)
        pw=$(echo "$settings" | jq -r --arg em "$email" '.clients[] | select(.email==$em) | .password // empty' 2>/dev/null)
        net=$(echo "$stream" | jq -r '.network // "tcp"' 2>/dev/null)
        sec=$(echo "$stream" | jq -r '.security // "none"' 2>/dev/null)

        case "${proto,,}" in
            vless)      link=$(build_vless_link "$uuid" "$server_ip" "$port" "$net" "$sec" "${email}-vless" "$stream") ;;
            vmess)      link=$(build_vmess_link "$uuid" "$server_ip" "$port" "$net" "$sec" "${email}-vmess" "$stream") ;;
            trojan)     link=$(build_trojan_link "$pw" "$server_ip" "$port" "$net" "$sec" "${email}-trojan" "$stream") ;;
            shadowsocks) local meth; meth=$(echo "$settings" | jq -r '.method // "chacha20-ietf-poly1305"')
                        link=$(build_ss_link "$meth" "$pw" "$server_ip" "$port" "${email}-ss") ;;
            hysteria2)  link=$(build_hysteria2_link "$pw" "$server_ip" "$port" "${email}-hy2") ;;
        esac
        [[ -n "${link:-}" ]] && all_configs+=("$link")
    done <<< "$results"

    echo ""
    echo -e "  ${GREEN}${B}تمام کانفیگ‌های ${email}:${R}"
    echo ""
    local i=1
    for cfg in "${all_configs[@]}"; do
        echo -e "  ${CYAN}[${i}]${R} ${cfg}"
        ((i++))
    done
    echo ""

    # Generate base64 subscription
    local sub_content
    sub_content=$(printf '%s\n' "${all_configs[@]}")
    local sub_b64
    sub_b64=$(echo "$sub_content" | base64 -w 0)
    echo -e "  ${YELLOW}${B}ساب‌اسکریپشن Base64:${R}"
    echo -e "  ${DIM}${sub_b64:0:80}...${R}"
    press_enter
}

show_qr_menu() {
    draw_header "QR Code کانفیگ" "QR Code Display"
    list_inbounds_table
    local inbound_id
    prompt_input "شماره اینباند" "" inbound_id
    [[ -z "$inbound_id" ]] && return
    list_clients_table "$inbound_id"
    local email
    prompt_input "ایمیل کاربر" "" email
    [[ -z "$email" ]] && return
    generate_config_link_for_email "$inbound_id" "$email"
    press_enter
}

# ==============================================================================
# SECTION 17: CLOUDFLARE INTEGRATION
# ==============================================================================

cloudflare_menu() {
    while true; do
        draw_header "یکپارچه‌سازی Cloudflare" "Cloudflare Integration"
        echo -e "\n  ${DIM}دامنه CF: ${WHITE}${PANEL_CF_DOMAIN:-تنظیم نشده}${R}\n"
        draw_menu_item "1" "☁️"  "تنظیم دامنه CDN"             "ورود دامنه Cloudflare"
        draw_menu_item "2" "🌐"  "تولید کانفیگ CDN"            "کانفیگ با دامنه Cloudflare"
        draw_menu_item "3" "🔵"  "تولید کانفیگ IP تمیز"        "بدون دامنه، با Clean IP"
        draw_menu_item "4" "📋"  "مدیریت IP تمیز"              "افزودن، حذف آی‌پی"
        draw_menu_item "5" "🔍"  "تست IP تمیز"                 "بررسی دسترسی آی‌پی‌ها"
        draw_menu_item "6" "🔑"  "API Cloudflare"              "مدیریت DNS خودکار"
        draw_menu_footer
        echo -ne "  ${B}${CYAN}انتخاب: ${R}"
        read -r choice
        case "$choice" in
            1) configure_cloudflare_domain ;;
            2) generate_cdn_configs ;;
            3) generate_clean_ip_configs ;;
            4) configure_clean_ips ;;
            5) test_clean_ips ;;
            6) cloudflare_api_menu ;;
            0|"") return ;;
            *) log_warn "گزینه نامعتبر."; sleep 1 ;;
        esac
    done
}

generate_cdn_configs() {
    draw_header "تولید کانفیگ CDN" "CDN Config Generation"

    if [[ -z "${PANEL_CF_DOMAIN:-}" ]]; then
        log_error "دامنه Cloudflare تنظیم نشده است."
        echo -e "  ${DIM}ابتدا از منو تنظیمات > دامنه Cloudflare را وارد کنید.${R}"
        press_enter; return
    fi

    echo -e "  ${GREEN}دامنه CDN: ${B}${PANEL_CF_DOMAIN}${R}\n"
    list_inbounds_table

    local inbound_id
    prompt_input "شماره اینباند" "" inbound_id
    [[ -z "$inbound_id" ]] && return

    list_clients_table "$inbound_id"
    local email
    prompt_input "ایمیل کاربر" "" email
    [[ -z "$email" ]] && return

    local settings stream_settings protocol port
    settings=$(get_inbound_settings "$inbound_id")
    stream_settings=$(get_inbound_stream_settings "$inbound_id")
    protocol=$(db_query "SELECT protocol FROM inbounds WHERE id=${inbound_id} LIMIT 1;")
    port=$(db_query "SELECT port FROM inbounds WHERE id=${inbound_id} LIMIT 1;")

    # Override host/SNI with CF domain and use port 443 for CDN
    local cdn_port="443"
    local cdn_stream
    cdn_stream=$(echo "$stream_settings" | jq \
        --arg domain "$PANEL_CF_DOMAIN" \
        '(.tlsSettings.serverName) = $domain |
         (.wsSettings.headers.Host) = $domain |
         (.xhttpSettings.host) = $domain |
         (.grpcSettings.authority) = $domain |
         (.security) = "tls"' 2>/dev/null || echo "$stream_settings")

    local uuid pw net sec
    uuid=$(echo "$settings" | jq -r --arg em "$email" '.clients[] | select(.email==$em) | .id // empty' 2>/dev/null)
    pw=$(echo "$settings" | jq -r --arg em "$email" '.clients[] | select(.email==$em) | .password // empty' 2>/dev/null)
    net=$(echo "$cdn_stream" | jq -r '.network // "ws"' 2>/dev/null)
    sec="tls"

    local config_link
    case "${protocol,,}" in
        vless)  config_link=$(build_vless_link "$uuid" "$PANEL_CF_DOMAIN" "$cdn_port" "$net" "$sec" "${email}-cdn" "$cdn_stream") ;;
        vmess)  config_link=$(build_vmess_link "$uuid" "$PANEL_CF_DOMAIN" "$cdn_port" "$net" "$sec" "${email}-cdn" "$cdn_stream") ;;
        trojan) config_link=$(build_trojan_link "$pw" "$PANEL_CF_DOMAIN" "$cdn_port" "$net" "$sec" "${email}-cdn" "$cdn_stream") ;;
        *)      log_error "پروتکل ${protocol} برای CDN پشتیبانی نمی‌شود."; press_enter; return ;;
    esac

    echo ""
    echo -e "  ${GREEN}${B}CDN کانفیگ (پورت 443):${R}"
    echo -e "  ${CYAN}${config_link}${R}"
    echo ""
    command -v qrencode &>/dev/null && echo "$config_link" | qrencode -t UTF8 -s 2
    press_enter
}

generate_clean_ip_configs() {
    draw_header "تولید کانفیگ IP تمیز" "Clean IP Config"

    list_inbounds_table
    local inbound_id
    prompt_input "شماره اینباند" "" inbound_id
    [[ -z "$inbound_id" ]] && return

    list_clients_table "$inbound_id"
    local email
    prompt_input "ایمیل کاربر" "" email
    [[ -z "$email" ]] && return

    local settings stream_settings protocol port
    settings=$(get_inbound_settings "$inbound_id")
    stream_settings=$(get_inbound_stream_settings "$inbound_id")
    protocol=$(db_query "SELECT protocol FROM inbounds WHERE id=${inbound_id} LIMIT 1;")
    port=$(db_query "SELECT port FROM inbounds WHERE id=${inbound_id} LIMIT 1;")

    # Get clean IPs
    local ip_list=()
    if [[ -n "${PANEL_CF_CLEAN_IPS:-}" ]]; then
        IFS=',' read -ra ip_list <<< "$PANEL_CF_CLEAN_IPS"
    else
        ip_list=("${CF_CLEAN_IPS[@]}")
    fi

    local uuid pw net sec
    uuid=$(echo "$settings" | jq -r --arg em "$email" '.clients[] | select(.email==$em) | .id // empty' 2>/dev/null)
    pw=$(echo "$settings" | jq -r --arg em "$email" '.clients[] | select(.email==$em) | .password // empty' 2>/dev/null)
    net=$(echo "$stream_settings" | jq -r '.network // "ws"' 2>/dev/null)
    sec=$(echo "$stream_settings" | jq -r '.security // "tls"' 2>/dev/null)

    # Domain for SNI (must be set for CDN clean IPs)
    local sni_domain="${PANEL_CF_DOMAIN:-$(pick_sni)}"

    echo ""
    echo -e "  ${GREEN}${B}کانفیگ‌های IP تمیز:${R}"
    echo ""

    for clean_ip in "${ip_list[@]}"; do
        local modified_stream
        modified_stream=$(echo "$stream_settings" | jq \
            --arg domain "$sni_domain" \
            --arg cleanip "$clean_ip" \
            '(.tlsSettings.serverName) = $domain |
             (.wsSettings.headers.Host) = $domain |
             (.xhttpSettings.host) = $domain' 2>/dev/null || echo "$stream_settings")

        local cfg_link
        case "${protocol,,}" in
            vless)  cfg_link=$(build_vless_link "$uuid" "$clean_ip" "$port" "$net" "$sec" "${email}-${clean_ip}" "$modified_stream") ;;
            vmess)  cfg_link=$(build_vmess_link "$uuid" "$clean_ip" "$port" "$net" "$sec" "${email}-${clean_ip}" "$modified_stream") ;;
            trojan) cfg_link=$(build_trojan_link "$pw" "$clean_ip" "$port" "$net" "$sec" "${email}-${clean_ip}" "$modified_stream") ;;
            *) continue ;;
        esac
        echo -e "  ${CYAN}[${clean_ip}]${R}"
        echo -e "  ${DIM}${cfg_link}${R}"
        echo ""
    done
    press_enter
}

test_clean_ips() {
    draw_header "تست IP تمیز Cloudflare" "Clean IP Test"
    echo -e "  ${DIM}بررسی دسترسی‌پذیری آی‌پی‌های تمیز...${R}\n"

    local ip_list=()
    if [[ -n "${PANEL_CF_CLEAN_IPS:-}" ]]; then
        IFS=',' read -ra ip_list <<< "$PANEL_CF_CLEAN_IPS"
    else
        ip_list=("${CF_CLEAN_IPS[@]}")
    fi

    printf "  ${CYAN}%-20s %-10s %-10s${R}\n" "آی‌پی" "وضعیت" "زمان پاسخ"
    draw_line "─" "$DIM"

    for ip in "${ip_list[@]}"; do
        local start end latency status
        start=$(date +%s%3N)
        if curl -s --max-time 5 --connect-timeout 3 \
            -H "Host: ${PANEL_CF_DOMAIN:-www.cloudflare.com}" \
            "https://${ip}" -o /dev/null 2>/dev/null; then
            status="${GREEN}✓ قابل دسترس${R}"
        else
            status="${RED}✗ غیرقابل دسترس${R}"
        fi
        end=$(date +%s%3N)
        latency=$((end - start))
        printf "  ${WHITE}%-20s${R} %-10b ${DIM}%sms${R}\n" "$ip" "$status" "$latency"
    done
    press_enter
}

cloudflare_api_menu() {
    draw_header "API Cloudflare" "Cloudflare API Management"
    echo -e "  ${DIM}برای مدیریت DNS خودکار، API Token و Zone ID را وارد کنید.${R}\n"

    local cf_token cf_zone
    prompt_input "Cloudflare API Token" "${CF_API_TOKEN:-}" cf_token
    prompt_input "Zone ID" "${CF_ZONE_ID:-}" cf_zone

    if [[ -z "$cf_token" || -z "$cf_zone" ]]; then
        log_warn "API Token یا Zone ID خالی است."
        press_enter; return
    fi

    CF_API_TOKEN="$cf_token"
    CF_ZONE_ID="$cf_zone"

    echo ""
    echo -e "  ${YELLOW}عملیات DNS:${R}"
    echo -e "  ${WHITE}1${R}) لیست رکوردهای DNS"
    echo -e "  ${WHITE}2${R}) افزودن رکورد A"
    echo -e "  ${WHITE}3${R}) حذف رکورد"
    echo -ne "  انتخاب: "
    read -r dns_choice

    case "$dns_choice" in
        1)
            local result
            result=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=A" \
                -H "Authorization: Bearer ${CF_API_TOKEN}" \
                -H "Content-Type: application/json" 2>/dev/null)
            echo ""
            echo "$result" | jq -r '.result[] | "\(.name) → \(.content) [\(.type)]"' 2>/dev/null \
                || echo -e "  ${RED}خطا در دریافت رکوردها.${R}"
            ;;
        2)
            local dns_name dns_content
            prompt_input "نام رکورد (مثال: vpn.example.com)" "" dns_name
            prompt_input "آی‌پی مقصد" "$PANEL_PUBLIC_IP" dns_content
            curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
                -H "Authorization: Bearer ${CF_API_TOKEN}" \
                -H "Content-Type: application/json" \
                --data "{\"type\":\"A\",\"name\":\"${dns_name}\",\"content\":\"${dns_content}\",\"ttl\":1,\"proxied\":true}" \
                | jq -r 'if .success then "✓ رکورد اضافه شد" else "✗ خطا: \(.errors[0].message)" end' 2>/dev/null
            ;;
        3)
            local record_id
            prompt_input "Record ID" "" record_id
            curl -s -X DELETE "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${record_id}" \
                -H "Authorization: Bearer ${CF_API_TOKEN}" \
                | jq -r 'if .success then "✓ رکورد حذف شد" else "✗ خطا" end' 2>/dev/null
            ;;
    esac
    press_enter
}

# ==============================================================================
# SECTION 18: SUBSCRIPTION SYSTEM
# ==============================================================================

subscription_menu() {
    while true; do
        draw_header "سیستم ساب‌اسکریپشن" "Subscription System"
        draw_menu_item "1" "🔗" "نمایش لینک ساب کاربر"          "Base64 / JSON"
        draw_menu_item "2" "🖥️" "راه‌اندازی سرور ساب"            "HTTP Server"
        draw_menu_item "3" "📊" "وضعیت سرور ساب"                ""
        draw_menu_item "4" "🔄" "بروزرسانی فایل‌های ساب"         ""
        draw_menu_item "5" "⚙️" "تنظیمات ساب‌اسکریپشن"          "پورت، مسیر"
        draw_menu_footer
        echo -ne "  ${B}${CYAN}انتخاب: ${R}"
        read -r choice
        case "$choice" in
            1) show_user_subscription_link ;;
            2) setup_subscription_server ;;
            3) subscription_server_status ;;
            4) regenerate_all_subscriptions ;;
            5) configure_subscription_server ;;
            0|"") return ;;
            *) log_warn "گزینه نامعتبر."; sleep 1 ;;
        esac
    done
}

show_user_subscription_link() {
    draw_header "لینک ساب‌اسکریپشن کاربر" "User Subscription Link"
    local email
    prompt_input "ایمیل کاربر" "" email
    [[ -z "$email" ]] && return

    # Collect all configs for user
    local inbound_ids
    inbound_ids=$(db_query "SELECT inbound_id FROM client_traffics WHERE email='${email}';")

    if [[ -z "$inbound_ids" ]]; then
        log_error "کاربر '${email}' یافت نشد."
        press_enter; return
    fi

    local all_configs=()
    local server_ip="${PANEL_PUBLIC_IP:-$(get_public_ip)}"

    while IFS= read -r iid; do
        local settings stream proto port
        settings=$(get_inbound_settings "$iid")
        stream=$(get_inbound_stream_settings "$iid")
        proto=$(db_query "SELECT protocol FROM inbounds WHERE id=${iid} LIMIT 1;")
        port=$(db_query "SELECT port FROM inbounds WHERE id=${iid} LIMIT 1;")

        local uuid pw net sec
        uuid=$(echo "$settings" | jq -r --arg em "$email" '.clients[] | select(.email==$em) | .id // empty' 2>/dev/null)
        pw=$(echo "$settings" | jq -r --arg em "$email" '.clients[] | select(.email==$em) | .password // empty' 2>/dev/null)
        net=$(echo "$stream" | jq -r '.network // "tcp"' 2>/dev/null)
        sec=$(echo "$stream" | jq -r '.security // "none"' 2>/dev/null)

        local link=""
        case "${proto,,}" in
            vless)       link=$(build_vless_link "$uuid" "$server_ip" "$port" "$net" "$sec" "${email}-${proto}" "$stream") ;;
            vmess)       link=$(build_vmess_link "$uuid" "$server_ip" "$port" "$net" "$sec" "${email}-${proto}" "$stream") ;;
            trojan)      link=$(build_trojan_link "$pw" "$server_ip" "$port" "$net" "$sec" "${email}-${proto}" "$stream") ;;
            shadowsocks) local meth; meth=$(echo "$settings" | jq -r '.method // "chacha20-ietf-poly1305"')
                         link=$(build_ss_link "$meth" "$pw" "$server_ip" "$port" "${email}-ss") ;;
            hysteria2)   link=$(build_hysteria2_link "$pw" "$server_ip" "$port" "${email}-hy2") ;;
        esac
        [[ -n "${link:-}" ]] && all_configs+=("$link")
    done <<< "$inbound_ids"

    # Generate subscription content (Base64)
    local sub_content
    sub_content=$(printf '%s\n' "${all_configs[@]}")
    local sub_b64
    sub_b64=$(echo "$sub_content" | base64 -w 0)

    # Save subscription file
    ensure_dir "$SUBSCRIPTION_DIR"
    local email_safe
    email_safe=$(echo "$email" | tr -cd '[:alnum:]._-')
    echo "$sub_b64" > "${SUBSCRIPTION_DIR}/${email_safe}.txt"
    echo "$sub_content" > "${SUBSCRIPTION_DIR}/${email_safe}.json"

    local sub_url="http://${server_ip}:${PANEL_SUB_PORT:-8080}/sub/${email_safe}"

    echo ""
    echo -e "  ${GREEN}${B}اطلاعات ساب‌اسکریپشن:${R}"
    echo -e "  ${CYAN}├─ لینک ساب: ${WHITE}${sub_url}${R}"
    echo -e "  ${CYAN}├─ تعداد کانفیگ: ${WHITE}${#all_configs[@]}${R}"
    echo ""
    echo -e "  ${YELLOW}محتوای Base64 (۱۰۰ کاراکتر اول):${R}"
    echo -e "  ${DIM}${sub_b64:0:100}...${R}"
    echo ""
    command -v qrencode &>/dev/null && echo "$sub_url" | qrencode -t UTF8 -s 2
    press_enter
}

setup_subscription_server() {
    draw_header "راه‌اندازی سرور ساب‌اسکریپشن" "Subscription Server Setup"

    local sub_port="${PANEL_SUB_PORT:-8080}"
    ensure_dir "$SUBSCRIPTION_DIR"

    # Check if already running
    if ss -tlnp "sport = :${sub_port}" 2>/dev/null | grep -q LISTEN; then
        log_warn "پورت ${sub_port} در حال استفاده است. سرور قبلاً در حال اجراست؟"
    fi

    # Create a simple Python HTTP server script
    local server_script="/usr/local/bin/xui-sub-server.py"
    cat > "$server_script" <<'PYEOF'
#!/usr/bin/env python3
"""X-UI Subscription Server"""
import http.server, socketserver, os, sys, urllib.parse

SUB_DIR = sys.argv[1] if len(sys.argv) > 1 else "/var/www/xui-subs"
PORT    = int(sys.argv[2]) if len(sys.argv) > 2 else 8080

class SubHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path.startswith("/sub/"):
            email = parsed.path[5:].rstrip("/")
            filepath = os.path.join(SUB_DIR, f"{email}.txt")
            if os.path.isfile(filepath):
                with open(filepath, "rb") as f:
                    data = f.read()
                self.send_response(200)
                self.send_header("Content-Type", "text/plain; charset=utf-8")
                self.send_header("Content-Disposition", f"attachment; filename={email}.txt")
                self.send_header("Profile-Update-Interval", "12")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            else:
                self.send_error(404, "Subscription not found")
        elif parsed.path == "/health":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")
        else:
            self.send_error(403, "Forbidden")

    def log_message(self, fmt, *args):
        pass  # Suppress logs

with socketserver.TCPServer(("", PORT), SubHandler) as httpd:
    print(f"Subscription server running on port {PORT}")
    httpd.serve_forever()
PYEOF
    chmod +x "$server_script"

    # Create systemd service
    cat > /etc/systemd/system/xui-sub.service <<EOF
[Unit]
Description=X-UI Subscription Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${server_script} ${SUBSCRIPTION_DIR} ${sub_port}
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable xui-sub.service &>/dev/null
    systemctl restart xui-sub.service

    log_success "سرور ساب‌اسکریپشن روی پورت ${sub_port} راه‌اندازی شد."
    echo -e "  ${CYAN}دسترسی: http://${PANEL_PUBLIC_IP:-SERVER_IP}:${sub_port}/sub/<EMAIL>${R}"
    press_enter
}

subscription_server_status() {
    draw_header "وضعیت سرور ساب" "Subscription Server Status"
    systemctl status xui-sub.service --no-pager 2>/dev/null \
        || echo -e "  ${RED}سرور ساب در حال اجرا نیست.${R}"
    press_enter
}

regenerate_all_subscriptions() {
    draw_header "بروزرسانی همه ساب‌اسکریپشن‌ها" "Regenerate All Subscriptions"
    local server_ip="${PANEL_PUBLIC_IP:-$(get_public_ip)}"
    local emails
    emails=$(db_query "SELECT DISTINCT email FROM client_traffics;")
    local count=0

    while IFS= read -r email; do
        [[ -z "$email" ]] && continue
        local inbound_ids all_configs=()
        inbound_ids=$(db_query "SELECT inbound_id FROM client_traffics WHERE email='${email}';")

        while IFS= read -r iid; do
            local settings stream proto port
            settings=$(get_inbound_settings "$iid")
            stream=$(get_inbound_stream_settings "$iid")
            proto=$(db_query "SELECT protocol FROM inbounds WHERE id=${iid} LIMIT 1;")
            port=$(db_query "SELECT port FROM inbounds WHERE id=${iid} LIMIT 1;")

            local uuid pw net sec link
            uuid=$(echo "$settings" | jq -r --arg em "$email" '.clients[] | select(.email==$em) | .id // empty' 2>/dev/null)
            pw=$(echo "$settings" | jq -r --arg em "$email" '.clients[] | select(.email==$em) | .password // empty' 2>/dev/null)
            net=$(echo "$stream" | jq -r '.network // "tcp"' 2>/dev/null)
            sec=$(echo "$stream" | jq -r '.security // "none"' 2>/dev/null)
            link=""
            case "${proto,,}" in
                vless)       link=$(build_vless_link "$uuid" "$server_ip" "$port" "$net" "$sec" "$email" "$stream") ;;
                vmess)       link=$(build_vmess_link "$uuid" "$server_ip" "$port" "$net" "$sec" "$email" "$stream") ;;
                trojan)      link=$(build_trojan_link "$pw" "$server_ip" "$port" "$net" "$sec" "$email" "$stream") ;;
                shadowsocks) local meth; meth=$(echo "$settings" | jq -r '.method // "chacha20-ietf-poly1305"')
                             link=$(build_ss_link "$meth" "$pw" "$server_ip" "$port" "$email") ;;
                hysteria2)   link=$(build_hysteria2_link "$pw" "$server_ip" "$port" "$email") ;;
            esac
            [[ -n "${link:-}" ]] && all_configs+=("$link")
        done <<< "$inbound_ids"

        if [[ ${#all_configs[@]} -gt 0 ]]; then
            local sub_content sub_b64 email_safe
            sub_content=$(printf '%s\n' "${all_configs[@]}")
            sub_b64=$(echo "$sub_content" | base64 -w 0)
            email_safe=$(echo "$email" | tr -cd '[:alnum:]._-')
            ensure_dir "$SUBSCRIPTION_DIR"
            echo "$sub_b64" > "${SUBSCRIPTION_DIR}/${email_safe}.txt"
            echo "$sub_content" > "${SUBSCRIPTION_DIR}/${email_safe}.json"
            ((count++))
        fi
    done <<< "$emails"

    log_success "${count} ساب‌اسکریپشن بروزرسانی شد."
    press_enter
}

# ==============================================================================
# SECTION 19: TELEGRAM BOT INTEGRATION
# ==============================================================================

telegram_bot_menu() {
    while true; do
        draw_header "ربات تلگرام" "Telegram Bot Integration"
        echo -e "\n  ${DIM}توکن: ${WHITE}${PANEL_TG_TOKEN:0:20}...${R}  |  ${DIM}Chat ID: ${WHITE}${PANEL_TG_CHAT_ID:-تنظیم نشده}${R}\n"
        draw_menu_item "1" "🤖" "پیکربندی ربات"                "توکن و Chat ID"
        draw_menu_item "2" "📤" "ارسال بکاپ دستی"              "ارسال DB به تلگرام"
        draw_menu_item "3" "⏰" "بکاپ خودکار"                  "تنظیم Cron Job"
        draw_menu_item "4" "📊" "ارسال گزارش ترافیک"           "خلاصه وضعیت کاربران"
        draw_menu_item "5" "🔔" "تنظیم هشدارها"               "اتمام ترافیک، انقضا"
        draw_menu_item "6" "📨" "ارسال پیام آزمایشی"           "تست اتصال"
        draw_menu_footer
        echo -ne "  ${B}${CYAN}انتخاب: ${R}"
        read -r choice
        case "$choice" in
            1) configure_telegram_bot ;;
            2) telegram_send_backup ;;
            3) setup_telegram_cron ;;
            4) telegram_send_traffic_report ;;
            5) setup_traffic_alerts ;;
            6) telegram_send_message "✅ تست اتصال پنل X-UI موفق بود! 🎉" && log_success "پیام ارسال شد." ;;
            0|"") return ;;
            *) log_warn "گزینه نامعتبر."; sleep 1 ;;
        esac
    done
}

telegram_send_message() {
    local message="$1"
    local token="${PANEL_TG_TOKEN:-}"
    local chat_id="${PANEL_TG_CHAT_ID:-}"

    if [[ -z "$token" || -z "$chat_id" ]]; then
        log_warn "ربات تلگرام پیکربندی نشده است."
        return 1
    fi

    curl -s --max-time 30 \
        "https://api.telegram.org/bot${token}/sendMessage" \
        -d "chat_id=${chat_id}" \
        -d "text=${message}" \
        -d "parse_mode=HTML" \
        -o /dev/null
}

telegram_send_file() {
    local filepath="$1"
    local caption="${2:-بکاپ X-UI}"
    local token="${PANEL_TG_TOKEN:-}"
    local chat_id="${PANEL_TG_CHAT_ID:-}"

    if [[ -z "$token" || -z "$chat_id" ]]; then
        log_warn "ربات تلگرام پیکربندی نشده است."
        return 1
    fi

    curl -s --max-time 120 \
        "https://api.telegram.org/bot${token}/sendDocument" \
        -F "chat_id=${chat_id}" \
        -F "document=@${filepath}" \
        -F "caption=${caption}" \
        -o /dev/null
}

telegram_send_backup() {
    draw_header "ارسال بکاپ به تلگرام" "Send Backup via Telegram"

    if [[ -z "${PANEL_TG_TOKEN:-}" || -z "${PANEL_TG_CHAT_ID:-}" ]]; then
        log_error "ربات تلگرام پیکربندی نشده. ابتدا توکن و Chat ID را وارد کنید."
        press_enter; return
    fi

    local backup_file timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    backup_file="${BACKUP_DIR}/xui_backup_${timestamp}.tar.gz"
    ensure_dir "$BACKUP_DIR"

    echo -e "  ${YELLOW}⟳${R}  در حال ساخت بکاپ..."
    if tar -czf "$backup_file" \
        -C / etc/x-ui \
        --exclude="*.log" \
        2>/dev/null; then
        log_success "بکاپ ساخته شد: ${backup_file}"
        echo -e "  ${YELLOW}⟳${R}  در حال ارسال به تلگرام..."
        telegram_send_file "$backup_file" \
            "🗄 بکاپ X-UI | سرور: ${PANEL_PUBLIC_IP:-unknown} | تاریخ: $(date '+%Y-%m-%d %H:%M')"
        log_success "بکاپ به تلگرام ارسال شد."
    else
        log_error "خطا در ساخت بکاپ."
    fi
    press_enter
}

telegram_send_traffic_report() {
    draw_header "ارسال گزارش ترافیک" "Traffic Report to Telegram"

    local total_up total_down total_users active_users
    total_up=$(db_query "SELECT COALESCE(SUM(up),0) FROM client_traffics;")
    total_down=$(db_query "SELECT COALESCE(SUM(down),0) FROM client_traffics;")
    total_users=$(db_query "SELECT count(*) FROM client_traffics;")
    active_users=$(db_query "SELECT count(*) FROM client_traffics WHERE enable=1;")

    local now_ms
    now_ms=$(( $(date +%s) * 1000 ))
    local expired_users
    expired_users=$(db_query "SELECT count(*) FROM client_traffics WHERE expiry_time > 0 AND expiry_time < ${now_ms};")

    local report
    report=$(cat <<EOF
📊 <b>گزارش وضعیت X-UI</b>
━━━━━━━━━━━━━━━━━━━━━
🖥 سرور: <code>${PANEL_PUBLIC_IP:-unknown}</code>
📅 تاریخ: $(date '+%Y-%m-%d %H:%M')
━━━━━━━━━━━━━━━━━━━━━
👥 کل کاربران: <b>${total_users}</b>
✅ فعال: <b>${active_users}</b>
⏰ منقضی: <b>${expired_users}</b>
━━━━━━━━━━━━━━━━━━━━━
⬆️ آپلود: <b>$(bytes_to_human "$total_up")</b>
⬇️ دانلود: <b>$(bytes_to_human "$total_down")</b>
━━━━━━━━━━━━━━━━━━━━━
EOF
)
    telegram_send_message "$report" && log_success "گزارش ارسال شد." || log_error "ارسال ناموفق."
    press_enter
}

setup_telegram_cron() {
    draw_header "بکاپ خودکار تلگرام" "Auto Backup Cron Setup"
    echo -e "  ${CYAN}انتخاب بازه:${R}"
    echo -e "  ${WHITE}1${R}) روزانه (ساعت ۰۰:۰۰)"
    echo -e "  ${WHITE}2${R}) هر ۱۲ ساعت"
    echo -e "  ${WHITE}3${R}) هفتگی (یکشنبه ساعت ۰۰:۰۰)"
    echo -e "  ${WHITE}4${R}) سفارشی (Cron Expression)"
    echo -ne "  انتخاب: "
    read -r cron_choice

    local cron_expr cron_label
    case "$cron_choice" in
        1) cron_expr="0 0 * * *";     cron_label="روزانه" ;;
        2) cron_expr="0 */12 * * *";  cron_label="هر ۱۲ ساعت" ;;
        3) cron_expr="0 0 * * 0";     cron_label="هفتگی" ;;
        4)
            prompt_input "Cron Expression" "0 0 * * *" cron_expr
            cron_label="سفارشی"
            ;;
        *) log_warn "گزینه نامعتبر."; press_enter; return ;;
    esac

    # Create backup script
    local backup_script="/usr/local/bin/xui-auto-backup.sh"
    cat > "$backup_script" <<BEOF
#!/usr/bin/env bash
source "${CONFIG_FILE}" 2>/dev/null || true
BACKUP_DIR="${BACKUP_DIR}"
TG_TOKEN="\${PANEL_TG_TOKEN:-}"
TG_CHAT="\${PANEL_TG_CHAT_ID:-}"
SERVER_IP="\${PANEL_PUBLIC_IP:-\$(curl -s --max-time 5 https://api.ipify.org)}"
TS=\$(date '+%Y%m%d_%H%M%S')
BK="\${BACKUP_DIR}/xui_auto_\${TS}.tar.gz"
mkdir -p "\$BACKUP_DIR"
tar -czf "\$BK" -C / etc/x-ui --exclude="*.log" 2>/dev/null || exit 1
# Keep only last 7 backups
ls -t "\${BACKUP_DIR}"/xui_auto_*.tar.gz 2>/dev/null | tail -n +8 | xargs rm -f 2>/dev/null
if [[ -n "\$TG_TOKEN" && -n "\$TG_CHAT" ]]; then
    curl -s --max-time 120 "https://api.telegram.org/bot\${TG_TOKEN}/sendDocument" \
        -F "chat_id=\${TG_CHAT}" \
        -F "document=@\${BK}" \
        -F "caption=🗄 بکاپ خودکار X-UI | سرور: \${SERVER_IP} | \$(date '+%Y-%m-%d %H:%M')" \
        -o /dev/null
fi
BEOF
    chmod +x "$backup_script"

    # Create traffic alert script
    local alert_script="/usr/local/bin/xui-traffic-alert.sh"
    cat > "$alert_script" <<AEOF
#!/usr/bin/env bash
source "${CONFIG_FILE}" 2>/dev/null || true
TG_TOKEN="\${PANEL_TG_TOKEN:-}"
TG_CHAT="\${PANEL_TG_CHAT_ID:-}"
[[ -z "\$TG_TOKEN" || -z "\$TG_CHAT" ]] && exit 0

XUI_DB="${XUI_DB}"
NOW_MS=\$(( \$(date +%s) * 1000 ))

# Check near-limit users (>90%)
NEAR_LIMIT=\$(sqlite3 "\$XUI_DB" \
    "SELECT email, up+down, total FROM client_traffics
     WHERE total > 0 AND (up+down)*100/total >= 90 AND enable=1;" 2>/dev/null)

if [[ -n "\$NEAR_LIMIT" ]]; then
    MSG="⚠️ <b>هشدار ترافیک X-UI</b>%0A"
    while IFS='|' read -r email used total; do
        PCT=\$(echo "scale=0; \$used*100/\$total" | bc 2>/dev/null || echo "??")
        MSG+="\n👤 \${email}: \${PCT}%% مصرف شده"
    done <<< "\$NEAR_LIMIT"
    curl -s "https://api.telegram.org/bot\${TG_TOKEN}/sendMessage" \
        -d "chat_id=\${TG_CHAT}&text=\${MSG}&parse_mode=HTML" -o /dev/null
fi

# Check newly expired users
EXPIRED=\$(sqlite3 "\$XUI_DB" \
    "SELECT email FROM client_traffics
     WHERE expiry_time > 0 AND expiry_time < \${NOW_MS} AND enable=1;" 2>/dev/null)
if [[ -n "\$EXPIRED" ]]; then
    MSG="⏰ <b>کاربران منقضی‌شده:</b>%0A"
    while IFS= read -r email; do
        MSG+="\n❌ \${email}"
    done <<< "\$EXPIRED"
    curl -s "https://api.telegram.org/bot\${TG_TOKEN}/sendMessage" \
        -d "chat_id=\${TG_CHAT}&text=\${MSG}&parse_mode=HTML" -o /dev/null
fi
AEOF
    chmod +x "$alert_script"

    # Install cron jobs
    local cron_backup="${cron_expr} root ${backup_script} >> /var/log/xui-panel.log 2>&1"
    local cron_alert="*/30 * * * * root ${alert_script} >> /var/log/xui-panel.log 2>&1"

    # Remove old entries first
    grep -v "xui-auto-backup\|xui-traffic-alert" /etc/crontab > /tmp/crontab.tmp 2>/dev/null || true
    echo "$cron_backup" >> /tmp/crontab.tmp
    echo "$cron_alert" >> /tmp/crontab.tmp
    mv /tmp/crontab.tmp /etc/crontab

    log_success "بکاپ خودکار ${cron_label} تنظیم شد."
    log_success "هشدار ترافیک هر ۳۰ دقیقه بررسی می‌شود."
    press_enter
}

setup_traffic_alerts() {
    draw_header "تنظیم هشدارهای ترافیک" "Traffic Alert Setup"
    echo -e "  ${DIM}هشدارهای خودکار هنگام اتمام ترافیک یا انقضا${R}"
    echo -e "  ${YELLOW}با اجرای 'بکاپ خودکار تلگرام' هشدارها هم تنظیم می‌شوند.${R}"
    echo ""
    echo -e "  ${WHITE}آستانه هشدار:${R} ۹۰٪ مصرف ترافیک"
    echo -e "  ${WHITE}بررسی هر:${R} ۳۰ دقیقه"
    echo -e "  ${WHITE}اسکریپت:${R} /usr/local/bin/xui-traffic-alert.sh"
    press_enter
}

# ==============================================================================
# SECTION 20: BACKUP SYSTEM
# ==============================================================================

backup_menu() {
    while true; do
        draw_header "سیستم بکاپ" "Backup System"
        draw_menu_item "1" "💾" "بکاپ دستی"                    "ذخیره دیتابیس و تنظیمات"
        draw_menu_item "2" "📤" "ارسال بکاپ به تلگرام"          ""
        draw_menu_item "3" "📋" "لیست بکاپ‌ها"                 "مشاهده فایل‌های ذخیره‌شده"
        draw_menu_item "4" "🔄" "بازیابی بکاپ"                 "Restore از فایل"
        draw_menu_item "5" "🗑️" "حذف بکاپ‌های قدیمی"          "نگه داشتن آخرین ۷ عدد"
        draw_menu_footer
        echo -ne "  ${B}${CYAN}انتخاب: ${R}"
        read -r choice
        case "$choice" in
            1) manual_backup ;;
            2) telegram_send_backup ;;
            3) list_backups ;;
            4) restore_backup ;;
            5) cleanup_old_backups ;;
            0|"") return ;;
            *) log_warn "گزینه نامعتبر."; sleep 1 ;;
        esac
    done
}

manual_backup() {
    draw_header "بکاپ دستی" "Manual Backup"
    ensure_dir "$BACKUP_DIR"

    local timestamp backup_file
    timestamp=$(date '+%Y%m%d_%H%M%S')
    backup_file="${BACKUP_DIR}/xui_manual_${timestamp}.tar.gz"

    echo -e "  ${YELLOW}⟳${R}  در حال ساخت بکاپ..."

    local backup_targets=()
    [[ -d "/etc/x-ui" ]]         && backup_targets+=("/etc/x-ui")
    [[ -f "$CONFIG_FILE" ]]      && backup_targets+=("$(dirname "$CONFIG_FILE")")
    [[ -d "$SUBSCRIPTION_DIR" ]] && backup_targets+=("$SUBSCRIPTION_DIR")

    if tar -czf "$backup_file" "${backup_targets[@]}" 2>/dev/null; then
        local size
        size=$(du -sh "$backup_file" | cut -f1)
        log_success "بکاپ ذخیره شد: ${backup_file} (${size})"
    else
        log_error "خطا در ساخت بکاپ."
    fi
    press_enter
}

list_backups() {
    draw_header "لیست بکاپ‌ها" "Backup List"
    ensure_dir "$BACKUP_DIR"
    echo ""
    printf "  ${CYAN}%-45s %-10s %-20s${R}\n" "نام فایل" "حجم" "تاریخ"
    draw_line "─" "$DIM"

    local count=0
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local size date_str
        size=$(du -sh "$file" 2>/dev/null | cut -f1)
        date_str=$(stat -c '%y' "$file" 2>/dev/null | cut -d'.' -f1)
        printf "  ${WHITE}%-45s${R} ${YELLOW}%-10s${R} ${DIM}%-20s${R}\n" \
            "$(basename "$file")" "$size" "$date_str"
        ((count++))
    done < <(ls -t "${BACKUP_DIR}"/*.tar.gz 2>/dev/null)

    if [[ $count -eq 0 ]]; then
        echo -e "  ${YELLOW}بکاپی یافت نشد.${R}"
    else
        echo -e "\n  ${DIM}جمع: ${count} بکاپ${R}"
    fi
    press_enter
}

restore_backup() {
    draw_header "بازیابی بکاپ" "Restore Backup"
    list_backups

    local backup_name
    prompt_input "نام فایل بکاپ (در پوشه ${BACKUP_DIR})" "" backup_name
    local backup_path="${BACKUP_DIR}/${backup_name}"

    if [[ ! -f "$backup_path" ]]; then
        log_error "فایل '${backup_path}' یافت نشد."
        press_enter; return
    fi

    if confirm_action "بازیابی بکاپ، تنظیمات فعلی را بازنویسی می‌کند!"; then
        systemctl stop x-ui 2>/dev/null || true
        tar -xzf "$backup_path" -C / 2>/dev/null \
            && log_success "بکاپ بازیابی شد." \
            || log_error "بازیابی ناموفق."
        systemctl start x-ui 2>/dev/null
    fi
    press_enter
}

cleanup_old_backups() {
    draw_header "حذف بکاپ‌های قدیمی" "Cleanup Old Backups"
    local keep="${1:-7}"
    local count_before count_after
    count_before=$(ls "${BACKUP_DIR}"/*.tar.gz 2>/dev/null | wc -l)

    ls -t "${BACKUP_DIR}"/*.tar.gz 2>/dev/null | tail -n +$((keep + 1)) | xargs rm -f 2>/dev/null

    count_after=$(ls "${BACKUP_DIR}"/*.tar.gz 2>/dev/null | wc -l)
    local deleted=$(( count_before - count_after ))
    log_success "${deleted} بکاپ قدیمی حذف شد. ${count_after} بکاپ باقیمانده."
    press_enter
}

# ==============================================================================
# SECTION 21: SSL SETUP (sslip.io + Let's Encrypt)
# ==============================================================================

ssl_menu() {
    while true; do
        draw_header "SSL و امنیت پنل" "SSL & Panel Security"
        echo -e "\n  ${DIM}راهکار: آی‌پی سرور + sslip.io → گواهی معتبر Let's Encrypt${R}\n"
        draw_menu_item "1" "🔒" "نصب SSL روی IP (sslip.io)"      "بدون نیاز به دامنه"
        draw_menu_item "2" "🌐" "نصب SSL روی دامنه"               "برای دامنه Cloudflare"
        draw_menu_item "3" "🔄" "تمدید SSL"                       "acme.sh --renew"
        draw_menu_item "4" "📋" "وضعیت گواهی‌ها"                 "نمایش تاریخ انقضا"
        draw_menu_item "5" "⚙️" "اعمال SSL به X-UI"               "پیکربندی پنل"
        draw_menu_item "6" "🚫" "حذف SSL"                         "بازگشت به HTTP"
        draw_menu_footer
        echo -ne "  ${B}${CYAN}انتخاب: ${R}"
        read -r choice
        case "$choice" in
            1) setup_ssl_sslip ;;
            2) setup_ssl_domain ;;
            3) renew_ssl ;;
            4) show_ssl_status ;;
            5) apply_ssl_to_xui ;;
            6) remove_ssl_from_xui ;;
            0|"") return ;;
            *) log_warn "گزینه نامعتبر."; sleep 1 ;;
        esac
    done
}

setup_ssl_sslip() {
    draw_header "SSL روی IP با sslip.io" "SSL via IP using sslip.io Loophole"

    local server_ip
    server_ip="${PANEL_PUBLIC_IP:-$(get_public_ip)}"

    # Convert IP to sslip domain: 1.2.3.4 → 1.2.3.4.sslip.io
    local sslip_domain="${server_ip}.sslip.io"

    echo -e "\n  ${CYAN}اطلاعات:${R}"
    echo -e "  ${DIM}آی‌پی سرور:${R}    ${WHITE}${server_ip}${R}"
    echo -e "  ${DIM}دامنه sslip:${R}   ${WHITE}${sslip_domain}${R}"
    echo -e "  ${DIM}نحوه کار:${R}      ${DIM}sslip.io → DNS مستقیم به IP شما${R}"
    echo -e "  ${DIM}نتیجه:${R}         ${GREEN}https://${sslip_domain}:PORT${R}"
    echo ""

    if ! command -v socat &>/dev/null; then
        echo -e "  ${YELLOW}⟳${R}  نصب socat..."
        apt-get install -y -qq socat &>/dev/null
    fi

    if [[ ! -f "${ACME_DIR}/acme.sh" ]]; then
        echo -e "  ${YELLOW}⟳${R}  نصب acme.sh..."
        curl -s https://get.acme.sh | sh -s email="admin@${sslip_domain}" &>/dev/null || {
            log_error "نصب acme.sh ناموفق."
            press_enter; return
        }
        source "${HOME}/.bashrc" 2>/dev/null || true
    fi

    # Stop any service using port 80 temporarily
    local port80_service
    port80_service=$(ss -tlnp 'sport = :80' 2>/dev/null | grep -oP '(?<=users:\(\(").*?(?=")' | head -1 || echo "")
    if [[ -n "$port80_service" ]]; then
        log_warn "پورت 80 توسط ${port80_service} استفاده می‌شود. موقتاً متوقف می‌شود..."
        systemctl stop "$port80_service" 2>/dev/null || true
    fi

    echo -e "  ${YELLOW}⟳${R}  درخواست گواهی SSL برای ${sslip_domain}..."
    "${ACME_DIR}/acme.sh" \
        --issue \
        --standalone \
        --domain "$sslip_domain" \
        --server letsencrypt \
        --keylength ec-256 \
        --force \
        2>&1 | tail -5

    local cert_dir="/etc/ssl/xui/${sslip_domain}"
    ensure_dir "$cert_dir"

    "${ACME_DIR}/acme.sh" \
        --install-cert \
        --domain "$sslip_domain" \
        --ecc \
        --cert-file   "${cert_dir}/cert.pem" \
        --key-file    "${cert_dir}/key.pem" \
        --fullchain-file "${cert_dir}/fullchain.pem" \
        --reloadcmd   "systemctl restart x-ui" \
        2>/dev/null

    if [[ -f "${cert_dir}/fullchain.pem" ]]; then
        PANEL_SSL_DOMAIN="$sslip_domain"
        PANEL_SSL_CERT="${cert_dir}/fullchain.pem"
        PANEL_SSL_KEY="${cert_dir}/key.pem"
        save_config

        # Restart stopped service
        [[ -n "$port80_service" ]] && systemctl start "$port80_service" 2>/dev/null || true

        log_success "گواهی SSL برای ${sslip_domain} صادر شد!"
        echo ""
        echo -e "  ${GREEN}${B}دسترسی امن به پنل:${R}"
        echo -e "  ${CYAN}https://${sslip_domain}:$(get_xui_port)${R}"
        echo ""

        # Auto-apply to X-UI
        echo -ne "  آیا SSL را به پنل X-UI اعمال کنید؟ (بله/خیر): "
        read -r apply_ans
        [[ "$apply_ans" =~ ^(بله|yes|y)$ ]] && apply_ssl_to_xui
    else
        [[ -n "$port80_service" ]] && systemctl start "$port80_service" 2>/dev/null || true
        log_error "صدور گواهی ناموفق. پورت 80 را بررسی کنید."
    fi
    press_enter
}

setup_ssl_domain() {
    draw_header "SSL روی دامنه" "SSL via Domain"

    local domain
    prompt_input "دامنه/ساب‌دامنه" "${PANEL_CF_DOMAIN:-}" domain
    [[ -z "$domain" ]] && return

    local email
    prompt_input "ایمیل برای Let's Encrypt" "admin@${domain}" email

    if [[ ! -f "${ACME_DIR}/acme.sh" ]]; then
        curl -s https://get.acme.sh | sh -s email="$email" &>/dev/null || {
            log_error "نصب acme.sh ناموفق."
            press_enter; return
        }
    fi

    echo -e "  ${CYAN}روش احراز:${R}"
    echo -e "  ${WHITE}1${R}) Standalone (پورت 80)"
    echo -e "  ${WHITE}2${R}) Webroot"
    echo -e "  ${WHITE}3${R}) DNS API (Cloudflare)"
    echo -ne "  انتخاب: "
    read -r verify_method

    local cert_dir="/etc/ssl/xui/${domain}"
    ensure_dir "$cert_dir"

    case "$verify_method" in
        1)
            "${ACME_DIR}/acme.sh" --issue --standalone \
                --domain "$domain" --server letsencrypt --keylength ec-256 --force
            ;;
        2)
            local webroot
            prompt_input "مسیر Webroot" "/var/www/html" webroot
            "${ACME_DIR}/acme.sh" --issue --webroot "$webroot" \
                --domain "$domain" --server letsencrypt --keylength ec-256 --force
            ;;
        3)
            local cf_token cf_zone
            prompt_input "Cloudflare API Token" "${CF_API_TOKEN:-}" cf_token
            prompt_input "Cloudflare Zone ID" "${CF_ZONE_ID:-}" cf_zone
            CF_Token="$cf_token" CF_Zone_ID="$cf_zone" \
            "${ACME_DIR}/acme.sh" --issue --dns dns_cf \
                --domain "$domain" --server letsencrypt --keylength ec-256 --force
            ;;
        *) log_error "روش نامعتبر."; press_enter; return ;;
    esac

    "${ACME_DIR}/acme.sh" --install-cert --domain "$domain" --ecc \
        --cert-file "${cert_dir}/cert.pem" \
        --key-file "${cert_dir}/key.pem" \
        --fullchain-file "${cert_dir}/fullchain.pem" \
        --reloadcmd "systemctl restart x-ui"

    if [[ -f "${cert_dir}/fullchain.pem" ]]; then
        PANEL_SSL_DOMAIN="$domain"
        PANEL_SSL_CERT="${cert_dir}/fullchain.pem"
        PANEL_SSL_KEY="${cert_dir}/key.pem"
        save_config
        log_success "گواهی SSL برای ${domain} نصب شد."
    else
        log_error "صدور گواهی ناموفق."
    fi
    press_enter
}

renew_ssl() {
    draw_header "تمدید SSL" "SSL Renewal"
    if [[ ! -f "${ACME_DIR}/acme.sh" ]]; then
        log_error "acme.sh نصب نشده است."
        press_enter; return
    fi
    echo -e "  ${YELLOW}⟳${R}  در حال تمدید گواهی‌ها..."
    "${ACME_DIR}/acme.sh" --renew-all --force 2>&1 | tail -20
    log_success "تمدید انجام شد."
    press_enter
}

show_ssl_status() {
    draw_header "وضعیت گواهی‌های SSL" "SSL Certificate Status"

    if [[ ! -f "${ACME_DIR}/acme.sh" ]]; then
        log_warn "acme.sh نصب نشده است."
        press_enter; return
    fi

    echo ""
    "${ACME_DIR}/acme.sh" --list 2>/dev/null || echo -e "  ${YELLOW}گواهی‌ای یافت نشد.${R}"
    echo ""

    if [[ -n "${PANEL_SSL_CERT:-}" && -f "${PANEL_SSL_CERT}" ]]; then
        draw_section "گواهی فعلی پنل"
        echo -e "  ${DIM}دامنه: ${WHITE}${PANEL_SSL_DOMAIN:-نامشخص}${R}"
        local exp_date
        exp_date=$(openssl x509 -enddate -noout -in "${PANEL_SSL_CERT}" 2>/dev/null | cut -d= -f2)
        echo -e "  ${DIM}انقضا: ${WHITE}${exp_date}${R}"
        echo -e "  ${DIM}فایل:  ${WHITE}${PANEL_SSL_CERT}${R}"
    fi
    press_enter
}

apply_ssl_to_xui() {
    draw_header "اعمال SSL به X-UI" "Apply SSL to X-UI Panel"

    local cert="${PANEL_SSL_CERT:-}"
    local key="${PANEL_SSL_KEY:-}"

    if [[ -z "$cert" || ! -f "$cert" ]]; then
        log_error "گواهی SSL یافت نشد. ابتدا SSL را نصب کنید."
        press_enter; return
    fi

    set_xui_setting "webCertFile" "$cert"
    set_xui_setting "webKeyFile"  "$key"

    restart_xui_service
    local panel_port
    panel_port=$(get_xui_port)

    log_success "SSL به پنل X-UI اعمال شد."
    echo ""
    echo -e "  ${GREEN}${B}دسترسی امن:${R}"
    echo -e "  ${CYAN}https://${PANEL_SSL_DOMAIN:-SERVER_IP.sslip.io}:${panel_port}${R}"
    press_enter
}

remove_ssl_from_xui() {
    draw_header "حذف SSL از X-UI" "Remove SSL from X-UI"
    if confirm_action "SSL از پنل حذف می‌شود و به HTTP برمی‌گردد."; then
        set_xui_setting "webCertFile" ""
        set_xui_setting "webKeyFile"  ""
        restart_xui_service
        log_success "SSL حذف شد. پنل به HTTP بازگشت."
    fi
    press_enter
}

# ==============================================================================
# SECTION 22: SELF-UPDATE FROM GITHUB
# ==============================================================================

self_update() {
    draw_header "بروزرسانی اسکریپت" "Self-Update from GitHub"
    echo -e "  ${DIM}منبع: ${WHITE}${GITHUB_REPO}${R}\n"

    if ! confirm_action "اسکریپت فعلی با نسخه جدید جایگزین می‌شود!"; then
        return
    fi

    echo -e "  ${YELLOW}⟳${R}  دانلود نسخه جدید..."
    local tmp_file="/tmp/xui-panel-update.sh"

    if curl -s --max-time 60 -L "$GITHUB_REPO" -o "$tmp_file" 2>/dev/null; then
        # Validate the downloaded file (basic check)
        if head -3 "$tmp_file" | grep -q "bash\|BASH"; then
            local current_version new_version
            current_version="$PANEL_VERSION"
            new_version=$(grep -m1 "PANEL_VERSION=" "$tmp_file" 2>/dev/null | cut -d'"' -f2 || echo "نامشخص")

            echo -e "  ${DIM}نسخه فعلی:${R} ${YELLOW}${current_version}${R}"
            echo -e "  ${DIM}نسخه جدید:${R} ${GREEN}${new_version}${R}"
            echo ""

            # Backup current script
            cp "$SCRIPT_PATH" "${SCRIPT_PATH}.backup.$(date +%Y%m%d)" 2>/dev/null || true

            # Replace script
            cp "$tmp_file" "$SCRIPT_PATH"
            chmod +x "$SCRIPT_PATH"
            rm -f "$tmp_file"

            log_success "بروزرسانی موفق! اسکریپت مجدداً راه‌اندازی می‌شود..."
            sleep 2
            exec bash "$SCRIPT_PATH"
        else
            log_error "فایل دانلودشده معتبر نیست."
            rm -f "$tmp_file"
        fi
    else
        log_error "دانلود ناموفق. اتصال اینترنت را بررسی کنید."
    fi
    press_enter
}

# ==============================================================================
# SECTION 23: CRON SCHEDULER FOR SUBSCRIPTIONS & ALERTS
# ==============================================================================

# Called from main script if sources this file
setup_default_cron_jobs() {
    local alert_script="/usr/local/bin/xui-traffic-alert.sh"
    # Only install if script exists and cron entry missing
    if [[ -f "$alert_script" ]]; then
        if ! grep -q "xui-traffic-alert" /etc/crontab 2>/dev/null; then
            echo "*/30 * * * * root ${alert_script} >> /var/log/xui-panel.log 2>&1" >> /etc/crontab
        fi
    fi

    # Auto-regenerate subscriptions every 6 hours
    if ! grep -q "xui-sub-regen" /etc/crontab 2>/dev/null; then
        echo "0 */6 * * * root bash -c 'source ${CONFIG_FILE} 2>/dev/null; source ${SCRIPT_PATH} 2>/dev/null; regenerate_all_subscriptions' >> /var/log/xui-panel.log 2>&1" >> /etc/crontab
    fi
}
