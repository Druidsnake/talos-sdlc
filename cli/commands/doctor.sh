#!/bin/sh
# talos doctor - verifica preconditions y reporta el nivel de enforcement REAL.
#
# No afirma que un requisito se cumple cuando su mecanismo no esta disponible.
# Ver system/00-enforcement.md 5.4.
#
# Sale 0 si todo lo requerido pasa, 2 si falla una precondition requerida.

set -eu

SYS="${TALOS_SYSTEM_ROOT:?}"
PROJ="${TALOS_PROJECT_ROOT:?}"
cd "$PROJ"

usage() {
    cat <<'USAGE'
talos doctor - verifica preconditions y reporta el nivel de enforcement real

USO
    talos doctor [--format json]

QUE VERIFICA
    git, identidad, remoto y autenticacion de gh
    validador de JSON Schema disponible
    artefactos del sistema presentes
    spec del producto, si existe
    runtime inicializado
    cuales de los 5 mecanismos de enforcement estan activos

NIVEL DE INSTALACION
    L0  solo documentacion, sin enforcement
    L1  valida artefactos y commits
    L2  gobierna el ciclo completo

    No afirma que un requisito se cumple cuando su mecanismo no esta
    disponible. Ver system/00-enforcement.md seccion 5.

SALIDA
    0  todas las preconditions requeridas pasan
    2  falla al menos una precondition requerida
USAGE
}
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

FORMAT=text
[ "${1:-}" = "--format" ] && [ "${2:-}" = "json" ] && FORMAT=json

fails=0
warns=0
rows=""

# estado|requerido|id|detalle|remediacion
record() {
    rows="${rows}$1|$2|$3|$4|$5
"
    [ "$1" = "fail" ] && [ "$2" = "si" ] && fails=$((fails + 1))
    [ "$1" = "warn" ] && warns=$((warns + 1))
    return 0
}

have() { command -v "$1" >/dev/null 2>&1; }

# ---------- git ----------
if have git; then
    record ok si git "$(git --version | head -1)" ""
else
    record fail si git "no instalado" "instala git"
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    record ok si repositorio "$(git rev-parse --show-toplevel)" ""

    name=$(git config user.name 2>/dev/null || true)
    mail=$(git config user.email 2>/dev/null || true)
    if [ -n "$name" ] && [ -n "$mail" ]; then
        record ok si identidad_git "$name <$mail>" ""
    else
        record fail si identidad_git "sin configurar" "git config user.name / user.email"
    fi

    if origin=$(git remote get-url origin 2>/dev/null); then
        record ok no remoto "$origin" ""
    else
        record warn no remoto "sin remoto origin" "git remote add origin <url>"
    fi

    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
    record ok no rama_actual "$branch" ""
else
    record fail si repositorio "no es un repositorio git" "git init"
fi

if have gh; then
    if gh auth status >/dev/null 2>&1; then
        who=$(gh api user --jq .login 2>/dev/null || echo "?")
        record ok no gh_auth "$who" ""
    else
        record warn no gh_auth "sin autenticar" "gh auth login"
    fi
else
    record warn no gh_auth "gh no instalado" "brew install gh"
fi

# ---------- validador ----------
# shellcheck source=../../hooks/lib/resolve-validator.sh
. "$SYS/hooks/lib/resolve-validator.sh"
if impl=$(talos_resolve_validator); then
    record ok si validador "$impl" ""
else
    record fail si validador "ninguno disponible" \
        "python3 -m venv .venv && .venv/bin/pip install jsonschema pyyaml"
fi

# ---------- artefactos del sistema ----------
# roles/ pasa a ser requerido: sin las instrucciones no se puede despachar
# un agente con rol, y despacharlo sin rol seria despacharlo sin scope.
for f in VERSION system/rules.yaml config/roles.yaml hooks/generated/write-scope.rules roles/developer.md; do
    if [ -f "$SYS/$f" ]; then
        record ok si "archivo:$f" "presente" ""
    else
        record fail si "archivo:$f" "falta" "reinstala Talos"
    fi
