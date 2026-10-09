#!/usr/bin/env bash
# Local SmartCast settings browser. Requires bash, curl, jq and dialog/whiptail.
set -uo pipefail
umask 077
for dep in curl jq; do
    command -v "$dep" >/dev/null || { echo "Missing dependency: $dep" >&2; exit 1; }
done
if command -v dialog >/dev/null; then UI=dialog
elif command -v whiptail >/dev/null; then UI=whiptail
else echo 'Install a menu frontend: sudo dnf install dialog' >&2; exit 1; fi
[[ -t 0 && -t 1 ]] || { echo 'Run this script in an interactive terminal.' >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
trap 'exit 130' INT TERM
cat > "$work/openssl.cnf" <<'EOF'
openssl_conf = init
[init]
ssl_conf = ssl_config
[ssl_config]
system_default = tv_config
[tv_config]
Options = UnsafeLegacyServerConnect
MinProtocol = TLSv1
CipherString = DEFAULT:@SECLEVEL=0
EOF
config_dir=${XDG_CONFIG_HOME:-$HOME/.config}/vizio-tui
config=$config_dir/connection.json
host=${VIZIO_HOST:-192.168.1.180}
port=${VIZIO_PORT:-9000}
token=${VIZIO_TOKEN:-}
if [[ -f $config ]]; then
    host=${VIZIO_HOST:-$(jq -r '.host // "192.168.1.180"' "$config")}
    port=${VIZIO_PORT:-$(jq -r '.port // "9000"' "$config")}
    token=${VIZIO_TOKEN:-$(jq -r '.token // ""' "$config")}
fi
ui() { "$UI" --title 'Vizio TV Settings' "$@"; }
ask() { ui "$@" 3>&1 1>&2 2>&3; }
message() { ui --msgbox "$1" 20 78; }
view() { printf '%s\n' "$1" > "$work/view.txt"; ui --textbox "$work/view.txt" 24 90; }
api() {
    local method=$1 path=$2 body=${3:-} result
    local -a args=(-skS --connect-timeout 5 --max-time 15 -H 'Content-Type: application/json' -X "$method")
    [[ -z $token ]] || args+=(-H "AUTH: $token")
    [[ -z $body ]] || args+=(--data-binary "$body")
    if [[ $port == 9000 ]]; then args+=(--ciphers 'DEFAULT:@SECLEVEL=0' --tlsv1.0 --tls-max 1.2); fi
    if ! result=$(OPENSSL_CONF="$work/openssl.cnf" curl "${args[@]}" "https://$host:$port/$path" 2>"$work/error"); then
        message "Connection failed. Keep the TV powered on.\n$(cat "$work/error")"; return 1
    fi
    if ! jq -e 'type == "object"' <<< "$result" >/dev/null 2>&1; then
        message "The TV did not return a JSON object.\n${result:0:1000}"; return 1
    fi
    printf '%s' "$result"
}
success() { jq -e '(.STATUS.RESULT // "" | ascii_downcase) == "success"' <<< "$1" >/dev/null; }
save_connection() {
    ui --yesno 'Save the address and authentication token for future runs? The token will be stored in a user-only configuration file.' 10 75 || return 0
    mkdir -p "$config_dir" || return 1
    jq -n --arg host "$host" --arg port "$port" --arg token "$token" '{host:$host,port:$port,token:$token}' > "$config"
    chmod 600 "$config"
}
connect() {
    host=$(ask --inputbox 'TV IP address (TV must be powered on):' 9 65 "$host") || return 1
    [[ $host =~ ^[a-zA-Z0-9.-]+$ ]] || { message 'Use an IPv4 address or hostname.'; return 1; }
    port=$(ask --inputbox 'API port: 9000 for this TV; 7345 for newer firmware.' 9 70 "$port") || return 1
    [[ $port =~ ^[0-9]+$ && ${#port} -le 5 ]] && ((10#$port > 0 && 10#$port <= 65535)) || { message 'Invalid port.'; return 1; }
    local choice reply pin req challenge id
    choice=$(ask --menu 'Authentication' 14 70 3 existing 'Enter an existing token' pair 'Start pairing and enter the TV PIN') || return 1
    if [[ $choice == existing ]]; then
        token=$(ask --passwordbox 'Enter your authentication token:' 9 65 "$token") || return 1
        [[ -n $token ]] || return 1
    else
        token=''
        id="linux-tui-$(date +%s)-$RANDOM"
        reply=$(api PUT pairing/start "$(jq -n --arg id "$id" '{DEVICE_ID:$id,DEVICE_NAME:"Linux TV Menu"}')") || return 1
        if ! success "$reply"; then view "$(jq . <<< "$reply")"; return 1; fi
        req=$(jq -r '.ITEM.PAIRING_REQ_TOKEN // empty' <<< "$reply")
        challenge=$(jq -r '.ITEM.CHALLENGE_TYPE // empty' <<< "$reply")
        [[ $req =~ ^[0-9]+$ && $challenge =~ ^[0-9]+$ ]] || { message 'Missing pairing challenge.'; return 1; }
        pin=$(ask --inputbox 'Enter the PIN on the TV. If the setup screen hides it, press Play/Pause on your remote.' 11 75) || return 1
        [[ $pin =~ ^[0-9]{4}$ ]] || { message 'Expected four digits.'; return 1; }
        reply=$(api PUT pairing/pair "$(jq -n --arg id "$id" --arg pin "$pin" --argjson req "$req" --argjson challenge "$challenge" '{DEVICE_ID:$id,RESPONSE_VALUE:$pin,PAIRING_REQ_TOKEN:$req,CHALLENGE_TYPE:$challenge}')") || return 1
        token=$(jq -r '.ITEM.AUTH_TOKEN // empty' <<< "$reply")
        [[ -n $token ]] || { view "$(jq . <<< "$reply")"; return 1; }
        message 'Pairing succeeded.'
    fi
    save_connection
}
edit_item() {
    local parent=$1 cname=$2 reply item type name value new body hash choice i
    local -a choices=()
    # Refresh just before editing so the hash and allowed values are current.
    reply=$(api GET "$parent") || return
    success "$reply" || { view "$(jq . <<< "$reply")"; return; }
    item=$(jq -c --arg c "$cname" '.ITEMS[]? | select(.CNAME == $c)' <<< "$reply")
    [[ -n $item ]] || { message 'Setting no longer exists.'; return; }
    name=$(jq -r '.NAME' <<< "$item")
    type=$(jq -r '.TYPE' <<< "$item")
    if [[ $(jq -r '.ENABLED' <<< "$item") != true ]]; then view "$(jq . <<< "$item")"; return; fi
    if [[ $type == T_MENU* ]]; then browse "$parent/$cname" "$name"; return; fi
    hash=$(jq -r '.HASHVAL // empty' <<< "$item")
    [[ $hash =~ ^[0-9]+$ ]] || { view "$(jq . <<< "$item")"; return; }
    value=$(jq -c '.VALUE' <<< "$item")
    if jq -e '(.ELEMENTS | type) == "array" and (.ELEMENTS | length) > 0 and all(.ELEMENTS[]; type == "string" or type == "number" or type == "boolean")' <<< "$item" >/dev/null; then
        i=0
        while IFS= read -r choice; do choices+=("$i" "$choice"); ((i+=1)); done < <(jq -r '.ELEMENTS[] | tostring' <<< "$item")
        choice=$(ask --menu "$name — current: $value" 20 80 12 "${choices[@]}") || return
        new=$(jq -c --argjson i "$choice" '.ELEMENTS[$i]' <<< "$item")
    elif [[ $type == T_VALUE_V1 || $type == T_VALUE_ABS_V1 || $type == T_STRING_V1 || $type == T_IP_ADDRESS_V1 ]]; then
        choice=$(ask --inputbox "$name — enter a new value (current: $value):" 11 78 "$(jq -r '.VALUE' <<< "$item")") || return
        case $(jq -r '.VALUE | type' <<< "$item") in
            number) new=$(jq -cn --arg v "$choice" '$v | tonumber') || { message 'Expected a number.'; return; } ;;
            boolean) [[ $choice == true || $choice == false ]] || { message 'Expected true or false.'; return; }; new=$choice ;;
            string) new=$(jq -cn --arg v "$choice" '$v') ;;
            *) view "$(jq . <<< "$item")"; return ;;
        esac
    else
        view "$(jq . <<< "$item")"
        return
    fi
    [[ $new == "$value" ]] && return
    ui --yesno "Change $name?\n\nCurrent: $value\nNew: $new\n\nNetwork changes may disconnect the TV." 14 78 || return
    body=$(jq -cn --argjson hash "$hash" --argjson v "$new" '{REQUEST:"MODIFY",HASHVAL:$hash,VALUE:$v}')
    reply=$(api PUT "$parent/$cname" "$body") || return
    view "$(jq . <<< "$reply")"
}
browse() {
    local path=$1 title=$2 reply selected row index name type value cname
    local -a entries=()
    while :; do
        reply=$(api GET "$path") || return
        success "$reply" || { view "$(jq . <<< "$reply")"; return; }
        entries=(raw 'View full JSON response')
        while IFS= read -r row; do
            index=$(jq -r '.key' <<< "$row")
            name=$(jq -r '.value.NAME // .value.CNAME' <<< "$row")
            type=$(jq -r '.value.TYPE' <<< "$row")
            value=$(jq -r '.value.VALUE | tostring' <<< "$row")
            [[ $type == T_MENU* ]] && value='[submenu]'
            [[ $(jq -r '.value.ENABLED' <<< "$row") == false ]] && value="$value [disabled]"
            entries+=("$index" "$name: ${value:0:100}")
        done < <(jq -c '(.ITEMS // []) | to_entries[]' <<< "$reply")
        selected=$(ask --menu "$title — Enter selects; Esc returns" 24 90 16 "${entries[@]}") || return
        if [[ $selected == raw ]]; then view "$(jq . <<< "$reply")"; continue; fi
        cname=$(jq -r --argjson i "$selected" '.ITEMS[$i].CNAME' <<< "$reply")
        [[ $cname =~ ^[a-zA-Z0-9_-]+$ ]] || { message 'Unsupported setting path. See full JSON.'; continue; }
        edit_item "$path" "$cname"
    done
}
[[ -n $token ]] || connect || exit 1
while :; do
    selection=$(ask --menu "TV: $host:$port — choose a settings category" 24 80 15 \
        system 'System / CEC / Power / Information' \
        picture 'Picture settings' audio 'Audio settings' timers 'Timers' \
        network 'Network settings' devices 'Inputs and devices' \
        channels 'Channels' closed_captions 'Closed captions' \
        mobile_devices 'Paired mobile devices' cast 'Cast settings' \
        connection 'Change connection / Pair' quit 'Exit') || break
    case $selection in
        quit) break ;;
        connection) connect || true ;;
        *) browse "menu_native/dynamic/tv_settings/$selection" "$selection" ;;
    esac
done
clear
