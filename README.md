# CS2 en Mac

Un lanzador abierto para ejecutar **el Counter-Strike 2 original de Valve** en
Mac con Apple Silicon mediante compatibilidad. Cada usuario usa el Steam oficial
de Windows, su cuenta y la descarga original del juego.

El lanzador está compilado para ARM64. El juego conserva sus binarios Windows
x86_64 y utiliza Wine, traducción Intel/Rosetta y DXMT. No es una recompilación
nativa del motor ni una reimplementación del gameplay.

**Primera prueba lograda en el equipo de desarrollo:** el usuario confirmó
inicio de sesión en Steam, un deathmatch offline y juego online en servidores
oficiales. El rendimiento todavía requiere optimización. Ver el
[registro de validación](docs/compatibility-validation.json).

## Lo implementado

- App macOS con apertura de Steam, diagnóstico y solicitud de cierre normal.
- Uso opcional de una instalación existente de Steam en CrossOver.
- Preparación de un entorno separado con Wine/DXMT descargados del proveedor y
  verificados por SHA-256, sin depender de una licencia de CrossOver.
- Instalador oficial de Steam; el usuario completa su instalación e inicia sesión
  en la interfaz de Valve.
- Reutilización de una instalación Windows mediante copia APFS independiente,
  sin compartir archivos modificables con la biblioteca original.
- Pruebas sintéticas del lanzador y del inspector PE/VPK de la investigación inicial.

El entorno abierto y el instalador de Steam se ejecutaron en el equipo de prueba.
Steam actualizó CS2 al build `26144732` y lanzó el ejecutable original.
La confirmación visual y de juego proviene del usuario; la herramienta de control
no pudo leer las ventanas posteriores a la actualización de Steam. Esto valida
una primera prueba, no compatibilidad universal ni rendimiento garantizado.

## Compilar y abrir

Para desarrollar: Apple Silicon, Xcode Command Line Tools y Python 3.9+ para las
pruebas. El lanzador compilado no necesita Python.

```sh
make install-app
```

Abrí **CS2 en Mac** en `~/Applications`. La aplicación ofrece:

1. **Instalar Rosetta…**: abre el instalador de Apple, que presenta su licencia.
2. **Preparar Steam**: prepara Wine/DXMT y abre el instalador oficial de Steam.
3. **Abrir Steam**: iniciá sesión, instalá CS2 y pulsá **Jugar** dentro de Steam.

Si la actualización inicial de Steam queda en «Iniciando Steam», esperá unos
segundos y pulsá **Abrir Steam** otra vez. El lanzador puede recuperar ese relevo
inicial de forma acotada; no programa reinicios en segundo plano.

Si ya tenés Steam y CS2 en CrossOver, elegí **Usar CrossOver existente…** y
seleccioná esa botella. Para el entorno abierto, **Reutilizar CS2 instalado…**
requiere completar primero la instalación de Steam. Con Steam cerrado, copia
el contenido existente en APFS sin una segunda descarga completa. Steam
puede necesitar espacio y red para verificar o actualizar el juego.

Los datos propios viven en `~/Library/Application Support/CS2Mac`; no se comparte
la biblioteca con Steam de macOS. Las credenciales se introducen únicamente en
Steam. La app no lee ni exporta contraseñas o tickets.

## Línea de comandos y pruebas

```sh
make check
'.build/CS2 en Mac.app/Contents/MacOS/cs2mac' doctor --json
'.build/CS2 en Mac.app/Contents/MacOS/cs2mac' steam --dry-run
make dist
```

`make dist` genera `artifacts/CS2Mac-0.2.0-arm64.zip`, con la app y sus documentos;
no incluye Wine, Steam ni archivos de CS2. La firma actual es ad hoc para pruebas,
sin notarización de distribución. El deployment target del lanzador es macOS 13;
su interfaz se comprobó en macOS 27. Otras versiones y equipos siguen pendientes.

Más instrucciones y límites en [el flujo de compatibilidad](docs/compatibility.md).

## Investigación y procedencia

La investigación estática anterior se conserva en
[initial-findings.md](docs/initial-findings.md),
[artifact-baseline.json](docs/artifact-baseline.json) y
[resources.md](docs/resources.md). El inspector C++ se compila con
`make .build/cs2-native-lab`. Sus resultados no demuestran ejecución del juego.

El código original del proyecto es [MIT](LICENSE). Cada componente externo conserva
su licencia: [THIRD_PARTY.md](THIRD_PARTY.md). No se distribuyen recursos de Valve,
fuentes filtradas ni pseudocódigo del juego. Proyecto comunitario sin afiliación
con Valve, Apple o CodeWeavers.
