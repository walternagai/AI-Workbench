# AI-Workbench Core v1.0
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg) ![CI](https://github.com/walternagai/AI-Workbench/actions/workflows/ci.yml/badge.svg)

Framework open source para preparação automática de estações Linux
destinadas ao desenvolvimento e execução de Inteligência Artificial Local.

Detecta automaticamente o hardware disponível (CPU, GPU, NPU, APIs de
aceleração), instala apenas os componentes compatíveis, padroniza ambientes
Python, gerencia modelos locais, compila runtimes otimizados, executa
benchmarks e gera diagnósticos completos — tudo de forma idempotente e
observável.
## Table of Contents
- [Instalação rápida](#instalação‑rápida)
- [Arquitetura](#arquitetura)
- [Fluxo do instalador](#fluxo‑do‑instalador)
- [Plataformas suportadas](#plataformas‑suportadas)
- [Modelos](#modelos)
- [Diagnóstico](#diagnóstico)
- [Serviços opcionais](#serviços-opcionais)
- [Segurança e trade-offs](#segurança-e-trade-offs)
- [Roadmap](#roadmap)
- [Licença](#licença)

## Requisitos de sistema

- Sistema operacional: Ubuntu 22.04 LTS ou superior, Pop!_OS ou Linux Mint. Debian puro e outras derivadas não são suportados: o instalador valida pelo ID da distro e monta caminhos de repositório Ubuntu.
- Pacotes base: `git`, `curl`, `wget`, `bash`, `apt`, `make`.
- Memória RAM recomendada: ≥ 8 GB (16 GB+ para modelos > 7 B).
- Espaço em disco: ≥ 20 GB livre para downloads e models.
- Suporte a GPU: driver NVIDIA ≥ 525, ou drivers AMD Mesa ≥ 23.0, ou Intel Mesa ≥ 23.1 para Vulkan.

## Instalação rápida

```bash
git clone <repo-url> AI-Workbench
cd AI-Workbench
cp config.local.env.example config.local.env   # segredos e serviços; depois: chmod 600 config.local.env
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

## Comandos CLI

| Sub‑comando | Descrição |
|---|---|
| awb install | instala o ambiente completo |
| awb doctor | executa diagnóstico |
| awb model install <nome> | baixa modelo |
| awb runtime install <nome> | instala runtime |
| awb benchmark <target> <args> | roda benchmark |
| awb info | exibe informações do sistema |

## Arquitetura

```text
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
├── python/             # criação dos venvs (core, openvino, rag, vision; speech opcional)
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

```text
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

## Serviços opcionais

Todos os serviços vêm desligados em `config.env`. Para ligar um, defina a flag em
`config.local.env` (modo 600, ver `config.local.env.example`):

| Serviço | Flag | Pré-requisito |
|---|---|---|
| Open WebUI | `INSTALL_OPENWEBUI` | `WEBUI_SECRET_KEY` com valor real |
| Qdrant | `INSTALL_QDRANT` | nenhum; publicado em `172.17.0.1` |
| ChromaDB | `INSTALL_CHROMADB` | `CHROMADB_EXTERNAL_NETWORK`, uma rede Docker existente. Sem ela, o serviço é pulado com aviso |
| Postgres | `INSTALL_POSTGRES` | `POSTGRES_PASSWORD` com valor real |
| ComfyUI | `INSTALL_COMFYUI` | `COMFYUI_GPU_UUID`, e a imagem `COMFYUI_IMAGE` construída localmente a partir de `services/comfyui/Dockerfile`. Sem a imagem, o serviço é pulado com aviso |

Um segredo que ainda é o placeholder `change-me` aborta a instalação, de propósito:
nunca se sobe um serviço com senha pública. Dependências externas ausentes (rede,
imagem) pulam o serviço com aviso, e o aviso aparece no log.

## Segurança e trade-offs

- **Instalador do Ollama sem verificação de integridade.** O `install.sh` oficial
  do Ollama é baixado por HTTPS, checado apenas pelo shebang e executado com `sh`.
  Nem o script oficial nem este instalador conferem checksum ou assinatura. A
  release publica `sha256sum.txt`, mas o hash viria da mesma origem do download,
  então verificá-lo só protege contra corrupção. Alternativa para quem precisar de
  integridade: fixar `OLLAMA_VERSION` e o SHA256 do asset em `config.env`, conferindo
  antes de executar. Não adotada por padrão, porque cada release exigiria atualizar o pin.

## Roadmap

- **v1.5** — perfis de configuração, cache de downloads, instalação offline, sistema de plugins.
- **v2.0** — interface web, painel de monitoramento, atualizações automáticas, gestão de múltiplas máquinas.

## Licença

MIT — veja [LICENSE](LICENSE).
