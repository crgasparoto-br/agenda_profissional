const vscode = require("vscode");
const { execFile } = require("node:child_process");
const { promisify } = require("node:util");

const execFileAsync = promisify(execFile);

let statusBarItem;
let outputChannel;

function activate(context) {
  outputChannel = vscode.window.createOutputChannel("Integracao Jira");
  statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
  statusBarItem.command = "integracaoJira.openMenu";
  context.subscriptions.push(outputChannel, statusBarItem);

  const commandHandlers = [
    ["integracaoJira.openMenu", openMenu],
    ["integracaoJira.checkConnection", checkConnection],
    ["integracaoJira.projectInfo", projectInfo],
    ["integracaoJira.createEpic", createEpic],
    ["integracaoJira.createIssue", createIssue],
    ["integracaoJira.updateIssue", updateIssue],
    ["integracaoJira.createSubtask", createSubtask],
    ["integracaoJira.addComment", addComment],
    ["integracaoJira.assignIssue", assignIssue],
    ["integracaoJira.linkIssues", linkIssues],
    ["integracaoJira.transitionIssue", transitionIssue],
    ["integracaoJira.searchIssues", searchIssues],
    ["integracaoJira.applyPlan", applyPlan]
  ];

  for (const [command, handler] of commandHandlers) {
    context.subscriptions.push(vscode.commands.registerCommand(command, handler));
  }

  context.subscriptions.push(vscode.workspace.onDidChangeConfiguration((event) => {
    if (event.affectsConfiguration("integracaoJira")) {
      updateStatusBar().catch(showError);
    }
  }));

  updateStatusBar().catch(showError);
}

function deactivate() {}

async function openMenu() {
  const items = [
    { label: "Check Connection", command: "integracaoJira.checkConnection" },
    { label: "Project Info", command: "integracaoJira.projectInfo" },
    { label: "Create Epic", command: "integracaoJira.createEpic" },
    { label: "Create Issue", command: "integracaoJira.createIssue" },
    { label: "Update Issue", command: "integracaoJira.updateIssue" },
    { label: "Create Subtask", command: "integracaoJira.createSubtask" },
    { label: "Add Comment", command: "integracaoJira.addComment" },
    { label: "Assign Issue", command: "integracaoJira.assignIssue" },
    { label: "Link Issues", command: "integracaoJira.linkIssues" },
    { label: "Transition Issue", command: "integracaoJira.transitionIssue" },
    { label: "Search Issues", command: "integracaoJira.searchIssues" },
    { label: "Apply Plan", command: "integracaoJira.applyPlan" }
  ];

  const picked = await vscode.window.showQuickPick(items, {
    placeHolder: "Escolha uma acao de Jira"
  });

  if (picked) {
    await vscode.commands.executeCommand(picked.command);
  }
}

async function checkConnection() {
  const result = await runCli(["check"], { json: false });
  showOutput("jira-check.txt", result.stdout || "Conexao validada.");
  vscode.window.showInformationMessage("Jira conectado com sucesso.");
}

async function projectInfo() {
  const projectKey = await pickProjectKey();
  if (!projectKey) {
    return;
  }

  const result = await runCli(["project:info", "--project", projectKey], { json: true });
  showOutput("jira-project-info.json", JSON.stringify(result.json, null, 2), "json");
}

async function createEpic() {
  const summary = await ask("Resumo do epic");
  if (!summary) {
    return;
  }

  const description = await ask("Descricao do epic", { multiLine: true });
  if (description === undefined) {
    return;
  }

  const args = ["epic:create", "--summary", summary];
  if (description.trim()) {
    args.push("--description", description);
  }

  const projectKey = await pickProjectKey();
  if (!projectKey) {
    return;
  }

  args.push("--project", projectKey);

  const result = await runCli(args, { json: true });
  notifyIssueCreated("Epic criado", result.json);
}

async function createIssue() {
  const projectKey = await pickProjectKey();
  if (!projectKey) {
    return;
  }

  const projectInfoResult = await runCli(["project:info", "--project", projectKey], { json: true });
  const issueTypes = (projectInfoResult.json.issueTypes || []).filter((item) => !item.subtask);
  const defaultType = projectInfoResult.json.resolvedTypes?.default || issueTypes[0]?.name || "Task";

  const type = await pickIssueType(issueTypes, defaultType, "Escolha o tipo da issue");
  if (!type) {
    return;
  }

  const summary = await ask("Resumo da issue");
  if (!summary) {
    return;
  }

  const description = await ask("Descricao da issue", { multiLine: true });
  if (description === undefined) {
    return;
  }

  const args = ["issue:create", "--project", projectKey, "--type", type, "--summary", summary];
  if (description.trim()) {
    args.push("--description", description);
  }

  const result = await runCli(args, { json: true });
  notifyIssueCreated("Issue criada", result.json);
}

