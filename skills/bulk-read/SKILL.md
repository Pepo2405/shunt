---
name: bulk-read
description: Usar cuando necesitás entender o responder una pregunta sobre archivos largos (más de ~350 líneas) sin cargarlos en el contexto. También cuando el hook de shunt deniega un Read o un cat por tamaño.
---

# bulk-read

Delegá la lectura de archivos grandes a un modelo barato. Vos formulás una pregunta concreta, el worker lee los archivos completos y te devuelve una respuesta con citas `archivo:línea`.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/bulk-read" --question "<pregunta concreta>" <archivo> [archivo...]
```

## Cuándo usarlo

- Entender qué hace un archivo o módulo grande antes de tocarlo.
- Ubicar dónde se implementa algo ("¿dónde se decide el siguiente track de la cola?").
- Comparar varios archivos a la vez ("¿qué diferencia hay entre estos dos handlers?").
- Cuando el hook denegó un `Read` o `cat` y no necesitás editar todavía.

## Cuándo NO usarlo

- **Para editar.** Con la respuesta ubicá el rango y usá `Read` con `offset` y `limit`, o `grep -n`. El worker no reemplaza tu lectura del fragmento que vas a modificar.
- **Para razonamiento fino.** Bugs sutiles de concurrencia, invariantes, revisión de seguridad: eso lo hacés vos leyendo el fragmento relevante.
- **Archivos chicos.** Menos de ~350 líneas: leelos directo, la ida y vuelta no vale la pena.

## Cómo preguntar bien

Una pregunta específica rinde más que "resumí este archivo". Pedí exactamente lo que necesitás saber para el próximo paso, y pedí ubicaciones. Podés encadenar: una primera pregunta amplia para orientarte, después `Read` acotado sobre las líneas citadas.

## Variables

- `SHUNT_MIN_LINES` (350): umbral del hook.
- `SHUNT_MODEL` (haiku): modelo worker.
- `SHUNT_OFF=1`: desactiva el hook.