done

n_schemas=$(find "$SYS/schemas" -name '*.schema.json' 2>/dev/null | wc -l | tr -d ' ')
if [ "$n_schemas" -gt 0 ]; then
    record ok si schemas "$n_schemas contratos" ""
else
    record fail si schemas "sin schemas" "reinstala Talos"
fi

# ---------- modo de operacion y capacidades (preconditions 27.1.15 y 37.4.3) ----------
#
# El nucleo no nombra implementaciones: lee la ligadura que declara el
# registry. Ver hooks/lib/resolve-capability.sh.
# shellcheck source=../../hooks/lib/resolve-capability.sh
. "$SYS/hooks/lib/resolve-capability.sh"

if [ -f "$SYS/config/system.yaml" ]; then
    exec_mode=$(grep -E '^execution_mode:' "$SYS/config/system.yaml" | head -1 \
                | sed 's/execution_mode:[[:space:]]*//' | tr -d '"')
    if [ -n "$exec_mode" ]; then
        record ok si modo_ejecucion "$exec_mode" ""
    else
        record fail si modo_ejecucion "sin declarar" "declara execution_mode en config/system.yaml"
    fi
else
    exec_mode=""
    record fail si modo_ejecucion "falta config/system.yaml" "reinstala Talos"
fi

if talos_capability_table >/dev/null 2>&1; then
    cap_rows=$(talos_capability_audit || true)
    cap_fails=$(talos_capability_failures "$cap_rows")
    n_bound=$(talos_capability_table | awk -F'\t' '$3 != "-"' | wc -l | tr -d ' ')
    if [ "$cap_fails" -eq 0 ]; then
        record ok si capacidades "$n_bound ligadas, requeridas sanas" ""
    else
        record fail si capacidades "$cap_fails requerida(s) sin satisfacer" "talos adapters"
    fi
else
    record fail si capacidades "sin tabla de capacidades" "python3 tools/build-registry.py"
fi

# Regla 37.4.5.6: reportar la ruta resuelta de cada binario externo. Talos no
# instala nada; cuando falta, muestra el comando exacto (regla 37.4.5.5).
# El bucle NO puede ir detras de un pipe: record acumula en una variable, y en
# un subshell ese acumulado se pierde al cerrar. Se captura primero.
bin_rows=$(talos_capability_binaries 2>/dev/null || true)
while IFS='|' read -r bcap bbin brange bpath; do
    [ -z "$bcap" ] && continue
    if [ "$bpath" = "-" ]; then
        record fail si "binario:$bbin" "no resuelto, requiere $brange" \
            "instala $bbin o define TALOS_$(printf '%s' "$bbin" | tr 'a-z' 'A-Z')_BIN"
    else
        record ok si "binario:$bbin" "$bpath ($brange)" ""
    fi
done <<EOF
$bin_rows
EOF

# ---------- spec del producto ----------
if [ -f spec/manifest.yaml ]; then
    if [ "$FORMAT" = json ] || "$SYS/hooks/validate-artifact.sh" spec-manifest spec/manifest.yaml >/dev/null 2>&1; then
        if "$SYS/hooks/validate-artifact.sh" spec-manifest spec/manifest.yaml >/dev/null 2>&1; then
            st=$(grep -E '^status:' spec/manifest.yaml | head -1 | sed 's/status:[[:space:]]*//' | tr -d '"')
            record ok no spec "valido, status=$st" ""
        else
            record fail no spec "no valida contra su schema" "talos spec check"
        fi
    fi
else
    record warn no spec "no existe spec/manifest.yaml" "talos init genera un esqueleto"
fi

# ---------- runtime ----------
if [ -f orchestration/.meta.json ]; then
    record ok no runtime "inicializado" ""
else
    record warn no runtime "sin inicializar" "talos init"
fi

