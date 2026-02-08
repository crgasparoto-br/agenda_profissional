# AGENTS.md - Agenda Profissional

## Objetivo
Persistir e aplicar a identidade visual da marca **Agenda Profissional** em toda tarefa de UI/UX (web, mobile, landing, dashboard, onboarding e componentes).

## Regra de aplicação
- Sempre que criar, alterar ou revisar interface, seguir estas definições como padrão.
- Em caso de conflito entre preferência estética pontual e estas diretrizes, priorizar estas diretrizes.
- Manter acessibilidade (WCAG AA) e consistência visual em todos os fluxos.

## 1) Fundamentos da marca
- Nome: `Agenda Profissional`
- Posicionamento: SaaS de agendamento e gestão de clientes para profissionais autônomos e pequenas clínicas.
- Promessa: "Sua agenda, organizada, confiável e sempre sob controle."
- Tradução visual:
- Organização: grid, alinhamento e espaçamentos consistentes.
- Confiabilidade: predominância de azul e verde com contraste estável.
- Produtividade: hierarquia forte e baixo ruído visual.
- Profissionalismo: tipografia neutra e destaques contidos.

## 2) Sistema de cores (tokens oficiais)
- `--ap-color-primary`: `#1F3A5F` (Azul Profundo)
- `--ap-color-secondary`: `#1FA4A9` (Teal)
- `--ap-color-bg`: `#FFFFFF`
- `--ap-color-surface`: `#F4F6F8`
- `--ap-color-muted`: `#AAB2BD`
- `--ap-color-text`: `#2E3440`
- `--ap-color-accent`: `#F4A261` (uso total recomendado: 5-8% da interface)

### Regras de contraste
- Botão primário: fundo escuro com texto branco.
- Nunca usar texto sobre `accent` sem contraste suficiente.
- Garantir contraste mínimo AA para texto, estados e componentes interativos.

## 3) Tipografia
- Fonte principal: `Inter` (fallback: `Source Sans 3`).
- Hierarquia:
- H1: Inter SemiBold
- H2: Inter Medium
- Texto padrão: Inter Regular
- Rótulos/metadados: Inter Medium com tamanho reduzido
- Dados numéricos: alinhamento tabular; datas e horários com espaçamento consistente.

## 4) Iconografia
- Estilo: linear, cantos levemente arredondados.
- Stroke: 2px no web (ajustado no mobile proporcionalmente).
- Metáforas prioritárias: calendário, check/confirmação, relógio/linha do tempo, fluxo/reagendamento.
- Evitar: ícones cartunizados, figuras humanas e ícones excessivamente detalhados.

## 5) Layout e espaçamento
- Grid base: 8pt.
- Border radius padrão de cards/inputs/botões: 12-16px (preferir 12px em componentes, 16px em cards maiores).
- Ritmo vertical consistente e alinhamento à esquerda.
- Superfícies flat, com borda 1px sutil ou sombra leve.
- Evitar gradientes; usar apenas microprofundidade quando necessário.

## 6) Linguagem gráfica e motion
- Formas abstratas inspiradas em calendário, blocos de horário, grades semanais e fluxos.
- Usar retângulos arredondados e camadas de baixa opacidade.
- Animações sutis: `fade`, `slide`, `scale` (sem bounce).

## 7) Ícone do aplicativo
- Conceito: calendário estilizado com um bloco destacado.
- Construção: fundo quadrado com cantos arredondados (azul ou teal), grade clara e um único destaque em laranja ou teal.
- Requisito: legível em tamanhos pequenos.

## 8) Splash screen
- Fundo branco ou cinza muito claro.
- Logo centralizada.
- Grade abstrata de fundo com 5-8% de opacidade.
- Sem excesso de texto.

## 9) Login e onboarding
- Login: card limpo, pouco texto, uma ação principal clara.
- Onboarding: máximo de 3-4 telas.
- Visuais abstratos ligados a agenda/blocos/fluxo.
- Títulos orientados a benefício:
- "Organize sua agenda"
- "Reduza faltas e cancelamentos"
- "Ganhe tempo todos os dias"

