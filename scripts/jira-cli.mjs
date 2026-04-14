#!/usr/bin/env node

import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import process from "node:process";

const HELP_TEXT = `
Jira CLI - Agenda Profissional

Uso:
  npm run jira -- help
  npm run jira -- check
  npm run jira -- project:info
  npm run jira -- user:find --query "Carlos"
  npm run jira -- issue:create --type Task --summary "Minha issue" --description "Detalhes"
  npm run jira -- issue:update AP-123 --summary "Novo resumo" --description "Nova descricao"
  npm run jira -- epic:create --summary "Epic" --description "Descricao"
  npm run jira -- subtask:create AP-123 --summary "Subtask" --description "Detalhes"
  npm run jira -- issue:get AP-123
  npm run jira -- comment:add AP-123 --body "Atualizacao do trabalho"
  npm run jira -- transition:list AP-123
  npm run jira -- issue:transition AP-123 --to "In Progress"
  npm run jira -- issue:assign AP-123 --account-id "<account-id>"
  npm run jira -- issue:link-types
  npm run jira -- issue:link AP-123 AP-456 --type blocks
  npm run jira -- search --jql "project = AP ORDER BY created DESC"
  npm run jira -- plan:apply --file scripts/jira-plan.example.json [--dry-run]

Variaveis esperadas em .env/.env.local na raiz:
  JIRA_BASE_URL
  JIRA_EMAIL
  JIRA_API_TOKEN
  JIRA_PROJECT_KEY

Opcionais:
  JIRA_DEFAULT_ISSUE_TYPE
  JIRA_EPIC_ISSUE_TYPE
  JIRA_SUBTASK_ISSUE_TYPE
  JIRA_DEFAULT_LABELS
  JIRA_EPIC_NAME_FIELD
`.trim();

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});

async function main() {
  loadLocalEnv();

  const cli = parseArgs(process.argv.slice(2));
  const command = cli.command ?? "help";

  if (["help", "--help", "-h"].includes(command)) {
    console.log(HELP_TEXT);
    return;
  }

  const config = getConfig();

  switch (command) {
    case "check":
      await handleCheck(config);
      return;
    case "project:info":
      await handleProjectInfo(config, cli);
      return;
    case "user:find":
      await handleUserFind(config, cli);
      return;
    case "issue:get":
      await handleIssueGet(config, cli);
      return;
    case "issue:create":
      await handleIssueCreate(config, cli);
      return;
    case "issue:update":
      await handleIssueUpdate(config, cli);
      return;
    case "epic:create":
      await handleEpicCreate(config, cli);
      return;
    case "subtask:create":
      await handleSubtaskCreate(config, cli);
      return;
    case "comment:add":
      await handleCommentAdd(config, cli);
      return;
    case "transition:list":
      await handleTransitionList(config, cli);
      return;
    case "issue:transition":
      await handleIssueTransition(config, cli);
      return;
    case "issue:assign":
      await handleIssueAssign(config, cli);
      return;
    case "issue:link-types":
      await handleIssueLinkTypes(config);
      return;
    case "issue:link":
      await handleIssueLink(config, cli);
      return;
    case "search":
      await handleSearch(config, cli);
      return;
    case "plan:apply":
      await handlePlanApply(config, cli);
      return;
    default:
      throw new Error(`Comando desconhecido: ${command}\n\n${HELP_TEXT}`);
  }
}

function loadLocalEnv() {
  const files = [".env", ".env.local"];
  const injectedKeys = new Set();

  for (const file of files) {
    const path = resolve(process.cwd(), file);

    if (!existsSync(path)) {
      continue;
    }

    const content = readFileSync(path, "utf8");
    const entries = parseEnvFile(content);

    for (const [key, value] of Object.entries(entries)) {
      if (process.env[key] === undefined || injectedKeys.has(key)) {
        process.env[key] = value;
        injectedKeys.add(key);
      }
    }
  }
}

