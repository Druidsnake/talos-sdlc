#!/bin/sh
# Traduce modelo y proveedor a los argumentos NATIVOS de opencode.
#
# El nucleo resuelve tier -> modelo leyendo config/models.yaml y no sabe como
# se le pide un modelo a un agente concreto: eso es vocabulario del runtime, y
# vive en su shim. opencode lo toma como  -m provider/model.
#
# Si el proveedor no es opencode, no se emite nada. Pasarle a un runtime el id
# de un modelo de otro proveedor es peor que no pasar ninguno: arranca con una
# cadena que no resuelve y falla lejos de aca.
#
# Uso:  agent-args.sh <modelo> <proveedor>

set -eu

modelo="${1:-}"
proveedor="${2:-}"

# --auto NO relaja el alcance: lo mueve al lugar donde se puede imponer.
#
# Sin esto, el runtime le pide permiso a una persona por cada acceso fuera de
# lo obvio -leer /tmp, correr un comando- y el agente queda BLOQUEADO hasta que
# alguien conteste. Un sistema que despacha agentes para que trabajen solos y
# los deja esperando a un humano por cada paso no despacha nada.
#
# Lo que contiene al agente es el mecanismo 2: el plugin que Thalos instala en
# su runtime deniega toda escritura fuera del alcance del rol, y eso ocurre
# despues de --auto y sin consultarlo. El dialogo del runtime pregunta; el hook
# de Thalos decide. Ver system/00-enforcement.md seccion 3.
_auto="--auto"

[ "$proveedor" = "opencode" ] || exit 0
[ -n "$modelo" ] || { printf -- '%s' "$_auto"; exit 0; }

printf -- '--model %s %s' "$modelo" "$_auto"