# ---------- mecanismos de enforcement ----------
mech_status() {
    case "$1" in
        1) [ -x "$SYS/hooks/validate-artifact.sh" ] && [ "$n_schemas" -gt 0 ] && echo activo || echo inactivo ;;
        2) [ -x "$SYS/hooks/check-write-scope.sh" ] && [ -f "$SYS/hooks/generated/write-scope.rules" ] && echo activo || echo inactivo ;;
        3) [ -f .github/workflows/talos.yml ] && echo activo || echo inactivo ;;
        4) { [ -e .git/hooks/pre-commit ] && [ -e .git/hooks/commit-msg ]; } && echo activo || echo inactivo ;;
        5) if have gh && git remote get-url origin >/dev/null 2>&1; then
               repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo "")
               if [ -n "$repo" ] && gh api "repos/$repo/branches/main/protection" >/dev/null 2>&1; then
                   echo activo
               else
                   echo inactivo
               fi
           else
               echo desconocido
           fi ;;
    esac
}

m1=$(mech_status 1); m2=$(mech_status 2); m3=$(mech_status 3)
m4=$(mech_status 4); m5=$(mech_status 5)

activos=0
for m in "$m1" "$m2" "$m3" "$m4" "$m5"; do
    [ "$m" = activo ] && activos=$((activos + 1))
done

if [ "$m1" = activo ] && [ "$m3" = activo ] && [ "$m4" = activo ]; then
    level=L2
    [ "$m5" = activo ] || level=L1
else
    level=L0
fi

# ---------- salida ----------
if [ "$FORMAT" = json ]; then
    printf '{\n  "talos_version": "%s",\n  "install_level": "%s",\n' \
        "${TALOS_VERSION:-?}" "$level"
    printf '  "mechanisms": {"1": "%s", "2": "%s", "3": "%s", "4": "%s", "5": "%s"},\n' \
        "$m1" "$m2" "$m3" "$m4" "$m5"
    printf '  "checks": [\n'
    first=1
    printf '%s' "$rows" | while IFS='|' read -r st req id detail rem; do
        [ -z "$st" ] && continue
        [ "$first" -eq 0 ] && printf ',\n'
        first=0
        printf '    {"id": "%s", "status": "%s", "required": %s, "detail": "%s"}' \
            "$id" "$st" "$([ "$req" = si ] && echo true || echo false)" "$detail"
    done
    printf '\n  ],\n  "failed": %s\n}\n' "$fails"
else
    echo "talos ${TALOS_VERSION:-?}"
    echo ""
    printf '%s' "$rows" | while IFS='|' read -r st req id detail rem; do
        [ -z "$st" ] && continue
        case "$st" in
            ok)   mark="ok  " ;;
            warn) mark="warn" ;;
            fail) mark="FALL" ;;
        esac
        req_mark=""
        [ "$req" = si ] && req_mark=" (requerido)"
        printf '  %s  %-28s %s%s\n' "$mark" "$id" "$detail" "$req_mark"
        # El cuerpo del bucle debe terminar en exito: con set -e, una ultima
        # fila sin remediacion hacia salir 1 al propio doctor.
        if [ -n "$rem" ]; then
            printf '        -> %s\n' "$rem"
        fi
    done

    echo ""
    echo "  mecanismos de enforcement"
    printf '    1 validacion de schema        %s\n' "$m1"
    printf '    2 hook bloqueante pre-accion  %s\n' "$m2"
    printf '    3 check de CI                 %s\n' "$m3"
    printf '    4 git hooks                   %s\n' "$m4"
    printf '    5 proteccion de rama          %s\n' "$m5"
    echo ""
    echo "  nivel de instalacion: $level  ($activos/5 mecanismos activos)"
    case "$level" in
        L0) echo "  L0 es documentacion, no gobierno. Ver system/00-enforcement.md 5." ;;
        L1) echo "  L1 verifica artefactos y commits. Falta proteccion de rama para L2." ;;
        L2) echo "  L2 gobierna el ciclo completo." ;;
    esac
    echo ""
    if [ "$fails" -gt 0 ]; then
        echo "  $fails precondition(s) requerida(s) fallando"
    else
        echo "  preconditions requeridas: OK"
    fi
fi

[ "$fails" -gt 0 ] && exit 2
exit 0