async function updateIssue() {
  const issueKey = await ask("Issue para atualizar, ex.: KAN-123");
  if (!issueKey) {
    return;
  }

  const currentIssue = await runCli(["issue:get", issueKey], { json: true });
  const current = currentIssue.json;

  const summary = await ask("Novo resumo da issue", {
    value: current.summary || ""
  });
  if (summary === undefined) {
    return;
  }

  const description = await ask("Nova descricao da issue. Deixe vazio para nao alterar.", {
    value: ""
  });
  if (description === undefined) {
    return;
  }

  const labels = await ask("Labels separadas por virgula. Deixe vazio para nao alterar.", {
    value: ""
  });
  if (labels === undefined) {
    return;
  }

  const args = ["issue:update", issueKey];

  if (summary.trim() && summary.trim() !== (current.summary || "").trim()) {
    args.push("--summary", summary.trim());
  }

  if (description.trim()) {
    args.push("--description", description);
  }

  if (labels.trim()) {
    args.push("--labels", labels);
  }

  if (args.length === 2) {
    vscode.window.showInformationMessage("Nenhuma alteracao informada.");
    return;
  }

  const result = await runCli(args, { json: true });
  showOutput("jira-update.json", JSON.stringify(result.json, null, 2), "json");
  vscode.window.showInformationMessage(`Issue ${result.json.key} atualizada.`);
}

async function createSubtask() {
  const parent = await ask("Issue pai, ex.: KAN-123");
  if (!parent) {
    return;
  }

  const summary = await ask("Resumo da subtask");
  if (!summary) {
    return;
  }

  const description = await ask("Descricao da subtask", { multiLine: true });
  if (description === undefined) {
    return;
  }

  const projectKey = await pickProjectKey();
  if (!projectKey) {
    return;
  }

  const args = ["subtask:create", parent, "--project", projectKey, "--summary", summary];
  if (description.trim()) {
    args.push("--description", description);
  }

  const result = await runCli(args, { json: true });
  notifyIssueCreated("Subtask criada", result.json);
}

async function addComment() {
  const issueKey = await ask("Issue para comentar, ex.: KAN-123");
  if (!issueKey) {
    return;
  }

  const body = await ask("Comentario", { multiLine: true });
  if (!body) {
    return;
  }

  const result = await runCli(["comment:add", issueKey, "--body", body], { json: true });
  showOutput("jira-comment.json", JSON.stringify(result.json, null, 2), "json");
  vscode.window.showInformationMessage(`Comentario adicionado em ${issueKey}.`);
}

async function assignIssue() {
  const issueKey = await ask("Issue para atribuir, ex.: KAN-123");
  if (!issueKey) {
    return;
  }

  const query = await ask("Nome ou email para buscar usuario no Jira");
  if (!query) {
    return;
  }

  const usersResult = await runCli(["user:find", "--query", query], { json: true });
  const users = usersResult.json || [];

  if (users.length === 0) {
    vscode.window.showWarningMessage("Nenhum usuario encontrado.");
    return;
  }

  const picked = await vscode.window.showQuickPick(
    users.map((user) => ({
      label: user.displayName,
      description: user.active ? "ativo" : "inativo",
      detail: user.accountId,
      value: user
    })),
    { placeHolder: "Selecione o responsavel" }
  );

  if (!picked) {
    return;
  }

  const result = await runCli(["issue:assign", issueKey, "--account-id", picked.value.accountId], { json: true });
  showOutput("jira-assign.json", JSON.stringify(result.json, null, 2), "json");
  vscode.window.showInformationMessage(`Issue ${issueKey} atribuida para ${picked.label}.`);
}

