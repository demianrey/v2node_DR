# v2node (Mod Español)
Un backend de V2board basado en un xray-core modificado.

**Nota: Este proyecto requiere usarse junto con [V2board modificado](https://github.com/wyx2685/v2board)**

## Instalacion del software

### Instalacion con un solo comando

```
wget -N https://raw.githubusercontent.com/demianrey/v2node_DR/mod/script/install.sh && bash install.sh
```

## Compilacion
``` bash
GOEXPERIMENT=jsonv2 go build -v -o build_assets/v2node -trimpath -ldflags "-X 'github.com/wyx2685/v2node/cmd.version=$version' -s -w -buildid="
```

## Registro de estrellas

[![Stargazers over time](https://starchart.cc/wyx2685/v2node.svg?variant=adaptive)](https://starchart.cc/wyx2685/v2node)
