# ComfyUI do host — backend de geração do Kage e de restauração do Fukugen
# (Seiryu).
#
# Base: seiryu/comfyui:0.42.1-cu128, a imagem que roda hoje no awb-comfyui.
# Ela deriva do snapshot `docker commit` de 2026-10-21 (estado real da RTX
# 5060 Ti: torch 2.7.1+cu128, ComfyUI 0.42.1, custom nodes) — a imagem
# ghcr.io/ai-dock/comfyui:latest é de 2024-09-26 (torch 2.4.1, ComfyUI 0.2.2)
# e não suporta Blackwell (sm_120). O tag do snapshot 0.37.1 não existe mais
# localmente; por isso o build parte da 0.42.1 e só acrescenta camadas.
#
# Atenção: os pesos vivem em /opt/ComfyUI/models, DENTRO da imagem (o volume
# comfyui_data monta em /workspace e não é o diretório de modelos) — trocar
# de imagem troca os pesos. Rollback: aponte o compose de volta para
# seiryu/comfyui:0.42.1-cu128 e recrie o container.
#
# torch: mantido em 2.7.1+cu128. Existe wheel 2.9.1+cu130 para cp310 (driver
# 595.104.02 / CUDA 13.2 suporta), mas o download do índice PyTorch estava a
# ~200 KB/s no build. Com cu130 o backend CUDA do comfy-kitchen passa a
# funcionar e o Qwen 2.1 pode liberar o 2K; sem ele, o teto de 1536² continua
# (PENDING documentado no relatório da task kage-revisao-completa-2026-10).
# Para habilitar depois, adicione o passo:
#   RUN /opt/environments/python/comfyui/bin/pip install --no-cache-dir \
#       --index-url https://download.pytorch.org/whl/cu130 \
#       torch==2.9.1 torchvision==0.24.1 torchaudio==2.9.1

FROM seiryu/comfyui:0.42.1-cu128

# Verificação de build: ComfyUI na versão alvo e torch funcional.
RUN cd /opt/ComfyUI && \
    /opt/environments/python/comfyui/bin/python -c \
    "import torch, comfyui_version; print('comfyui', comfyui_version.__version__, 'torch', torch.__version__, 'cuda', torch.version.cuda)" && \
    git describe --tags

# ── Restauração de fotos: colorização (DDColor) e upscale (Real-ESRGAN) ──
# DDColor: node kijai/ComfyUI-DDColor (Apache-2.0) pinado no commit; pesos
# piddnad/DDColor-models (Apache-2.0). O node baixa os pesos em runtime via
# huggingface_hub — aqui eles entram na imagem com sha256 pinado, então o
# container funciona sem rede e o build é reproduzível.
# Real-ESRGAN: RealESRGAN_x4plus.pth oficial (release v0.1.0 do xinntao,
# BSD-3), consumido pelo ImageUpscaleWithModel nativo do ComfyUI.
ARG DDCOLOR_NODE_REF=30d5b8e7666382a6a78404caee28dfa87f741037
ARG DDCOLOR_TINY_SHA256=81dd643904f4664c3718513e3320ae3db0c567f0d3e18398606659adee7bfc17
ARG DDCOLOR_PAPER_SHA256=789781789db1bafc2165e1cf9658580f871cce64a81901ec49127877813f10b9
ARG REALESRGAN_SHA256=4fa0d38905f75ac06eb49a7951b426670021be3018265fd191d2125df9d682f1

RUN git clone --quiet https://github.com/kijai/ComfyUI-DDColor \
        /opt/ComfyUI/custom_nodes/ComfyUI-DDColor && \
    git -C /opt/ComfyUI/custom_nodes/ComfyUI-DDColor checkout --quiet "${DDCOLOR_NODE_REF}" && \
    rm -rf /opt/ComfyUI/custom_nodes/ComfyUI-DDColor/.git

# Dependências: cv2 (opencv-python-headless 4.10), huggingface_hub 1.30, timm,
# numpy e Pillow já vêm na base — nada a instalar. Os pesos ficam na imagem,
# então o fallback de download do node (snapshot_download com
# local_dir_use_symlinks, removido no hub 1.x) nunca é executado.

RUN set -eux; \
    dir=/opt/ComfyUI/custom_nodes/ComfyUI-DDColor/checkpoints; \
    mkdir -p "$dir"; \
    curl -fsSL -o "$dir/ddcolor_paper_tiny.pth" \
        https://huggingface.co/piddnad/DDColor-models/resolve/main/ddcolor_paper_tiny.pth; \
    echo "${DDCOLOR_TINY_SHA256}  $dir/ddcolor_paper_tiny.pth" | sha256sum -c -; \
    curl -fsSL -o "$dir/ddcolor_paper.pth" \
        https://huggingface.co/piddnad/DDColor-models/resolve/main/ddcolor_paper.pth; \
    echo "${DDCOLOR_PAPER_SHA256}  $dir/ddcolor_paper.pth" | sha256sum -c -

RUN set -eux; \
    curl -fsSL -o /opt/ComfyUI/models/upscale_models/RealESRGAN_x4plus.pth \
        https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth; \
    echo "${REALESRGAN_SHA256}  /opt/ComfyUI/models/upscale_models/RealESRGAN_x4plus.pth" | sha256sum -c -

# Verificação de build: deps importáveis e pesos no lugar (o node importa cv2
# e huggingface_hub no topo, então faltar qualquer um derruba o ComfyUI).
RUN /opt/environments/python/comfyui/bin/python -c \
    "import cv2, huggingface_hub, timm; print('restore deps', cv2.__version__, huggingface_hub.__version__, timm.__version__)" && \
    test -s /opt/ComfyUI/custom_nodes/ComfyUI-DDColor/checkpoints/ddcolor_paper.pth && \
    test -s /opt/ComfyUI/custom_nodes/ComfyUI-DDColor/checkpoints/ddcolor_paper_tiny.pth && \
    test -s /opt/ComfyUI/models/upscale_models/RealESRGAN_x4plus.pth