async function linkIssues() {
  const fromIssue = await ask("Issue de origem, ex.: KAN-123");
  if (!fromIssue) {
    return;
  }

  const toIssue = await ask("Issue de destino, ex.: KAN-456");
  if (!toIssue) {
    return;
  }

  const linkTypesResult = await runCli(["issue:link-types"], { json: true });
  const linkTypes = linkTypesResult.json || [];

  if (linkTypes.length === 0) {
    vscode.window.showWarningMessage("Nenhum tipo de link retornado pelo Jira.");
    return;
  }

  const picked = await vscode.window.showQuickPick(
    linkTypes.map((linkType) => ({
      label: linkType.name,
      description: `${linkType.outward} / ${linkType.inward}`,
      value: linkType.name
    })),
    { placeHolder: "Selecione o tipo de link" }
  );

  if (!picked) {
    return;
  }

  const result = await runCli(["issue:link", fromIssue, toIssue, "--type", picked.value], { json: true });
  showOutput("jira-link.json", JSON.stringify(result.json, null, 2), "json");
  vscode.window.showInformationMessage(`Link criado entre ${fromIssue} e ${toIssue}.`);
}

async function transitionIssue() {
  const issueKey = await ask("Issue para transicionar, ex.: KAN-123");
  if (!issueKey) {
    return;
  }

  const transitionsResult = await runCli(["transition:list", issueKey], { json: true });
  const transitions = transitionsResult.json || [];
  if (transitions.length === 0) {
    vscode.window.showWarningMessage(`Nenhuma transicao disponivel para ${issueKey}.`);
    return;
  }

  const picked = await vscode.window.showQuickPick(
    transitions.map((transition) => ({
      label: transition.name,
      description: transition.toStatus || "",
      value: transition.name
    })),
    { placeHolder: `Escolha a transicao para ${issueKey}` }
  );

  if (!picked) {
    return;
  }

  const result = await runCli(["issue:transition", issueKey, "--to", picked.value], { json: true });
  showOutput("jira-transition.json", JSON.stringify(result.json, null, 2), "json");
  vscode.window.showInformationMessage(`${issueKey} movida para ${result.json.targetStatus || picked.value}.`);
}

async function searchIssues() {
  const projectKey = await pickProjectKey();
  if (!projectKey) {
    return;
  }

  const jql = await ask("JQL para busca", {
    value: `project = ${projectKey} ORDER BY updated DESC`
  });
  if (!jql) {
    return;
  }

  const result = await runCli(["search", "--jql", jql], { json: true });
  const issues = result.json.issues || [];

  if (issues.length === 0) {
    vscode.window.showInformationMessage("Nenhuma issue encontrada.");
    return;
  }

  const picked = await vscode.window.showQuickPick(
    issues.map((issue) => ({
      label: issue.key,
      description: issue.status || "",
      detail: `${issue.issueType || ""} - ${issue.summary || ""}`,
      value: issue
    })),
    { placeHolder: "Resultados da busca. Escolha uma issue para copiar a chave." }
  );

  showOutput("jira-search.json", JSON.stringify(result.json, null, 2), "json");

  if (picked) {
    await vscode.env.clipboard.writeText(picked.value.key);
    vscode.window.showInformationMessage(`Chave ${picked.value.key} copiada para a area de transferencia.`);
  }
}

async function applyPlan() {
  const config = getExtensionConfig();
  const defaultPlan = resolveWorkspacePath(config.get("planFilePath", "${workspaceFolder}/scripts/jira-plan.example.json"));
  const selected = await vscode.window.showOpenDialog({
    canSelectMany: false,
    defaultUri: vscode.Uri.file(defaultPlan),
    filters: {
      JSON: ["json"]
    },
    openLabel: "Selecionar arquivo de plano Jira"
  });

  if (!selected || selected.length === 0) {
    return;
  }

  const dryRunChoice = await vscode.window.showQuickPick(
    [
      { label: "Validar apenas (dry-run)", value: true },
      { label: "Aplicar no Jira", value: false }
    ],
    { placeHolder: "Como deseja executar o plano?" }
  );

  if (!dryRunChoice) {
    return;
  }

  const projectKey = await pickProjectKey();
  if (!projectKey) {
    return;
  }

  const args = ["plan:apply", "--file", selected[0].fsPath, "--project", projectKey];
  if (dryRunChoice.value) {
    args.push("--dry-run");
  }

  const result = await runCli(args, { json: true });
  showOutput("jira-plan-result.json", JSON.stringify(result.json, null, 2), "json");
  vscode.window.showInformationMessage(
    dryRunChoice.value ? "Plano validado com sucesso." : "Plano aplicado no Jira com sucesso."
  );
}

