#!/usr/bin/env bash
# PreToolUse guard: deny full reads of large files and point the model to bulk-read.
# Any internal error => allow (print nothing, exit 0). Never block work on a broken hook.
set -u

MIN="${SHUNT_MIN_LINES:-350}"
[ "${SHUNT_OFF:-0}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)" || exit 0
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$cwd" ] && cwd="$PWD"

root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
bulk="$root/scripts/bulk-read"

lines_of() {
  local p="$1"
  case "$p" in /*) ;; ~*) p="${p/#\~/$HOME}" ;; *) p="$cwd/$p" ;; esac
  [ -f "$p" ] || { echo 0; return; }
  wc -l < "$p" | tr -d ' '
}

deny() {
  local what="$1" n="$2" target="${3:-<archivos...>}"
  jq -cn --arg r "shunt: $what tiene $n líneas (umbral $MIN); no lo cargues entero en el contexto. Hacé UNA llamada con tu pregunta real en vez de encadenar grep y Reads parciales: $bulk --question \"<qué necesitás saber, pidiendo archivo:línea>\" $target  (corre Haiku, ~15s). Solo para editar: después usá Read con offset y limit sobre las líneas citadas. Desactivar: SHUNT_OFF=1." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

case "$tool" in
  Read)
    fp="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')"
    limit="$(printf '%s' "$input" | jq -r '.tool_input.limit // empty')"
    [ -z "$fp" ] && exit 0
    [ -n "$limit" ] && exit 0
    n="$(lines_of "$fp")"
    [ "$n" -gt "$MIN" ] 2>/dev/null && deny "$fp" "$n" "$fp"
    exit 0
    ;;
  Bash)
    cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty')"
    [ -z "$cmd" ] && exit 0
    # Split on ; && || and newlines; inspect each pipeline.
    printf '%s\n' "$cmd" | sed -E 's/&&|\|\||;/\n/g' | while IFS= read -r stmt; do
      # A pipeline whose output is consumed by a filter is fine.
      if printf '%s' "$stmt" | grep -Eq '\|'; then continue; fi
      # Strip redirections and leading env assignments.
      stmt="$(printf '%s' "$stmt" | sed -E 's/[0-9]*[<>]{1,2}[^ ]*//g; s/^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^ ]* )*//')"
      set -- $stmt
      [ $# -ge 2 ] || continue
      case "$1" in
        cat|bat)
          total=0; first=""
          shift
          for a in "$@"; do
            case "$a" in -*) continue ;; esac
            n="$(lines_of "$a")"; total=$((total + n)); [ -z "$first" ] && first="$a"
          done
          [ "$total" -gt "$MIN" ] && deny "cat ${first}…" "$total" "$first"
          ;;
        head|tail)
          shift; num=""
          while [ $# -gt 0 ]; do
            case "$1" in
              -n) num="$2"; shift 2 ;;
              -n*) num="${1#-n}"; shift ;;
              -[0-9]*) num="${1#-}"; shift ;;
              -*) shift ;;
              *) break ;;
            esac
          done
          num="${num//[^0-9]/}"
          [ -n "$num" ] && [ "$num" -gt "$MIN" ] && [ $# -ge 1 ] && [ "$(lines_of "$1")" -gt "$MIN" ] && deny "$1 (head/tail -n $num)" "$(lines_of "$1")" "$1"
          ;;
      esac
    done
    exit 0
    ;;
esac
exit 0