# ── Rosto (GFPGAN) e riscos (LaMa) ─────────────────────────────────────
# GFPGAN: node comfyorg/comfyui_gfpgan (Apache-2.0) pinado; usa
# basicsr-fixed (fork compatível com torchvision novo) e facexlib. Os pesos
# (GFPGANv1.4 + detecção + parsing) entram na imagem — o node baixaria em
# runtime. LaMa: node Acly/comfyui-inpaint-nodes (GPL-3.0) pinado; modelo
# big-lama.pt (Apache-2.0, advimman/lama) em models/inpaint.
ARG GFPGAN_NODE_REF=77577e49ae49e59e44098549d8d04ab2cba87fda
ARG INPAINT_NODE_REF=5b7681746fe19e563113d27366ba85236bc1ba5b
ARG GFPGAN_SHA256=e2cd4703ab14f4d01fd1383a8a8b266f9a5833dacee8e6a79d3bf21a1b6be5ad
ARG FACE_DETECTION_SHA256=6d1de9c2944f2ccddca5f5e010ea5ae64a39845a86311af6fdf30841b0a5a16d
ARG FACE_PARSING_SHA256=468e13ca13a9b43cc0881a9f99083a430e9c0a38abd935431d1c28ee94b26567
ARG LAMA_SHA256=344c77bbcb158f17dd143070d1e789f38a66c04202311ae3a258ef66667a9ea9

RUN git clone --quiet https://github.com/comfyorg/comfyui_gfpgan \
        /opt/ComfyUI/custom_nodes/comfyui_gfpgan && \
    git -C /opt/ComfyUI/custom_nodes/comfyui_gfpgan checkout --quiet "${GFPGAN_NODE_REF}" && \
    rm -rf /opt/ComfyUI/custom_nodes/comfyui_gfpgan/.git && \
    git clone --quiet https://github.com/Acly/comfyui-inpaint-nodes \
        /opt/ComfyUI/custom_nodes/comfyui-inpaint-nodes && \
    git -C /opt/ComfyUI/custom_nodes/comfyui-inpaint-nodes checkout --quiet "${INPAINT_NODE_REF}" && \
    rm -rf /opt/ComfyUI/custom_nodes/comfyui-inpaint-nodes/.git

# Bug do node no commit pinado: gfpganer.py usa warnings.warn sem importar
# warnings — o enhance() estoura, o node engole a exceção e devolve a imagem
# original (o "restaurar rosto" não fazia nada). Correção de uma linha.
RUN sed -i '1i import warnings' /opt/ComfyUI/custom_nodes/comfyui_gfpgan/src/comfyui_gfpgan/gfpganer.py && \
    grep -q '^import warnings' /opt/ComfyUI/custom_nodes/comfyui_gfpgan/src/comfyui_gfpgan/gfpganer.py

# basicsr-fixed evita o basicsr original (quebrado com torchvision novo);
# gfpgan entra com --no-deps para não puxar basicsr/tb-nightly. facexlib
# traz filterpy/numba.
RUN /opt/environments/python/comfyui/bin/pip install --no-cache-dir \
        "basicsr-fixed==1.4.2" "facexlib==0.3.0" && \
    /opt/environments/python/comfyui/bin/pip install --no-cache-dir --no-deps "gfpgan==1.3.8"

RUN set -eux; \
    mkdir -p /opt/ComfyUI/models/face_restoration \
             /opt/ComfyUI/models/face_detection \
             /opt/ComfyUI/models/inpaint; \
    curl -fsSL -o /opt/ComfyUI/models/face_restoration/GFPGANv1.4.pth \
        https://github.com/TencentARC/GFPGAN/releases/download/v1.3.0/GFPGANv1.4.pth; \
    echo "${GFPGAN_SHA256}  /opt/ComfyUI/models/face_restoration/GFPGANv1.4.pth" | sha256sum -c -; \
    curl -fsSL -o /opt/ComfyUI/models/face_detection/detection_Resnet50_Final.pth \
        https://github.com/xinntao/facexlib/releases/download/v0.1.0/detection_Resnet50_Final.pth; \
    echo "${FACE_DETECTION_SHA256}  /opt/ComfyUI/models/face_detection/detection_Resnet50_Final.pth" | sha256sum -c -; \
    curl -fsSL -o /opt/ComfyUI/models/face_detection/parsing_bisenet.pth \
        https://github.com/xinntao/facexlib/releases/download/v0.2.0/parsing_bisenet.pth; \
    echo "${FACE_PARSING_SHA256}  /opt/ComfyUI/models/face_detection/parsing_bisenet.pth" | sha256sum -c -; \
    curl -fsSL -o /opt/ComfyUI/models/inpaint/big-lama.pt \
        https://github.com/Sanster/models/releases/download/add_big_lama/big-lama.pt; \
    echo "${LAMA_SHA256}  /opt/ComfyUI/models/inpaint/big-lama.pt" | sha256sum -c -

RUN /opt/environments/python/comfyui/bin/python -c \
    "import basicsr, facexlib, gfpgan, cv2, spandrel; print('restore deps ok')" && \
    test -s /opt/ComfyUI/models/face_restoration/GFPGANv1.4.pth && \
    test -s /opt/ComfyUI/models/face_detection/detection_Resnet50_Final.pth && \
    test -s /opt/ComfyUI/models/face_detection/parsing_bisenet.pth && \
    test -s /opt/ComfyUI/models/inpaint/big-lama.pt