function parseEnvFile(content) {
  const env = {};

  for (const rawLine of content.split(/\r?\n/u)) {
    const line = rawLine.trim();

    if (!line || line.startsWith("#")) {
      continue;
    }

    const separatorIndex = line.indexOf("=");
    if (separatorIndex === -1) {
      continue;
    }

    const key = line.slice(0, separatorIndex).trim();
    let value = line.slice(separatorIndex + 1).trim();

    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }

    env[key] = value;
  }

  return env;
}

function parseArgs(argv) {
  let command = null;
  const positionals = [];
  const flags = {};

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];

    if (token.startsWith("--")) {
      const [rawKey, inlineValue] = token.slice(2).split("=", 2);

      if (inlineValue !== undefined) {
        flags[rawKey] = inlineValue;
        continue;
      }

      const next = argv[index + 1];
      if (next && !next.startsWith("--")) {
        flags[rawKey] = next;
        index += 1;
      } else {
        flags[rawKey] = true;
      }

      continue;
    }

    if (!command) {
      command = token;
      continue;
    }

    positionals.push(token);
  }

  return { command, positionals, flags };
}

function getConfig() {
  const baseUrl = requireEnv("JIRA_BASE_URL");
  const email = requireEnv("JIRA_EMAIL");
  const apiToken = requireEnv("JIRA_API_TOKEN");

  return {
    baseUrl: baseUrl.replace(/\/+$/u, ""),
    email,
    apiToken,
    projectKey: process.env.JIRA_PROJECT_KEY?.trim() || "",
    defaultIssueType: process.env.JIRA_DEFAULT_ISSUE_TYPE?.trim() || "Task",
    epicIssueType: process.env.JIRA_EPIC_ISSUE_TYPE?.trim() || "Epic",
    subtaskIssueType: process.env.JIRA_SUBTASK_ISSUE_TYPE?.trim() || "Subtask",
    defaultLabels: parseCsv(process.env.JIRA_DEFAULT_LABELS || ""),
    epicNameField: process.env.JIRA_EPIC_NAME_FIELD?.trim() || "",
    projectProfiles: new Map()
  };
}

