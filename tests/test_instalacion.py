#!/usr/bin/env python3
"""Donde vive Thalos cuando se lo invoca. Ver thalos-0.0.7.md seccion 8.

Hay dos formas de tenerlo y no compiten: vendoreado en `.thalos/` del proyecto
-que fija una version para ese proyecto- o instalado una sola vez y accesible
por el PATH.

Lo que se verifica aca es que la raiz del SISTEMA se resuelva bien en las dos,
porque confundirla hace que Thalos busque su propia configuracion donde vive el
producto, o el spec del producto dentro de si mismo.
"""
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent


def check(label, cond, detail=""):
    if cond:
        print(f"  ok   {label}")
        return True
    print(f"  FALLA {label}")
    if detail:
        print(f"       {detail}")
    return False


def corre(lanzador, cwd, *args, env=None):
    e = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"),
         "HOME": str(pathlib.Path.home())}
    if env:
        e.update(env)
    p = subprocess.run([str(lanzador), *args], capture_output=True, text=True,
                       cwd=str(cwd), env=e)
    return p.returncode, p.stdout + p.stderr


def raiz_reportada(lanzador, cwd, env=None):
    """La raiz del sistema tal como la ve el propio lanzador."""
    e = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"),
         "HOME": str(pathlib.Path.home())}
    if env:
        e.update(env)
    p = subprocess.run(
        ["sh", "-c", f'THALOS_ECHO_ROOT=1 "{lanzador}" version >/dev/null 2>&1;'
                     f' "{lanzador}" adapters --format json 2>/dev/null | head -1'],
        capture_output=True, text=True, cwd=str(cwd), env=e)
    return p.stdout


def main():
    results = []
    proyecto = pathlib.Path(tempfile.mkdtemp()) / "proyecto"
    proyecto.mkdir(parents=True)

    # ---------- invocado por su ruta real ----------
    directo = ROOT / "cli" / "thalos"
    rc, out = corre(directo, proyecto, "version")
    results.append(check(
        "invocado por su ruta real, arranca",
        rc == 0 and "thalos" in out, f"rc={rc} {out[:120]}"))

    # ---------- invocado por un ENLACE en el PATH ----------
    #
    # EL CASO QUE NO ANDABA. El lanzador derivaba la raiz del sistema de
    # dirname($0). Con un enlace en ~/.local/bin, dirname da ~/.local/bin y la
    # raiz salia ~/.local: Thalos se buscaba a si mismo donde no estaba y
    # fallaba con archivos que si existen, en otro lado.
    bin_dir = pathlib.Path(tempfile.mkdtemp()) / "bin"
    bin_dir.mkdir(parents=True)
    enlace = bin_dir / "thalos"
    enlace.symlink_to(directo)

    rc, out = corre(enlace, proyecto, "version")
    results.append(check(
        "invocado por un enlace en el PATH, tambien arranca",
        rc == 0 and "thalos" in out, f"rc={rc} {out[:160]}"))

    rc, out = corre(enlace, proyecto, "rules")
    results.append(check(
        "y encuentra sus propios archivos, no los busca junto al enlace",
        rc == 0 and "R-ROLE-001" in out, f"rc={rc} {out[:160]}"))

    # Un enlace al enlace: sigue la cadena entera.
    bin2 = pathlib.Path(tempfile.mkdtemp()) / "bin"
    bin2.mkdir(parents=True)
    enlace2 = bin2 / "thalos"
    enlace2.symlink_to(enlace)
    rc, out = corre(enlace2, proyecto, "rules")
    results.append(check(
        "resuelve una cadena de enlaces, no solo el primero",
        rc == 0 and "R-ROLE-001" in out, f"rc={rc} {out[:160]}"))

    # ---------- el proyecto sigue mandando sobre su propia version ----------
    #
    # Un proyecto que vendorea `.thalos/` fijo una version a proposito. Correrle
    # encima el Thalos global seria ejecutar otra version contra sus artefactos,
    # que es justo lo que la seccion 12.3 trata como migracion y no como rutina.
    vend = pathlib.Path(tempfile.mkdtemp()) / "vendoreado"
    (vend / ".thalos" / "cli").mkdir(parents=True)
    marca = vend / ".thalos" / "cli" / "thalos"
    marca.write_text("#!/bin/sh\necho VENDOREADO-GANA\n")
    marca.chmod(0o755)

    rc, out = corre(enlace, vend, "version")
    results.append(check(
        "si el proyecto vendorea .thalos, ese gana sobre el global",
        "VENDOREADO-GANA" in out, f"rc={rc} {out[:160]}"))

    rc, out = corre(enlace, proyecto, "version")
    results.append(check(
        "y sin .thalos en el proyecto, sigue usando el global",
        rc == 0 and "VENDOREADO" not in out, f"rc={rc} {out[:160]}"))

    # ---------- la salida explicita manda sobre las dos ----------
    rc, out = corre(enlace, vend, "version",
                    env={"THALOS_SYSTEM_ROOT": str(ROOT)})
    results.append(check(
        "THALOS_SYSTEM_ROOT explicito gana sobre el vendoreado",
        "VENDOREADO-GANA" not in out and rc == 0, f"rc={rc} {out[:160]}"))

    print()
    ok = sum(1 for x in results if x)
    print(f"{ok}/{len(results)} checks de instalacion")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
