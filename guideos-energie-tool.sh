#!/bin/bash
# GuideOS Energie-Profil Umschalter (Zenity-Version)
# Entwickelt von evilware666 für GuideOS

# --------------------
# ⚠️ Liquorix-Kernel Warnung
# --------------------
if uname -r | grep -qi "liquorix"; then
    zenity --warning --title="Warnung: Liquorix-Kernel erkannt" --text="Der Liquorix-Kernel ist auf maximale Leistung optimiert.\n\nDas Energie-Profil kann mit diesem Kernel möglicherweise nicht richtig geändert werden.\n\nBitte den Standard-Kernel verwenden und neu starten!"
fi

# --------------------
# 🔍 Prüfe verfügbare Tools
# --------------------
detect_tools() {
    command -v cpupower &>/dev/null && echo "cpupower"
    command -v powerprofilesctl &>/dev/null && echo "powerprofilesctl"
}
tools=($(detect_tools))
tool=""
for t in cpupower powerprofilesctl; do
    for avail in "${tools[@]}"; do
        [[ "$t" == "$avail" ]] && { tool=$t; break 2; }
    done
done
[[ -z "$tool" ]] && { zenity --error --title="Fehler" --text="Kein cpupower oder powerprofilesctl gefunden!"; exit 1; }

# --------------------
# 🔑 Passwort nur einmal
# --------------------
PASSWORT=$(zenity --password --title="Administrator-Rechte" --text="Bitte gib dein Passwort ein:")
[[ -z "$PASSWORT" ]] && exit 0
echo "$PASSWORT" | sudo -S true &>/dev/null || { zenity --error --title="Fehler" --text="Falsches Passwort!"; exit 1; }

# --------------------
# 🔧 Zusatz-Funktionen
# --------------------
set_brightness() {
    pct=$1
    if command -v brightnessctl &>/dev/null; then
        echo "$PASSWORT" | sudo -S brightnessctl set "${pct}%"
    else
        for b in /sys/class/backlight/*/; do
            max=$(cat "$b/max_brightness")
            val=$((max * pct / 100))
            echo "$val" | sudo tee "$b/brightness" &>/dev/null
        done
    fi
}

set_kbd_backlight() {
    pct=$1
    if command -v brightnessctl &>/dev/null; then
        echo "$PASSWORT" | sudo -S brightnessctl -d 'smc::kbd_backlight' set "${pct}%"
    else
        for k in /sys/class/leds/*kbd_backlight*/; do
            max=$(cat "$k/max_brightness")
            val=$((max * pct / 100))
            echo "$val" | sudo tee "$k/brightness" &>/dev/null
        done
    fi
}

set_usb_powersave() {
    mode=$1  # "on" = kein Autosuspend, "auto" = Autosuspend an
    for dev in /sys/bus/usb/devices/*/power/control; do
        echo "$mode" | sudo tee "$dev" &>/dev/null
    done
}

# --------------------
# 🔄 Aktuellen Modus ermitteln
# --------------------
get_current_mode() {
    case "$tool" in
        powerprofilesctl)
            prof=$(powerprofilesctl get)
            [[ "$prof" == "power-saver" ]] && echo "powersave" || echo "$prof" ;;
        cpupower)
            gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
            case "$gov" in
                ondemand)  echo "balanced" ;;
                performance) echo "performance" ;;
                powersave) echo "powersave" ;;
                *) echo "unknown" ;;
            esac ;;
    esac
}
current=$(get_current_mode)

# --------------------
# 🌐 Modi und Labels
# --------------------
MODI=(balanced performance powersave)
LABELS=("Ausgeglichen" "Leistung" "Energiesparmodus")

# --------------------
# 📋 Zenity-Liste
# --------------------
ZENITY_LIST=()
for i in "${!MODI[@]}"; do
    m=${MODI[$i]}; l=${LABELS[$i]}; sel=FALSE
    [[ "$m" == "$current" ]] && { sel=TRUE; l+=" (Aktiv)"; }
    ZENITY_LIST+=("$sel" "$l")
done

auswahl=$(zenity --list --title="Energie-Modus wählen" \
    --text="Wähle einen Energie-Modus aus:" --radiolist --width=400 --height=280 \
    --column="Auswählen" --column="Modus" "${ZENITY_LIST[@]}")
[[ -z "$auswahl" ]] && exit 0

SAUBER=$(echo "$auswahl" | sed 's/ (Aktiv)//')
case "$SAUBER" in
    "Leistung")     NEU="performance" ;;
    "Ausgeglichen") NEU="balanced"    ;;
    "Energiesparmodus") NEU="powersave" ;;
    *) exit 1 ;;
esac

# --------------------
# 🛠️ CPU-Modus setzen
# --------------------
set_ok=false
if [[ "$tool" == "cpupower" ]]; then
    gov=$NEU; [[ "$NEU" == "balanced" ]] && gov="ondemand"
    echo "$PASSWORT" | sudo -S cpupower -c all frequency-set -g "$gov" &>/dev/null && set_ok=true
fi
if ! $set_ok && [[ "$tool" == "powerprofilesctl" ]]; then
    prof=$NEU; [[ "$NEU" == "powersave" ]] && prof="power-saver"
    echo "$PASSWORT" | sudo -S powerprofilesctl set "$prof" &>/dev/null && set_ok=true
fi

# --------------------
# 🔆 Zusätzliche Einstellungen
# --------------------
if $set_ok; then
    case "$NEU" in
        performance)
            set_brightness 100
            set_kbd_backlight 100
            set_usb_powersave on
            ;;
        balanced)
            set_brightness 70
            set_kbd_backlight 50
            set_usb_powersave auto
            ;;
        powersave)
            set_brightness 30
            set_kbd_backlight 20
            set_usb_powersave auto
            ;;
    esac

    zenity --info --title="Erfolg" --text="Energie-Modus geändert zu: $SAUBER"
    notify-send "GuideOS Energie" "Folgender Modus ist aktiv: $SAUBER"
else
    zenity --error --title="Fehler" --text="Modus konnte nicht geändert werden."
    exit 1
fi
