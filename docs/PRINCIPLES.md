# Princípios de Projeto — AI-Workbench Core v1.0

Estes princípios são normativos: todo script novo adicionado ao AI-Workbench
deve segui-los, e revisões de código devem rejeitar contribuições que os
violem sem justificativa explícita documentada.

## 1. Fail-loud sobre degradação silenciosa

Um pré-requisito ausente (comando, arquivo, variável de ambiente) **aborta**
o script com uma mensagem clara e acionável (`fail_loud`), em vez de deixar
a execução continuar em um estado degradado que só vai falhar — de forma
confusa — três passos depois.

Exceções deliberadas e documentadas usam `log_warn` + continuação, nunca
por omissão: `platforms/intel/oneapi.sh` e `platforms/intel/npu.sh`, por
exemplo, são best-effort porque não são caminhos críticos de aceleração.

## 2. Pré-requisitos compartilhados, incondicionalmente, primeiro

`install.sh` chama `section_prereqs` (que roda `ensure_prereq_dirs`) **antes**
de qualquer branch condicional de plataforma ou runtime. Um bug real dessa
classe — um runtime que assumia silenciosamente um diretório criado apenas
por um branch de plataforma que ainda não tinha executado — foi identificado
e corrigido durante o QA da v1.0. A lição: nunca mover a criação de recursos
compartilhados para dentro de um `if`.

## 3. Reexecução seletiva via flags booleanas

Todo comportamento opcional é controlado por uma flag em `config.env`
(`INSTALL_OLLAMA`, `INSTALL_QDRANT`, etc.), lida via `is_true()`. Isso permite
reexecuções parciais idempotentes (`install.sh --only runtimes`,
`make install-platform`) sem precisar reinstalar tudo do zero.

## 4. Vulkan como caminho prático de aceleração em iGPU Intel

Em iGPUs Intel Arc, o caminho viável de aceleração para llama.cpp é Vulkan
via Mesa ANV. O caminho XPU/SYCL do vLLM é impraticável em iGPUs dado a
complexidade de configuração e o suporte limitado da comunidade — por isso
`platforms/intel/install.sh` não instala IPEX-LLM por padrão.

## 5. Quantização escala com o tamanho do modelo

Em modelos pequenos (ex. Gemma E2B), `Q8_0` é preferível a `Q4_K_M`: a perda
de qualidade da quantização de 4 bits é proporcionalmente mais impactante em
modelos pequenos. Modelos maiores toleram quantizações mais agressivas melhor.
`models/install.sh` reflete isso no catálogo padrão e emite um aviso quando
detecta um sistema com pouca memória.

## 6. Observabilidade

Toda ação relevante gera log estruturado (`logs/installation.log`, via
`lib/logger.sh`) e os relatórios finais (`reports/hardware.json`,
`reports/doctor.json`, `reports/doctor.md`, `reports/install_report.md`)
documentam o que foi verificado e o que foi corrigido.

## 7. Modularidade e extensibilidade

Cada fabricante (`platforms/*`) e cada runtime (`runtimes/*`) é independente
e segue o mesmo contrato mínimo: um `install.sh` que expõe uma função
`install_<nome>`, opcionalmente `update_<nome>` e `remove_<nome>`. Novos
runtimes, plataformas e modelos podem ser adicionados como módulos sem
alterar o núcleo (`install.sh`, `doctor.sh`, `detect.sh`).