function requireEnv(name) {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Variavel obrigatoria ausente: ${name}`);
  }

  return value;
}

function parseCsv(value) {
  return value
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function uniqueList(values) {
  return [...new Set(values.filter(Boolean))];
}

function getFlag(cli, ...names) {
  for (const name of names) {
    if (cli.flags[name] !== undefined) {
      return cli.flags[name];
    }
  }

  return undefined;
}

function requirePositional(cli, index, label) {
  const value = cli.positionals[index];
  if (!value) {
    throw new Error(`Parametro obrigatorio ausente: ${label}`);
  }

  return value;
}

function requireText(value, label) {
  if (!value || !String(value).trim()) {
    throw new Error(`Campo obrigatorio ausente: ${label}`);
  }

  return String(value).trim();
}

async function jiraRequest(config, path, init = {}, options = {}) {
  const response = await fetch(`${config.baseUrl}${path}`, {
    ...init,
    headers: {
      Accept: "application/json",
      Authorization: `Basic ${Buffer.from(`${config.email}:${config.apiToken}`).toString("base64")}`,
      ...(init.body ? { "Content-Type": "application/json" } : {}),
      ...init.headers
    }
  });

  const text = await response.text();
  const data = text ? tryParseJson(text) ?? text : null;

  if (!response.ok) {
    if (options.allow404 && response.status === 404) {
      return null;
    }

    const detail = formatJiraError(data);
    throw new Error(`Jira ${response.status} ${response.statusText}${detail ? `: ${detail}` : ""}`);
  }

  return data;
}

function tryParseJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function formatJiraError(data) {
  if (!data) {
    return "";
  }

  if (typeof data === "string") {
    return data;
  }

  const parts = [];

  if (Array.isArray(data.errorMessages)) {
    parts.push(...data.errorMessages);
  }

  if (data.errors && typeof data.errors === "object") {
    for (const [field, message] of Object.entries(data.errors)) {
      parts.push(`${field}: ${message}`);
    }
  }

  return parts.join(" | ");
}

function toAdf(text) {
  const trimmed = String(text || "").trim();
  if (!trimmed) {
    return null;
  }

  const paragraphs = trimmed.split(/\n\s*\n/u).filter(Boolean);
  return {
    type: "doc",
    version: 1,
    content: paragraphs.map((paragraph) => ({
      type: "paragraph",
      content: paragraph.split(/\n/u).flatMap((line, index, lines) => {
        const nodes = [];

        if (line.length > 0) {
          nodes.push({ type: "text", text: line });
        }

        if (index < lines.length - 1) {
          nodes.push({ type: "hardBreak" });
        }

        return nodes;
      })
    }))
  };
}

function mergeLabels(config, labels = []) {
  return uniqueList([...config.defaultLabels, ...labels]);
}

function resolveProjectKey(config, cliOrValue) {
  if (typeof cliOrValue === "string" && cliOrValue.trim()) {
    return cliOrValue.trim();
  }

  const flagProjectKey = typeof cliOrValue === "object" ? getFlag(cliOrValue, "project", "project-key") : undefined;
  if (flagProjectKey && String(flagProjectKey).trim()) {
    return String(flagProjectKey).trim();
  }

  if (config.projectKey) {
    return config.projectKey;
  }

  throw new Error("Defina JIRA_PROJECT_KEY ou passe --project <KEY>.");
}

async function jiraApi(config, resourcePath, init, options) {
  return jiraRequest(config, `/rest/api/3${resourcePath}`, init, options);
}

async function jiraAgile(config, resourcePath, init, options) {
  return jiraRequest(config, `/rest/agile/1.0${resourcePath}`, init, options);
}

async function handleCheck(config) {
  const myself = await jiraApi(config, "/myself");
  const projectKey = config.projectKey || "(nao definido)";
  const projectProfile = config.projectKey ? await resolveProjectProfile(config, config.projectKey) : null;

  console.log(`Conexao Jira OK`);
  console.log(`Usuario: ${myself.displayName} <${myself.emailAddress ?? config.email}>`);
  console.log(`Projeto padrao: ${projectKey}`);
  if (projectProfile) {
    console.log(`Tipos resolvidos: epic=${projectProfile.epicIssueType}, default=${projectProfile.defaultIssueType}, subtask=${projectProfile.subtaskIssueType}`);
  }
}

async function handleProjectInfo(config, cli) {
  const projectKey = resolveProjectKey(config, cli);
  const project = await jiraApi(config, `/project/${encodeURIComponent(projectKey)}`);
  const projectProfile = await resolveProjectProfile(config, projectKey);

  console.log(JSON.stringify({
    id: project.id,
    key: project.key,
    name: project.name,
    style: project.style,
    simplified: project.simplified,
    resolvedTypes: {
      epic: projectProfile.epicIssueType,
      default: projectProfile.defaultIssueType,
      subtask: projectProfile.subtaskIssueType
    },
    issueTypes: Array.isArray(project.issueTypes)
      ? project.issueTypes.map((item) => ({
          id: item.id,
          name: item.name,
          subtask: item.subtask
        }))
      : []
  }, null, 2));
}

async function handleUserFind(config, cli) {
  const query = requireText(getFlag(cli, "query", "q"), "--query");
  const users = await jiraApi(
    config,
    `/user/search?${new URLSearchParams({ query, maxResults: "10" }).toString()}`
  );

  console.log(JSON.stringify(
    users.map((user) => ({
      accountId: user.accountId,
      displayName: user.displayName,
      active: user.active
    })),
    null,
    2
  ));
}

async function handleIssueGet(config, cli) {
  const issueKey = requirePositional(cli, 0, "issue key");
  const issue = await jiraApi(
    config,
    `/issue/${encodeURIComponent(issueKey)}?${new URLSearchParams({
      fields: "summary,status,parent,issuetype,assignee,labels,description,comment"
    }).toString()}`
  );

  console.log(JSON.stringify({
    key: issue.key,
    summary: issue.fields.summary,
    issueType: issue.fields.issuetype?.name,
    status: issue.fields.status?.name,
    parent: issue.fields.parent?.key ?? null,
    assignee: issue.fields.assignee?.displayName ?? null,
    labels: issue.fields.labels ?? [],
    comments: issue.fields.comment?.comments?.map((comment) => ({
      id: comment.id,
      author: comment.author?.displayName ?? null
    })) ?? []
  }, null, 2));
}

async function handleIssueCreate(config, cli) {
  const projectKey = resolveProjectKey(config, cli);
  const projectProfile = await resolveProjectProfile(config, projectKey);
  const issue = await createIssueFromCli(config, cli, {
    projectKey,
    type: getFlag(cli, "type") ? requireText(getFlag(cli, "type"), "--type") : projectProfile.defaultIssueType
  });

  console.log(JSON.stringify(issue, null, 2));
}

async function handleIssueUpdate(config, cli) {
  const issueKey = requirePositional(cli, 0, "issue key");
  const summary = getFlag(cli, "summary");
  const descriptionFlagPresent = getFlag(cli, "description") !== undefined || getFlag(cli, "description-file") !== undefined;
  const description = getTextInput(cli, "description");
  const labelsRaw = getFlag(cli, "labels");
  const clearDescription = Boolean(getFlag(cli, "clear-description"));
  const fields = {};

  if (summary !== undefined) {
    fields.summary = requireText(summary, "--summary");
  }

  if (descriptionFlagPresent) {
    fields.description = description.trim() ? toAdf(description) : null;
  }

  if (clearDescription) {
    fields.description = null;
  }

  if (labelsRaw !== undefined) {
    fields.labels = parseCsv(String(labelsRaw));
  }

  if (Object.keys(fields).length === 0) {
    throw new Error("Informe ao menos um campo para atualizar: --summary, --description, --clear-description ou --labels.");
  }

  await jiraApi(config, `/issue/${encodeURIComponent(issueKey)}`, {
    method: "PUT",
    body: JSON.stringify({ fields })
  });

  const updatedIssue = await jiraApi(
    config,
    `/issue/${encodeURIComponent(issueKey)}?${new URLSearchParams({
      fields: "summary,status,issuetype,assignee,labels"
    }).toString()}`
  );

  console.log(JSON.stringify({
    key: updatedIssue.key,
    summary: updatedIssue.fields.summary,
    issueType: updatedIssue.fields.issuetype?.name ?? null,
    status: updatedIssue.fields.status?.name ?? null,
    assignee: updatedIssue.fields.assignee?.displayName ?? null,
    labels: updatedIssue.fields.labels ?? []
  }, null, 2));
}

async function handleEpicCreate(config, cli) {
  const projectKey = resolveProjectKey(config, cli);
  const projectProfile = await resolveProjectProfile(config, projectKey);
  const issue = await createIssueFromCli(config, cli, {
    projectKey,
    type: projectProfile.epicIssueType,
    epicName: getFlag(cli, "epic-name")
  });

  console.log(JSON.stringify(issue, null, 2));
}

async function handleSubtaskCreate(config, cli) {
  const parent = requirePositional(cli, 0, "parent issue key");
  const projectKey = resolveProjectKey(config, cli);
  const projectProfile = await resolveProjectProfile(config, projectKey);
  const summary = requireText(getFlag(cli, "summary"), "--summary");
  const description = getTextInput(cli, "description");
  const labels = parseCsv(String(getFlag(cli, "labels") || ""));
  const issue = await createIssue(config, {
    projectKey,
    type: projectProfile.subtaskIssueType,
    summary,
    description,
    labels,
    parent
  });

  console.log(JSON.stringify(issue, null, 2));
}

async function handleCommentAdd(config, cli) {
  const issueKey = requirePositional(cli, 0, "issue key");
  const body = requireText(getTextInput(cli, "body"), "--body");

  const comment = await jiraApi(config, `/issue/${encodeURIComponent(issueKey)}/comment`, {
    method: "POST",
    body: JSON.stringify({
      body: toAdf(body)
    })
  });

  console.log(JSON.stringify({
    issueKey,
    commentId: comment.id
  }, null, 2));
}

async function handleTransitionList(config, cli) {
  const issueKey = requirePositional(cli, 0, "issue key");
  const transitions = await getTransitions(config, issueKey);

  console.log(JSON.stringify(
    transitions.map((transition) => ({
      id: transition.id,
      name: transition.name,
      toStatus: transition.to?.name ?? null
    })),
    null,
    2
  ));
}

async function handleIssueTransition(config, cli) {
  const issueKey = requirePositional(cli, 0, "issue key");
  const target = requireText(getFlag(cli, "to", "name"), "--to");
  const result = await transitionIssue(config, issueKey, target);

  console.log(JSON.stringify(result, null, 2));
}

async function handleIssueAssign(config, cli) {
  const issueKey = requirePositional(cli, 0, "issue key");
  const accountId = requireText(getFlag(cli, "account-id"), "--account-id");

  await jiraApi(config, `/issue/${encodeURIComponent(issueKey)}/assignee`, {
    method: "PUT",
    body: JSON.stringify({ accountId })
  });

  console.log(JSON.stringify({ issueKey, accountId }, null, 2));
}

async function handleIssueLinkTypes(config) {
  const payload = await jiraApi(config, "/issueLinkType");

  console.log(JSON.stringify(
    (payload.issueLinkTypes ?? []).map((linkType) => ({
      id: linkType.id,
      name: linkType.name,
      inward: linkType.inward,
      outward: linkType.outward
    })),
    null,
    2
  ));
}

async function handleIssueLink(config, cli) {
  const outwardIssue = requirePositional(cli, 0, "from issue key");
  const inwardIssue = requirePositional(cli, 1, "to issue key");
  const typeName = requireText(getFlag(cli, "type"), "--type");

  await jiraApi(config, "/issueLink", {
    method: "POST",
    body: JSON.stringify({
      type: { name: typeName },
      outwardIssue: { key: outwardIssue },
      inwardIssue: { key: inwardIssue }
    })
  });

  console.log(JSON.stringify({ outwardIssue, inwardIssue, type: typeName }, null, 2));
}

async function handleSearch(config, cli) {
  const jql = requireText(getFlag(cli, "jql"), "--jql");
  const maxResults = String(getFlag(cli, "max-results") || "20");
  const fields = String(getFlag(cli, "fields") || "summary,status,issuetype,parent,assignee");
  const result = await searchIssues(config, { jql, maxResults, fields });

  console.log(JSON.stringify({
    isLast: result.isLast,
    nextPageToken: result.nextPageToken ?? null,
    issues: (result.issues ?? []).map((issue) => ({
      key: issue.key,
      summary: issue.fields?.summary ?? null,
      issueType: issue.fields?.issuetype?.name ?? null,
      status: issue.fields?.status?.name ?? null,
      parent: issue.fields?.parent?.key ?? null,
      assignee: issue.fields?.assignee?.displayName ?? null
    }))
  }, null, 2));
}

async function handlePlanApply(config, cli) {
  const filePath = requireText(getFlag(cli, "file"), "--file");
  const dryRun = Boolean(getFlag(cli, "dry-run"));
  const absolutePath = resolve(process.cwd(), filePath);

  if (!existsSync(absolutePath)) {
    throw new Error(`Arquivo nao encontrado: ${absolutePath}`);
  }

  const raw = readFileSync(absolutePath, "utf8");
  const plan = JSON.parse(raw);
  const projectKey = resolveProjectKey(config, plan.projectKey || cli);
  const projectProfile = await resolveProjectProfile(config, projectKey);

  const summary = summarizePlan(plan, projectKey, projectProfile);

  if (dryRun) {
    console.log(JSON.stringify({ dryRun: true, ...summary }, null, 2));
    return;
  }

  const refs = new Map();
  const created = [];
  const pendingLinks = [];

  if (Array.isArray(plan.epics)) {
    for (const epic of plan.epics) {
      const epicIssue = await createIssue(config, {
        projectKey,
        type: projectProfile.epicIssueType,
        summary: requireText(epic.summary, "epic.summary"),
        description: epic.description || "",
        labels: epic.labels || [],
        epicName: epic.epicName || epic.summary
      });

      registerRef(refs, epic.ref, epicIssue.key);
      created.push({ ref: epic.ref || null, key: epicIssue.key, type: projectProfile.epicIssueType, summary: epic.summary });

      for (const child of epic.children || []) {
        await createPlanItem(config, refs, created, pendingLinks, projectKey, projectProfile, child, {
          parent: epicIssue.key,
          defaultType: projectProfile.defaultIssueType
        });
      }
    }
  }

  if (Array.isArray(plan.issues)) {
    for (const item of plan.issues) {
      await createPlanItem(config, refs, created, pendingLinks, projectKey, projectProfile, item, {
        defaultType: projectProfile.defaultIssueType
      });
    }
  }

  for (const pendingLink of pendingLinks) {
    const targetKey = resolveTargetReference(refs, pendingLink.link);
    if (!targetKey) {
      throw new Error(`Nao foi possivel resolver link para ${pendingLink.fromKey}`);
    }

    await jiraApi(config, "/issueLink", {
      method: "POST",
      body: JSON.stringify({
        type: { name: requireText(pendingLink.link.type, "link.type") },
        outwardIssue: { key: pendingLink.fromKey },
        inwardIssue: { key: targetKey }
      })
    });
  }

  console.log(JSON.stringify({ projectKey, created }, null, 2));
}

function summarizePlan(plan, projectKey, projectProfile) {
  const counters = { epics: 0, issues: 0, subtasks: 0, projectKey };

  for (const epic of plan.epics || []) {
    counters.epics += 1;
    walkPlanItems(epic.children || [], counters, projectProfile.defaultIssueType);
  }

  walkPlanItems(plan.issues || [], counters, projectProfile.defaultIssueType);
  return counters;
}

function walkPlanItems(items, counters, defaultType = "Task") {
  for (const item of items) {
    const resolvedType = normalizeIssueTypeName(item.type || defaultType);

    if (resolvedType === "subtask" || resolvedType === "sub-task" || resolvedType === "subtarefa") {
      counters.subtasks += 1;
    } else {
      counters.issues += 1;
    }

    walkPlanItems(item.children || [], counters, defaultType);
    walkPlanItems(item.subtasks || [], counters, "Subtask");
  }
}

async function createPlanItem(config, refs, created, pendingLinks, projectKey, projectProfile, item, context = {}) {
  const resolvedParent = resolveParentReference(refs, item.parentRef) || item.parent || context.parent || null;
  const explicitType = item.type || context.defaultType || projectProfile.defaultIssueType;

  const issue = await createIssue(config, {
    projectKey,
    type: explicitType,
    summary: requireText(item.summary, "item.summary"),
    description: item.description || "",
    labels: item.labels || [],
    parent: resolvedParent,
    epicName: item.epicName
  });

  registerRef(refs, item.ref, issue.key);
  created.push({ ref: item.ref || null, key: issue.key, type: explicitType, summary: item.summary });

  for (const link of item.links || []) {
    pendingLinks.push({ fromKey: issue.key, link });
  }

  for (const child of item.children || []) {
    await createPlanItem(config, refs, created, pendingLinks, projectKey, projectProfile, child, {
      parent: issue.key,
      defaultType: projectProfile.defaultIssueType
    });
  }

  for (const subtask of item.subtasks || []) {
    await createPlanItem(
      config,
      refs,
      created,
      pendingLinks,
      projectKey,
      projectProfile,
      { ...subtask, type: projectProfile.subtaskIssueType },
      {
        parent: issue.key,
        defaultType: projectProfile.subtaskIssueType
      }
    );
  }
}

function registerRef(refs, ref, key) {
  if (!ref) {
    return;
  }

  if (refs.has(ref)) {
    throw new Error(`Referencia duplicada no plano: ${ref}`);
  }

  refs.set(ref, key);
}

function resolveParentReference(refs, ref) {
  if (!ref) {
    return null;
  }

  const resolved = refs.get(ref);
  if (!resolved) {
    throw new Error(`Referencia pai nao encontrada: ${ref}`);
  }

  return resolved;
}

function resolveTargetReference(refs, link) {
  if (link.targetKey) {
    return link.targetKey;
  }

  if (link.targetRef) {
    const resolved = refs.get(link.targetRef);
    if (!resolved) {
      throw new Error(`Referencia de link nao encontrada: ${link.targetRef}`);
    }

    return resolved;
  }

  return null;
}

async function createIssueFromCli(config, cli, overrides = {}) {
  const summary = requireText(getFlag(cli, "summary"), "--summary");
  const description = getTextInput(cli, "description");
  const labels = parseCsv(String(getFlag(cli, "labels") || ""));
  const parent = getFlag(cli, "parent");
  const projectKey = overrides.projectKey || resolveProjectKey(config, cli);

  return createIssue(config, {
    projectKey,
    type: overrides.type,
    summary,
    description,
    labels,
    parent,
    epicName: overrides.epicName
  });
}

function getTextInput(cli, flagName) {
  const direct = getFlag(cli, flagName);
  if (direct !== undefined) {
    return String(direct);
  }

  const fileFlag = getFlag(cli, `${flagName}-file`);
  if (fileFlag) {
    const filePath = resolve(process.cwd(), String(fileFlag));
    if (!existsSync(filePath)) {
      throw new Error(`Arquivo nao encontrado: ${filePath}`);
    }

    return readFileSync(filePath, "utf8");
  }

  return "";
}

async function createIssue(config, input) {
  const projectProfile = await resolveProjectProfile(config, input.projectKey);
  const fields = {
    project: { key: input.projectKey },
    issuetype: { name: input.type },
    summary: input.summary
  };

  if (input.description?.trim()) {
    fields.description = toAdf(input.description);
  }

  const labels = mergeLabels(config, input.labels || []);
  if (labels.length > 0) {
    fields.labels = labels;
  }

  if (input.parent) {
    fields.parent = { key: input.parent };
  }

  if (config.epicNameField && equalsIgnoreCase(input.type, projectProfile.epicIssueType)) {
    fields[config.epicNameField] = input.epicName || input.summary;
  }

  try {
    const created = await jiraApi(config, "/issue", {
      method: "POST",
      body: JSON.stringify({ fields })
    });

    return {
      id: created.id,
      key: created.key,
      self: created.self
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    const canFallbackToEpicLink =
      input.parent &&
      !isSubtaskTypeName(input.type, projectProfile) &&
      !equalsIgnoreCase(input.type, projectProfile.epicIssueType) &&
      /(parent|hierarchy|epic)/iu.test(errorMessage);

    if (!canFallbackToEpicLink) {
      throw error;
    }

    const parentType = await getIssueTypeName(config, input.parent);
    if (!equalsIgnoreCase(parentType, projectProfile.epicIssueType)) {
      throw error;
    }

    const fallbackFields = { ...fields };
    delete fallbackFields.parent;

    const created = await jiraApi(config, "/issue", {
      method: "POST",
      body: JSON.stringify({ fields: fallbackFields })
    });

    await jiraAgile(config, `/epic/${encodeURIComponent(input.parent)}/issue`, {
      method: "POST",
      body: JSON.stringify({
        issues: [created.key]
      })
    });

    return {
      id: created.id,
      key: created.key,
      self: created.self
    };
  }
}

async function getTransitions(config, issueKey) {
  const payload = await jiraApi(config, `/issue/${encodeURIComponent(issueKey)}/transitions`);
  return payload.transitions ?? [];
}

async function transitionIssue(config, issueKey, target) {
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    const transitions = await getTransitions(config, issueKey);
    const transition = transitions.find((item) => equalsIgnoreCase(item.name, target) || equalsIgnoreCase(item.to?.name, target));

    if (!transition) {
      throw new Error(`Transicao nao encontrada para ${issueKey}: ${target}`);
    }

    try {
      await jiraApi(config, `/issue/${encodeURIComponent(issueKey)}/transitions`, {
        method: "POST",
        body: JSON.stringify({
          transition: { id: transition.id }
        })
      });

      return {
        issueKey,
        transitionId: transition.id,
        transitionName: transition.name,
        targetStatus: transition.to?.name ?? null
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      const isConflict = message.includes(" 409 ");

      if (!isConflict || attempt === 3) {
        throw error;
      }

      await sleep(500 * attempt);
    }
  }

  throw new Error(`Nao foi possivel transicionar ${issueKey}.`);
}

function equalsIgnoreCase(left, right) {
  return String(left || "").trim().toLowerCase() === String(right || "").trim().toLowerCase();
}

function isSubtaskTypeName(typeName, projectProfile) {
  const normalized = normalizeIssueTypeName(typeName);
  return normalized === normalizeIssueTypeName(projectProfile.subtaskIssueType) || normalized === "sub-task";
}

async function getIssueTypeName(config, issueKey) {
  const issue = await jiraApi(
    config,
    `/issue/${encodeURIComponent(issueKey)}?${new URLSearchParams({ fields: "issuetype" }).toString()}`
  );

  return issue.fields?.issuetype?.name || "";
}

async function searchIssues(config, input) {
  const params = new URLSearchParams({
    jql: input.jql,
    maxResults: String(input.maxResults),
    fields: input.fields
  });

  try {
    return await jiraApi(config, `/search/jql?${params.toString()}`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const shouldFallback =
      message.includes(" 404 ") ||
      message.includes(" 405 ") ||
      message.includes(" 400 ");

    if (!shouldFallback) {
      throw error;
    }

    const legacyResult = await jiraApi(config, "/search", {
      method: "POST",
      body: JSON.stringify({
        jql: input.jql,
        maxResults: Number(input.maxResults),
        fields: String(input.fields)
          .split(",")
          .map((field) => field.trim())
          .filter(Boolean)
      })
    });

    return {
      isLast: true,
      nextPageToken: null,
      issues: legacyResult.issues ?? []
    };
  }
}

async function resolveProjectProfile(config, projectKey) {
  if (config.projectProfiles.has(projectKey)) {
    return config.projectProfiles.get(projectKey);
  }

  const project = await jiraApi(config, `/project/${encodeURIComponent(projectKey)}`);
  const issueTypes = Array.isArray(project.issueTypes) ? project.issueTypes : [];

  const profile = {
    key: project.key,
    style: project.style,
    simplified: project.simplified,
    defaultIssueType: pickDefaultIssueType(config, issueTypes),
    epicIssueType: pickEpicIssueType(config, issueTypes),
    subtaskIssueType: pickSubtaskIssueType(config, issueTypes),
    issueTypes
  };

  config.projectProfiles.set(projectKey, profile);
  return profile;
}

function pickEpicIssueType(config, issueTypes) {
  const override = findIssueTypeByName(issueTypes, config.epicIssueType);
  if (override) {
    return override.name;
  }

  const match = findIssueTypeBySynonyms(issueTypes, ["epic"]);
  return match?.name || "Epic";
}

function pickSubtaskIssueType(config, issueTypes) {
  const override = findIssueTypeByName(issueTypes, config.subtaskIssueType);
  if (override) {
    return override.name;
  }

  const subtask = issueTypes.find((item) => item.subtask);
  if (subtask) {
    return subtask.name;
  }

  const match = findIssueTypeBySynonyms(issueTypes, ["subtask", "sub-task", "subtarefa"]);
  return match?.name || "Subtask";
}

function pickDefaultIssueType(config, issueTypes) {
  const override = findIssueTypeByName(issueTypes, config.defaultIssueType);
  if (override) {
    return override.name;
  }

  const candidates = issueTypes.filter((item) => !item.subtask && normalizeIssueTypeName(item.name) !== "epic");
  const preferred = findIssueTypeBySynonyms(candidates, ["task", "tarefa", "story", "historia", "história"]);
  if (preferred) {
    return preferred.name;
  }

  return candidates[0]?.name || config.defaultIssueType || "Task";
}

function findIssueTypeByName(issueTypes, name) {
  return issueTypes.find((item) => normalizeIssueTypeName(item.name) === normalizeIssueTypeName(name));
}

function findIssueTypeBySynonyms(issueTypes, synonyms) {
  const normalizedSynonyms = synonyms.map((item) => normalizeIssueTypeName(item));
  return issueTypes.find((item) => normalizedSynonyms.includes(normalizeIssueTypeName(item.name)));
}

function normalizeIssueTypeName(value) {
  return String(value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/gu, "")
    .trim()
    .toLowerCase();
}

function sleep(ms) {
  return new Promise((resolvePromise) => {
    setTimeout(resolvePromise, ms);
  });
}
