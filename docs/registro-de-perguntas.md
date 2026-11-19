# Registro de Perguntas

Cada pergunta feita ao Notebook recebe uma linha na tabela de registros, com a resposta resumida, as Fontes citadas e o Print de Chat que mostra as citações. As perguntas candidatas ficam na lista separada, mais abaixo, e só passam para a tabela depois de respondidas e conferidas.

## Regras de preenchimento

- **nº:** inteiro sequencial, começando em 1.
- **pergunta:** de 1 a 300 caracteres.
- **resposta resumida:** de 1 a 500 caracteres.
- **Fontes citadas:** de 1 a 5 nomes de documentos carregados no Notebook, separados por vírgula. Se a resposta do Notebook não trouxer citação de Fonte, escreva exatamente "sem citação".
- **Print de Chat:** link relativo no formato `[texto](../materiais/prints-chat/nome-do-arquivo.png)`, apontando para exatamente 1 imagem existente no repositório.

## Quando a pergunta é válida

Uma pergunta é válida quando a resposta tem pelo menos 1 Fonte citada (diferente de "sem citação") e o link do Print de Chat resolve para um arquivo de imagem existente. Respostas marcadas com "sem citação" e perguntas com link de Print quebrado são inválidas e não contam para o mínimo de 3 perguntas válidas do README. O README mostra no máximo 10 perguntas válidas. As demais ficam somente neste arquivo.

Antes de registrar uma resposta, confira cada citação no trecho original da Fonte. Se o trecho não contém a informação afirmada, descarte a resposta e repita a pergunta, ou registre a divergência.

## Tabela de registros

| nº | pergunta | resposta resumida | Fontes citadas | Print de Chat |
|---|---|---|---|---|

## Perguntas candidatas

Cada pergunta se liga a um tópico do Tema proposto.

1. **Camada scriptada:** O que a camada scriptada faz sozinha, sem modelo de linguagem, e o que fica de fora dela?
2. **Trilhas:** Como uma trilha de aprendizagem organiza os conteúdos em etapas, e que critério define o avanço de uma etapa para a seguinte?
3. **Testes:** Que tipos de teste verificam se o comportamento determinístico do sistema continua correto depois de uma mudança?
4. **SLM como tutor socrático:** Como um modelo de linguagem pequeno (SLM) conduz o estudante por perguntas, em vez de entregar a resposta pronta?
5. **Regras determinísticas:** Por que regras determinísticas devem decidir o que o sistema pode afirmar, e o que o modelo pode fazer dentro desses limites?
6. **Camada scriptada e SLM:** Como a camada scriptada e o SLM dividem as responsabilidades em uma mesma interação com o estudante?
7. **Trilhas e testes:** Como os testes comprovam que uma trilha leva ao resultado de aprendizagem esperado?
