# ComfyUI do host — backend de geração do Kage (Seiryu).
#
# Base: seiryu/comfyui:snapshot-0.37.1-cu128, o snapshot `docker commit` do
# container awb-comfyui em 2026-10-21. Ela preserva o estado REAL que rodava
# na RTX 5060 Ti (torch 2.7.1+cu128, ComfyUI 0.37.1, custom nodes) — a
# imagem ghcr.io/ai-dock/comfyui:latest é de 2024-09-26 (torch 2.4.1,
# ComfyUI 0.2.2) e não suporta Blackwell (sm_120). Usar o snapshot como base
# evita reinstalar ~3 GB de torch e mantém o build reproduzível.
#
# Upgrade: ComfyUI v0.42.1 (última release em 2026-10-19).
#
# torch: mantido em 2.7.1+cu128 nesta rodada. Existe wheel 2.9.1+cu130 para
# cp310 (driver 595.104.02 / CUDA 13.2 suporta), mas o download do índice
# PyTorch estava a ~200 KB/s no build. Com cu130 o backend CUDA do
# comfy-kitchen passa a funcionar e o Qwen 2.1 pode liberar o 2K; sem ele, o
# teto de 1536² continua (PENDING documentado no relatório da task
# kage-revisao-completa-2026-10). Para habilitar depois, troque a base pelo
# snapshot e adicione o passo:
#   RUN /opt/environments/python/comfyui/bin/pip install --no-cache-dir \
#       --index-url https://download.pytorch.org/whl/cu130 \
#       torch==2.9.1 torchvision==0.24.1 torchaudio==2.9.1
#
# Rollback: aponte o compose para seiryu/comfyui:snapshot-0.37.1-cu128 e
# recrie o container (os pesos vivem no volume comfyui_data).

FROM seiryu/comfyui:snapshot-0.37.1-cu128

ENV COMFYUI_REF=v0.42.1

# ComfyUI pinado na release alvo + dependências (comfy-kitchen 0.2.39,
# comfy-aimdo 0.5.6, frontend 1.55.18, templates 0.11.89).
RUN /opt/ai-dock/bin/update-comfyui.sh -r "${COMFYUI_REF}"

# Verificação de build: ComfyUI na versão alvo e torch funcional.
RUN cd /opt/ComfyUI && \
    /opt/environments/python/comfyui/bin/python -c \
    "import torch, comfyui_version; print('comfyui', comfyui_version.__version__, 'torch', torch.__version__, 'cuda', torch.version.cuda)" && \
    git describe --tags
