# AI-Workbench Core v1.0

Framework open source para preparação automática de estações Linux
destinadas ao desenvolvimento e execução de Inteligência Artificial Local.

Detecta automaticamente o hardware disponível (CPU, GPU, NPU, APIs de
aceleração), instala apenas os componentes compatíveis, padroniza ambientes
Python, gerencia modelos locais, compila runtimes otimizados, executa
benchmarks e gera diagnósticos completos — tudo de forma idempotente e
observável.

## Instalação rápida

```bash
git clone <repo-url> AI-Workbench
cd AI-Workbench
cp config.env config.env.local   # opcional: revise as flags antes de instalar
./install.sh
```

Ao final, rode um diagnóstico completo:

```bash
./doctor.sh
```

Ou use o CLI unificado (após adicionar `scripts/` ao PATH, ou via `./scripts/awb`):

```bash
awb install
awb doctor
awb info
awb model install gemma3-e2b
awb runtime install llama.cpp
awb benchmark llm ~/ai/models/gguf/gemma-3n-E2B-it-Q8_0.gguf
```

## Arquitetura

```
AI-Workbench/
├── install.sh        # orquestrador principal
├── update.sh          # atualização do framework e de runtimes/modelos
├── doctor.sh          # 40+ verificações de diagnóstico
├── detect.sh          # detecção de hardware (fonte de verdade das variáveis)
├── config.env         # flags de instalação
├── Makefile           # atalhos (make install, make doctor, ...)
│
├── lib/                # logger, cores, utils, downloader, validação
├── platforms/          # intel/ amd/ nvidia/ cpu/ — instalação por fabricante
├── runtimes/           # llama.cpp/ ollama/ openvino/ onnxruntime/ whisper/
├── python/             # criação dos venvs (core, openvino, rag, vision, speech)
├── models/             # Model Manager (catálogo GGUF + downloads via HF)
├── benchmarks/         # llm/ whisper/ vision/ embeddings/
├── monitoring/         # snapshots de cpu/gpu/memória/temperatura
├── services/           # docker-compose: Open WebUI, Qdrant, ChromaDB, Postgres
├── scripts/awb         # CLI unificado
├── reports/            # hardware.json, doctor.json/md, install_report.md
├── logs/                # installation.log (trilha completa e timestampada)
└── docs/                # princípios de projeto e notas por plataforma
```

## Fluxo do instalador

```
install.sh
  → validar SO / arquitetura / RAM / disco
  → atualizar sistema (apt update/upgrade + toolchain base)
  → pré-requisitos compartilhados (incondicional, antes de qualquer branch)
  → detect.sh (hardware)
  → módulo da plataforma (Intel | AMD | NVIDIA | CPU — CPU sempre roda)
  → criar ambientes Python
  → instalar runtimes (llama.cpp, Ollama, OpenVINO, ONNX Runtime, Whisper)
  → baixar modelo padrão
  → subir serviços (Open WebUI, Qdrant, ChromaDB, Postgres — opcionais)
  → benchmark
  → relatório final
```

Cada seção pode ser reexecutada isoladamente:

```bash
./install.sh --only platform
./install.sh --skip services --skip benchmark
make install-runtimes
```

## Plataformas suportadas

| Fabricante | Aceleração primária                    | Compatível com                                   |
|------------|------------------------------------------|---------------------------------------------------|
| Intel      | Vulkan (Mesa ANV)                        | Arc, Iris Xe, Meteor Lake, Lunar Lake, Battlemage, Arrow Lake |
| AMD        | Vulkan (Mesa RADV) + ROCm/HIP             | GPUs discretas AMD com suporte ROCm                |
| NVIDIA     | CUDA + cuDNN (+ TensorRT opcional)        | GPUs discretas NVIDIA                              |
| CPU        | OpenBLAS (+ oneDNN via wheels)            | Sempre instalado, como fallback universal        |

> Nota de design: em iGPUs Intel, o caminho de aceleração usado é Vulkan via
> Mesa ANV. O caminho XPU/SYCL (vLLM/IPEX-LLM) não é instalado por padrão —
> ver `docs/PRINCIPLES.md`.

## Modelos

```bash
awb model list
awb model install gemma3-e2b     # recomendado para sistemas com pouca memória
awb model install custom <hf_repo_id> <filename>
```

## Diagnóstico

`doctor.sh` roda mais de 40 verificações organizadas em nove categorias
(Sistema, Aceleração, Fabricante de GPU, Runtimes, Ambientes Python, Serviços,
Segurança, Recursos, Modelos) e grava `reports/doctor.json` +
`reports/doctor.md`. O total exato varia conforme o hardware detectado, já que
as checagens por fabricante são mutuamente exclusivas.

## Roadmap

- **v1.5** — perfis de configuração, cache de downloads, instalação offline, sistema de plugins.
- **v2.0** — interface web, painel de monitoramento, atualizações automáticas, gestão de múltiplas máquinas.

## Licença

MIT — veja [LICENSE](LICENSE).
