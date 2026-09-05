#!/usr/bin/env bash
# =============================================================
#  FPTN — переиспользуемая TUI-библиотека
#  ------------------------------------------------------------
#  Функции (whiptail-first, fallback на stdin):
#    tui_info        <title> <text>
#    tui_msgbox      <title> <text>
#    tui_yesno       <title> <text>           -> 0 (yes) | 1 (no)
#    tui_input       <title> <text> <default> -> stdout
#    tui_password    <title> <text>           -> stdout
#    tui_menu        <title> <text> <tag item tag item...> -> stdout (tag)
#    tui_checklist   <title> <text> <tag item on|off ...>  -> stdout (tags, space-separated)
#    tui_gauge_start <title> <text> <percent>
#    tui_gauge_update <percent>
#    tui_gauge_end
#
#  Авто-выбор бэкенда: whiptail > dialog > stdin.
#  Если TUI невозможен (нет /dev/tty, не-интерактив) — fallback на stdin.
# =============================================================

# ---- определение бэкенда ----
_TUI_BACKEND=""
_TUI_WIDTH=70
_TUI_HEIGHT=20

_tui_detect_backend() {
  # Неинтерактивная сессия (нет tty или пустой TERM) — fallback на stdin
  if [[ ! -t 0 || ! -t 1 || -z "${TERM:-}" || "${TERM:-dumb}" == "dumb" ]]; then
    _TUI_BACKEND="stdin"
    return
  fi
  if [[ -r /dev/tty ]] && command -v whiptail >/dev/null 2>&1; then
    _TUI_BACKEND="whiptail"
  elif [[ -r /dev/tty ]] && command -v dialog >/dev/null 2>&1; then
    _TUI_BACKEND="dialog"
  else
    _TUI_BACKEND="stdin"
  fi
}

_tui_detect_backend

# ---- низкоуровневые обёртки ----
_tui_run() {
  if [[ "$_TUI_BACKEND" == "whiptail" ]]; then
    whiptail "$@" 3>&1 1>&2 2>&3
  elif [[ "$_TUI_BACKEND" == "dialog" ]]; then
    dialog "$@" 3>&1 1>&2 2>&3
  fi
}

# ---- высокоуровневые функции ----

# tui_info <title> <text>  — информационное окно (OK)
tui_info() {
  local title="$1" text="$2"
  case "$_TUI_BACKEND" in
    whiptail) whiptail --title "$title" --msgbox "$text" "$_TUI_HEIGHT" "$_TUI_WIDTH" ;;
    dialog)   dialog   --title "$title" --msgbox "$text" "$_TUI_HEIGHT" "$_TUI_WIDTH" ;;
    stdin)    printf '\n=== %s ===\n%s\n' "$title" "$text"; read -rp "Нажмите Enter..." ;;
  esac
}

# tui_yesno <title> <text>  -> 0 = yes, 1 = no
tui_yesno() {
  local title="$1" text="$2"
  case "$_TUI_BACKEND" in
    whiptail) whiptail --title "$title" --yesno "$text" "$_TUI_HEIGHT" "$_TUI_WIDTH" ;;
    dialog)   dialog   --title "$title" --yesno "$text" "$_TUI_HEIGHT" "$_TUI_WIDTH" ;;
    stdin)
      local ans
      while true; do
        printf '\n=== %s ===\n%s\n' "$title" "$text"
        read -rp "Введите y/n: " ans
        [[ "$ans" =~ ^[Yy]$ ]] && return 0
        [[ "$ans" =~ ^[Nn]$ ]] && return 1
      done
      ;;
  esac
}

# tui_input <title> <text> <default>  -> stdout
tui_input() {
  local title="$1" text="$2" default="${3:-}"
  case "$_TUI_BACKEND" in
    whiptail) whiptail --title "$title" --inputbox "$text" "$_TUI_HEIGHT" "$_TUI_WIDTH" "$default" ;;
    dialog)   dialog   --title "$title" --inputbox "$text" "$_TUI_HEIGHT" "$_TUI_WIDTH" "$default" ;;
    stdin)
      local _prompt="[$default]"
      printf '\n=== %s ===\n%s\nТекущее: %s\n' "$title" "$text" "$_prompt"
      read -rp "Значение: " val
      [[ -z "$val" && -n "$default" ]] && echo "$default" || echo "$val"
      ;;
  esac
}

