# system/

Las reglas normativas de Talos, en la forma en que el agente las consume.

| Archivo | Qué es |
|---|---|
| [`00-enforcement.md`](00-enforcement.md) | cómo se fuerza una regla sobre un modelo. Leelo primero |
| [`rules.yaml`](rules.yaml) | el registro: cada regla con su mecanismo e implementación |

---

## El registro es el que manda

`talos-0.0.7.md` son 3000 líneas para una persona. `rules.yaml` es el mismo contenido en la forma que importa para gobernar: **cada requisito atado al mecanismo concreto que lo hace cumplir**.

```yaml
- id: R-EVID-002
  nivel_normativo: NO_DEBE
  requisito: Un rol agente no debe declarar que las pruebas pasaron; debe referenciar el reporte del adapter.
  mecanismo: 1
  implementacion:
    - schemas/task-result.schema.json
  spec_ref: talos-0.0.7.md#30-4-verificacion-de-pruebas
```

Sin el campo `mecanismo`, esa línea sería una aspiración. Con él, se puede verificar que la promesa tiene respaldo.

---

## La fuerza no se declara: se deriva

Una regla **no** dice qué tan fuerte es. Lo dice su mecanismo:

```txt
1-5   duro    -> el requisito ES obligatorio
6-8   medio   -> obligatorio, con ventana de violación
9-10  blando  -> consultivo, aunque el texto suene a orden
```

Guardar la fuerza como campo aparte permitiría que contradiga al mecanismo. Derivarla lo hace imposible.

---

## La auditoría es el propio mecanismo 1

El criterio 3 de `00-enforcement.md` pide que la auditoría de mapeo se ejecute sola y falle si aparece un `DEBE` sin respaldo. Eso **no** se implementó con un script a medida: se implementó con un schema.

`schemas/rules-registry.schema.json` hace que estos documentos no validen:

```txt
RECHAZA  DEBE con mecanismo 10 (solo un .md)
RECHAZA  NO_DEBE con mecanismo 9
RECHAZA  RECOMENDADO blando sin estrategia de guía
RECHAZA  mecanismo ejecutable sin nombrar quién lo ejecuta
```

Escribir `DEBE` sobre algo que solo está respaldado por un archivo de instrucciones **no es una mala práctica: es un documento inválido**. Talos se aplica a sí mismo el mecanismo que le exige a los demás.

---

## Estado real, sin maquillaje

27 reglas registradas:

| Fuerza | Reglas |
|---|---|
| dura | 24 |
| media | 1 |
| blanda | 2 |

| Mecanismo | Reglas |
|---|---|
| 1 — validación de schema | 14 |
| 2 — hook bloqueante pre-acción | 5 |
| 5 — protección de rama | 3 |
| 3 — check de CI | 1 |
| 4 — git hook | 1 |
| 7 — presencia de artefacto | 1 |
| 9 — contexto por rol | 1 |
| 10 — instrucción en `.md` | 1 |

Las tres reglas no duras están declaradas como tales, con su estrategia de guía asociada. Son las que dependen de juicio: que una revisión sea buena, que un criterio de aceptación sea testeable, que el Developer no amplíe el alcance. No se pueden forzar, y el registro no finge que sí.

Las tres de mecanismo 5 dependen de que alguien corra `tools/setup-branch-protection.sh`. Hasta entonces, están declaradas pero no activas — ver `00-enforcement.md` §5, regla 4: **Talos no debe afirmar que un requisito se cumple cuando su mecanismo no está disponible**.

---

## Verificar

```bash
python3 tests/test_rules.py
```

58 checks: que el registro valide, que los ids sean únicos, que ningún `DEBE` se apoye en mecanismo blando, que cada implementación citada exista en disco, y que cada `spec_ref` apunte a un archivo real.

Ese último es el que atrapa la deriva: una regla puede estar bien formada y citar un archivo que se borró hace tres commits.
