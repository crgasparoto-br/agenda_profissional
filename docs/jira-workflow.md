# Automacao Jira

Este projeto agora possui um CLI local para operar o Jira Cloud via REST API v3.

O objetivo e permitir que o backlog e a execucao do trabalho sejam controlados daqui, sem depender da interface web do Jira para as tarefas mais comuns.

## Setup

1. Copie a raiz `.env.example` para `.env.local`.
2. Preencha:
   - `JIRA_BASE_URL`
   - `JIRA_EMAIL`
   - `JIRA_API_TOKEN`
   - `JIRA_PROJECT_KEY`
3. Valide a conexao:

```bash
npm run jira:check
```

Para usar outro espaco/projeto no mesmo Jira Cloud, troque apenas `JIRA_PROJECT_KEY`.
Os tipos de issue sao descobertos automaticamente com base na configuracao do projeto.

## Comandos principais

```bash
npm run jira -- help
npm run jira -- check
npm run jira -- project:info
npm run jira -- project:info --project OUTRO
npm run jira -- user:find --query "Carlos"
npm run jira -- issue:create --type Task --summary "Criar dashboard" --description "Primeira versao"
npm run jira -- issue:update KAN-123 --summary "Novo resumo" --description "Detalhes revisados"
npm run jira -- epic:create --summary "Onboarding MVP" --description "Fluxo inicial"
npm run jira -- subtask:create AP-123 --summary "Ajustar contraste"
npm run jira -- comment:add AP-123 --body "Iniciei a implementacao"
npm run jira -- transition:list AP-123
npm run jira -- issue:transition AP-123 --to "In Progress"
npm run jira -- issue:assign AP-123 --account-id "<atlassian-account-id>"
npm run jira -- issue:link-types
npm run jira -- issue:link AP-123 AP-456 --type blocks
npm run jira -- issue:get AP-123
npm run jira -- search --jql "project = AP ORDER BY created DESC"
```

## Planejamento em lote

Use o arquivo [scripts/jira-plan.example.json](/d:/SolverIT/agenda_profissional/scripts/jira-plan.example.json) como modelo.

Aplicar o plano:

```bash
npm run jira -- plan:apply --file scripts/jira-plan.example.json
```

Validar sem criar nada:

```bash
npm run jira -- plan:apply --file scripts/jira-plan.example.json --dry-run
```

## Formato do plano

- `projectKey`: opcional se `JIRA_PROJECT_KEY` estiver definido.
- `epics`: lista de epicos com `children`.
- `issues`: lista de itens soltos.
- `ref`: apelido local para referenciar um item criado no mesmo plano.
- `children`: filhos diretos de um epic.
- `subtasks`: subtarefas de uma issue.
- `links`: relacoes entre issues. Aceita `targetKey` ou `targetRef`.

## Observacoes

- O CLI usa `parent` para relacionamento hierarquico no create/update de issues.
- O tipo padrao, o tipo de epic e o tipo de subtask sao resolvidos automaticamente por projeto.
- Os overrides `JIRA_DEFAULT_ISSUE_TYPE`, `JIRA_EPIC_ISSUE_TYPE` e `JIRA_SUBTASK_ISSUE_TYPE` continuam disponiveis se voce quiser forcar um mapeamento.
- Para company-managed projects que exigem `Epic Name`, configure `JIRA_EPIC_NAME_FIELD`.
- Comentarios e descricoes sao enviados em ADF simples, convertidos a partir de texto puro.
- O comando `issue:transition` tenta resolver o nome da transicao e faz retry curto em caso de `409 Conflict`.

## Extensao VS Code

Ha uma extensao local em `.tools/integracao_jira` para operar a integracao pelo VS Code.

Fluxo rapido:

1. Abra a pasta `.tools/integracao_jira`
2. Pressione `F5`
3. Na janela nova, abra o workspace principal
4. Use `Integracao Jira: Menu`

Na versao `0.1.1`, a extensao tambem suporta:

- editar issue existente
- atribuir responsavel
- criar links entre issues

Empacotar em `.vsix`:

```bash
cd .tools/integracao_jira
npm install
npm run package
```