## 10) Dashboard e agenda
- A agenda é o elemento central.
- Dia atual sempre destacado.
- Conflitos e horários livres claramente diferenciados.
- Codificação de estados:
- Confirmado: Teal
- Pendente: contorno cinza
- Cancelado: vermelho discreto
- Disponível: cinza claro

## 11) Componentes de UI
- Botão primário: Azul Profundo.
- Botão secundário: outline.
- Botão destrutivo: vermelho suave.
- Raio padrão: 12px.
- Cards: fundo cinza claro, borda sutil/sombra leve, espaçamento interno bem definido.
- Formulários: campos full width, foco visível, label sempre visível (não depender de placeholder).

## Diretriz final de consistência
- Toda entrega visual nova deve parecer parte do mesmo sistema de design do Agenda Profissional.
- Evitar estilos genéricos, aleatórios ou que desviem da paleta/hierarquia definida acima.

## 12) Contexto de produto (AgendaProfi)
- Aplicar estas definicoes em backlog, arquitetura, UX, copy e priorizacao funcional.
- Tratar `Agenda Profissional` e `AgendaProfi` como a mesma marca/produto neste projeto.

### Objetivo do produto
- Produto: AgendaProfi (agendamento e gestao de clientes para profissionais).
- Foco: reduzir faltas, evitar conflitos de agenda, aumentar previsibilidade de receita e produtividade.

### Perfil do usuario
- Profissional liberal com atendimento presencial.
- Exemplos: cabeleireiro, dentista, terapeuta, personal trainer, consultor.
- Contexto: atende varios clientes por dia e sofre com cancelamentos, no-show e duplicidade de horario.

### Problema central
- Dores principais:
- cliente nao aparece e nao avisa
- agendamento duplicado
- perda de horario produtivo
- cliente esquece compromisso
- Frequencia: diaria, impactando varios atendimentos.
- Perdas: dinheiro, tempo operacional e satisfacao/retencao de clientes.

### Problema invisivel
- Sentimento recorrente: frustracao e sensacao de desorganizacao.
- Riscos silenciosos:
- receita imprevisivel
- dificuldade de planejamento diario
- perda de clientes por falha de confirmacao

### Solucao via app
- Agendamento online self-service.
- Confirmacao automatica por SMS/WhatsApp.
- Lembretes automatizados (ex.: 24h antes).
- Bloqueio de horarios duplicados.
- Visao clara de agenda para o profissional.
- IA para:
- sugerir organizacao de agenda e intervalos (descanso e entre consultas)
- conversar com cliente via WhatsApp para escolha de horario
- analisar cancelamento e sugerir realocacao
- estimar deslocamento cliente -> local de atendimento e alertar possivel atraso via WhatsApp
- em desistencias, analisar agendas futuras e sugerir antecipacao para clientes elegiveis via WhatsApp
- Suportar contratacao:
- individual
- grupo/clinica (multiplos profissionais e/ou especialidades)
- Regra obrigatoria: agendamento deve considerar disponibilidade por profissional e especialidade.

### Monetizacao
- Modelo: freemium.
- Free: ate 50 agendamentos/mes + lembretes basicos.
- Premium: agendamentos ilimitados, lembretes automaticos, integracao WhatsApp, relatorios.
- Preco referencia premium: R$ 34/mes.
- Faixa de ticket medio alvo: R$ 34-49/mes.
- Justificativa de pagamento:
- reduz no-show e aumenta receita
- economiza tempo de confirmacao
- melhora organizacao operacional

### Regra de prioridade funcional
- Em duvidas de escopo, priorizar funcionalidades que:
- reduzam faltas e cancelamentos
- evitem conflitos de agenda
- aumentem ocupacao de horarios
- diminuam trabalho manual de confirmacao e remarcacao
