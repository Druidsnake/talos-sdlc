#!/usr/bin/env python3
"""Lee un valor de una config de Thalos. Ver thalos-0.0.7.md seccion 43.

POR QUE EXISTE

Los umbrales viven en config/ (regla 43.3) y quien los necesita es shell. Sin
un lector, cada comando terminaba haciendo su propio sed, y un sed sobre YAML
anidado solo funciona mientras la clave sea unica en todo el archivo:
`max_attempts` aparece en siete operaciones distintas de reliability.yaml y
cualquier sed devuelve la primera, que casi nunca es la que se pedia.

DEGRADA, NO ROMPE

Sin pyyaml devuelve el default. Un umbral que no se pudo leer no debe tumbar
un despacho: el default es el mismo numero que la spec documenta, asi que el
comportamiento sigue siendo el especificado aunque el archivo no se lea.

USO
    config.py <archivo> <ruta.con.puntos> [default]

SALIDA
    El valor por salida estandar. Sale 0 siempre que haya algo que imprimir,
    1 si no hay valor ni default.
"""
import pathlib
import sys


def leer(archivo, ruta, default=None):
    try:
        import yaml
    except ImportError:
        return default
    try:
        doc = yaml.safe_load(pathlib.Path(archivo).read_text())
    except (OSError, ValueError):
        return default
    cur = doc
    for parte in ruta.split("."):
        if not isinstance(cur, dict) or parte not in cur:
            return default
        cur = cur[parte]
    if isinstance(cur, (dict, list)):
        return default
    return cur


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        return 1
    default = argv[3] if len(argv) > 3 else None
    v = leer(argv[1], argv[2], default)
    if v is None:
        return 1
    print(v if not isinstance(v, bool) else str(v).lower())
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
