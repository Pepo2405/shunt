---
name: bulk-read
description: Usar PRIMERO, antes de grep o Reads parciales, cuando hay que entender cómo funciona algo en un archivo de más de ~350 líneas o repartido en varios archivos. Una sola llamada reemplaza la cadena grep → Read → grep → Read y devuelve la respuesta con citas archivo:línea. También cuando el hook de shunt deniega un Read o un cat.
---

# bulk-read

Delegá la lectura de archivos grandes a un modelo barato. Vos formulás una pregunta concreta, el worker lee los archivos completos y te devuelve una respuesta con citas `archivo:línea`. Cuesta una llamada y unos 15 segundos; una cadena de grep y Reads parciales cuesta cinco o seis turnos y llena tu contexto de fragmentos que después no usás.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/bulk-read" --question "<pregunta concreta>" <archivo> [archivo...]
```

## Flujo recomendado

1. `wc -l` o el deny del hook te dicen que el archivo es grande.
2. **Una** llamada a `bulk-read` con la pregunta real que tenés, pidiendo ubicaciones.
3. Si vas a editar, `Read` con `offset` y `limit` sobre las líneas citadas. Nada más.

No hagas grep exploratorio antes del paso 2: la pregunta que le harías al grep es la que le hacés a `bulk-read`.

## Cuándo usarlo

- Entender qué hace un archivo o módulo grande antes de tocarlo.
- Ubicar dónde se implementa algo ("¿dónde se decide el siguiente track de la cola?").
- Seguir un flujo que cruza varios archivos ("¿cómo llega un click en la UI hasta el engine?"), pasándolos todos en la misma llamada.
- Cuando el hook denegó un `Read` o `cat`.

## Cuándo NO usarlo

- **Para editar.** Con la respuesta ubicá el rango y usá `Read` con `offset` y `limit`. El worker no reemplaza tu lectura del fragmento que vas a modificar.
- **Para razonamiento fino.** Bugs sutiles de concurrencia, invariantes, revisión de seguridad: eso lo hacés vos leyendo el fragmento relevante.
- **Archivos chicos.** Menos de ~350 líneas: leelos directo.
- **Buscar un identificador exacto.** Si ya sabés el nombre y solo querés la línea, `grep -n` es más rápido.

## Cómo preguntar bien

Una pregunta específica rinde más que "resumí este archivo". Pedí exactamente lo que necesitás saber para el próximo paso y pedí ubicaciones. Podés hacer varias preguntas en una sola llamada, numeradas.

## Variables

- `SHUNT_MIN_LINES` (350): umbral del hook.
- `SHUNT_MODEL` (haiku): modelo worker.
- `SHUNT_OFF=1`: desactiva el hook.
