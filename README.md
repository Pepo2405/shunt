# shunt

Plugin de Claude Code que desvía las lecturas de archivos grandes a un modelo barato, para que el modelo principal no gaste contexto en I/O. Inspirado en [Portal by Spotify cut my Claude Code token usage by 90%](https://engineering.atspotify.com/2026/9/portal-by-spotify-cut-my-claude-code-token-usage-by-90), pero sin Portal: el worker es Haiku vía `claude -p`, con tu misma suscripción.

## Qué hace

- **Hook `PreToolUse`** sobre `Read` y `Bash`. Deniega `Read` de archivos con más de 350 líneas cuando no hay `limit`, y `cat`/`bat`/`head -n N` grandes en Bash cuando la salida no va a un filtro (`head`, `grep`, `wc`, etc.). El mensaje de deny le dice al modelo qué hacer en su lugar.
- **Hook `PostToolUse`** sobre `Bash` y `Grep`. Tras el primer `grep`/`rg` sobre un archivo grande en la sesión, inyecta un aviso sugiriendo `bulk-read`. Una vez por archivo y sesión; no bloquea nada.
- **`scripts/bulk-read`**: recibe una pregunta y N archivos, los numera, los manda a Haiku con un system prompt mínimo (sin tools, sin MCP, sin settings: ~400 tokens de overhead) y devuelve una respuesta con citas `archivo:línea`.
- **Skill `bulk-read`**: cuándo delegar y cuándo no.

Lo que no hace, a propósito: no delega edits ni razonamiento fino. Después de `bulk-read`, el modelo principal lee con `Read` + `offset`/`limit` el rango que va a tocar.

## Instalación

```bash
claude plugin marketplace add Pepo2405/shunt
claude plugin install shunt@shunt
```

Requiere `jq` y el CLI `claude` en el PATH.

## Uso

El hook actúa solo. Para consultar a mano:

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/bulk-read" --question "¿Dónde se decide el siguiente track?" core/src/player/engine.rs
```

## Configuración

| Variable | Default | Efecto |
|---|---|---|
| `SHUNT_MIN_LINES` | `350` | Umbral de líneas para denegar |
| `SHUNT_MODEL` | `haiku` | Modelo worker |
| `SHUNT_MAX_BYTES` | `800000` | Tamaño total máximo por consulta |
| `SHUNT_OFF` | | `1` desactiva ambos hooks |
| `SHUNT_NO_NUDGE` | | `1` desactiva solo el aviso PostToolUse |

## Tests

```bash
bash tests/run.sh
```

Ejecuta el hook contra llamadas simuladas y verifica allow/deny.
