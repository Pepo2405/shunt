#!/usr/bin/env bash
# PostToolUse nudge: after the first grep/rg over a large file in a session, suggest bulk-read once.
# Never blocks. Any error => silent exit 0.
set -u
MIN="${SHUNT_MIN_LINES:-350}"
[ "${SHUNT_OFF:-0}" = "1" ] && exit 0
[ "${SHUNT_NO_NUDGE:-0}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)" || exit 0
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"; [ -z "$cwd" ] && cwd="$PWD"
sid="$(printf '%s' "$input" | jq -r '.session_id // "nosession"' 2>/dev/null)"
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
bulk="$root/scripts/bulk-read"
state="${TMPDIR:-/tmp}/shunt-nudge-$sid"; mkdir -p "$state" 2>/dev/null || exit 0

abs() { case "$1" in /*) printf '%s' "$1" ;; ~*) printf '%s' "${1/#\~/$HOME}" ;; *) printf '%s/%s' "$cwd" "$1" ;; esac; }

candidates=()
case "$tool" in
  Grep)
    p="$(printf '%s' "$input" | jq -r '.tool_input.path // empty')"; [ -n "$p" ] && candidates+=("$p") ;;
  Bash)
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
    printf '%s' "$cmd" | grep -Eq '(^|[;&| ])(grep|rg|egrep)[[:space:]]' || exit 0
    # Every token that names an existing regular file is a candidate.
    for tok in $(printf '%s' "$cmd" | tr '|;&' '   ' | sed -E "s/['\"]//g"); do
      case "$tok" in -*|grep|rg|egrep|head|tail|sort|uniq|wc|cut|awk|sed|xargs|find|cd) continue ;; esac
      f="$(abs "$tok")"; [ -f "$f" ] && candidates+=("$f")
    done ;;
  *) exit 0 ;;
esac
[ "${#candidates[@]}" -gt 0 ] || exit 0

big=(); shown=""
for f in "${candidates[@]}"; do
  f="$(abs "$f")"; [ -f "$f" ] || continue
  n="$(wc -l < "$f" | tr -d ' ')"; [ "$n" -gt "$MIN" ] 2>/dev/null || continue
  key="$(printf '%s' "$f" | shasum | cut -c1-16)"
  [ -e "$state/$key" ] && continue
  : > "$state/$key"
  big+=("$f"); shown="$shown ${f#$cwd/} ($n líneas)"
done
[ "${#big[@]}" -gt 0 ] || exit 0

files="$(printf '%s ' "${big[@]#$cwd/}")"
jq -cn --arg ctx "shunt: estás grepeando archivos grandes:$shown. Si estás explorando para entender cómo funciona algo (no buscando un identificador que ya conocés), una sola llamada reemplaza la cadena grep → Read → grep → Read y cita archivo:línea: $bulk --question \"<qué necesitás saber>\" $files (Haiku, ~15-30s). Aviso único por archivo." \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
exit 0
