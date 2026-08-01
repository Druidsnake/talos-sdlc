// Plantilla del plugin de alcance. install.sh la copia al proyecto y le
// reemplaza __TALOS_SHIM__ por la ruta absoluta de pre-tool-use.sh.
//
// opencode descubre solo cualquier *.js o *.ts bajo .opencode/plugin/. El hook
// tool.execute.before se dispara ANTES de ejecutar la herramienta; si tira una
// excepcion, la llamada no ocurre. Ese es el unico mecanismo de bloqueo que
// expone el runtime, y es el que convierte al alcance en algo IMPUESTO y no
// declarado.
import { spawnSync } from "node:child_process";

const SHIM = "__TALOS_SHIM__";

export const TalosScope = async () => ({
  "tool.execute.before": async (input, output) => {
    const veredicto = spawnSync(SHIM, [], {
      input: JSON.stringify({ tool: input.tool, args: output.args }),
      encoding: "utf8",
    });

    // Fallar por no poder EJECUTAR el shim no es lo mismo que ser denegado.
    // Si el shim no corre, el alcance no se esta imponiendo, y seguir seria
    // trabajar sin bloqueo creyendo que hay uno.
    if (veredicto.error) {
      throw new Error(
        `talos: no se pudo ejecutar el bloqueo de alcance (${SHIM}): ${veredicto.error.message}`,
      );
    }
    if (veredicto.status !== 0) {
      const motivo = (veredicto.stderr || "").trim();
      throw new Error(motivo || "talos: DENEGADO por el alcance del rol");
    }
  },
});

export default TalosScope;
