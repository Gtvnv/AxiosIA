# AXIOS - Segundo cérebro com IA

O AXIOS é um segundo cérebro com IA: um notebook especialista em um único tema, alimentado apenas por fontes confiáveis em mais de um formato (vídeos do YouTube, artigos e PDFs). O notebook responde com citações das fontes e gera materiais de estudo, como mapa mental, slides, guia de estudos e resumo em áudio. Este repositório documenta todo o trabalho: critérios de confiança, registro de fontes, diretriz de comportamento, perguntas e respostas, materiais gerados e um script de validação.

## 1. Tema e objetivo

Tema: arquitetura de um copiloto de ensino de lógica de programação que combina camada scriptada e Small Language Model (SLM) atuando como tutor socrático, com o objetivo de entender como essa combinação funciona (proposto).

## 2. Fontes e por que são confiáveis

Os critérios usados para aprovar uma fonte estão em [Critérios de confiança](docs/criterios-de-confianca.md). O modelo da tabela está em [Registro de fontes](docs/registro-de-fontes.md).

[PREENCHER: tabela com pelo menos 3 fontes aprovadas, sendo ao menos 1 vídeo do YouTube, 1 artigo e 1 PDF, com título, formato, link, autoria, data e o motivo da confiança citando por nome ao menos 3 dos 5 critérios, entre eles autoria identificável e acesso público]

## 3. Diretriz de comportamento

Diretriz de Comportamento a ser aplicada ao Notebook:

```text
Comporte-se como um especialista em arquitetura de um copiloto de ensino de lógica de programação que combina camada scriptada e Small Language Model (SLM) atuando como tutor socrático.

Siga sempre estas instruções:

1. Responda sempre em português do Brasil.
2. Indique a Fonte, pelo nome do documento, ao final de cada afirmação feita na resposta.
3. Se as Fontes não contiverem a informação necessária para responder à pergunta, declare essa limitação na resposta e não responda com conhecimento externo às Fontes.
```

## 4. Perguntas, respostas e fontes

O modelo da tabela e as perguntas candidatas estão em [Registro de perguntas](docs/registro-de-perguntas.md).

[PREENCHER: de 3 a 10 perguntas válidas, cada uma com a resposta resumida, as fontes citadas pelo nome do documento e o link relativo para o print do chat em materiais/prints-chat]

## 5. Link do notebook

[PREENCHER: link de compartilhamento do notebook, iniciado por https://, validado em janela anônima do navegador]

## Materiais gerados

Ainda não há arquivos gerados no Estúdio. Os guias de cada pasta de materiais e os documentos de apoio já existem:

- [Guia da pasta do mapa mental](materiais/mapa-mental/README.md)
- [Guia da pasta dos slides](materiais/slides/README.md)
- [Guia da pasta dos prints do chat](materiais/prints-chat/README.md)
- [Critérios de confiança](docs/criterios-de-confianca.md)
- [Registro de fontes](docs/registro-de-fontes.md)
- [Diretriz de comportamento (arquivo)](docs/diretriz-de-comportamento.md)
- [Roteiro manual](docs/roteiro-manual.md)
- [Registro de perguntas](docs/registro-de-perguntas.md)
- [Checklist de qualidade](docs/checklist-qualidade.md)
- [Evoluções opcionais](docs/evolucoes.md)

[PREENCHER: um item para cada material gerado e salvo no repositório (mapa mental em PNG, slides em PDF, guia de estudos e resumo em áudio), com o nome do material e o link relativo para o arquivo]

## O que é automatizado e o que é manual

### Tarefas do Agente

- Criar a estrutura de pastas do repositório e o arquivo `.gitignore`.
- Escrever o README e os templates de documentação.
- Redigir os critérios de confiança e a diretriz de comportamento.
- Criar o roteiro manual, o checklist de qualidade e a lista de evoluções.
- Criar o script de validação `scripts/validar.ps1`.
- Fazer os commits com `git add` por nome de arquivo.

### Tarefas do Usuário

- Definir o objetivo e confirmar o tema.
- Separar e avaliar as fontes pelos critérios de confiança.
- Criar o notebook e aplicar a diretriz de comportamento.
- Executar o Deep Research e conversar com as fontes.
- Conferir cada citação no trecho original da fonte.
- Gerar e baixar os materiais no Estúdio.
- Compartilhar o notebook e testar o link em janela anônima.
- Criar o repositório remoto e publicar.
