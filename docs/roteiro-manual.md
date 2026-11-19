# Roteiro manual

Este roteiro reúne as etapas que o Usuário executa à mão no Gemini Notebook (https://notebook.google.com/) e no GitHub. Siga os nove passos na ordem. Cada passo indica o artefato a salvar no Repositório e a pasta de destino.

Antes de começar, tenha em mãos o [registro de fontes](registro-de-fontes.md), os [critérios de confiança](criterios-de-confianca.md) e a [diretriz de comportamento](diretriz-de-comportamento.md).

1. **Definir o Objetivo.**
   - Ação: escreva em uma única frase o que o Notebook deve ajudar a aprender ou decidir, com no máximo 300 caracteres e um único ponto final. A frase também declara o Tema.
   - Artefato a salvar: `README.md`, na seção "Tema e objetivo".
   - Pasta de destino: raiz do Repositório.
2. **Separar as Fontes.**
   - Ação: liste as Fontes candidatas (vídeos do YouTube, artigos e PDFs) e avalie cada uma pelos cinco critérios de `docs/criterios-de-confianca.md`, respondendo sim ou não a cada critério. Uma Fonte é aprovada somente se tiver autoria identificável, acesso público e pelo menos 3 dos 5 critérios atendidos. Registre as demais como descartadas, com o motivo, e não as remova da tabela. Descarte também qualquer Fonte com Dado Pessoal, sem permissão de compartilhamento ou com link que não abre.
   - Artefato a salvar: `registro-de-fontes.md`.
   - Pasta de destino: `docs/`.
3. **Criar o Notebook.**
   - Ação: acesse https://notebook.google.com/, crie um Notebook novo e dê a ele um nome que cite o Tema. Anote o endereço provisório do Notebook; ele só será definitivo depois do passo 8.
   - Artefato a salvar: anotação do link provisório na seção "Link do notebook" do `README.md`.
   - Pasta de destino: raiz do Repositório.
4. **Aplicar a Diretriz de Comportamento.**
   - Ação: abra as configurações de instrução do Notebook e cole o texto integral de `docs/diretriz-de-comportamento.md`, sem alterar nenhum caractere. Confirme que o texto começa com "Comporte-se como um especialista em".
   - Artefato a salvar: `diretriz-de-comportamento.md`, sem alterações. Se você ajustar o texto, salve o ajuste nesse arquivo e atualize o bloco de código correspondente no `README.md`.
   - Pasta de destino: `docs/`.
5. **Executar o Deep Research.**
   - Ação: rode o Deep Research com o Tema e importe no Notebook somente as Fontes aprovadas, isto é, as que atendem à autoria identificável, ao acesso público e a pelo menos 3 dos 5 critérios. Exclua da importação as demais Fontes sugeridas e registre-as como descartadas. Garanta que haja pelo menos uma Fonte aprovada de cada formato: vídeo do YouTube, artigo e PDF.
   - Artefato a salvar: `registro-de-fontes.md` atualizado com número, título, formato, link, autoria, data, status e motivo de cada Fonte.
   - Pasta de destino: `docs/`.
6. **Conversar com as Fontes.**
   - Ação: faça de 3 a 10 perguntas ao Notebook, escolhendo entre as perguntas candidatas de `docs/registro-de-perguntas.md`. Em cada resposta, abra cada citação exibida no chat e confira se o trecho citado na Fonte contém a informação afirmada na resposta.
   - Se o trecho citado não contiver a informação afirmada, descarte a resposta e repita a pergunta, ou registre a divergência no Repositório (por exemplo, em uma linha do registro de perguntas marcada como divergente). Não use uma resposta divergente como evidência.
   - Para cada resposta conferida, faça um Print de Chat que mostre as citações e registre a pergunta, a resposta resumida, as Fontes citadas (pelo nome do documento) e o link relativo do print. Antes de salvar o print, remova qualquer Dado Pessoal da imagem.
   - Artefatos a salvar: `registro-de-perguntas.md` e os Prints de Chat, com nomes só em letras minúsculas, dígitos e hífens.
   - Pastas de destino: `docs/` e `materiais/prints-chat/`.
7. **Gerar os Materiais de Estudo no Estúdio.**
   - Ação: no Estúdio do Notebook, gere os 4 Materiais de Estudo: mapa mental, slides, guia de estudos e resumo em áudio.
   - Baixe o mapa mental em formato PNG e os slides em formato PDF, e salve os dois arquivos no Repositório. Se quiser guardar o guia de estudos e o resumo em áudio, salve cada arquivo na pasta de `materiais/` do seu tipo e liste o nome dele no `README.md` dessa pasta.
   - Artefatos a salvar: o arquivo PNG do mapa mental e o arquivo PDF dos slides, com nomes só em letras minúsculas, dígitos e hífens, sem acentos, espaços ou underscores, com no máximo 100 caracteres.
   - Pastas de destino: `materiais/mapa-mental/` (PNG) e `materiais/slides/` (PDF).
8. **Compartilhar o Notebook.**
   - Ação: nas opções de compartilhamento do Notebook, ative o acesso por link, de modo que o Link do Notebook abra para qualquer pessoa que o receba, sem exigir permissão adicional sua. Copie o link.
   - Teste: abra o link em uma janela anônima do navegador, sem login na sua conta, e confirme que o Notebook abre em leitura, com as Fontes listadas e em menos de 10 segundos. Só depois desse teste registre o link no Repositório. Se o link falhar, corrija o compartilhamento e teste de novo; enquanto falhar, mantenha desmarcado o item correspondente de `docs/checklist-qualidade.md` e não considere o projeto pronto para entrega.
   - Antes de registrar, confira em cada Fonte a ausência de Dado Pessoal e a permissão de compartilhamento.
   - Artefato a salvar: o Link do Notebook, uma única URL iniciada por `https://`, na seção "Link do notebook" do `README.md`.
   - Pasta de destino: raiz do Repositório.
9. **Publicar o Repositório.**
   - Ação: crie o Repositório público `axios-segundo-cerebro` na conta Gtvnv, adicione o remoto `origin` com `https://github.com/Gtvnv/axios-segundo-cerebro` e envie a branch `main` com `git push -u origin main`. Não use `push --force`. Confirme nas configurações do GitHub que a visibilidade é pública e execute `scripts/validar.ps1` antes do envio.
   - Artefato a salvar: a URL do Repositório, `https://github.com/Gtvnv/axios-segundo-cerebro`, que é o link a submeter na entrega (e não o Link do Notebook).
   - Pasta de destino: raiz do Repositório (`README.md`).