async function pickProjectKey() {
  const config = getExtensionConfig();
  const configuredKey = (config.get("projectKey", "") || "").trim();
  if (configuredKey) {
    return configuredKey;
  }

  const projectInfo = await runCli(["project:info"], { json: true });
  const defaultKey = projectInfo.json.key;

  const typed = await ask("Project key do Jira", { value: defaultKey });
  return typed ? typed.trim() : "";
}

async function pickIssueType(issueTypes, defaultType, placeHolder) {
  const picked = await vscode.window.showQuickPick(
    issueTypes.map((item) => ({
      label: item.name,
      description: item.name === defaultType ? "padrao" : "",
      value: item.name
    })),
    { placeHolder }
  );

  return picked ? picked.value : "";
}

function getExtensionConfig() {
  return vscode.workspace.getConfiguration("integracaoJira");
}

async function updateStatusBar() {
  const config = getExtensionConfig();
  const configuredKey = (config.get("projectKey", "") || "").trim();

  if (configuredKey) {
    statusBarItem.text = `$(issues) Jira ${configuredKey}`;
    statusBarItem.tooltip = "Abrir menu do Jira";
    statusBarItem.show();
    return;
  }

  try {
    const result = await runCli(["project:info"], { json: true });
    statusBarItem.text = `$(issues) Jira ${result.json.key}`;
  } catch {
    statusBarItem.text = "$(issues) Jira";
  }

  statusBarItem.tooltip = "Abrir menu do Jira";
  statusBarItem.show();
}

async function runCli(args, options = {}) {
  const workspaceFolder = getWorkspaceFolder();
  const config = getExtensionConfig();
  const cliPath = resolveWorkspacePath(config.get("cliPath", "${workspaceFolder}/scripts/jira-cli.mjs"));
  const nodePath = config.get("nodePath", "node");
  const fullArgs = [cliPath, ...args];

  outputChannel.appendLine(`> ${nodePath} ${fullArgs.map(quoteArg).join(" ")}`);

  try {
    const result = await execFileAsync(nodePath, fullArgs, {
      cwd: workspaceFolder,
      env: process.env,
      windowsHide: true,
      maxBuffer: 10 * 1024 * 1024
    });

    const stdout = (result.stdout || "").trim();
    const stderr = (result.stderr || "").trim();

    if (stdout) {
      outputChannel.appendLine(stdout);
    }

    if (stderr) {
      outputChannel.appendLine(stderr);
    }

    if (options.json) {
      return {
        stdout,
        stderr,
        json: stdout ? JSON.parse(stdout) : {}
      };
    }

    return { stdout, stderr };
  } catch (error) {
    const stdout = (error.stdout || "").trim();
    const stderr = (error.stderr || "").trim();
    if (stdout) {
      outputChannel.appendLine(stdout);
    }

    if (stderr) {
      outputChannel.appendLine(stderr);
    }

    const message = stderr || stdout || error.message || "Falha ao executar Jira CLI.";
    throw new Error(message);
  }
}

function getWorkspaceFolder() {
  const folder = vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders[0];
  if (!folder) {
    throw new Error("Abra uma pasta de projeto no VS Code para usar a extensao do Jira.");
  }

  return folder.uri.fsPath;
}

function resolveWorkspacePath(value) {
  const workspaceFolder = getWorkspaceFolder();
  return value.replace(/\$\{workspaceFolder\}/gu, workspaceFolder);
}

async function ask(prompt, options = {}) {
  return vscode.window.showInputBox({
    prompt,
    value: options.value || "",
    ignoreFocusOut: true
  });
}

function showOutput(fileName, content, language = "plaintext") {
  outputChannel.show(true);
  vscode.workspace
    .openTextDocument({ content, language })
    .then((document) => vscode.window.showTextDocument(document, { preview: false }));
}

function notifyIssueCreated(title, payload) {
  showOutput("jira-create-result.json", JSON.stringify(payload, null, 2), "json");
  vscode.window.showInformationMessage(`${title}: ${payload.key}`);
}

function quoteArg(value) {
  if (!/\s/u.test(value)) {
    return value;
  }

  return `"${String(value).replace(/"/gu, '\\"')}"`;
}

function showError(error) {
  const message = error instanceof Error ? error.message : String(error);
  outputChannel.show(true);
  vscode.window.showErrorMessage(message);
}

module.exports = {
  activate,
  deactivate
};