# tui_password <title> <text>  -> stdout
tui_password() {
  local title="$1" text="$2"
  case "$_TUI_BACKEND" in
    whiptail) whiptail --title "$title" --passwordbox "$text" "$_TUI_HEIGHT" "$_TUI_WIDTH" ;;
    dialog)   dialog   --title "$title" --passwordbox "$text" "$_TUI_HEIGHT" "$_TUI_WIDTH" ;;
    stdin)
      printf '\n=== %s ===\n%s\n' "$title" "$text"
      read -rsp "Значение: " val; echo
      echo "$val"
      ;;
  esac
}

# tui_menu <title> <text> <item1> <desc1> <item2> <desc2> ...  -> stdout (item tag)
# (В stdin-режиме: показывает список, читает номер, возвращает tag.)
tui_menu() {
  local title="$1" text="$2"
  shift 2
  case "$_TUI_BACKEND" in
    whiptail) whiptail --title "$title" --menu "$text" "$_TUI_HEIGHT" "$_TUI_WIDTH" 10 "$@" ;;
    dialog)   dialog   --title "$title" --menu "$text" "$_TUI_HEIGHT" "$_TUI_WIDTH" 10 "$@" ;;
    stdin)
      printf '\n=== %s ===\n%s\n' "$title" "$text"
      local i=1 choice
      while [[ $# -gt 0 ]]; do
        printf '  %d) %-20s — %s\n' "$i" "$1" "$2"
        i=$((i+1)); shift 2
      done
      read -rp "Выберите номер: " choice
      # Найти tag по индексу
      local idx=1
      local -a args=("$@")
      while [[ $# -gt 0 ]]; do
        if [[ "$idx" -eq "$choice" ]]; then
          echo "$1"
          return 0
        fi
        idx=$((idx+1)); shift 2
      done
      echo "${args[0]:-}"
      ;;
  esac
}

# tui_checklist <title> <text> <tag1> <desc1> <on|off> <tag2> <desc2> <on|off> ...  -> stdout (space-separated tags)
tui_checklist() {
  local title="$1" text="$2"
  shift 2
  case "$_TUI_BACKEND" in
    whiptail) whiptail --title "$title" --separate-output --checklist "$text" "$_TUI_HEIGHT" "$_TUI_WIDTH" 10 "$@" ;;
    dialog)
      # dialog checklist: tag item status
      dialog   --title "$title" --separate-output --checklist "$text" "$_TUI_HEIGHT" "$_TUI_WIDTH" 10 "$@"
      ;;
    stdin)
      printf '\n=== %s ===\n%s\n(введите теги через пробел, пусто = ничего)\n' "$title" "$text"
      while [[ $# -gt 0 ]]; do
        printf '  [ ] %-15s — %s\n' "$1" "$2"
        shift 2
      done
      read -rp "Теги: " vals
      echo "$vals"
      ;;
  esac
}

# ---- gauge (progress bar) ----
_tui_gauge_pid=""

tui_gauge_start() {
  local title="$1" text="$2" percent="${3:-0}"
  case "$_TUI_BACKEND" in
    whiptail|dialog)
      {
        for ((p=percent; p<=100; p+=1)); do
          printf 'XXX\n%d\n%s (%d%%)\nXXX\n' "$p" "$text" "$p"
          sleep 0.05
        done
      } | ${_TUI_BACKEND} --title "$title" --gauge "$text" "$_TUI_HEIGHT" "$_TUI_WIDTH" "$percent" &
      _tui_gauge_pid=$!
      ;;
    stdin)
      printf '\n=== %s ===\n%s\n' "$title" "$text"
      ;;
  esac
}

tui_gauge_end() {
  if [[ -n "$_tui_gauge_pid" ]] && kill -0 "$_tui_gauge_pid" 2>/dev/null; then
    sleep 0.3
    kill "$_tui_gauge_pid" 2>/dev/null || true
    wait "$_tui_gauge_pid" 2>/dev/null || true
  fi
  _tui_gauge_pid=""
}

# Экспорт для отладки
tui_backend() { echo "$_TUI_BACKEND"; }
