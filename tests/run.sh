#!/usr/bin/env bash
# Runs the PreToolUse guard against simulated tool calls and checks allow/deny.
set -u
cd "$(dirname "$0")"
HOOK="../hooks/check.sh"
big="$PWD/fixtures/big.txt"; small="$PWD/fixtures/small.txt"
seq 1 500 > "$big"; seq 1 50 > "$small"

pass=0; fail=0
check() { # name expected(json) tool_name tool_input(json)
  local name="$1" expected="$2" tool="$3" tin="$4"
  local out; out="$(jq -cn --arg t "$tool" --argjson i "$tin" --arg c "$PWD" '{tool_name:$t,tool_input:$i,cwd:$c}' | CLAUDE_PLUGIN_ROOT="$PWD/.." bash "$HOOK")"
  local got="allow"; printf '%s' "$out" | grep -q '"permissionDecision":"deny"' && got="deny"
  if [ "$got" = "$expected" ]; then pass=$((pass+1)); echo "ok    $name"; else fail=$((fail+1)); echo "FAIL  $name  (esperado $expected, obtuvo $got) -> $out"; fi
}

check "Read grande sin limit"            deny  Read "$(jq -cn --arg p "$big" '{file_path:$p}')"
check "Read grande con offset+limit"     allow Read "$(jq -cn --arg p "$big" '{file_path:$p,offset:100,limit:80}')"
check "Read chico"                       allow Read "$(jq -cn --arg p "$small" '{file_path:$p}')"
check "Read path relativo grande"        deny  Read '{"file_path":"fixtures/big.txt"}'
check "Read inexistente"                 allow Read '{"file_path":"/nope/nada.rs"}'
check "cat grande"                       deny  Bash "$(jq -cn --arg c "cat $big" '{command:$c}')"
check "cat chico"                        allow Bash "$(jq -cn --arg c "cat $small" '{command:$c}')"
check "cat grande | head"                allow Bash "$(jq -cn --arg c "cat $big | head -20" '{command:$c}')"
check "cat grande | grep"                allow Bash "$(jq -cn --arg c "cat $big | grep -n foo" '{command:$c}')"
check "cat con -n y redirección"         deny  Bash "$(jq -cn --arg c "cat -n $big 2>/dev/null" '{command:$c}')"
check "dos cats chicos que suman >350"   deny  Bash "$(jq -cn --arg c "cat $small $big" '{command:$c}')"
check "echo && cat grande"               deny  Bash "$(jq -cn --arg c "echo hi && cat $big" '{command:$c}')"
check "head -n 20 grande"                allow Bash "$(jq -cn --arg c "head -n 20 $big" '{command:$c}')"
check "head -n 400 grande"               deny  Bash "$(jq -cn --arg c "head -n 400 $big" '{command:$c}')"
check "head -400 grande"                 deny  Bash "$(jq -cn --arg c "head -400 $big" '{command:$c}')"
check "sed -n rango"                     allow Bash "$(jq -cn --arg c "sed -n '100,150p' $big" '{command:$c}')"
check "grep grande"                      allow Bash "$(jq -cn --arg c "grep -n foo $big" '{command:$c}')"
check "wc -l grande"                     allow Bash "$(jq -cn --arg c "wc -l $big" '{command:$c}')"
# SHUNT_OFF case needs env; redo explicitly
out="$(jq -cn --arg p "$big" '{tool_name:"Read",tool_input:{file_path:$p},cwd:"/"}' | SHUNT_OFF=1 bash "$HOOK")"
if [ -z "$out" ]; then pass=$((pass+1)); echo "ok    SHUNT_OFF=1 desactiva"; else fail=$((fail+1)); echo "FAIL  SHUNT_OFF=1 -> $out"; fi
out="$(jq -cn --arg p "$big" '{tool_name:"Read",tool_input:{file_path:$p},cwd:"/"}' | SHUNT_MIN_LINES=1000 bash "$HOOK")"
if [ -z "$out" ]; then pass=$((pass+1)); echo "ok    SHUNT_MIN_LINES=1000 permite 500"; else fail=$((fail+1)); echo "FAIL  SHUNT_MIN_LINES -> $out"; fi
out="$(printf 'esto no es json' | bash "$HOOK")"
if [ -z "$out" ]; then pass=$((pass+1)); echo "ok    input roto => allow"; else fail=$((fail+1)); echo "FAIL  input roto -> $out"; fi

# --- nudge (PostToolUse) ---
NUDGE="../hooks/nudge.sh"; SID="test-$$"; rm -rf "${TMPDIR:-/tmp}/shunt-nudge-$SID"
nudge() { jq -cn --arg t "$1" --argjson i "$2" --arg c "$PWD" --arg s "$SID" '{tool_name:$t,tool_input:$i,cwd:$c,session_id:$s}' | CLAUDE_PLUGIN_ROOT="$PWD/.." bash "$NUDGE"; }
expect() { local name="$1" exp="$2" out="$3"; local got="silent"; printf '%s' "$out" | grep -q additionalContext && got="nudge"
  if [ "$got" = "$exp" ]; then pass=$((pass+1)); echo "ok    $name"; else fail=$((fail+1)); echo "FAIL  $name (esperado $exp, obtuvo $got) -> $out"; fi; }
expect "nudge: grep en archivo grande"        nudge  "$(nudge Bash "$(jq -cn --arg c "grep -n foo $big" '{command:$c}')")"
expect "nudge: segunda vez mismo archivo"     silent "$(nudge Bash "$(jq -cn --arg c "grep -n bar $big" '{command:$c}')")"
expect "nudge: grep en archivo chico"         silent "$(nudge Bash "$(jq -cn --arg c "grep -n foo $small" '{command:$c}')")"
expect "nudge: cat no dispara"                silent "$(nudge Bash "$(jq -cn --arg c "cat $small" '{command:$c}')")"
expect "nudge: Grep tool path relativo"       nudge  "$(SID="$SID-b" nudge Grep '{"pattern":"foo","path":"fixtures/big.txt"}')"
expect "nudge: SHUNT_NO_NUDGE"                silent "$(SHUNT_NO_NUDGE=1 SID="$SID-c" nudge Bash "$(jq -cn --arg c "grep -n foo $big" '{command:$c}')")"
expect "nudge: input roto"                    silent "$(printf 'nope' | bash "$NUDGE")"
rm -rf "${TMPDIR:-/tmp}"/shunt-nudge-"$SID"*

rm -f "$big" "$small"
echo; echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
